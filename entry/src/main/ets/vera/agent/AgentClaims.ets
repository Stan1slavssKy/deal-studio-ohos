/**
 * What the composer leaves out of the plan because "a section of the catalogue does it" is a claim, and the section's own
 * options decide whether it does: a button for each item, a calendar, a style. The finished screen is read against each
 * claim, as a written section is read against its needs (AgentCustom.ets), and what it does not do is put back in the plan
 * to be written, or reported on the screen, rather than lost without a word.
 */

import { OperationCancellation, throwIfCancelled } from '../OperationCancellation'
import { CustomRequest, DOES_ABOVE, undone, verifyRequest } from './AgentCustom'
import { ScreenPlan } from '../ScreenPlan'

/** The claimed needs the program, as assembled, is not read as doing; [] when it does all, or Jev did not answer. */
export async function claimsUndone(claimed: string[], prompt: string, source: string,
    askJev: (body: string) => Promise<string>, cancellation?: OperationCancellation): Promise<string[]> {
  throwIfCancelled(cancellation)
  if (claimed.length === 0) { return [] }
  let request = new CustomRequest()
  request.needs = claimed
  request.prompt = prompt
  let reply = await askJev(verifyRequest(request, source))
  throwIfCancelled(cancellation)
  return undone(request, reply)
}

/** Puts the needs back in the plan as slots to write; the section hole that follows writes them, or reports them. */
export function putBack(plan: ScreenPlan, needs: string[]): void {
  for (let i = 0; i < needs.length; i++) { plan.addToWrite('claimed.' + i.toString(), needs[i]) }
}

/**
 * Of the needs, those the program, as assembled, is read as doing; [] when Jev did not answer or did not answer for a need, so
 * nothing is taken for done that was not said to be. A need the sections chosen for the screen already do in their own way (how
 * entries are labelled, what a chart is drawn from) is then not written again.
 */
export async function claimsDone(needs: string[], prompt: string, source: string,
    askJev: (body: string) => Promise<string>, cancellation?: OperationCancellation): Promise<string[]> {
  throwIfCancelled(cancellation)
  if (needs.length === 0) { return [] }
  let request = new CustomRequest()
  request.needs = needs
  request.prompt = prompt
  let answers: Record<string, Object> = {}
  try {
    let reply = await askJev(verifyRequest(request, source))
    throwIfCancelled(cancellation)
    if (reply.length === 0) { return [] }
    answers = (JSON.parse(reply) as Record<string, Object>)['answers'] as Record<string, Object>
  } catch (_e) {
    throwIfCancelled(cancellation)
    if ((_e as Error).name === 'OperationCancelledError') { throw (_e as Error) }
    return []
  }
  let out: string[] = []
  for (let i = 0; i < needs.length; i++) {
    let a = answers['does.' + i.toString()] as Record<string, Object>
    let p = a !== undefined && a !== null ? (a['probabilities'] as Record<string, Object>) : null
    if (p !== null && p !== undefined && typeof p['yes'] === 'number' && (p['yes'] as number) >= DOES_ABOVE) { out.push(needs[i]) }
  }
  return out
}

/** Words of a button or a need, lower case, hyphens and punctuation as spaces: "Remove last" and "the remove-last button" meet. */
function wordsOf(text: string): string {
  return ' ' + text.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim() + ' '
}

/**
 * The needs a button already on the screen does, by its label: a need that names "the remove-last button" or "the start-over button"
 * when the screen draws ui.Button(..., "Remove last", ...) and ui.Button(..., "Start over", ...). Jev did not read the record log's
 * own buttons as doing them, and the section written for them drew a second pair (Shared costs). Labels of two words or more only:
 * "Add" or "Save" is in too many needs to mean one button.
 */
export function buttonsOnScreen(needs: string[], source: string): string[] {
  let labels = buttonLabels(source).filter(isTwoWords)
  return needs.filter((need: string): boolean => {
    let n = wordsOf(need)
    return labels.some((l: string): boolean => n.indexOf(l + 'button ') >= 0 || n.indexOf(' ' + l.trim() + ' is tapped') >= 0 ||
      BUTTON_MEANINGS.some((m: ButtonMeaning): boolean => m.label.test(l) && m.need.test(n)))
  })
}

/** A label of two words or more: "Add" or "Save" is in too many needs, and too many forms, to mean one button. */
function isTwoWords(label: string): boolean {
  return label.trim().split(' ').length >= 2
}

/** A button label and the needs it does in other words: the plan says "the remove button" or "clears all payments". */
class ButtonMeaning {
  label: RegExp
  need: RegExp
  constructor(label: RegExp, need: RegExp) { this.label = label; this.need = need }
}

const BUTTON_MEANINGS: ButtonMeaning[] = [
  new ButtonMeaning(/ (remove|delete|undo) last /, / (remove|removes|delete|deletes|undo|undoes) (the )?(last|most recent|most recently|latest)\b/),
  new ButtonMeaning(/ start over | clear all | reset all /, / (clear|clears|reset|resets|wipe|wipes|delete|deletes|remove|removes) (all|every|everything)\b| start over | starts over /)
]

/** The index just past the call that opens at `open` (the index of its "("), strings skipped; -1 when it does not close. */
function closeOf(text: string, open: number): number {
  let depth = 0
  let i = open
  while (i < text.length) {
    let ch = text.charAt(i)
    if (ch === '"') {
      i++
      while (i < text.length && text.charAt(i) !== '"') { if (text.charAt(i) === '\\') { i++ } i++ }
    } else if (ch === '(' || ch === '[') { depth++ }
    else if (ch === ')' || ch === ']') { depth--; if (depth === 0) { return i + 1 } }
    i++
  }
  return -1
}

/** The labels of the buttons a program draws, as wordsOf has them. */
function buttonLabels(source: string): string[] {
  let out: string[] = []
  let pattern = /ui\.Button\(\s*"[a-z]+"\s*,\s*"([^"]+)"/g
  let m = pattern.exec(source)
  while (m !== null) {
    let w = wordsOf(m[1])
    if (out.indexOf(w) < 0) { out.push(w) }
    m = pattern.exec(source)
  }
  return out
}

/**
 * A written section's view without the buttons the rest of the screen already draws under the same label: a second "Remove last" and
 * "Start over" under the record log's (Shared costs), which the writer put in whatever it was told. A button inside ui.When goes with
 * its When; the comma that separated it goes too. Labels of one word ("Add") are left: they belong to the section's own form.
 */
export function withoutRepeatedButtons(view: string, rest: string): string {
  let taken = buttonLabels(rest).filter(isTwoWords)
  if (taken.length === 0) { return view }
  let out = view
  let from = 0
  while (true) {
    let at = out.indexOf('ui.Button(', from)
    if (at < 0) { break }
    let end = closeOf(out, at + 'ui.Button'.length)
    if (end < 0) { break }
    let label = /^ui\.Button\(\s*"[a-z]+"\s*,\s*"([^"]+)"/.exec(out.substring(at, end))
    if (label === null || taken.indexOf(wordsOf(label[1])) < 0) { from = end; continue }
    let start = at
    // ui.When(cond, ui.Button(...)): the When goes with it.
    let before = out.substring(0, at)
    let when = before.lastIndexOf('ui.When(')
    if (when >= 0) {
      let whenEnd = closeOf(out, when + 'ui.When'.length)
      if (whenEnd === end + 1 || (whenEnd > end && out.substring(end, whenEnd).trim() === ')')) { start = when; end = whenEnd }
    }
    let after = out.substring(end)
    let lead = out.substring(0, start)
    // Only an element of a list can go: anywhere else (an argument, a let) the code left would not compile.
    if (!/[\[,]\s*$/.test(lead) || !/^\s*[,\]]/.test(after)) { from = end; continue }
    if (/^\s*,/.test(after)) { after = after.replace(/^\s*,\s*/, '') }
    else if (/,\s*$/.test(lead)) { lead = lead.replace(/,\s*$/, '') }
    out = lead + after
    from = lead.length
  }
  return out
}

