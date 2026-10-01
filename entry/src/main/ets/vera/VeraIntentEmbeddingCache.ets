/**
 * On-device embedding cache for VeraIntentIndex's pool -- the curated
 * catalogue (7 rows) plus whatever VeraIntentRegistry has read off this
 * phone (0 to ~640, changes only when apps are installed/removed).
 *
 * Different shape from VeraSdkEmbeddingCache.ets on purpose, not by
 * oversight: that corpus is a static, versioned rawfile recomputed whole on
 * any mismatch, because there are 16,511 of them and no identity worth
 * tracking row to row. This one is small and keyed by identity (catalog
 * name, or raw registry target) specifically so a phone's rarely-changing
 * intent set only ever pays to embed entries it hasn't seen before --
 * installing one more app should not re-embed the other 639.
 *
 * Persisted as JSON, not a flat binary buffer: at this size (≤~650 rows) the
 * parse cost is trivial, and a key->vector map is the natural shape for
 * "which keys are missing" -- no need for sdk-index.json-style layout
 * invalidation.
 */

import fs from '@ohos.file.fs'
import hilog from '@ohos.hilog'
import { IntentEntry, allEntries } from './VeraIntentIndex'
import { embedBatch, embedOne, embeddingModelReady } from './VeraEmbeddings'

const DOMAIN = 0x0000
// See VeraSdkEmbeddingCache.ets's own comment on this constant -- same
// reasoning, same number: ~145ms/entry on-device means one chunk's native
// call blocks the main thread for about 1.2s, safely under the 3s warning
// threshold HarmonyOS's freeze watchdog logs before a kill.
const CHUNK_SIZE = 8

function entryKey(e: IntentEntry): string { return e.kind + ':' + e.name }

function entryEmbeddingText(e: IntentEntry): string { return e.name + ' ' + e.description }

/** key -> L2-normalized vector. Whatever's in here is usable; a key missing
 * from it (model never loaded, or not embedded yet) is simply skipped by
 * findIntentFunctionByEmbedding, not treated as a reason to fail. */
let vectors: Map<string, number[]> = new Map<string, number[]>()
let dimension = 0
let loadedFromDisk = false
let building: Promise<void> | null = null

export function intentEmbeddingsReady(): boolean { return vectors.size > 0 }

function cacheFilePath(filesDir: string): string { return filesDir + '/vera/intent-embeddings.json' }

function readCache(filesDir: string): void {
  if (loadedFromDisk) { return }
  loadedFromDisk = true
  try {
    let stat = fs.statSync(cacheFilePath(filesDir))
    if (stat.size === 0) { return }
    let text = fs.readTextSync(cacheFilePath(filesDir))
    let obj = JSON.parse(text) as Record<string, Object>
    let dim = obj['dimension'] as number
    let rows = obj['vectors'] as Record<string, Object>
    if (rows === null || rows === undefined) { return }
    for (let key of Object.keys(rows)) {
      let v = rows[key] as number[]
      if (v.length === dim) { vectors.set(key, v) }
    }
    dimension = dim
    hilog.info(DOMAIN, 'VERA', 'VERA-INTENT-EMBED cache hit, ' + vectors.size.toString() + ' vectors, dim=' + dim.toString())
  } catch (_e) {
    // No cache file yet, or an unreadable one -- start from empty, same as
    // VeraIntentRegistry.loadRegistry()'s own "failure is not an error" rule.
  }
}

function writeCache(filesDir: string): void {
  try {
    let rows: Record<string, Object> = {}
    vectors.forEach((v: number[], key: string) => { rows[key] = v })
    let obj: Record<string, Object> = {}
    obj['dimension'] = dimension
    obj['vectors'] = rows
    let file = fs.openSync(cacheFilePath(filesDir),
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, JSON.stringify(obj))
    } finally {
      fs.closeSync(file)
    }
  } catch (e) {
    hilog.warn(DOMAIN, 'VERA', 'VERA-INTENT-EMBED cache write failed: ' + (e as Error).message)
  }
}

async function build(filesDir: string): Promise<void> {
  readCache(filesDir)
  let entries = allEntries()
  let missing: IntentEntry[] = []
  for (let e of entries) {
    if (!vectors.has(entryKey(e))) { missing.push(e) }
  }
  if (missing.length === 0) { return }
  if (!embeddingModelReady()) { return }

  let startedAt = Date.now()
  let embedded = 0
  for (let start = 0; start < missing.length; start += CHUNK_SIZE) {
    let chunk = missing.slice(start, Math.min(start + CHUNK_SIZE, missing.length))
    let texts: string[] = []
    for (let e of chunk) { texts.push(entryEmbeddingText(e)) }
    let vecs = await embedBatch(texts)
    if (vecs === null) {
      hilog.warn(DOMAIN, 'VERA', 'VERA-INTENT-EMBED build aborted at ' + start.toString() +
        '/' + missing.length.toString() + ' -- embedding became unavailable')
      break
    }
    for (let i = 0; i < chunk.length; i++) {
      let v = vecs[i]
      if (v.length === 0) { continue } // this one entry failed to embed -- leave it absent, not zeroed
      if (dimension === 0) { dimension = v.length }
      if (v.length === dimension) {
        vectors.set(entryKey(chunk[i]), v)
        embedded++
      }
    }
  }
  if (embedded > 0) {
    hilog.info(DOMAIN, 'VERA', 'VERA-INTENT-EMBED embedded ' + embedded.toString() + ' new of ' +
      missing.length.toString() + ' missing in ' + (Date.now() - startedAt).toString() + 'ms')
    writeCache(filesDir)
  }
}

/**
 * Kicks off the cache build (missing-keys only), fire-and-forget safe from
 * GeneratePage.ets -- and safe to call again later (e.g. once
 * loadRegistry() actually finishes, or after a fresh app install changes
 * the registry): each call only coalesces with one already in flight, not
 * with one that has already finished, so a later call always re-checks
 * `allEntries()` for anything still missing. This matters in practice --
 * loadRegistry()'s own device read is a separate, independent async
 * operation with no ordering guarantee against this one, so the first call
 * here can genuinely run before the registry has populated at all (confirmed
 * on-device this session: a first pass embedded only the 7 catalog rows
 * plus a handful of early raw entries, not the full ~640).
 */
export function ensureIntentEmbeddings(filesDir: string): Promise<void> {
  if (building === null) {
    building = build(filesDir).then((): void => { building = null })
  }
  return building!
}

/**
 * The top `limit` intent candidates for `need` by cosine similarity --
 * null means "nothing embedded yet", which DeepSeekEngine.ets treats as
 * "fall back to findIntentFunction". Scores only entries that have a cached
 * vector; one that doesn't (never embedded, or failed to embed) is simply
 * absent from the ranking, not a zero score dragging it to the bottom --
 * either way it does not surface, but this way a partially-built cache
 * degrades by shrinking the candidate pool, not by never favouring anything.
 */
export async function findIntentFunctionByEmbedding(need: string, limit: number = 8): Promise<IntentEntry[] | null> {
  if (vectors.size === 0) { return null }
  let q = await embedOne(need)
  if (q === null) { return null }

  let entries = allEntries()
  let scored: IntentEntry[] = []
  let scores: Map<string, number> = new Map<string, number>()
  for (let e of entries) {
    let v = vectors.get(entryKey(e))
    if (v === undefined || v.length !== dimension) { continue }
    let dot = 0
    for (let d = 0; d < dimension; d++) { dot = dot + q[d] * v[d] }
    scores.set(entryKey(e), dot)
    scored.push(e)
  }
  scored.sort((a: IntentEntry, b: IntentEntry) => {
    let sa = scores.get(entryKey(a)) as number
    let sb = scores.get(entryKey(b)) as number
    return sb - sa
  })
  return scored.slice(0, limit)
}
