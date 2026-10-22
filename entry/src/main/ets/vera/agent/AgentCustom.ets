/**
 * The custom section: what neither the composition's own parts nor a section of the catalogue does, written by the
 * model as one block of the program -- its state fields, its handlers, its view -- into the program the rest already
 * makes, and settled like any block: compiled, then run once with every handler tapped (VeraSmoke.ets), with the
 * failing lines quoted back for a repair, at most twice. The model sees the language as generation does (the host's
 * skill prompt) and writes only the missing piece, so it is small and its names are its own (c_...).
 *
 * What the phone or another app must do, it does with sdk.call -- but only to a target the phone's own lookups found for
 * that need (find_intent_function, find_sdk_function), copied exactly: the compiler does not check targets, so a made-up
 * one compiles and does nothing. Every target in what it writes is checked against those found before it is served.
 */

import { FragmentSpec, StateFieldSpec } from '../VeraTemplates'
import { compileVeraSource, CompileError } from '../VeraCompiler'
import { smokeRun } from '../VeraSmoke'

/**
 * Asks the model for code: (system prompt, request, most tokens to write, whether it thinks first) -> its reply, or null
 * when there was none.
 */
export type CodeAsk = (system: string, user: string, budget: number, think: boolean) => Promise<string | null>

/** Room for one section with its handlers and view. */
export const SECTION_TOKENS: number = 3000
/** Room for a whole screen written as one section. */
export const SCREEN_TOKENS: number = 8000

const REPAIRS: number = 2
/** A thinking reply spends tokens on its reasoning before the section: this many times the budget. */
const THINKING_ROOM: number = 3

const CONTRACT: string = '\n\nNow you do not write a whole program. You add ONE section to a VERA-L program that already exists, ' +
  'and you write only that section, in exactly this form and nothing else:\n' +
  '<classes>\nany @jsonable record classes the section needs, or nothing\n</classes>\n' +
  '<fields>\none state field per line, as  name: type = initial value  (or nothing)\n</fields>\n' +
  '<functions>\nthe handlers and helper functions the section needs\n</functions>\n' +
  '<view>\nstatements that build the section and add it with sections.push(ui.Section(...));\n</view>\n' +
  'Rules for the section:\n' +
  '- Begin the name of every class, field and function with c_ (classes with C_), so nothing clashes with the program.\n' +
  '- A handler returns only the fields it changes, followed by __PASSTHROUGH__ just before the closing brace, which stands ' +
  'for every other field of the state kept as it is: return {c_count: state.c_count + 1__PASSTHROUGH__};\n' +
  '- The view statements run inside view(state): they may read any state field, but the local variables of the program\'s ' +
  'other sections are not visible there.\n' +
  '- Do not repeat, change or restyle anything the program already has. Do what the section must do, completely.\n'

/** What <cannot> holds: it is shown to the person on the screen, in place of what could not be built. */
const CANNOT_FORM: string = 'one short sentence for the person using the app, in plain words about their phone and its apps: ' +
  'what this app cannot do, and why (for example: This phone does not let apps set alarms in the Clock app.). Never mention ' +
  'the language, the section, sdk.call or code'

/** The rule for phone calls: none, or only the targets the phone's lookups found. */
function phoneRule(phone: string): string {
  if (phone.length === 0) {
    return '- The section never calls sdk.call: what the phone does is not its job.\n' +
      '- If the section cannot really do it with this language and these components -- it needs a camera, a live feed, ' +
      'the person\'s location or data the phone does not hold -- answer only <cannot>' + CANNOT_FORM + '</cannot>. Never fake it with made-up data.\n'
  }
  return '- What the phone or another app must do, the section does with sdk.call from a handler, calling ONLY targets from ' +
    '"Phone functions found" in the request, copied exactly, with the parameters they show, values from the screen\'s state. ' +
    'Its answer handler shows what came back: an answer starting with "declined" or "error" is a failure, anything else succeeded.\n' +
    '- If none of the phone functions found does what is needed, or it needs something the phone cannot give a program ' +
    '(a camera, a live feed, the person\'s location), answer only <cannot>' + CANNOT_FORM + '</cannot>. Never fake it, never pretend a call happened, ' +
    'never call a target that is not listed.\n'
}

/** The targets the phone's lookups found, as the "call" or "target" of each result. */
export function foundTargets(phone: string): string[] {
  let out: string[] = []
  let patterns: RegExp[] = [new RegExp('sdk\\.call\\(\\\\?"([^"\\\\]+)\\\\?"', 'g'), new RegExp('"target"\\s*:\\s*"([^"]+)"', 'g')]
  for (let pattern of patterns) {
    let m: RegExpExecArray | null = pattern.exec(phone)
    while (m !== null) {
      if (out.indexOf(m[1]) < 0) { out.push(m[1]) }
      m = pattern.exec(phone)
    }
  }
  return out
}

/** '' when every sdk.call in the reply calls a target found, else what is wrong. */
function callProblem(reply: string, found: string[]): string {
  let calls = reply.split('sdk.call(').length - 1
  if (calls === 0) { return '' }
  if (found.length === 0) { return 'The section calls sdk.call, which it never may: write it without phone calls, or answer <cannot>.' }
  let literal = new RegExp('sdk\\.call\\(\\s*"([^"]+)"', 'g')
  let named = 0
  let m: RegExpExecArray | null = literal.exec(reply)
  while (m !== null) {
    named++
    if (found.indexOf(m[1]) < 0) {
      return 'The section calls "' + m[1] + '", which is not one of the phone functions found. Call only those, copied exactly, or answer <cannot>.'
    }
    m = literal.exec(reply)
  }
  return named === calls ? '' : 'Every sdk.call names its target as a string literal copied from the phone functions found.'
}

export class CustomRequest {
  /** What the section must do, each in words. */
  needs: string[] = []
  /** The person's request. */
  prompt: string = ''
  /** Inputs on the screen nothing else reads, with the state field each is in: there for the section to use. */
  inputs: string[] = []
  /** The program for a given section ('' for none): the rest of the screen with that section after it. */
  compose: (section: FragmentSpec | null) => string = (_section: FragmentSpec | null): string => ''
  /** Other things the writer is told: the fixed numbers the plan names. */
  facts: string[] = []
  /** The phone's functions found for the needs that are something the phone does (the lookups' answers); '' for none. */
  phone: string = ''
  /** Jev, to read a section that compiles and runs against the needs; null serves it unread. */
  verify: ((body: string) => Promise<string>) | null = null
  /** The section is the whole screen: the program so far has nothing but its header. */
  whole: boolean = false
}

/** Jev reads the section against each need: a section that only says it cannot, or does something else, does not count. */
const DOES_ABOVE: number = 0.5

/** The Jev request: does the section, as written, do each need. */
export function verifyRequest(request: CustomRequest, reply: string): string {
  let questions: Record<string, Object> = {}
  for (let i = 0; i < request.needs.length; i++) {
    let criteria: Record<string, Object> = {}
    criteria['yes'] = 'yes: used as written, it really does that'
    criteria['no'] = 'no: it only says it cannot, asks the person to do it some other way, shows made-up data, or does something else'
    let q: Record<string, Object> = {}
    q['type'] = 'choice'
    q['instructions'] = 'Does this section of the app do "' + request.needs[i] + '"?'
    q['criteria'] = criteria
    questions['does.' + i.toString()] = q
  }
  let body: Record<string, Object> = {}
  body['model'] = 'jev-latest'
  // What the code does not show: the runtime keeps the app's state between visits by itself.
  body['state'] = 'Request: ' + request.prompt + '\nThe app\'s state (every field) is saved and restored by the phone between ' +
    'visits without any code for it.\nThe section, as code:\n' + reply
  body['questions'] = questions
  return JSON.stringify(body)
}

/** The needs Jev does not confidently read the section as doing; [] when it does all, or when there was no answer. */
export function undone(request: CustomRequest, answer: string): string[] {
  let out: string[] = []
  try {
    let answers = (JSON.parse(answer) as Record<string, Object>)['answers'] as Record<string, Object>
    for (let i = 0; i < request.needs.length; i++) {
      let a = answers['does.' + i.toString()] as Record<string, Object>
      let p = a !== undefined && a !== null ? (a['probabilities'] as Record<string, Object>) : null
      let yes = p !== null && p !== undefined && typeof p['yes'] === 'number' ? p['yes'] as number : 1
      if (yes < DOES_ABOVE) { out.push(request.needs[i]) }
    }
  } catch (_e) {
    return []
  }
  return out
}

export class CustomResult {
  /** The section that compiled and ran, null when none did. */
  section: FragmentSpec | null = null
  /** The writer's own sentence for the person when it answered that it cannot do it; '' otherwise. */
  cannot: string = ''
  /** The last try was made with thinking on. */
  thought: boolean = false
  /**
   * The needs Jev does not read `section` as doing, when no try did them all: the best section that compiles and runs is
   * served, and only these are reported. Empty when the section does everything.
   */
  missed: string[] = []
  /** Model calls made: the first and the repairs. */
  attempts: number = 0
  /** Why it did not work out, '' when it did. */
  failed: string = ''
  ms: number = 0
}

function between(text: string, tag: string): string | null {
  let open = text.indexOf('<' + tag + '>')
  let close = text.indexOf('</' + tag + '>')
  if (open < 0 || close < open) { return null }
  return text.substring(open + tag.length + 2, close).trim()
}

/** The reply as a block, or null when it is not in the form asked for. */
export function parseSection(reply: string): FragmentSpec | null {
  let functions = between(reply, 'functions')
  let view = between(reply, 'view')
  let fieldsText = between(reply, 'fields')
  if (functions === null || view === null || fieldsText === null) { return null }
  let classes = between(reply, 'classes') ?? ''
  if (classes.startsWith('any @jsonable') || classes === 'nothing') { classes = '' }
  let fields: StateFieldSpec[] = []
  let inits: string[] = []
  for (let line of fieldsText.split('\n')) {
    let text = line.trim()
    if (text.endsWith(';')) { text = text.substring(0, text.length - 1).trim() }
    if (text.length === 0 || text === 'nothing') { continue }
    let colon = text.indexOf(':')
    let equals = text.indexOf('=', colon + 1)
    if (colon <= 0 || equals <= colon) { return null }
    let name = text.substring(0, colon).trim()
    fields.push(new StateFieldSpec(name, text.substring(colon + 1, equals).trim()))
    inits.push(name + ': ' + text.substring(equals + 1).trim())
  }
  let spec = new FragmentSpec('custom', '', classes, fields, '', inits.join(', '), functions, '{\n' + view + '\n}', [], [])
  spec.indexed = false
  return spec
}

/** The diagnostics with the program line each one points at, so the repair sees what it wrote there. */
/**
 * How to fix a diagnostic the message alone does not say how to: a writer told only "expected View, found View[]" wrote
 * the same line four times over, thinking included.
 */
const FIXES: string[][] = [
  ['expected View, found View[]', 'a list of views is not one view: wrap it as ui.Column("default", theList)'],
  ['expected View[], found View', 'one view is not a list: put it in brackets, [theView]']
]

function quoted(source: string, errors: string): string {
  let lines = source.split('\n')
  let out: string[] = []
  for (let e of errors.split('\n')) {
    out.push(e)
    let colon = e.indexOf(':')
    let n = colon > 0 ? Number(e.substring(0, colon)) : NaN
    if (!isNaN(n) && n >= 1 && n <= lines.length) { out.push('    line ' + n.toString() + ': ' + lines[n - 1].trim()) }
    for (let fix of FIXES) { if (e.indexOf(fix[0]) >= 0) { out.push('    fix: ' + fix[1]) } }
  }
  return out.join('\n')
}

/** '' when the program compiles and runs, else what went wrong with the lines it points at. */
function check(source: string): string {
  try {
    let ran = smokeRun(compileVeraSource(source))
    return ran.length > 0 ? quoted(source, ran) : ''
  } catch (e) {
    let message = e instanceof CompileError ? (e as CompileError).message : (e as Error).message
    return quoted(source, message)
  }
}

export async function writeSection(request: CustomRequest, language: string, ask: CodeAsk): Promise<CustomResult> {
  let result = new CustomResult()
  let started = Date.now()
  let found = foundTargets(request.phone)
  let phone = found.length > 0 ? request.phone : ''
  let system = language + CONTRACT + phoneRule(phone)
  let asked = 'Request: ' + request.prompt + '\n\nThe section must do:\n- ' + request.needs.join('\n- ') +
    (request.inputs.length > 0 ? '\n\nThe person sets these on the screen and nothing else uses them yet; the section uses them:\n- ' +
      request.inputs.join('\n- ') : '') +
    (request.facts.length > 0 ? '\n\nFixed numbers the app uses:\n- ' + request.facts.join('\n- ') : '') +
    (phone.length > 0 ? '\n\nPhone functions found (the only targets the section may call):\n' + phone : '') +
    (request.whole ? '\n\nThe program has nothing yet but its header: your section is the whole screen, everything the request ' +
      'asks for. It may push several ui.Section(...) in its view.' : '') +
    '\n\nThe program so far, which the section joins (do not repeat it):\n' + request.compose(null)
  let user = asked
  // The best section that compiled and ran but that Jev reads as missing a need: kept, in case no try does them all.
  let best: FragmentSpec | null = null
  let bestMissed: string[] = []
  // The first try and its repairs without thinking, then one more with it: slower, for what the quick tries got wrong.
  for (let attempt = 0; attempt <= REPAIRS + 1; attempt++) {
    let think = attempt > REPAIRS
    result.attempts = attempt + 1
    result.thought = think
    let budget = request.whole ? SCREEN_TOKENS : SECTION_TOKENS
    let reply = await ask(system, user, think ? budget * THINKING_ROOM : budget, think)
    if (reply === null) { result.failed = 'no answer for the custom section'; break }
    let cannot = between(reply, 'cannot')
    if (cannot !== null) { result.cannot = cannot; result.failed = 'custom section cannot: ' + cannot; break }
    let section = parseSection(reply)
    // A phone call the section makes up compiles and does nothing: its targets are not checked until the phone answers.
    let calls = section === null ? '' : callProblem(reply, found)
    let problem = section === null ? 'The answer was not in the form asked for: <classes>, <fields>, <functions> and <view>.' :
      (calls.length > 0 ? calls : check(request.compose(section)))
    if (problem.length === 0) {
      // It compiles and runs; whether it does what it is for is Jev's reading. One it reads as not doing a need is asked
      // for again, saying which.
      let missed: string[] = request.verify !== null ? undone(request, await request.verify!(verifyRequest(request, reply))) : []
      if (missed.length === 0) {
        result.section = section
        result.failed = ''
        break
      }
      result.failed = 'custom section does not do: ' + missed.join('; ')
      // One Jev reads as doing none of it is no part of the screen.
      if (missed.length < request.needs.length && (best === null || missed.length < bestMissed.length)) {
        best = section
        bestMissed = missed
      }
      problem = 'Read against the request, it does not do: ' + missed.join('; ') + '. It must really do that, used as written -- ' +
        'or, if it cannot be done here, answer <cannot>.'
    } else {
      result.failed = 'custom section: ' + problem.split('\n')[0]
    }
    user = asked + '\n\nYour section was:\n' + reply + '\n\nIt failed:\n' + problem + '\n\nWrite the whole section again, fixed, in the same form.'
  }
  // No try did everything, but one works and does part of it: that one is served, and what it misses is reported.
  if (result.section === null && result.cannot.length === 0 && best !== null) {
    result.section = best
    result.missed = bestMissed
    result.failed = 'custom section does not do: ' + bestMissed.join('; ')
  }
  result.ms = Date.now() - started
  return result
}
