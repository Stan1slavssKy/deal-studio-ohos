/**
 * Experiment only (experiment/jev-template-select branch): asks Jev,
 * TypeSafe's System One model, to pick one of VeraTemplates.ets's two
 * hand-written `.vera` screens for a request, instead of generating one.
 *
 * Same endpoint and client shape as JevSelector.ets, which this file is
 * deliberately modeled on rather than reinventing: one POST,
 * never throws, any doubt falls back to null so the caller
 * (GeneratePage.tryTemplateSelect) falls straight through to the normal
 * generation path. JevSelector.ets itself is untouched; nothing here calls
 * it and nothing it does calls this.
 *
 * Known, permanent limitation of Jev itself: it answers only 'choice' (one
 * label from a closed set), 'noul' (yes/no as a probability) and 'score'
 * questions -- it cannot free-write a title or any other open text. Every
 * slot in both templates is therefore a cosmetic choice (theme, density,
 * header style, whether a fixed banner shows), never something derived from
 * the user's own wording, and that part of this file is unaffected by what
 * follows. The title and item/label text themselves (VeraTemplates.ets's
 * ContentFieldSpec) are filled separately, best-effort, by
 * VeraTemplateContent.ets's own narrow generative call -- a different model,
 * not Jev -- which runs only after this file's selectTemplate() has already
 * returned a non-null pick, and which degrades field-by-field to today's
 * literal copy ("Checklist", "Demo Dashboard", ...) on any failure. Nothing
 * in this file calls it or depends on it.
 *
 * The top-level `template` choice is a shape match against a one-line
 * description, not a check of feature coverage: a request can look list-
 * shaped or number-shaped while also needing real data, search, or a phone
 * API neither template can provide (confirmed live -- a detailed itinerary
 * brief asking for real navigation/calendar SDK calls still matched
 * `list_detail` at 0.95 confidence). VeraTemplates.vetoes() adds three
 * shared yes/no questions, asked once per request regardless of which
 * template matched, that veto the pick outright on a "yes" -- see readPick.
 * This is a semantic gate (another classifier judgment on top of the first),
 * not a structural one (deal-embedding's own `isCatalogue()`/`isPreparation()`
 * check real SDK function signatures, which only makes sense when a template
 * actually wires in a discovered capability; these two templates call
 * nothing, so there is no signature to check against).
 */

import http from '@ohos.net.http'
import hilog from '@ohos.hilog'
import { TemplateSpec, SlotSpec, VetoSpec, templates, vetoes, bannerLiteral } from './VeraTemplates'

const DOMAIN = 0x0000
const ENDPOINT: string = 'https://api.typesafe.ai/v1/systemone'
const MODEL: string = 'jev-latest'

/** Top-level template pick: a wrong answer here skips generation entirely, so the bar is higher than a slot's. */
const PICK_ABOVE: number = 0.5
/** Per-slot bar, same as JevSelector.ets's intent PICK_ABOVE -- a miss here only loses a cosmetic default. */
const SLOT_PICK_ABOVE: number = 0.25

export class TemplatePick {
  templateId: string
  /** token -> chosen value, e.g. "__THEME__" -> "soft". */
  slotValues: Map<string, string>
  /** What to put in the status line. */
  note: string
  constructor(templateId: string, slotValues: Map<string, string>, note: string) {
    this.templateId = templateId
    this.slotValues = slotValues
    this.note = note
  }
}

/**
 * Every outcome of readPick, not just an accepted one, so the caller's
 * status line can say *why* a request fell through to normal generation
 * instead of just "none" -- especially for a veto, where knowing which
 * question fired (and at what probability) is the only way to tell a
 * wrongly-cautious veto from a correctly-cautious one without re-deriving it
 * from scratch each time.
 */
export class PickOutcome {
  pick: TemplatePick | null
  /** Always set, even on rejection, e.g. "none (Jev said none)", "vetoed needs_integration=0.80 (would have been list_detail 0.95)". */
  note: string
  constructor(pick: TemplatePick | null, note: string) {
    this.pick = pick
    this.note = note
  }
}

/** "__HEADER_STYLE__" -> "header_style"; the request/response key suffix for a slot. */
function slotKey(token: string): string {
  let trimmed = token
  if (trimmed.startsWith('__')) { trimmed = trimmed.substring(2) }
  if (trimmed.endsWith('__')) { trimmed = trimmed.substring(0, trimmed.length - 2) }
  return trimmed.toLowerCase()
}

function criteriaRecord(criteria: Map<string, string>): Record<string, Object> {
  let out: Record<string, Object> = {}
  criteria.forEach((text: string, key: string) => { out[key] = text })
  return out
}

/**
 * One batched request: the template pick and every slot of every template,
 * not a template pick followed by a second slot-specific round trip. A
 * second call would spend the latency this approach exists to save; the
 * slot answers for whichever template is not picked are simply ignored in
 * readPick.
 */
export function buildSelectRequest(prompt: string): string {
  let specs = templates()
  let questions: Record<string, Object> = {}

  let templateCriteria: Record<string, Object> = {}
  for (let spec of specs) { templateCriteria[spec.id] = spec.criteria }
  templateCriteria['none'] = 'neither of these fits the request -- including when it needs real or ' +
    'named data, a phone API or app/intent integration, or capability beyond a short generic list ' +
    'or a couple of generic numbers'
  let templateQuestion: Record<string, Object> = {}
  templateQuestion['type'] = 'choice'
  templateQuestion['instructions'] = 'Which of these screen shapes best fits what the person described? ' +
    'Answer none if neither clearly fits, or if the request needs anything beyond generic placeholder ' +
    'content and simple taps -- real data, search, charts, forms, or calling any phone API, SDK ' +
    'function or other app.'
  templateQuestion['criteria'] = templateCriteria
  questions['template'] = templateQuestion

  for (let spec of specs) {
    for (let slot of spec.slots) {
      let question: Record<string, Object> = {}
      question['type'] = slot.kind
      question['instructions'] = slot.instructions
      question['criteria'] = criteriaRecord(slot.criteria)
      questions[spec.id + '.' + slotKey(slot.token)] = question
    }
  }

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

function findTemplate(specs: TemplateSpec[], id: string): TemplateSpec | null {
  for (let spec of specs) { if (spec.id === id) { return spec } }
  return null
}

function readSlotValue(answers: Record<string, Object>, templateId: string, slot: SlotSpec): string {
  let key = templateId + '.' + slotKey(slot.token)
  let fallback = slot.values[0]
  let raw = answers[key]
  if (raw === null || raw === undefined) { return fallback }
  let answer = raw as Record<string, Object>
  if (slot.kind === 'noul') {
    let value = answer['noul']
    if (value === null || value === undefined || typeof value !== 'number') { return fallback }
    let probability = value as number
    // slot.values is [hide, show] by construction -- see bannerSlot() in VeraTemplates.ets.
    return probability > SLOT_PICK_ABOVE ? slot.values[1] : slot.values[0]
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

/**
 * Interprets Jev's answer. Any doubt about the top-level template choice
 * (unreadable JSON, missing/invalid answer, low confidence, "none") or a
 * tripped veto returns a PickOutcome with a null pick and a note saying why
 * -- the caller must fall through to normal generation. A single bad slot
 * answer never does that; it just falls back to that slot's hardcoded
 * default, because compileVeraSource is still the final gate downstream.
 */
export function readPick(body: string): PickOutcome {
  let specs = templates()
  let answers: Record<string, Object> = {}
  try {
    let parsed = JSON.parse(body) as Record<string, Object>
    let found = parsed['answers']
    if (found === null || found === undefined) { return new PickOutcome(null, 'none (no answers)') }
    answers = found as Record<string, Object>
  } catch (_e) {
    return new PickOutcome(null, 'none (answer unreadable)')
  }

  let templateAnswer = answers['template']
  if (templateAnswer === null || templateAnswer === undefined) { return new PickOutcome(null, 'none (no template answer)') }
  let ta = templateAnswer as Record<string, Object>
  let choice = ta['choice']
  if (choice === null || choice === undefined || typeof choice !== 'string') { return new PickOutcome(null, 'none (no template answer)') }
  let templateId = choice as string
  if (templateId === 'none') { return new PickOutcome(null, 'none (Jev said none)') }
  let spec = findTemplate(specs, templateId)
  if (spec === null) { return new PickOutcome(null, 'none (unknown template)') }
  let confidence = ta['confidence']
  let sure = confidence !== null && confidence !== undefined && typeof confidence === 'number' ? confidence as number : 1
  if (sure < PICK_ABOVE) { return new PickOutcome(null, 'none (template confidence ' + sure.toFixed(2) + ')') }

  // The template choice alone is a shape match against a one-line description and does not check
  // feature coverage -- a request can look list-shaped or number-shaped while also demanding
  // capability neither template has. These run once regardless of which template matched; any
  // doubt about one is treated as triggered (see readVeto), because rejecting only costs a normal
  // generation, while wrongly accepting silently drops whatever capability was actually asked for.
  let vetoNotes: string[] = []
  for (let veto of vetoes()) {
    let probability = readVetoProbability(answers, veto)
    if (probability > veto.above) { vetoNotes.push(veto.key + '=' + probability.toFixed(2)) }
  }
  if (vetoNotes.length > 0) {
    return new PickOutcome(null, 'vetoed ' + vetoNotes.join(' ') + ' (would have been ' + templateId + ' ' + sure.toFixed(2) + ')')
  }

  let slotValues: Map<string, string> = new Map<string, string>()
  let notes: string[] = []
  for (let slot of spec!.slots) {
    let value = readSlotValue(answers, templateId, slot)
    slotValues.set(slot.token, value)
    notes.push(slotKey(slot.token) + '=' + value)
  }
  let note = templateId + ' (' + sure.toFixed(2) + ') ' + notes.join(' ')
  return new PickOutcome(new TemplatePick(templateId, slotValues, note), note)
}

/** Missing/unreadable is treated as triggered (1), not 0 -- doubt about a veto must cost a normal generation. */
function readVetoProbability(answers: Record<string, Object>, veto: VetoSpec): number {
  let raw = answers['veto.' + veto.key]
  if (raw === null || raw === undefined) { return 1 }
  let answer = raw as Record<string, Object>
  let value = answer['noul']
  if (value === null || value === undefined || typeof value !== 'number') { return 1 }
  return value as number
}

/**
 * Plain source.split(token).join(value) substitution. Most values here are
 * closed-set identifiers (Jev's slot picks), but a caller may also merge in
 * VeraTemplateContent.ets's free-text content fields before calling this --
 * those are pre-escaped by escapeForVeraString, which (among other things)
 * collapses any run of two-or-more underscores so escaped text can never
 * itself contain a __NAME__-shaped token, keeping this loop order-
 * independent regardless of which tokens are merged in or in what order.
 */
export function substitute(templateId: string, slotValues: Map<string, string>): string {
  let spec = findTemplate(templates(), templateId)
  if (spec === null) { return '' }
  let source = spec.source
  slotValues.forEach((value: string, token: string) => {
    let replacement = value
    if (token === '__BANNER_SECTION__') { replacement = value === 'show' ? bannerLiteral() : '' }
    source = source.split(token).join(replacement)
  })
  return source
}

/**
 * Live call. Never throws and never rejects -- a selector that cannot answer
 * must not stop generation, same rule JevSelector.ets follows.
 */
export async function selectTemplate(prompt: string, apiKey: string): Promise<PickOutcome> {
  if (apiKey.length === 0 || prompt.trim().length === 0) { return new PickOutcome(null, 'none (no key or prompt)') }
  let client = http.createHttp()
  try {
    let headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + apiKey
    let started = Date.now()
    let response = await client.request(ENDPOINT, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: buildSelectRequest(prompt),
      connectTimeout: 5000,
      readTimeout: 15000
    })
    let code = response.responseCode as number
    if (code !== 200) {
      hilog.warn(DOMAIN, 'VERA', 'VERA-TEMPLATE http ' + code.toString())
      return new PickOutcome(null, 'none (selector answered ' + code.toString() + ')')
    }
    let outcome = readPick(response.result as string)
    hilog.info(DOMAIN, 'VERA', 'VERA-TEMPLATE ms=' + (Date.now() - started).toString() + ' picked=' + outcome.note)
    return outcome
  } catch (e) {
    hilog.warn(DOMAIN, 'VERA', 'VERA-TEMPLATE failed: ' + (e as Error).message)
    return new PickOutcome(null, 'none (selector unreachable)')
  } finally {
    client.destroy()
  }
}
