/**
 * Composition from a sketch: json-render's Jev composer, generalised to programs with logic.
 *
 * json-render (vercel-labs) has Jev pick among app-owned, fully configured component recipes and
 * assembles the result in code; Jev never writes text or code, and nothing computes. Here the
 * recipes are generated per request instead of prepared in advance, and logic is a finite choice too:
 *
 *   1. sketch  -- the generating model, thinking off, turns the request into data: the inputs with
 *                 their ranges and options, the values the screen must show, a countdown, and the
 *                 events the request names. No code.
 *   2. choose  -- Jev answers one independent question per requirement: which widget for each input,
 *                 which formula from a fixed library produces each value and from which operands
 *                 (only inputs, earlier values and the countdown's quantities are offered), what
 *                 drives the countdown, which effect from a fixed catalogue each event is.
 *   3. build   -- this file assembles a VERA program from the answers; the compiler checks it.
 *
 * Coverage is structural: a value with no formula, an operand that does not exist yet, or an event
 * with no effect is reported as unbound rather than replaced by a default, and a composition with
 * anything unbound is not served.
 */

import http from '@ohos.net.http'
import { deepseek } from './DeepSeekEngine'

const JEV_ENDPOINT: string = 'https://api.typesafe.ai/v1/systemone'

/** On whenever there is a TypeSafe key; `--ps veraCompose 0` switches it off for the session. */
let enabled: boolean = true
export function setComposeEnabled(on: boolean): void { enabled = on }
export function composeEnabled(): boolean { return enabled }

export const SKETCH_PROMPT: string =
  'You turn a request for a small phone app into a JSON sketch of its data. Write no code. Answer with one JSON object:\n' +
  '{"title": short app title, "eyebrow": 1-3 word label in capitals, "subtitle": one short line,\n' +
  ' "inputs": [{"id": camelCase, "label": shown label, "kind": "amount" | "percent" | "count" | "choice" | "toggle",\n' +
  '   "measure": "money" | "percent" | "count" | "seconds" | "number", "min": number, "max": number, "value": starting number, "unit": "$" or "" ...,\n' +
  '   "options": only for choice: [{"label": shown text, "value": number}]; a choice\'s "value" is the index of the starting option}],\n' +
  ' "countdown": null, or {"label": what is being timed} when the app counts down a time,\n' +
  ' "values": [{"id": camelCase, "label": shown label, "means": what the number is, in plain words,\n' +
  '   "format": "money" | "percent" | "count" | "seconds" | "fraction" | "plain", "unit": "$" or ""}],\n' +
  ' "events": [{"id": camelCase, "when": the moment, "what": what the phone should do}]}\n' +
  'Rules: inputs are only what the person sets. values are every number the request asks to show, in an order where ' +
  'each can be worked out from inputs and the values before it; a progress bar is a value with format fraction. ' +
  'Times are in seconds: a choice whose options are durations gives each option its duration in seconds as value. ' +
  'events are only things the phone does by itself, such as vibrating; leave it empty otherwise. ' +
  'Use the numbers the request gives; where it gives none, pick sensible ones.'

export class SketchOption {
  label: string = ''
  value: number = 0
}

export class SketchInput {
  id: string = ''
  label: string = ''
  kind: string = 'count'
  min: number = 0
  max: number = 100
  value: number = 0
  unit: string = ''
  /** money, percent, count, seconds or number: what the input measures, for unit-checked formulas. */
  measure: string = 'number'
  options: SketchOption[] = []
}

export class SketchValue {
  id: string = ''
  label: string = ''
  means: string = ''
  format: string = 'plain'
  unit: string = ''
}

export class SketchEvent {
  id: string = ''
  when: string = ''
  what: string = ''
}

export class Sketch {
  title: string = ''
  eyebrow: string = ''
  subtitle: string = ''
  inputs: SketchInput[] = []
  values: SketchValue[] = []
  countdown: string = ''
  hasCountdown: boolean = false
  events: SketchEvent[] = []
}

const INPUT_KINDS: string[] = ['amount', 'percent', 'count', 'choice', 'toggle']
const VALUE_FORMATS: string[] = ['money', 'percent', 'count', 'seconds', 'fraction', 'plain']
const MEASURES: string[] = ['money', 'percent', 'count', 'seconds', 'number']

function str(o: Record<string, Object>, key: string, fallback: string): string {
  let v = o[key]
  return typeof v === 'string' ? v as string : fallback
}

function num(o: Record<string, Object>, key: string, fallback: number): number {
  let v = o[key]
  return typeof v === 'number' && isFinite(v as number) ? v as number : fallback
}

function isIdentifier(s: string): boolean {
  return /^[a-z][A-Za-z0-9]*$/.test(s) && RESERVED_IDS.indexOf(s) < 0
}

/** Names the assembled program uses for itself; an input or value may not take them. */
const RESERVED_IDS: string[] = ['state', 'value', 'elapsedMs', 'running', 'finished', 'effectStatus', 'remaining',
  'elapsed', 'duration', 'view', 'init', 'ui', 'math', 'strings', 'sdk', 'time']

/** The sketch from the model's reply, or null when it is not one. Ids that cannot be names are dropped. */
export function parseSketch(text: string): Sketch | null {
  let start = text.indexOf('{')
  let end = text.lastIndexOf('}')
  if (start < 0 || end <= start) { return null }
  let o: Record<string, Object>
  try {
    o = JSON.parse(text.substring(start, end + 1)) as Record<string, Object>
  } catch (_e) {
    return null
  }
  let sketch = new Sketch()
  sketch.title = str(o, 'title', 'App')
  sketch.eyebrow = str(o, 'eyebrow', '')
  sketch.subtitle = str(o, 'subtitle', '')
  let seen: string[] = []
  let inputs = o['inputs']
  if (Array.isArray(inputs)) {
    for (let raw of inputs as Object[]) {
      let r = raw as Record<string, Object>
      let input = new SketchInput()
      input.id = str(r, 'id', '')
      if (!isIdentifier(input.id) || seen.indexOf(input.id) >= 0) { continue }
      input.label = str(r, 'label', input.id)
      input.kind = str(r, 'kind', 'count')
      if (INPUT_KINDS.indexOf(input.kind) < 0) { input.kind = 'count' }
      input.min = num(r, 'min', 0)
      input.max = num(r, 'max', 100)
      input.value = num(r, 'value', input.min)
      input.unit = str(r, 'unit', '')
      input.measure = str(r, 'measure', input.kind === 'percent' ? 'percent' : (input.kind === 'count' ? 'count' : 'number'))
      if (MEASURES.indexOf(input.measure) < 0) { input.measure = 'number' }
      let options = r['options']
      if (Array.isArray(options)) {
        for (let rawOption of options as Object[]) {
          let ro = rawOption as Record<string, Object>
          let option = new SketchOption()
          option.label = str(ro, 'label', '')
          option.value = num(ro, 'value', 0)
          if (option.label.length > 0) { input.options.push(option) }
        }
      }
      if (input.kind === 'choice' && input.options.length === 0) { continue }
      if (input.kind === 'choice') {
        // The starting choice is an option index; a model sometimes gives the option's value instead.
        let at = input.options.findIndex((o: SketchOption): boolean => o.value === input.value)
        if (!(Number.isInteger(input.value) && input.value >= 0 && input.value < input.options.length)) {
          input.value = at >= 0 ? at : 0
        }
      }
      seen.push(input.id)
      sketch.inputs.push(input)
    }
  }
  let countdown = o['countdown']
  if (countdown !== null && countdown !== undefined && typeof countdown === 'object') {
    sketch.hasCountdown = true
    sketch.countdown = str(countdown as Record<string, Object>, 'label', 'Timer')
  }
  let values = o['values']
  if (Array.isArray(values)) {
    for (let raw of values as Object[]) {
      let r = raw as Record<string, Object>
      let value = new SketchValue()
      value.id = str(r, 'id', '')
      if (!isIdentifier(value.id) || seen.indexOf(value.id) >= 0) { continue }
      value.label = str(r, 'label', value.id)
      value.means = str(r, 'means', value.label)
      value.format = str(r, 'format', 'plain')
      if (VALUE_FORMATS.indexOf(value.format) < 0) { value.format = 'plain' }
      value.unit = str(r, 'unit', '')
      seen.push(value.id)
      sketch.values.push(value)
    }
  }
  let events = o['events']
  if (Array.isArray(events)) {
    for (let raw of events as Object[]) {
      let r = raw as Record<string, Object>
      let event = new SketchEvent()
      event.id = str(r, 'id', '')
      event.when = str(r, 'when', '')
      event.what = str(r, 'what', '')
      if (event.what.length > 0) { sketch.events.push(event) }
    }
  }
  return sketch
}

// ---- The vocabulary Jev chooses from ----

class Formula {
  id: string
  operands: number
  describe: string
  constructor(id: string, operands: number, describe: string) {
    this.id = id
    this.operands = operands
    this.describe = describe
  }
}

/**
 * Formulas are never chosen apart from their operands: Jev answered "add a percent" and "the tip
 * amount" to two separate questions and the program added 75% instead of $75. As in json-render,
 * every option Jev sees is a complete recipe -- here an expression over named operands -- and only
 * the ones whose units fit are offered at all.
 */
const FORMULAS: Formula[] = [
  new Formula('copy', 1, 'exactly the first operand, unchanged'),
  new Formula('add', 2, 'the first operand plus the second'),
  new Formula('subtract', 2, 'the first operand minus the second'),
  new Formula('multiply', 2, 'the first operand times the second'),
  new Formula('divide', 2, 'the first operand divided by the second (an equal share, a rate, or a fraction of a whole)'),
  new Formula('percent_of', 2, 'the second operand percent of the first, i.e. first * second / 100'),
  new Formula('add_percent', 2, 'the first operand increased by the second operand percent, i.e. first * (1 + second / 100)')
]

class Widget {
  id: string
  kinds: string[]
  describe: string
  constructor(id: string, kinds: string[], describe: string) {
    this.id = id
    this.kinds = kinds
    this.describe = describe
  }
}

const WIDGETS: Widget[] = [
  new Widget('typed_number', ['amount', 'count', 'percent'], 'a text field the person types a number into, for any amount such as money'),
  new Widget('stepper', ['count', 'percent'], 'a whole number set with - and + buttons, for small counts such as people or servings'),
  new Widget('slider', ['percent', 'count', 'amount'], 'a slider across a range, for a percentage or a level'),
  new Widget('select', ['choice'], 'a drop-down of the named options'),
  new Widget('switch', ['toggle'], 'an on/off switch')
]

class Effect {
  id: string
  describe: string
  call: string
  constructor(id: string, describe: string, call: string) {
    this.id = id
    this.describe = describe
    this.call = call
  }
}

const EFFECTS: Effect[] = [
  new Effect('vibrate', 'vibrate the phone',
    'sdk.call("SensorServiceKit.vibrator.vibrate", ["duration", "2000"], "onEffect");')
]

const SHOWS: string[] = ['stat', 'hero', 'progress']

function describeInput(input: SketchInput): string {
  if (input.kind === 'choice') {
    let parts: string[] = []
    for (let o of input.options) { parts.push(o.label + ' = ' + o.value.toString()) }
    return 'input "' + input.label + '": the number of the chosen option (' + parts.join(', ') + ')'
  }
  return 'input "' + input.label + '" (' + input.kind + (input.unit.length > 0 ? ', ' + input.unit : '') + ')'
}

class Operand {
  id: string
  label: string
  measure: string
  constructor(id: string, label: string, measure: string) {
    this.id = id
    this.label = label
    this.measure = measure
  }
}

function operandList(sketch: Sketch, index: number): Operand[] {
  let out: Operand[] = []
  for (let input of sketch.inputs) {
    if (input.kind !== 'toggle') { out.push(new Operand(input.id, input.label, input.measure)) }
  }
  for (let i = 0; i < index; i++) {
    let v = sketch.values[i]
    out.push(new Operand(v.id, v.label, v.format === 'plain' ? 'number' : v.format))
  }
  if (sketch.hasCountdown) {
    out.push(new Operand('remaining', 'seconds left on the countdown', 'seconds'))
    out.push(new Operand('elapsed', 'seconds passed on the countdown', 'seconds'))
    out.push(new Operand('duration', 'whole length of the countdown', 'seconds'))
  }
  return out
}

/** What `formula` over a and b measures, or '' when their units do not fit it. */
function resultMeasure(formula: string, a: Operand, b: Operand | null): string {
  let scalar = (m: string): boolean => m === 'count' || m === 'number'
  if (formula === 'copy') { return a.measure }
  if (b === null || a.id === b.id) { return '' }
  if (formula === 'add' || formula === 'subtract') { return a.measure === b.measure && a.measure !== 'percent' ? a.measure : '' }
  if (formula === 'multiply') { return scalar(b.measure) && a.measure !== 'percent' ? a.measure : '' }
  if (formula === 'divide') {
    if (scalar(b.measure)) { return a.measure }
    return a.measure === b.measure ? 'fraction' : ''
  }
  if (formula === 'percent_of' || formula === 'add_percent') { return b.measure === 'percent' && a.measure !== 'percent' ? a.measure : '' }
  return ''
}

function expressionText(formula: string, a: Operand, b: Operand | null): string {
  let bl = b !== null ? b.label : ''
  if (formula === 'copy') { return a.label + ', as it is' }
  if (formula === 'add') { return a.label + ' + ' + bl }
  if (formula === 'subtract') { return a.label + ' - ' + bl }
  if (formula === 'multiply') { return a.label + ' x ' + bl }
  if (formula === 'divide') { return a.label + ' / ' + bl }
  if (formula === 'percent_of') { return bl + ' percent of ' + a.label }
  return a.label + ' increased by ' + bl + ' percent'
}

/** Every unit-consistent expression for value number `index`, keyed "formula:a:b". */
export function expressionsFor(sketch: Sketch, index: number): Map<string, string> {
  let v = sketch.values[index]
  let want = v.format === 'plain' ? '' : v.format
  let operands = operandList(sketch, index)
  let out: Map<string, string> = new Map<string, string>()
  for (let f of FORMULAS) {
    for (let a of operands) {
      if (f.operands === 1) {
        let m = resultMeasure(f.id, a, null)
        if (m.length > 0 && (want.length === 0 || m === want)) { out.set(f.id + ':' + a.id + ':', expressionText(f.id, a, null)) }
        continue
      }
      for (let b of operands) {
        let m = resultMeasure(f.id, a, b)
        if (m.length > 0 && (want.length === 0 || m === want)) { out.set(f.id + ':' + a.id + ':' + b.id, expressionText(f.id, a, b)) }
      }
    }
  }
  return out
}

function choice(instructions: string, criteria: Map<string, string>): Record<string, Object> {
  let c: Record<string, Object> = {}
  criteria.forEach((describe: string, key: string) => { c[key] = describe })
  let q: Record<string, Object> = {}
  q['type'] = 'choice'
  q['instructions'] = instructions
  q['criteria'] = c
  return q
}

export function describeSketch(sketch: Sketch): string {
  let lines: string[] = []
  for (let input of sketch.inputs) { lines.push('- ' + describeInput(input)) }
  if (sketch.hasCountdown) { lines.push('- a countdown: ' + sketch.countdown) }
  for (let v of sketch.values) { lines.push('- shows "' + v.label + '": ' + v.means) }
  for (let e of sketch.events) { lines.push('- when ' + e.when + ': ' + e.what) }
  return lines.join('\n')
}

/** The Jev request: one independent choice per requirement in the sketch. */
export function buildComposeRequest(prompt: string, sketch: Sketch): string {
  let questions: Record<string, Object> = {}

  let theme: Map<string, string> = new Map<string, string>()
  theme.set('clean', 'restrained and neutral')
  theme.set('soft', 'calm and friendly')
  theme.set('expressive', 'bold and atmospheric')
  theme.set('technical', 'precise, for numbers and tools')
  theme.set('playful', 'light and fun')
  questions['theme'] = choice('Which overall look fits this app best?', theme)

  for (let input of sketch.inputs) {
    let widgets: Map<string, string> = new Map<string, string>()
    for (let w of WIDGETS) {
      if (w.kinds.indexOf(input.kind) >= 0) { widgets.set(w.id, w.describe) }
    }
    if (widgets.size > 1) {
      questions['widget.' + input.id] = choice('How should the person set "' + input.label + '"? Follow the request where it names a control.', widgets)
    }
  }

  for (let i = 0; i < sketch.values.length; i++) {
    let v = sketch.values[i]
    let expressions = expressionsFor(sketch, i)
    if (expressions.size === 0) { continue }
    expressions.set('unavailable', 'none of these is it')
    questions['expr.' + v.id] = choice('Which of these works out "' + v.label + '" (' + v.means + ')?', expressions)
    let shows: Map<string, string> = new Map<string, string>()
    shows.set('stat', 'one figure among the others in a row of figures')
    shows.set('hero', 'the one big number the screen is about')
    shows.set('progress', 'a progress bar (the value is a fraction from 0 to 1)')
    questions['show.' + v.id] = choice('How should "' + v.label + '" be shown?', shows)
  }

  if (sketch.hasCountdown) {
    let sources: Map<string, string> = new Map<string, string>()
    for (let input of sketch.inputs) {
      if (input.kind !== 'toggle') { sources.set(input.id, describeInput(input)) }
    }
    questions['countdown.length'] = choice('Which input sets how many seconds the countdown "' + sketch.countdown + '" runs?', sources)
  }

  for (let e of sketch.events) {
    let effects: Map<string, string> = new Map<string, string>()
    for (let fx of EFFECTS) { effects.set(fx.id, fx.describe) }
    effects.set('unavailable', 'none of these')
    questions['effect.' + e.id] = choice('What should the phone do ' + e.when + ' ("' + e.what + '")?', effects)
  }

  let body: Record<string, Object> = {}
  body['model'] = 'jev-latest'
  body['state'] = 'Request: ' + prompt + '\nThe app has:\n' + describeSketch(sketch)
  body['questions'] = questions
  return JSON.stringify(body)
}

// ---- Reading Jev's answers ----

export class Binding {
  formula: string = ''
  a: string = ''
  b: string = ''
  show: string = 'stat'
}

export class Composition {
  sketch: Sketch
  theme: string = 'clean'
  widgets: Map<string, string> = new Map<string, string>()
  bindings: Map<string, Binding> = new Map<string, Binding>()
  countdownFrom: string = ''
  effects: Map<string, string> = new Map<string, string>()
  /** Requirements nothing in the vocabulary was chosen for; a composition with any is not served. */
  unbound: string[] = []
  /** Every answer with its confidence, for the trace. */
  answers: string[] = []
  constructor(sketch: Sketch) { this.sketch = sketch }
}

const PICK_ABOVE: number = 0.25

function answerOf(answers: Record<string, Object>, key: string, allowed: string[], log: string[]): string {
  let a = answers[key] as Record<string, Object>
  if (a === null || a === undefined) { log.push(key + '=?'); return '' }
  let c = a['choice']
  let confidence = typeof a['confidence'] === 'number' ? a['confidence'] as number : 1
  let picked = typeof c === 'string' ? c as string : ''
  log.push(key + '=' + picked + '@' + confidence.toFixed(2))
  if (allowed.indexOf(picked) < 0 || confidence < PICK_ABOVE) { return '' }
  return picked
}

export function readComposition(body: string, sketch: Sketch): Composition {
  let comp = new Composition(sketch)
  let answers: Record<string, Object> = {}
  try {
    let parsed = JSON.parse(body) as Record<string, Object>
    let found = parsed['answers']
    if (found !== null && found !== undefined) { answers = found as Record<string, Object> }
  } catch (_e) {
    comp.unbound.push('no answer from Jev')
    return comp
  }
  let theme = answerOf(answers, 'theme', ['clean', 'soft', 'expressive', 'technical', 'playful'], comp.answers)
  comp.theme = theme.length > 0 ? theme : 'clean'

  for (let input of sketch.inputs) {
    let allowed: string[] = []
    for (let w of WIDGETS) { if (w.kinds.indexOf(input.kind) >= 0) { allowed.push(w.id) } }
    let picked = allowed.length === 1 ? allowed[0] : answerOf(answers, 'widget.' + input.id, allowed, comp.answers)
    comp.widgets.set(input.id, picked.length > 0 ? picked : allowed[0])
  }

  for (let i = 0; i < sketch.values.length; i++) {
    let v = sketch.values[i]
    let keys: string[] = []
    expressionsFor(sketch, i).forEach((_d: string, key: string) => { keys.push(key) })
    let binding = new Binding()
    if (keys.length === 0) {
      comp.unbound.push('"' + v.label + '": nothing to work it out from')
      comp.bindings.set(v.id, binding)
      continue
    }
    let picked = answerOf(answers, 'expr.' + v.id, keys, comp.answers)
    if (picked.length > 0) {
      let parts = picked.split(':')
      binding.formula = parts[0]
      binding.a = parts[1]
      binding.b = parts[2]
    }
    let show = answerOf(answers, 'show.' + v.id, SHOWS, comp.answers)
    binding.show = show.length > 0 ? show : (v.format === 'fraction' ? 'progress' : 'stat')
    let formula = FORMULAS.find((f: Formula): boolean => f.id === binding.formula)
    if (formula === undefined) {
      comp.unbound.push('"' + v.label + '": no formula')
    } else if (binding.a.length === 0 || (formula.operands === 2 && binding.b.length === 0)) {
      comp.unbound.push('"' + v.label + '": ' + formula.id + ' without its operands')
    }
    comp.bindings.set(v.id, binding)
  }

  if (sketch.hasCountdown) {
    let sources: string[] = []
    for (let input of sketch.inputs) { if (input.kind !== 'toggle') { sources.push(input.id) } }
    comp.countdownFrom = answerOf(answers, 'countdown.length', sources, comp.answers)
    if (comp.countdownFrom.length === 0) { comp.unbound.push('countdown: nothing sets its length') }
  }

  let effectIds: string[] = []
  for (let fx of EFFECTS) { effectIds.push(fx.id) }
  for (let e of sketch.events) {
    let picked = answerOf(answers, 'effect.' + e.id, effectIds, comp.answers)
    if (picked.length === 0) { comp.unbound.push('event "' + e.what + '": no effect') }
    comp.effects.set(e.id, picked)
  }
  return comp
}

// ---- Assembling the program ----

function quote(s: string): string {
  return '"' + s.split('\\').join('\\\\').split('"').join('\\"').split('\n').join(' ') + '"'
}

function numberLiteral(n: number): string {
  return isFinite(n) ? n.toString() : '0'
}

class Field {
  name: string
  type: string
  init: string
  constructor(name: string, type: string, init: string) {
    this.name = name
    this.type = type
    this.init = init
  }
}

function stateFields(comp: Composition): Field[] {
  let fields: Field[] = []
  for (let input of comp.sketch.inputs) {
    let widget = comp.widgets.get(input.id) ?? ''
    if (input.kind === 'toggle') {
      fields.push(new Field(input.id, 'boolean', input.value !== 0 ? 'true' : 'false'))
    } else if (input.kind === 'choice') {
      let start = Math.max(0, Math.min(input.options.length - 1, Math.round(input.value)))
      fields.push(new Field(input.id + 'Index', 'number', start.toString()))
    } else if (widget === 'typed_number') {
      fields.push(new Field(input.id + 'Text', 'string', quote(numberLiteral(input.value))))
    } else {
      fields.push(new Field(input.id, 'number', numberLiteral(input.value)))
    }
  }
  if (comp.sketch.hasCountdown) {
    fields.push(new Field('elapsedMs', 'number', '0'))
    fields.push(new Field('running', 'boolean', 'false'))
    fields.push(new Field('finished', 'boolean', 'false'))
  }
  if (comp.sketch.events.length > 0) { fields.push(new Field('effectStatus', 'string', '""')) }
  return fields
}

/** `{a: state.a, b: value, ...}` with the named fields replaced. */
function rebuild(fields: Field[], replaced: Map<string, string>): string {
  let parts: string[] = []
  for (let f of fields) { parts.push(f.name + ': ' + (replaced.get(f.name) ?? 'state.' + f.name)) }
  return '{' + parts.join(', ') + '}'
}

/** Lines that bring every numeric input into a local of its own name, read from state. */
function inputLocals(comp: Composition): string[] {
  let lines: string[] = []
  for (let input of comp.sketch.inputs) {
    let widget = comp.widgets.get(input.id) ?? ''
    if (input.kind === 'toggle') { continue }
    if (input.kind === 'choice') {
      let values: string[] = []
      for (let o of input.options) { values.push(numberLiteral(o.value)) }
      lines.push('  let ' + input.id + 'Values: number[] = [' + values.join(', ') + '];')
      lines.push('  let ' + input.id + ': number = ' + input.id + 'Values[state.' + input.id + 'Index];')
    } else if (widget === 'typed_number') {
      lines.push('  let ' + input.id + ': number = strings.toNumber(state.' + input.id + 'Text, 0);')
    } else {
      lines.push('  let ' + input.id + ': number = state.' + input.id + ';')
    }
  }
  return lines
}

function formulaExpr(b: Binding): string {
  if (b.formula === 'copy') { return b.a }
  if (b.formula === 'add') { return b.a + ' + ' + b.b }
  if (b.formula === 'subtract') { return b.a + ' - ' + b.b }
  if (b.formula === 'multiply') { return b.a + ' * ' + b.b }
  if (b.formula === 'divide') { return 'share(' + b.a + ', ' + b.b + ')' }
  if (b.formula === 'percent_of') { return b.a + ' * ' + b.b + ' / 100' }
  if (b.formula === 'add_percent') { return b.a + ' * (1 + ' + b.b + ' / 100)' }
  return '0'
}

function statFor(v: SketchValue, expr: string): string {
  if (v.format === 'seconds') {
    return 'ui.Stat("default", ' + quote(v.label) + ', ui.durationToString(math.ceil(' + expr + ')), "", "clock")'
  }
  let prefix = v.format === 'money' ? v.unit : ''
  let suffix = v.format === 'percent' ? '%' : (v.format === 'seconds' ? ' s' : (v.format !== 'money' && v.unit.length > 0 ? ' ' + v.unit : ''))
  let decimals = v.format === 'money' ? 2 : (v.format === 'count' || v.format === 'seconds' ? 0 : 1)
  let value = v.format === 'seconds' ? 'math.ceil(' + expr + ')' : expr
  return 'ui.NumberStat("default", ' + quote(v.label) + ', ' + value + ', ' + quote(prefix) + ', ' + quote(suffix) + ', 1, "", "chart", ' + decimals.toString() + ')'
}

function heroText(v: SketchValue, expr: string): string {
  if (v.format === 'seconds') { return 'ui.durationToString(math.ceil(' + expr + '))' }
  if (v.format === 'money') { return quote(v.unit) + ' + ui.formatNumber(' + expr + ', 2)' }
  if (v.format === 'percent') { return 'ui.formatNumber(' + expr + ', 1) + "%"' }
  return 'ui.formatNumber(' + expr + ', ' + (v.format === 'count' ? '0' : '1') + ')'
}

/** The program, or '' when the composition has anything unbound. */
export function assembleProgram(comp: Composition): string {
  if (comp.unbound.length > 0) { return '' }
  let sketch = comp.sketch
  let fields = stateFields(comp)
  let lines: string[] = []

  lines.push('@jsonable')
  lines.push('class AppState {')
  for (let f of fields) { lines.push('  ' + f.name + ': ' + f.type + ';') }
  lines.push('}')
  lines.push('')
  let inits: string[] = []
  for (let f of fields) { inits.push(f.name + ': ' + f.init) }
  lines.push('function init(): AppState {')
  lines.push('  return {' + inits.join(', ') + '};')
  lines.push('}')

  // One setter per input. A new countdown length restarts the countdown.
  for (let input of sketch.inputs) {
    let widget = comp.widgets.get(input.id) ?? ''
    let replaced: Map<string, string> = new Map<string, string>()
    let type = 'number'
    if (input.kind === 'toggle') { replaced.set(input.id, 'value'); type = 'boolean' }
    else if (input.kind === 'choice') { replaced.set(input.id + 'Index', 'value') }
    else if (widget === 'typed_number') { replaced.set(input.id + 'Text', 'value'); type = 'string' }
    else { replaced.set(input.id, 'value') }
    if (sketch.hasCountdown && comp.countdownFrom === input.id) {
      replaced.set('elapsedMs', '0'); replaced.set('running', 'false'); replaced.set('finished', 'false')
    }
    lines.push('')
    lines.push('function set_' + input.id + '(state: AppState, value: ' + type + '): AppState {')
    lines.push('  return ' + rebuild(fields, replaced) + ';')
    lines.push('}')
  }

  if (sketch.hasCountdown) {
    lines.push('')
    lines.push('function countdownSeconds(state: AppState): number {')
    for (let l of inputLocals(comp)) { lines.push(l) }
    lines.push('  return ' + comp.countdownFrom + ';')
    lines.push('}')

    let effectCalls: string[] = []
    for (let e of sketch.events) {
      let fx = EFFECTS.find((x: Effect): boolean => x.id === comp.effects.get(e.id))
      if (fx !== undefined) { effectCalls.push('  ' + fx.call) }
    }
    let done: Map<string, string> = new Map<string, string>()
    done.set('elapsedMs', 'total'); done.set('running', 'false'); done.set('finished', 'true')
    if (effectCalls.length > 0) { done.set('effectStatus', '"pending"') }
    let ticking: Map<string, string> = new Map<string, string>()
    ticking.set('elapsedMs', 'next')
    lines.push('')
    lines.push('function onTick(state: AppState, elapsedMs: number): AppState {')
    lines.push('  if (!state.running) { return state; }')
    lines.push('  let total: number = countdownSeconds(state) * 1000;')
    lines.push('  let next: number = state.elapsedMs + elapsedMs;')
    lines.push('  if (next < total) { return ' + rebuild(fields, ticking) + '; }')
    for (let c of effectCalls) { lines.push(c) }
    lines.push('  return ' + rebuild(fields, done) + ';')
    lines.push('}')

    let start: Map<string, string> = new Map<string, string>()
    start.set('running', 'true'); start.set('finished', 'false')
    start.set('elapsedMs', 'startAt')
    let stop: Map<string, string> = new Map<string, string>()
    stop.set('running', 'false')
    let reset: Map<string, string> = new Map<string, string>()
    reset.set('running', 'false'); reset.set('finished', 'false'); reset.set('elapsedMs', '0')
    lines.push('')
    lines.push('function onStart(state: AppState, ignored: number): AppState {')
    lines.push('  let startAt: number = state.elapsedMs;')
    lines.push('  if (state.finished) { startAt = 0; }')
    lines.push('  return ' + rebuild(fields, start) + ';')
    lines.push('}')
    lines.push('')
    lines.push('function onStop(state: AppState, ignored: number): AppState {')
    lines.push('  return ' + rebuild(fields, stop) + ';')
    lines.push('}')
    lines.push('')
    lines.push('function onReset(state: AppState, ignored: number): AppState {')
    lines.push('  return ' + rebuild(fields, reset) + ';')
    lines.push('}')
  }

  if (sketch.events.length > 0) {
    let status: Map<string, string> = new Map<string, string>()
    status.set('effectStatus', 'value')
    lines.push('')
    lines.push('function onEffect(state: AppState, value: string): AppState {')
    lines.push('  return ' + rebuild(fields, status) + ';')
    lines.push('}')
  }

  lines.push('')
  lines.push('function share(a: number, b: number): number {')
  lines.push('  if (b === 0) { return 0; }')
  lines.push('  return a / b;')
  lines.push('}')

  // The view: every input as a local, every value in sketch order, then the screen.
  lines.push('')
  lines.push('function view(state: AppState): ui.View {')
  for (let l of inputLocals(comp)) { lines.push(l) }
  if (sketch.hasCountdown) {
    lines.push('  let duration: number = ' + comp.countdownFrom + ';')
    lines.push('  let elapsed: number = math.min(state.elapsedMs / 1000, duration);')
    lines.push('  let remaining: number = duration - elapsed;')
  }
  for (let v of sketch.values) {
    let b = comp.bindings.get(v.id)!
    lines.push('  let ' + v.id + ': number = ' + formulaExpr(b) + ';')
  }

  if (sketch.events.length > 0) {
    lines.push('  let effectNote: string = "Phone: " + state.effectStatus;')
    lines.push('  if (state.effectStatus === "pending") { effectNote = "Asking the phone..."; }')
  }

  let heroes: string[] = []
  let bars: string[] = []
  let stats: string[] = []
  for (let v of sketch.values) {
    let b = comp.bindings.get(v.id)!
    if (b.show === 'hero') { heroes.push(v.id) }
    else if (b.show === 'progress') { bars.push('ui.Progress("accent", ' + quote(v.label) + ', math.round(math.min(math.max(' + v.id + ', 0), 1) * 1000), 1000)') }
    else { stats.push(statFor(v, v.id)) }
  }

  let controls: string[] = []
  for (let input of sketch.inputs) {
    let widget = comp.widgets.get(input.id) ?? ''
    let handler = quote('set_' + input.id)
    if (widget === 'select') {
      let labels: string[] = []
      for (let o of input.options) { labels.push(quote(o.label)) }
      controls.push('ui.Select("default", ' + quote(input.label) + ', [' + labels.join(', ') + '], state.' + input.id + 'Index, ' + handler + ')')
    } else if (widget === 'switch') {
      controls.push('ui.Toggle("default", ' + quote(input.label) + ', state.' + input.id + ', ' + handler + ')')
    } else if (widget === 'typed_number') {
      controls.push('ui.TextField("default", ' + quote(input.label) + ', state.' + input.id + 'Text, ' + handler + ', "number")')
    } else if (widget === 'slider') {
      let label = input.kind === 'percent' ? quote(input.label + ' ') + ' + ui.numberToString(state.' + input.id + ') + "%"' : quote(input.label)
      controls.push('ui.Slider("accent", ' + label + ', state.' + input.id + ', ' + numberLiteral(input.min) + ', ' + numberLiteral(input.max) + ', ' + handler + ')')
    } else {
      controls.push('ui.NumberField("default", ' + quote(input.label) + ', state.' + input.id + ', ' + numberLiteral(input.min) + ', ' + numberLiteral(input.max) + ', ' + handler + ')')
    }
  }

  let children: string[] = []
  if (sketch.hasCountdown) { children.push('ui.Ticker("default", "countdown", 200, state.running, "onTick")') }
  children.push('ui.Header("default", ' + quote(sketch.title) + ', ' + quote(sketch.eyebrow) + ', ' + quote(sketch.subtitle) + ', "' + (sketch.hasCountdown ? 'clock' : 'chart') + '")')
  let heroChildren: string[] = bars.slice()
  if (sketch.hasCountdown) {
    heroChildren.push('ui.ActionBar("spread", [ui.Button("primary", "Start", "onStart", 0, !state.running), ' +
      'ui.Button("secondary", "Stop", "onStop", 0, state.running), ui.Button("secondary", "Reset", "onReset", 0, true)])')
  }
  if (heroes.length > 0) {
    let v = sketch.values.find((x: SketchValue): boolean => x.id === heroes[0])!
    children.push('ui.Section("hero", "", "", [ui.Hero("accent", ' + quote(v.label) + ', ' + heroText(v, v.id) + ', "", [' + heroChildren.join(', ') + '])])')
  } else if (heroChildren.length > 0) {
    children.push('ui.Section("content", "", "", [' + heroChildren.join(', ') + '])')
  }
  if (controls.length > 0) { children.push('ui.Section("content", "", "", [' + controls.join(', ') + '])') }
  if (stats.length > 0) {
    children.push('ui.Section("summary", "", "", [ui.MetricGroup("default", ' + Math.min(stats.length, 3).toString() + ', [' + stats.join(', ') + '])])')
  }
  if (sketch.events.length > 0) {
    children.push('ui.When(state.effectStatus !== "", ui.InsetBanner("default", "Done", effectNote, "", "", "info"))')
  }
  lines.push('  return ui.AppTheme(' + quote(comp.theme) + ', "", [')
  lines.push('    ' + children.join(',\n    '))
  lines.push('  ]);')
  lines.push('}')
  return lines.join('\n')
}


// ---- The whole route, as the Generate screen runs it ----

export class ComposeResult {
  /** The assembled program; empty when the request cannot be composed. */
  source: string = ''
  /** One line for the trace and the status area: why, or what was chosen. */
  note: string = ''
  sketchMs: number = 0
  jevMs: number = 0
  sketch: string = ''
  answers: string[] = []
}

async function askJev(body: string, apiKey: string): Promise<string> {
  let client = http.createHttp()
  try {
    let headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + apiKey
    let response = await client.request(JEV_ENDPOINT, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 5000,
      readTimeout: 15000
    })
    if ((response.responseCode as number) !== 200) { return '' }
    return response.result as string
  } catch (_e) {
    return ''
  } finally {
    client.destroy()
  }
}

/** Sketch, Jev, assembly. Never throws: anything that goes wrong comes back as an empty source and a note. */
export async function composeFromPrompt(prompt: string, apiKey: string): Promise<ComposeResult> {
  let result = new ComposeResult()
  let started = Date.now()
  let text = await deepseek.extractSketch(SKETCH_PROMPT, prompt)
  result.sketchMs = Date.now() - started
  if (text === null) { result.note = 'no sketch'; return result }
  result.sketch = text
  let sketch = parseSketch(text)
  if (sketch === null) { result.note = 'sketch did not parse'; return result }
  started = Date.now()
  let body = await askJev(buildComposeRequest(prompt, sketch), apiKey)
  result.jevMs = Date.now() - started
  if (body.length === 0) { result.note = 'Jev did not answer'; return result }
  let comp = readComposition(body, sketch)
  result.answers = comp.answers
  if (comp.unbound.length > 0) { result.note = 'unbound: ' + comp.unbound.join('; '); return result }
  result.source = assembleProgram(comp)
  result.note = 'composed: ' + sketch.inputs.length.toString() + ' inputs, ' + sketch.values.length.toString() + ' values' +
    (sketch.hasCountdown ? ', countdown' : '') + (sketch.events.length > 0 ? ', ' + sketch.events.length.toString() + ' effects' : '')
  return result
}
