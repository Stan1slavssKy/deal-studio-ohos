/**
 * The custom section: what neither the composition's own parts nor a section of the catalogue does, written by the
 * model as one block of the program -- its state fields, its handlers, its view -- into the program the rest already
 * makes, and settled like any block: compiled, then run once with every handler tapped (VeraSmoke.ets), with the
 * failing lines quoted back for a repair, at most twice. The model sees the language as generation does (the host's
 * skill prompt) and writes only the missing piece, so it is small and its names are its own (c_...).
 */

import { FragmentSpec, StateFieldSpec } from '../VeraTemplates'
import { compileVeraSource, CompileError } from '../VeraCompiler'
import { smokeRun } from '../VeraSmoke'

/** Asks the model for code: (system prompt, request) -> its reply, or null when there was none. */
export type CodeAsk = (system: string, user: string) => Promise<string | null>

const REPAIRS: number = 2

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
  '- Do not repeat, change or restyle anything the program already has. Do what the section must do, completely.\n' +
  '- The section never calls sdk.call: what the phone does is not its job.\n' +
  '- If the section cannot really do it with this language and these components -- it needs a camera, a live feed, ' +
  'the person\'s location or data the phone does not hold -- answer only <cannot>why</cannot>. Never fake it with made-up data.\n'

export class CustomRequest {
  /** What the section must do, each in words. */
  needs: string[] = []
  /** The person's request. */
  prompt: string = ''
  /** The program for a given section ('' for none): the rest of the screen with that section after it. */
  compose: (section: FragmentSpec | null) => string = (_section: FragmentSpec | null): string => ''
  /** Jev, to read a section that compiles and runs against the needs; null serves it unread. */
  verify: ((body: string) => Promise<string>) | null = null
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
  body['state'] = 'Request: ' + request.prompt + '\nThe section, as code:\n' + reply
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
function quoted(source: string, errors: string): string {
  let lines = source.split('\n')
  let out: string[] = []
  for (let e of errors.split('\n')) {
    out.push(e)
    let colon = e.indexOf(':')
    let n = colon > 0 ? Number(e.substring(0, colon)) : NaN
    if (!isNaN(n) && n >= 1 && n <= lines.length) { out.push('    line ' + n.toString() + ': ' + lines[n - 1].trim()) }
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
  let system = language + CONTRACT
  let asked = 'Request: ' + request.prompt + '\n\nThe section must do:\n- ' + request.needs.join('\n- ') +
    '\n\nThe program so far, which the section joins (do not repeat it):\n' + request.compose(null)
  let user = asked
  for (let attempt = 0; attempt <= REPAIRS; attempt++) {
    result.attempts = attempt + 1
    let reply = await ask(system, user)
    if (reply === null) { result.failed = 'no answer for the custom section'; break }
    let cannot = between(reply, 'cannot')
    if (cannot !== null) { result.failed = 'custom section cannot: ' + cannot; break }
    let section = parseSection(reply)
    // A phone call the section makes up compiles and does nothing: its targets are not checked until the phone answers.
    let problem = section === null ? 'The answer was not in the form asked for: <classes>, <fields>, <functions> and <view>.' :
      (reply.indexOf('sdk.call') >= 0 ? 'The section calls sdk.call, which it never may: write it without phone calls, or answer <cannot>.' :
      check(request.compose(section)))
    if (problem.length === 0) {
      // It compiles and runs; whether it does what it is for is Jev's reading, and a section that does not is refused,
      // not repaired: the model has already said what it can do.
      let missed: string[] = request.verify !== null ? undone(request, await request.verify!(verifyRequest(request, reply))) : []
      if (missed.length > 0) { result.failed = 'custom section does not do: ' + missed.join('; '); break }
      result.section = section
      result.failed = ''
      break
    }
    result.failed = 'custom section: ' + problem.split('\n')[0]
    user = asked + '\n\nYour section was:\n' + reply + '\n\nIt failed:\n' + problem + '\n\nWrite the whole section again, fixed, in the same form.'
  }
  result.ms = Date.now() - started
  return result
}
