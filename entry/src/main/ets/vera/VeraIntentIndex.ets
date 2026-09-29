/**
 * A searchable, tool-callable view over the two places a generated program's
 * intent calls come from: the curated catalogue (VeraIntentCatalog, 7 rows,
 * typed, probed on a phone) and the raw device registry (VeraIntentRegistry,
 * up to 640 addresses, uncurated). Existed before this file as text spliced
 * into the prompt ahead of generation, chosen by JevSelector's two-stage
 * classifier (or its lexical fallback when Jev doesn't answer).
 *
 * That pre-splicing is what broke the comparison with sdk.call: whatever
 * JevSelector picked (or its lexical tail found) was already sitting in the
 * prompt as ready text before the model started reasoning, so it won even
 * when the model also called find_sdk_function and got a correct answer for
 * the same request (docs/selector-design.md). Giving intents the same
 * mechanism sdk.call already uses -- one tool the model calls when it
 * decides it needs something, searched locally, no network, no pre-selection
 * -- means neither has a head start baked into how the prompt was built.
 *
 * JevSelector.ets and its network round trips are untouched and still
 * callable; nothing here deletes them. GeneratePage simply stops invoking
 * them in favour of this.
 */

import { INTENT_CATALOG, IntentSpec } from './VeraIntentCatalog'
import { registryEntries, RegistryEntry, requestWords } from './VeraIntentRegistry'
import { identifierTokens, needWords } from './VeraSdkIndex'

/** One candidate find_intent_function can return. */
export class IntentEntry {
  /** 'catalog' (typed, checked) or 'raw' (intent.call escape hatch). */
  kind: string = ''
  /** catalog: the intent.<name> function; raw: the intent.call target. */
  name: string = ''
  domain: string = ''
  description: string = ''
  /** A ready-to-adapt call, so the model copies a working shape rather than
   * reconstructing one from a param list. */
  callHint: string = ''
  nameTokens: string[] = []
  descriptionTokens: string[] = []
}

function catalogEntry(spec: IntentSpec): IntentEntry {
  let e = new IntentEntry()
  e.kind = 'catalog'
  e.name = spec.name
  e.domain = spec.domain
  let fields: string[] = []
  let example: string[] = []
  for (let p of spec.params) {
    let vals = p.values.length > 0 ? ', one of: ' + p.values.join(' ') : ''
    fields.push(p.name + ' (' + p.kind + vals + ')')
    example.push(p.name + ': "' + (p.values.length > 0 ? p.values[0] : '') + '"')
  }
  e.description = spec.summary + (fields.length > 0 ? '. Fields: ' + fields.join(', ') : '')
  e.callHint = 'intent.' + spec.name + '({ ' + example.join(', ') + ' }, "yourHandlerName")'
  e.nameTokens = identifierTokens(spec.name)
  e.descriptionTokens = requestWords(e.description)
  return e
}

function rawEntry(entry: RegistryEntry): IntentEntry {
  let e = new IntentEntry()
  e.kind = 'raw'
  e.name = entry.target
  e.domain = entry.domain
  let bits: string[] = [entry.intentName + ' (' + entry.bundle + ')']
  if (entry.params.length > 0) { bits.push('parameters: ' + entry.params.join(' ')) }
  if (entry.words.length > 0) { bits.push(entry.words) }
  e.description = bits.join(', ')
  let mode = entry.modes.indexOf('background') >= 0 ? 'background' : 'foreground'
  e.callHint = 'intent.call("' + entry.target + '", [], "' + mode + '", "yourHandlerName")'
  e.nameTokens = identifierTokens(entry.intentName)
  e.descriptionTokens = requestWords(e.description)
  return e
}

const W_NAME = 3
const W_DOMAIN = 2
const W_DESCRIPTION = 1

function scoreEntry(e: IntentEntry, words: string[]): number {
  let score = 0
  let domainTokens = identifierTokens(e.domain)
  for (let w of words) {
    if (e.nameTokens.indexOf(w) >= 0) { score = score + W_NAME }
    if (domainTokens.indexOf(w) >= 0) { score = score + W_DOMAIN }
    if (e.descriptionTokens.indexOf(w) >= 0) { score = score + W_DESCRIPTION }
  }
  return score
}

/**
 * The top `limit` intent candidates for `need` -- a fresh brute-force scan
 * over the catalogue (7 rows) and whatever's in the registry (0 to ~640,
 * however much of it is loaded), same reasoning as findSdkFunction: cheap
 * enough at this size that caching the index buys nothing and risks locking
 * in an empty registry if this runs before loadRegistry() finishes.
 *
 * Ties favour a catalog row over a raw one: it is typed and probed, and
 * docs/demo-prompts.md's own guidance is to prefer it whenever it fits.
 */
export function findIntentFunction(need: string, limit: number = 8): IntentEntry[] {
  let entries: IntentEntry[] = []
  for (let spec of INTENT_CATALOG) { entries.push(catalogEntry(spec)) }
  for (let reg of registryEntries()) { entries.push(rawEntry(reg)) }

  let words = needWords(need)
  let scored: IntentEntry[] = []
  let scores: Map<string, number> = new Map<string, number>()
  for (let e of entries) {
    let s = scoreEntry(e, words)
    if (s > 0) {
      let key = e.kind + ':' + e.name
      scores.set(key, s)
      scored.push(e)
    }
  }
  scored.sort((a: IntentEntry, b: IntentEntry) => {
    let ka = a.kind + ':' + a.name
    let kb = b.kind + ':' + b.name
    let sa = scores.get(ka) as number
    let sb = scores.get(kb) as number
    if (sa !== sb) { return sb - sa }
    if (a.kind !== b.kind) { return a.kind === 'catalog' ? -1 : 1 }
    return ka < kb ? -1 : 1
  })
  return scored.slice(0, limit)
}
