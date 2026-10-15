/**
 * Experiment only (experiment/jev-template-select branch): the dynamic-composition counterpart
 * to VeraTemplateSelect.ets. Instead of picking one of two whole-screen TemplateSpecs,
 * selectSections() asks Jev, in one batched request, which FragmentSpec (VeraTemplates.ets) goes
 * in each of SECTION_COUNT ordered slots -- or 'none' for an empty slot -- then composeProgram()
 * assembles the chosen fragments into one `.vera` program for compileVeraSource.
 *
 * Why a composer instead of TemplateSpec's plain substitute(): a fragment is not a whole program,
 * it is one piece (state fields, an init() contribution, handler function(s), one view() block)
 * that has to be merged with zero or more other fragments' pieces into a single AppState/init/
 * view. Two mechanics make that merge safe:
 *
 * - Every fragment's state field and function names contain the literal substring "IDX",
 *   replaced here with the fragment's 1-based slot number, so two instances of the same kind
 *   (e.g. two `metrics` sections) never collide.
 * - Vera has no object-spread, so every fragment's update function must return the *entire*
 *   AppState literally. A fragment's `functions` text therefore carries one `__PASSTHROUGH__`
 *   token, filled in here with `, otherField: state.otherField` for every *other* chosen
 *   fragment's state fields -- the only piece of this merge a fragment cannot write for itself,
 *   because only the composer knows the full set of fragments present in a given composition.
 *
 * Everything else a fragment's view() block computes (loop counters, row arrays, local flags)
 * needs no indexing or pass-through at all: each fragment's viewBlock is wrapped in its own bare
 * `{ ... }` statement, and VeraCompiler.ets's checkBlock gives every such block its own child
 * Scope, so sibling blocks' same-named locals never collide -- confirmed by the host compile
 * sweep (tools/..., see conversation history) before this file was written, not assumed.
 *
 * Mirrors VeraTemplateSelect.ets's shape throughout: one POST, never throws, any doubt falls back
 * to a null pick so the caller falls straight through to normal generation. Vetoes are the same
 * VeraTemplates.vetoes() list, asked once per request regardless of composition, with the same
 * meaning (a capability gate on the whole request) -- `needs_multiple_counters` still exists
 * unchanged for now; its wording only needs to stop treating two counters as automatically
 * disqualifying once this lands and is verified (see the plan), not before.
 */

import http from '@ohos.net.http'
import hilog from '@ohos.hilog'
import { FragmentSpec, StateFieldSpec, SlotSpec, VetoSpec, ContentFieldSpec, fragments, vetoes, bannerSectionView } from './VeraTemplates'

const DOMAIN = 0x0000
const ENDPOINT: string = 'https://api.typesafe.ai/v1/systemone'
const MODEL: string = 'jev-latest'

/** Ordered section slots composed into one screen. Small and bounded -- see this file's header comment and the plan's "no per-node round trips" non-goal. */
const SECTION_COUNT: number = 4

/** Top-level bar for a section's fragment-kind choice: a wrong answer here skips that slot entirely. */
const SECTION_PICK_ABOVE: number = 0.5
/** Per-slot cosmetic bar, same role as VeraTemplateSelect.ets's SLOT_PICK_ABOVE. */
const SLOT_PICK_ABOVE: number = 0.25

/**
 * Vetoes that no longer drop a request to generation from scratch: whatever they flag (a calculation,
 * a form, a search, a second counter, a phone API) is something the model can add on top of a
 * composed base, so Jev still picks the visual structure. Measured on the gold sets
 * (eval/results/2026-10-15-jev-baseline.json): with every veto hard, 23 of 49 prompts left the
 * template path, 12 of them on needs_search_or_form alone.
 */
const SOFT_VETOES: string[] = ['needs_integration', 'needs_search_or_form', 'needs_multiple_counters', 'needs_live_ticking', 'needs_logic']
/**
 * Above this probability needs_integration stays a hard veto: a request that is mostly a phone API or
 * another app (camera, video call, navigation) has no fragment worth keeping as a base. The baseline's
 * camera-app, video-call, shanghai-layover and map-restaurants all sit at 0.90 or more.
 */
const INTEGRATION_HARD_ABOVE: number = 0.9
/**
 * A soft veto starts a model call instead of ending the template path, so it must be surer than the
 * old reject-and-regenerate bars (0.3 to 0.65) were: "Grocery list app" scored needs_search_or_form
 * 0.61 against a 0.6 bar and would have paid for a completion it does not need. Floor for the vetoes
 * whose old bars were low; needs_integration keeps its own bar, because a model that adds the phone
 * call is exactly what those requests need.
 */
const SOFT_MIN_ABOVE: number = 0.7
const SOFT_FLOORED: string[] = ['needs_search_or_form', 'needs_live_ticking', 'needs_multiple_counters']

const GLOBAL_THEME_VALUES: string[] = ['clean', 'soft', 'expressive', 'editorial', 'technical', 'playful']

function globalThemeCriteria(): Map<string, string> {
  let m: Map<string, string> = new Map<string, string>()
  m.set('clean', 'restrained and neutral')
  m.set('soft', 'calm and friendly')
  m.set('expressive', 'bold and atmospheric')
  m.set('editorial', 'text-forward, magazine-like')
  m.set('technical', 'dense, precise numbers')
  m.set('playful', 'energetic')
  return m
}

function globalHeaderStyleCriteria(): Map<string, string> {
  let m: Map<string, string> = new Map<string, string>()
  m.set('default', 'left-aligned')
  m.set('center', 'centered')
  return m
}

function globalBannerCriteria(): Map<string, string> {
  let m: Map<string, string> = new Map<string, string>()
  m.set('true', 'yes, show one')
  m.set('false', 'no')
  return m
}

/** One section slot's outcome: a chosen kind (with its slot values, tokens still containing "IDX") or 'none'. */
export class SectionPick {
  kind: string
  /** token (containing "IDX") -> chosen value; empty when kind is 'none'. */
  slotValues: Map<string, string>
  constructor(kind: string, slotValues: Map<string, string>) {
    this.kind = kind
    this.slotValues = slotValues
  }
}

/** Every outcome of selectSections, mirroring VeraTemplateSelect.ets's PickOutcome. */
export class SectionPickOutcome {
  /** null when every slot is 'none', vetoed, or any doubt makes the whole composition unsafe to attempt. */
  sections: SectionPick[] | null
  /** Global (not per-slot) cosmetic choices: "__THEME__", "__HEADER_STYLE__", "__BANNER_SECTION__". */
  globalValues: Map<string, string>
  note: string
  /**
   * True only when needs_real_data alone cleared its bar (no other veto did) and fragment-picking
   * ran anyway -- the caller should ground content-fill in one web search rather than treating
   * this as a hard veto.
   */
  needsRealData: boolean
  /**
   * True when one or more soft vetoes (SOFT_VETOES) fired: the sections are still a good visual
   * base, but the request also needs behaviour no fragment has. The caller composes the base and
   * hands it to the model to finish, instead of dropping to generation from scratch.
   */
  needsLogic: boolean
  constructor(sections: SectionPick[] | null, globalValues: Map<string, string>, note: string, needsRealData: boolean = false,
      needsLogic: boolean = false) {
    this.sections = sections
    this.globalValues = globalValues
    this.note = note
    this.needsRealData = needsRealData
    this.needsLogic = needsLogic
  }
}

function criteriaRecord(criteria: Map<string, string>): Record<string, Object> {
  let out: Record<string, Object> = {}
  criteria.forEach((text: string, key: string) => { out[key] = text })
  return out
}

/** "__LIST_STYLE_IDX__" -> "list_style"; the request/response key suffix for a per-slot cosmetic SlotSpec. */
function slotKey(token: string): string {
  let trimmed = token
  if (trimmed.startsWith('__')) { trimmed = trimmed.substring(2) }
  if (trimmed.endsWith('__')) { trimmed = trimmed.substring(0, trimmed.length - 2) }
  trimmed = trimmed.split('_IDX').join('')
  return trimmed.toLowerCase()
}

/**
 * One batched request: a `choice` for every section slot (which fragment kind, or none), every
 * kind's own cosmetic slots for every slot (asked regardless of outcome, same "ask everything"
 * pattern VeraTemplateSelect.ets's buildSelectRequest already uses), the three global cosmetic
 * choices, and the veto questions. A second call per slot would spend the latency this approach
 * exists to save.
 */
export function buildSectionRequest(prompt: string): string {
  let specs = fragments()
  let questions: Record<string, Object> = {}

  let kindCriteria: Record<string, Object> = {}
  for (let spec of specs) { kindCriteria[spec.kind] = spec.criteria }
  kindCriteria['none'] = 'nothing is needed in this part of the screen'

  for (let i = 1; i <= SECTION_COUNT; i++) {
    let question: Record<string, Object> = {}
    question['type'] = 'choice'
    question['instructions'] = 'What belongs in section ' + i.toString() + ' of the screen (in top-to-bottom order)? ' +
      'Answer none if this section is not needed, or if what is needed is anything beyond generic ' +
      'placeholder content and simple taps -- search, forms, or calling any ' +
      'phone API, SDK function or other app. A specific real-world fact, price, or figure is fine to ' +
      'show as a plain labelled number or short fact, even though its exact value is not known yet -- ' +
      'so is a simple chart of a handful of data points.'
    question['criteria'] = kindCriteria
    questions['section' + i.toString()] = question

    for (let spec of specs) {
      for (let slot of spec.slots) {
        let slotQuestion: Record<string, Object> = {}
        slotQuestion['type'] = slot.kind
        slotQuestion['instructions'] = slot.instructions
        slotQuestion['criteria'] = criteriaRecord(slot.criteria)
        questions['section' + i.toString() + '.' + spec.kind + '.' + slotKey(slot.token)] = slotQuestion
      }
    }
  }

  let themeQuestion: Record<string, Object> = {}
  themeQuestion['type'] = 'choice'
  themeQuestion['instructions'] = 'Which overall look fits best for the whole screen?'
  themeQuestion['criteria'] = criteriaRecord(globalThemeCriteria())
  questions['__THEME__'] = themeQuestion

  let headerQuestion: Record<string, Object> = {}
  headerQuestion['type'] = 'choice'
  headerQuestion['instructions'] = 'Should the title block be left-aligned (default) or centered?'
  headerQuestion['criteria'] = criteriaRecord(globalHeaderStyleCriteria())
  questions['__HEADER_STYLE__'] = headerQuestion

  let bannerQuestion: Record<string, Object> = {}
  bannerQuestion['type'] = 'noul'
  bannerQuestion['instructions'] = 'Does this app need a standing info note visible at all times?'
  bannerQuestion['criteria'] = criteriaRecord(globalBannerCriteria())
  questions['__BANNER_SECTION__'] = bannerQuestion

  for (let veto of vetoes()) {
    let question: Record<string, Object> = {}
    question['type'] = 'noul'
    question['instructions'] = veto.instructions
    question['criteria'] = criteriaRecord(veto.criteria)
    questions['veto.' + veto.key] = question
  }

  let body: Record<string, Object> = {}
  body['model'] = MODEL
  body['state'] = prompt
  body['questions'] = questions
  return JSON.stringify(body)
}

function findFragment(specs: FragmentSpec[], kind: string): FragmentSpec | null {
  for (let spec of specs) { if (spec.kind === kind) { return spec } }
  return null
}

function readChoiceValue(answers: Record<string, Object>, key: string, allowed: string[], above: number, fallback: string): string {
  let raw = answers[key]
  if (raw === null || raw === undefined) { return fallback }
  let answer = raw as Record<string, Object>
  let choice = answer['choice']
  if (choice === null || choice === undefined || typeof choice !== 'string') { return fallback }
  let picked = choice as string
  if (allowed.indexOf(picked) < 0) { return fallback }
  let confidence = answer['confidence']
  let sure = confidence !== null && confidence !== undefined && typeof confidence === 'number' ? confidence as number : 1
  if (sure < above) { return fallback }
  return picked
}

function readNoulValue(answers: Record<string, Object>, key: string, above: number): boolean {
  let raw = answers[key]
  if (raw === null || raw === undefined) { return false }
  let answer = raw as Record<string, Object>
  let value = answer['noul']
  if (value === null || value === undefined || typeof value !== 'number') { return false }
  return (value as number) > above
}

function readSlotValue(answers: Record<string, Object>, slotIndex: number, kind: string, slot: SlotSpec): string {
  let key = 'section' + slotIndex.toString() + '.' + kind + '.' + slotKey(slot.token)
  let fallback = slot.values[0]
  let raw = answers[key]
  if (raw === null || raw === undefined) { return fallback }
  let answer = raw as Record<string, Object>
  if (slot.kind === 'noul') {
    let value = answer['noul']
    if (value === null || value === undefined || typeof value !== 'number') { return fallback }
    return (value as number) > SLOT_PICK_ABOVE ? slot.values[1] : slot.values[0]
  }
  let choice = answer['choice']
  if (choice === null || choice === undefined || typeof choice !== 'string') { return fallback }
  let picked = choice as string
  if (slot.values.indexOf(picked) < 0) { return fallback }
  let confidence = answer['confidence']
  let sure = confidence !== null && confidence !== undefined && typeof confidence === 'number' ? confidence as number : 1
  if (sure < SLOT_PICK_ABOVE) { return fallback }
  return picked
}

/** Missing/unreadable is treated as triggered (1), not 0 -- same rule as VeraTemplateSelect.ets's readVetoProbability. */
function readVetoProbability(answers: Record<string, Object>, veto: VetoSpec): number {
  let raw = answers['veto.' + veto.key]
  if (raw === null || raw === undefined) { return 1 }
  let answer = raw as Record<string, Object>
  let value = answer['noul']
  if (value === null || value === undefined || typeof value !== 'number') { return 1 }
  return value as number
}

/**
 * Interprets Jev's answer. Any doubt (unreadable JSON, a tripped veto) returns a null `sections`
 * list so the caller falls through to normal generation -- same contract as
 * VeraTemplateSelect.ets's readPick. A single slot landing on 'none' or low confidence is not
 * doubt about the *whole* request; it just leaves that slot empty, same as a single bad cosmetic
 * slot answer falling back to its default.
 */
export function readSectionPick(body: string): SectionPickOutcome {
  let specs = fragments()
  let emptyGlobals: Map<string, string> = new Map<string, string>()
  let answers: Record<string, Object> = {}
  try {
    let parsed = JSON.parse(body) as Record<string, Object>
    let found = parsed['answers']
    if (found === null || found === undefined) { return new SectionPickOutcome(null, emptyGlobals, 'none (no answers)') }
    answers = found as Record<string, Object>
  } catch (_e) {
    return new SectionPickOutcome(null, emptyGlobals, 'none (answer unreadable)')
  }

  let vetoNotes: string[] = []
  let logicNotes: string[] = []
  let needsRealData = false
  let realDataProbability = 0
  for (let veto of vetoes()) {
    let probability = readVetoProbability(answers, veto)
    let bar = SOFT_FLOORED.indexOf(veto.key) >= 0 ? Math.max(veto.above, SOFT_MIN_ABOVE) : veto.above
    if (probability > bar) {
      let tag = veto.key + '=' + probability.toFixed(2)
      if (veto.key === 'needs_real_data') {
        needsRealData = true
        realDataProbability = probability
      } else if (SOFT_VETOES.indexOf(veto.key) >= 0 && !(veto.key === 'needs_integration' && probability >= INTEGRATION_HARD_ABOVE)) {
        logicNotes.push(tag)
      } else {
        vetoNotes.push(tag)
      }
    }
  }
  if (vetoNotes.length > 0) {
    let note = 'vetoed ' + vetoNotes.join(' ')
    if (needsRealData) { note = note + ' needs_real_data=' + realDataProbability.toFixed(2) }
    return new SectionPickOutcome(null, emptyGlobals, note)
  }

  let kindIds: string[] = []
  for (let spec of specs) { kindIds.push(spec.kind) }
  let allowedKinds: string[] = kindIds.concat(['none'])

  let picks: SectionPick[] = []
  let notes: string[] = []
  for (let i = 1; i <= SECTION_COUNT; i++) {
    let kind = readChoiceValue(answers, 'section' + i.toString(), allowedKinds, SECTION_PICK_ABOVE, 'none')
    if (kind === 'none') {
      picks.push(new SectionPick('none', new Map<string, string>()))
      notes.push('section' + i.toString() + '=none')
      continue
    }
    let spec = findFragment(specs, kind)
    if (spec === null) {
      picks.push(new SectionPick('none', new Map<string, string>()))
      notes.push('section' + i.toString() + '=none(unknown)')
      continue
    }
    // Jev answers every slot independently, and for a plain list it said "checklist" twice in 10 of
    // 11 baseline prompts -- two identical lists on screen. A kind already placed above is dropped.
    let repeated = false
    for (let earlier of picks) { if (earlier.kind === kind) { repeated = true } }
    if (repeated) {
      picks.push(new SectionPick('none', new Map<string, string>()))
      notes.push('section' + i.toString() + '=none(duplicate ' + kind + ')')
      continue
    }
    let slotValues: Map<string, string> = new Map<string, string>()
    for (let slot of spec.slots) {
      slotValues.set(slot.token, readSlotValue(answers, i, kind, slot))
    }
    picks.push(new SectionPick(kind, slotValues))
    notes.push('section' + i.toString() + '=' + kind)
  }

  let anyChosen = false
  for (let pick of picks) { if (pick.kind !== 'none') { anyChosen = true } }
  if (!anyChosen) {
    return new SectionPickOutcome(null, emptyGlobals, 'none (' + notes.join(' ') + ')')
  }

  // A chosen search_list already is the search a needs_search_or_form veto asks for; keeping the veto
  // would pay for a model completion that adds nothing.
  let hasSearchList = false
  for (let pick of picks) { if (pick.kind === 'search_list') { hasSearchList = true } }
  if (hasSearchList) {
    let kept: string[] = []
    for (let tag of logicNotes) { if (!tag.startsWith('needs_search_or_form=')) { kept.push(tag) } }
    logicNotes = kept
  }

  let globals: Map<string, string> = new Map<string, string>()
  globals.set('__THEME__', readChoiceValue(answers, '__THEME__', GLOBAL_THEME_VALUES, SLOT_PICK_ABOVE, 'clean'))
  globals.set('__HEADER_STYLE__', readChoiceValue(answers, '__HEADER_STYLE__', ['default', 'center'], SLOT_PICK_ABOVE, 'default'))
  globals.set('__BANNER_SECTION__', readNoulValue(answers, '__BANNER_SECTION__', SLOT_PICK_ABOVE) ? 'show' : 'hide')

  let note = notes.join(' ')
  if (needsRealData) { note = note + ' needs_real_data=' + realDataProbability.toFixed(2) }
  if (logicNotes.length > 0) { note = note + ' logic=' + logicNotes.join(',') }
  return new SectionPickOutcome(picks, globals, note, needsRealData, logicNotes.length > 0)
}

/**
 * Assembles one `.vera` program from the chosen fragments. Both `chosenKinds` and
 * `instanceValues` are indexed by *original* slot position (0-based here, 1-based in the
 * generated identifiers) -- a 'none'/unknown slot is simply skipped, it does not shift later
 * slots' instance numbers or `instanceValues` indices. This matters because a caller naturally
 * builds `instanceValues` the same way SectionPickOutcome.sections and
 * VeraTemplateContent.ets's SectionContentFillResult.instanceValues already are: one entry per
 * slot, including empty entries for 'none' slots, never compacted. Content tokens come from
 * VeraTemplateContent.ets's content-fill the same way they do for a flat TemplateSpec, just keyed
 * per slot instance.
 */
/**
 * Resolves "IDX" to a slot's instance number, then applies every one of that slot's own
 * slot/content token->value substitutions. Used by composeProgram for every per-instance text
 * piece (initStatements, functions, viewBlock alike) -- a content token like "__ITEM1_IDX__" can
 * live in any of them (checklist's item labels are built in init()'s initStatements, not view()),
 * so substitution cannot be limited to just the view block. Module-level, not nested inside
 * composeProgram -- ArkTS does not support nested functions (arkts-no-nested-funcs).
 */
function resolveInstanceText(text: string, idx: string, values: Map<string, string> | undefined): string {
  let resolved = text.split('IDX').join(idx)
  if (values !== undefined) {
    values.forEach((value: string, token: string) => {
      let resolvedToken = token.split('IDX').join(idx)
      resolved = resolved.split(resolvedToken).join(value)
    })
  }
  return resolved
}

export function composeProgram(chosenKinds: string[], globalValues: Map<string, string>, instanceValues: Map<string, string>[]): string {
  let allSpecs = fragments()
  /** specAt[i] is null for a 'none'/unknown slot i; every other array below is indexed the same way, by original slot position. */
  let specAt: (FragmentSpec | null)[] = []
  for (let kind of chosenKinds) { specAt.push(findFragment(allSpecs, kind)) }

  let supportClasses: string[] = []
  let extraImports: string[] = []
  for (let spec of specAt) {
    if (spec === null) { continue }
    if (spec.supportClass.length > 0 && supportClasses.indexOf(spec.supportClass) < 0) {
      supportClasses.push(spec.supportClass)
    }
    for (let imp of spec.imports) {
      if (extraImports.indexOf(imp) < 0) { extraImports.push(imp) }
    }
  }

  let allFieldNames: string[][] = []
  let classFieldLines: string[] = []
  for (let i = 0; i < specAt.length; i++) {
    let spec = specAt[i]
    let idx = (i + 1).toString()
    let names: string[] = []
    if (spec !== null) {
      for (let field of spec.stateFields) {
        let name = field.name.split('IDX').join(idx)
        names.push(name)
        classFieldLines.push('  ' + name + ': ' + field.type + ';')
      }
    }
    allFieldNames.push(names)
  }

  let initStatementLines: string[] = []
  let initEntryParts: string[] = []
  for (let i = 0; i < specAt.length; i++) {
    let spec = specAt[i]
    if (spec === null) { continue }
    let idx = (i + 1).toString()
    if (spec.initStatements.length > 0) { initStatementLines.push(resolveInstanceText(spec.initStatements, idx, instanceValues[i])) }
    if (spec.initEntries.length > 0) { initEntryParts.push(spec.initEntries.split('IDX').join(idx)) }
  }

  let functionBlocks: string[] = []
  for (let i = 0; i < specAt.length; i++) {
    let spec = specAt[i]
    if (spec === null) { continue }
    let idx = (i + 1).toString()
    let passthrough = ''
    for (let j = 0; j < specAt.length; j++) {
      if (j === i) { continue }
      for (let name of allFieldNames[j]) { passthrough = passthrough + ', ' + name + ': state.' + name }
    }
    let fn = resolveInstanceText(spec.functions, idx, instanceValues[i])
    fn = fn.split('__PASSTHROUGH__').join(passthrough)
    functionBlocks.push(fn)
  }

  let viewBlocks: string[] = []
  for (let i = 0; i < specAt.length; i++) {
    let spec = specAt[i]
    if (spec === null) { continue }
    let idx = (i + 1).toString()
    let block = resolveInstanceText(spec.viewBlock, idx, instanceValues[i])
    viewBlocks.push(block)
  }

  let bannerShow = globalValues.get('__BANNER_SECTION__') === 'show'
  let theme = globalValues.get('__THEME__')
  if (theme === undefined) { theme = 'clean' }
  let headerStyle = globalValues.get('__HEADER_STYLE__')
  if (headerStyle === undefined) { headerStyle = 'default' }
  let title = globalValues.get('__TITLE__')
  if (title === undefined) { title = '' }

  let lines: string[] = []
  lines.push('import * as ui from "std/ui"')
  for (let imp of extraImports) { lines.push(imp) }
  lines.push('')
  for (let sc of supportClasses) { lines.push(sc); lines.push('') }
  lines.push('@jsonable')
  lines.push('class AppState {')
  for (let l of classFieldLines) { lines.push(l) }
  lines.push('}')
  lines.push('')
  lines.push('function init(): AppState {')
  for (let l of initStatementLines) { lines.push(l) }
  lines.push('  return {' + initEntryParts.join(', ') + '};')
  lines.push('}')
  lines.push('')
  for (let fb of functionBlocks) { lines.push(fb); lines.push('') }
  lines.push('function view(state: AppState): ui.View {')
  lines.push('  let sections: ui.View[] = [];')
  lines.push('  sections.push(ui.Header("' + headerStyle + '", "' + title + '", "", "", "check"));')
  for (let vb of viewBlocks) { lines.push('  ' + vb.split('\n').join('\n  ')) }
  if (bannerShow) { lines.push('  sections.push(' + bannerSectionView() + ');') }
  lines.push('  return ui.AppTheme("' + theme + '", "", sections);')
  lines.push('}')
  return lines.join('\n')
}

/**
 * Live call. Never throws and never rejects -- a selector that cannot answer must not stop
 * generation, same rule VeraTemplateSelect.ets's selectTemplate and JevSelector.ets follow.
 */
export async function selectSections(prompt: string, apiKey: string): Promise<SectionPickOutcome> {
  let emptyGlobals: Map<string, string> = new Map<string, string>()
  if (apiKey.length === 0 || prompt.trim().length === 0) { return new SectionPickOutcome(null, emptyGlobals, 'none (no key or prompt)') }
  let client = http.createHttp()
  try {
    let headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + apiKey
    let started = Date.now()
    let response = await client.request(ENDPOINT, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: buildSectionRequest(prompt),
      connectTimeout: 5000,
      readTimeout: 15000
    })
    let code = response.responseCode as number
    if (code !== 200) {
      hilog.warn(DOMAIN, 'VERA', 'VERA-SECTIONS http ' + code.toString())
      return new SectionPickOutcome(null, emptyGlobals, 'none (selector answered ' + code.toString() + ')')
    }
    let outcome = readSectionPick(response.result as string)
    hilog.info(DOMAIN, 'VERA', 'VERA-SECTIONS ms=' + (Date.now() - started).toString() + ' picked=' + outcome.note)
    return outcome
  } catch (e) {
    hilog.warn(DOMAIN, 'VERA', 'VERA-SECTIONS failed: ' + (e as Error).message)
    return new SectionPickOutcome(null, emptyGlobals, 'none (selector unreachable)')
  } finally {
    client.destroy()
  }
}
