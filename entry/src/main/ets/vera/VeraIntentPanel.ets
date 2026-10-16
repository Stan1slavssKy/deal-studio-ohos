/**
 * The intent panel's rows (VeraTemplates.ets, intent_panel): which phone actions a request wants, taken only from what
 * this phone has. The host finds the candidates, the content model only picks among them by number, and every row is
 * rebuilt here from the registry: the model never writes a target, a parameter name or a mode.
 */

import { IntentEntry, findIntentFunction } from './VeraIntentIndex'
import { findIntentFunctionByEmbedding } from './VeraIntentEmbeddingCache'
import { registryEntries } from './VeraIntentRegistry'
import { celiaIntentIndexEntries } from './VeraCeliaIntentIndex'
import { INTENT_CATALOG } from './VeraIntentCatalog'

/** 16 candidates found 0.74 of the expected intents of docs/prompts/intent-coverage.md by token search, 24 found 0.80. */
export const CANDIDATE_LIMIT: number = 24
const MAX_ROWS: number = 10
const MAX_LABEL: number = 40
const MAX_VALUE: number = 200
const PANEL_KIND: string = 'intent_panel'

/**
 * Up to `limit` intents for the whole request: embedding hits first when the phone has the vectors, then token hits,
 * without repeats. The embedding search is what finds "put it out" for CloseFlashlight; the token search alone is what
 * the host and a phone without the model have.
 */
export async function intentCandidates(prompt: string, limit: number = CANDIDATE_LIMIT): Promise<IntentEntry[]> {
  let byToken = findIntentFunction(prompt, limit)
  let byEmbedding: IntentEntry[] | null = null
  try {
    byEmbedding = await findIntentFunctionByEmbedding(prompt, limit)
  } catch (_e) {
    byEmbedding = null
  }
  let out: IntentEntry[] = []
  let seen: Set<string> = new Set<string>()
  let lists: IntentEntry[][] = byEmbedding === null ? [byToken] : [byEmbedding, byToken]
  // Alternate the two lists so neither crowds the other out of the limit.
  for (let i = 0; i < limit && out.length < limit; i++) {
    for (let list of lists) {
      if (i < list.length && out.length < limit && !seen.has(list[i].name)) {
        seen.add(list[i].name)
        out.push(list[i])
      }
    }
  }
  return out
}

export class IntentRowsFill {
  /** Hole key ("intentRows2") -> the rows hole's body, only for panels that got at least one row. */
  bodies: Map<string, string>
  note: string
  /** Rows kept over all panels. */
  rows: number
  constructor(bodies: Map<string, string>, note: string, rows: number) {
    this.bodies = bodies
    this.note = note
    this.rows = rows
  }
}

/** What one candidate needs to become a row: where the call goes, how, and which parameters it may carry. */
class CallShape {
  target: string = ''
  mode: string = 'foreground'
  /** Parameter names the intent declares; a name the model gives that is not here is dropped. */
  names: string[] = []
  /** Name and value pairs sent when the model gives no value (a catalogue row's example). */
  defaults: string[] = []
}

const HINT = new RegExp('^sdk\\.call\\("([^"]+)", \\[(.*)\\], "yourHandlerName"(?:, "(foreground|background)")?\\)$')
const PAIR = new RegExp('"([^"]+)", "([^"]*)"', 'g')

function callShape(e: IntentEntry): CallShape | null {
  let m = HINT.exec(e.callHint)
  if (m === null) { return null }
  let shape = new CallShape()
  shape.target = m[1]
  if (m[3] !== undefined) { shape.mode = m[3] }
  PAIR.lastIndex = 0
  let pair: RegExpExecArray | null = PAIR.exec(m[2])
  while (pair !== null) {
    shape.defaults.push(pair[1])
    shape.defaults.push(pair[2])
    pair = PAIR.exec(m[2])
  }
  if (e.kind === 'catalog') {
    for (let spec of INTENT_CATALOG) {
      if (spec.name === e.name) { for (let p of spec.params) { shape.names.push(p.platformName) } }
    }
  } else {
    for (let r of registryEntries()) {
      if (r.target === shape.target) { for (let p of r.params) { shape.names.push(p) } }
    }
    let parts = shape.target.split('/')
    for (let c of celiaIntentIndexEntries()) {
      if (c.bundle === parts[0] && c.intentName === parts[parts.length - 1]) {
        for (let p of c.params) {
          let name = p.platformName.length > 0 ? p.platformName : p.name
          if (shape.names.indexOf(name) < 0) { shape.names.push(name) }
        }
      }
    }
  }
  return shape
}

/** Text safe inside a Vera string literal, on one line, at most `max` characters. */
function literal(text: string, max: number): string {
  let flat = text.replace(new RegExp('[\\r\\n\\t]+', 'g'), ' ').trim()
  if (flat.length > max) { flat = flat.substring(0, max) }
  return flat.replace(new RegExp('\\\\', 'g'), '\\\\').replace(new RegExp('"', 'g'), '\\"')
}

function scalar(v: Object | null | undefined): string | null {
  if (typeof v === 'string') { return v as string }
  if (typeof v === 'number' || typeof v === 'boolean') { return (v as Object).toString() }
  return null
}

function candidateLine(n: number, e: IntentEntry, shape: CallShape): string {
  let about = e.summary.length > 0 ? e.summary : e.description
  if (about.length > 160) { about = about.substring(0, 157) + '...' }
  let name = e.kind === 'catalog' ? e.name : e.label
  let line = n.toString() + '. ' + name + ' -- ' + about
  if (shape.names.length > 0) { line = line + ' Parameters: ' + shape.names.join(', ') + '.' }
  return line
}

const SYSTEM: string = 'You choose phone actions for a screen of buttons. Each button runs one of the numbered actions ' +
  'this phone has. Choose only actions the request asks for, in the order the request names them, at most ' + MAX_ROWS.toString() +
  ' per panel. Answer with JSON only: {"section<N>": [{"n": <action number>, "label": "<button text, 1-4 words>", ' +
  '"params": {"<parameter name>": "<value>"}}]} with one key per panel named in the request. Give params only for the ' +
  'parameters an action lists; write {input} as a value when the person types it into the text box on the screen. ' +
  'An empty list is right when no action fits.'

/**
 * The rows of every intent_panel in `kinds`. Never throws: an answer that cannot be used leaves a panel without rows,
 * and its default body shows an empty state.
 */
export async function fillIntentRows(prompt: string, kinds: string[], ask: (system: string, user: string) => Promise<string | null>): Promise<IntentRowsFill> {
  let bodies: Map<string, string> = new Map<string, string>()
  let slots: number[] = []
  for (let i = 0; i < kinds.length; i++) { if (kinds[i] === PANEL_KIND) { slots.push(i + 1) } }
  if (slots.length === 0) { return new IntentRowsFill(bodies, '', 0) }
  try {
    let candidates: IntentEntry[] = []
    let shapes: CallShape[] = []
    for (let e of await intentCandidates(prompt)) {
      let shape = callShape(e)
      if (shape !== null) { candidates.push(e); shapes.push(shape) }
    }
    if (candidates.length === 0) { return new IntentRowsFill(bodies, 'intents=none(no candidates)', 0) }
    let lines: string[] = []
    for (let i = 0; i < candidates.length; i++) { lines.push(candidateLine(i + 1, candidates[i], shapes[i])) }
    let panels: string[] = []
    for (let slot of slots) { panels.push('section' + slot.toString()) }
    let user = 'Request: ' + prompt + '\nPanels: ' + panels.join(', ') + '\nActions on this phone:\n' + lines.join('\n')
    let raw = await ask(SYSTEM, user)
    if (raw === null) { return new IntentRowsFill(bodies, 'intents=none(no answer)', 0) }
    let parsed = JSON.parse(raw) as Record<string, Object>
    let total = 0
    for (let slot of slots) {
      let list = parsed['section' + slot.toString()]
      if (!Array.isArray(list)) { continue }
      let rows: string[] = []
      let used: number[] = []
      for (let item of list as Object[]) {
        if (rows.length >= MAX_ROWS) { break }
        if (typeof item !== 'object' || item === null) { continue }
        let rec = item as Record<string, Object>
        if (typeof rec['n'] !== 'number') { continue }
        let n = rec['n'] as number
        if (!Number.isInteger(n) || n < 1 || n > candidates.length || used.indexOf(n) >= 0) { continue }
        used.push(n)
        let e = candidates[n - 1]
        let shape = shapes[n - 1]
        let label = scalar(rec['label'])
        if (label === null || label.trim().length === 0) { label = e.kind === 'catalog' ? e.name : e.label }
        let given: Map<string, string> = new Map<string, string>()
        let params = rec['params']
        if (typeof params === 'object' && params !== null && !Array.isArray(params)) {
          let p = params as Record<string, Object>
          for (let name of Object.keys(p)) {
            let value = scalar(p[name])
            if (shape.names.indexOf(name) >= 0 && value !== null) { given.set(name, value) }
          }
        }
        let pairs: string[] = []
        for (let k = 0; k + 1 < shape.defaults.length; k = k + 2) {
          if (!given.has(shape.defaults[k])) { pairs.push(literal(shape.defaults[k], MAX_VALUE)); pairs.push(literal(shape.defaults[k + 1], MAX_VALUE)) }
        }
        let input = false
        given.forEach((value: string, name: string) => {
          pairs.push(literal(name, MAX_VALUE))
          pairs.push(literal(value, MAX_VALUE))
          if (value.indexOf('{input}') >= 0) { input = true }
        })
        rows.push('{label: "' + literal(label, MAX_LABEL) + '", target: "' + literal(shape.target, MAX_VALUE) + '", params: "' +
          pairs.join('\\n') + '", mode: "' + shape.mode + '", input: ' + (input ? 'true' : 'false') + '}')
      }
      if (rows.length > 0) {
        bodies.set('intentRows' + slot.toString(), '  return [\n    ' + rows.join(',\n    ') + '\n  ];')
        total = total + rows.length
      }
    }
    if (total === 0) { return new IntentRowsFill(bodies, 'intents=none(no usable row)', 0) }
    return new IntentRowsFill(bodies, 'intents=' + total.toString() + '/' + candidates.length.toString(), total)
  } catch (e) {
    return new IntentRowsFill(new Map<string, string>(), 'intents=none(' + (e as Error).message + ')', 0)
  }
}
