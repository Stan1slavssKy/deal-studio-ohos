/**
 * On-device embedding cache for VeraSdkIndex's corpus (tools/build-sdk-index.py's
 * 16,511 entries) -- the piece EmbeddingGemma can't precompute host-side,
 * because the model only runs through the native llama.cpp binding
 * (VeraEmbeddings.ets), which is device-only. Computed once per device, in
 * the background, and cached to disk as a flat Float32Array; nothing calls
 * into this cache until it (or a fresh build) is ready.
 *
 * Recomputed whole, not incrementally: unlike the intent registry (up to
 * ~640 entries, changes as apps are installed -- see
 * VeraIntentEmbeddingCache.ets), sdk-index.json is a static, versioned
 * rawfile baked in at build time. A source-hash mismatch (the index was
 * rebuilt) invalidates the whole cache rather than trying to patch it.
 */

import fs from '@ohos.file.fs'
import hilog from '@ohos.hilog'
import { SdkEntry, sdkIndexEntries } from './VeraSdkIndex'
import { embedBatch, embedOne, embeddingModelReady } from './VeraEmbeddings'

const DOMAIN = 0x0000
/** 'VSD1' as an int32 -- just a tag to reject a file that isn't this cache. */
const MAGIC = 0x56534431
const HEADER_INTS = 5 // magic, version, count, dimension, source hash
/**
 * How many entries go into one native llamaEmbedBatch call. Measured on
 * device this session: ~145ms/entry, sequential (the native side decodes
 * one text at a time; see napi_llama.cpp's LlamaEmbedBatch). 8 keeps one
 * chunk's blocking native call around 1.2s -- comfortably under the 3s
 * THREAD_BLOCK_3S warning HarmonyOS's watchdog logs before a sustained 6s
 * block kills the process (confirmed on-device: a run with no inter-chunk
 * yield at all hit exactly that and was killed -- see
 * VeraEmbeddings.ets's embedBatch, which now yields to the event loop after
 * every call).
 */
const CHUNK_SIZE = 8

function sdkKey(e: SdkEntry): string { return e.kit + '.' + e.module + '.' + e.name }

function sdkEmbeddingText(e: SdkEntry): string {
  return e.kit + ' ' + e.module + ' ' + e.name + ' ' + e.description
}

function fnv1a(s: string, seed: number): number {
  let h = seed
  for (let i = 0; i < s.length; i++) {
    h = h ^ s.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h >>> 0
}

/** Over entry identity only (kit.module.name), not their descriptions --
 * cheap, and sdk-index.json is rebuilt as a whole file, so a changed
 * description always comes with a changed entry set to key off of. */
function sourceHash(entries: SdkEntry[]): number {
  let h = 0x811c9dc5
  for (let e of entries) { h = fnv1a(sdkKey(e), h) }
  return h >>> 0
}

/** One L2-normalized vector per entry, in sdkIndexEntries() order, flattened. */
let vectors: Float32Array | null = null
let dimension = 0
let ready = false
let building: Promise<void> | null = null

export function sdkEmbeddingsReady(): boolean { return ready }

function cacheFilePath(filesDir: string): string { return filesDir + '/vera/sdk-embeddings.bin' }

function readCache(filesDir: string, entries: SdkEntry[]): boolean {
  let path = cacheFilePath(filesDir)
  try {
    let stat = fs.statSync(path)
    if (stat.size < HEADER_INTS * 4) { return false }
    let file = fs.openSync(path, fs.OpenMode.READ_ONLY)
    try {
      let headerBuf = new ArrayBuffer(HEADER_INTS * 4)
      fs.readSync(file.fd, headerBuf)
      let header = new Int32Array(headerBuf)
      if (header[0] !== MAGIC) { return false }
      let count = header[2]
      let dim = header[3]
      let hash = header[4]
      if (count !== entries.length) { return false }
      if (hash !== sourceHash(entries)) { return false }
      let payloadBytes = count * dim * 4
      if (stat.size < HEADER_INTS * 4 + payloadBytes) { return false }
      let payloadBuf = new ArrayBuffer(payloadBytes)
      fs.readSync(file.fd, payloadBuf)
      vectors = new Float32Array(payloadBuf)
      dimension = dim
      ready = true
      return true
    } finally {
      fs.closeSync(file)
    }
  } catch (_e) {
    return false
  }
}

function writeCache(filesDir: string, entries: SdkEntry[], dim: number, flat: Float32Array): void {
  try {
    let file = fs.openSync(cacheFilePath(filesDir),
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    try {
      let headerBuf = new ArrayBuffer(HEADER_INTS * 4)
      let header = new Int32Array(headerBuf)
      header[0] = MAGIC
      header[1] = 1
      header[2] = entries.length
      header[3] = dim
      header[4] = sourceHash(entries)
      fs.writeSync(file.fd, headerBuf)
      fs.writeSync(file.fd, flat.buffer)
    } finally {
      fs.closeSync(file)
    }
  } catch (e) {
    hilog.warn(DOMAIN, 'VERA', 'VERA-SDK-EMBED cache write failed: ' + (e as Error).message)
  }
}

async function build(filesDir: string): Promise<void> {
  let entries = sdkIndexEntries()
  if (entries.length === 0) { return }
  if (readCache(filesDir, entries)) {
    hilog.info(DOMAIN, 'VERA', 'VERA-SDK-EMBED cache hit, ' + entries.length.toString() +
      ' vectors, dim=' + dimension.toString())
    return
  }
  if (!embeddingModelReady()) { return }

  let dim = 0
  let flatList: number[] = []
  let startedAt = Date.now()
  for (let start = 0; start < entries.length; start += CHUNK_SIZE) {
    let chunk = entries.slice(start, Math.min(start + CHUNK_SIZE, entries.length))
    let texts: string[] = []
    for (let e of chunk) { texts.push(sdkEmbeddingText(e)) }
    let chunkStartedAt = Date.now()
    let vecs = await embedBatch(texts)
    if (vecs === null) {
      hilog.warn(DOMAIN, 'VERA', 'VERA-SDK-EMBED build aborted at ' + start.toString() +
        '/' + entries.length.toString() + ' -- embedding became unavailable')
      return
    }
    // Every ~50 chunks, not every one -- enough to watch real cadence
    // (confirm chunks are genuinely spaced out, not a replay of the
    // continuous-block freeze this logging helped catch) without flooding
    // hilog over a ~16,511-entry build.
    if (start === 0 || (start / CHUNK_SIZE) % 50 === 0) {
      hilog.info(DOMAIN, 'VERA', 'VERA-SDK-EMBED progress ' + start.toString() + '/' + entries.length.toString() +
        ' chunk ' + (Date.now() - chunkStartedAt).toString() + 'ms total ' + (Date.now() - startedAt).toString() + 'ms')
    }
    for (let v of vecs) {
      if (dim === 0 && v.length > 0) { dim = v.length }
      if (dim > 0 && v.length === dim) {
        for (let x of v) { flatList.push(x) }
      } else {
        // A single entry's text failed to embed (too long, decode error) --
        // zero vector, so it scores 0 against every query and simply never
        // surfaces, rather than corrupting every later entry's offset.
        for (let i = 0; i < dim; i++) { flatList.push(0) }
      }
    }
  }
  if (dim === 0) { return }

  let flat = new Float32Array(flatList.length)
  for (let i = 0; i < flatList.length; i++) { flat[i] = flatList[i] }
  vectors = flat
  dimension = dim
  ready = true
  hilog.info(DOMAIN, 'VERA', 'VERA-SDK-EMBED built ' + entries.length.toString() +
    ' vectors, dim=' + dim.toString() + ' in ' + (Date.now() - startedAt).toString() + 'ms')
  writeCache(filesDir, entries, dim, flat)
}

/**
 * Kicks off the cache build (or disk load), fire-and-forget safe from
 * GeneratePage.ets -- and safe to call again later, the same "coalesce with
 * one in flight, not with one already finished" shape
 * VeraIntentEmbeddingCache.ets's ensureIntentEmbeddings uses, for the same
 * reason: loadSdkIndex()'s own rawfile read is a separate, independent
 * async operation with no ordering guarantee against this one, and this
 * call can genuinely run before it finishes -- confirmed on-device this
 * session (entries.length was still 0, so build() took its very first
 * early-return and never actually started embedding anything).
 */
export function ensureSdkEmbeddings(filesDir: string): Promise<void> {
  if (building === null) {
    building = build(filesDir).then((): void => { building = null })
  }
  return building!
}

/**
 * The top `limit` sdk candidates for `need` by cosine similarity alone --
 * null means "not ready" (cache still building, or embedding unavailable
 * this session), which DeepSeekEngine.ets treats as "fall back to
 * findSdkFunction", never as an error. Compares the query against the
 * *whole* corpus, not a token-prefiltered shortlist -- the whole point,
 * since the motivating failures (VeraSdkIndex.ets's doc comment) share zero
 * tokens with their correct answer and would never reach a shortlist built
 * that way.
 */
export async function findSdkFunctionByEmbedding(need: string, limit: number = 8): Promise<SdkEntry[] | null> {
  if (!ready || vectors === null) { return null }
  let q = await embedOne(need)
  if (q === null) { return null }
  let entries = sdkIndexEntries()
  if (entries.length * dimension !== vectors!.length) { return null }

  let scores: number[] = new Array(entries.length)
  for (let i = 0; i < entries.length; i++) {
    let dot = 0
    let base = i * dimension
    for (let d = 0; d < dimension; d++) { dot = dot + q[d] * vectors![base + d] }
    scores[i] = dot
  }
  let idx: number[] = []
  for (let i = 0; i < entries.length; i++) { idx.push(i) }
  idx.sort((a: number, b: number) => scores[b] - scores[a])

  let out: SdkEntry[] = []
  for (let i = 0; i < idx.length && i < limit; i++) { out.push(entries[idx[i]]) }
  return out
}
