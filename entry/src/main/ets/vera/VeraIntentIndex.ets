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
 *
 * Both a catalogue row and a raw registry hit are now offered as sdk.call,
 * never intent.call or a typed intent.<name>: std/intent is no longer a
 * module a new program can import at all (VeraCompiler.collectImports), so
 * sdk.call is the only way a program written from now on reaches an intent.
 * A catalogue row's real address, mode and probed platform values (including
 * any valueMap translation, e.g. "work" -> the platform's own literal) are
 * substituted directly into the suggested call, and 'launch' rows (nothing to
 * tell the target, e.g. opening the calendar app) come back as a three-part
 * target -- see runRawIntent in VeraIntents.ets for how the two target shapes
 * are told apart and run. std/intent is no longer registered by the compiler
 * at all (a separate, revertible commit), so a program saved before that
 * change keeps running from its existing bytecode but cannot be recompiled
 * (Refine) without reverting it.
 */

import { INTENT_CATALOG, IntentSpec, IntentParam } from './VeraIntentCatalog'
import { registryEntries, RegistryEntry, requestWords } from './VeraIntentRegistry'
import { identifierTokens, needWords } from './VeraSdkIndex'

/** One candidate find_intent_function can return. */
export class IntentEntry {
  /** 'catalog' (probed, so its address and values are trustworthy) or 'raw'
   * (the device registry, unverified). Both come back as an sdk.call. */
  kind: string = ''
  /** An internal identifier only -- never shown to the model. */
  name: string = ''
  domain: string = ''
  description: string = ''
  /** A ready-to-copy sdk.call, so the model copies a working shape -- with
   * real platform values already substituted in -- rather than reconstructing
   * one from a param list. */
  callHint: string = ''
  nameTokens: string[] = []
  descriptionTokens: string[] = []
}

/**
 * The one value a closed-set param would send for a given program-level
 * value, translating through the row's own valueMap when it has one (e.g.
 * startNavigate's "work" -> "公司") and passing it through unchanged
 * otherwise. Every closed-set value the row accepts is shown this way in the
 * description, not just the first, so the model can write whichever one the
 * request actually needs instead of only ever copying the example.
 */
function platformValue(p: IntentParam, programValue: string): string {
  let mapped = p.valueMap.get(programValue)
  return mapped !== undefined ? mapped as string : programValue
}

function catalogEntry(spec: IntentSpec): IntentEntry {
  let e = new IntentEntry()
  e.kind = 'catalog'
  e.name = spec.name
  e.domain = spec.domain
  let fields: string[] = []
  let pairs: string[] = []
  for (let p of spec.params) {
    if (p.values.length > 0) {
      let shown: string[] = []
      for (let v of p.values) { shown.push(v + '=' + platformValue(p, v)) }
      fields.push(p.platformName + ' (one of: ' + shown.join(' ') + ')')
    } else {
      fields.push(p.platformName + ' (' + p.kind + ')')
    }
    let example = p.values.length > 0 ? platformValue(p, p.values[0]) : ''
    if (example.length > 0) { pairs.push('"' + p.platformName + '", "' + example + '"') }
  }
  e.description = spec.summary + (fields.length > 0 ? '. Platform fields: ' + fields.join(', ') : '')
  // 'launch' has no intent name and nothing to tell the target, so the target
  // is just bundle/module/ability -- three parts, not four. runRawIntent
  // (VeraIntents.ets) tells the two shapes apart the same way.
  let target = spec.via === 'launch'
    ? spec.bundle + '/' + spec.moduleName + '/' + spec.ability
    : spec.bundle + '/' + spec.moduleName + '/' + spec.ability + '/' + spec.intentName
  let modeArg = spec.via === 'launch' ? '' : ', "' + spec.mode + '"'
  e.callHint = 'sdk.call("' + target + '", [' + pairs.join(', ') + '], "yourHandlerName"' + modeArg + ')'
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
  // sdk.call, not intent.call: the two raw escape hatches are unified (see
  // buildStdSdkModule in VeraCompiler.ets). Argument order is (target,
  // params, handler, mode) -- mode trails because it is the optional one,
  // unlike intent.call's own (target, params, mode, handler).
  e.callHint = 'sdk.call("' + entry.target + '", [], "yourHandlerName", "' + mode + '")'
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
