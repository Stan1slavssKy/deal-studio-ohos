/**
 * The words a project and its versions are listed under.
 *
 * A version's `prompt` is the whole history of its requests: the first one, then "Refinement:" and each change asked for
 * after it. `note` is the last request, cut to a hundred characters. A list that shows only the note names every version
 * after the first by its change ("Add a one-tap button"), which says what changed and not what the app is.
 */

const REFINEMENT_MARK: string = '\n\nRefinement:\n'

/** What the app is: the first line of the request it began as (the note when no request was kept). */
export function requestHeadline(prompt: string, note: string): string {
  let text = prompt.length > 0 ? prompt : note
  let cut = text.indexOf('\n')
  return (cut >= 0 ? text.substring(0, cut) : text).trim()
}

/** What this version changed: the last request of a refinement, and '' for a version that is the first answer to its request. */
export function changeNote(prompt: string, note: string): string {
  if (prompt.indexOf(REFINEMENT_MARK) < 0) { return '' }
  let text = note.trim()
  return text.startsWith(WIDGET_ASK_TEXT) ? 'Widget: ' + text.substring(WIDGET_ASK_TEXT.length) : text
}

/**
 * How Make widget words a request (WIDGET_ASK in agent/AgentWidget.ets, which this file cannot import: the card's process
 * reads it through ProjectStore). The list shows it as "Widget: ...". widget-status-check holds the two equal.
 */
export const WIDGET_ASK_TEXT: string = 'The home-screen widget should show: '

/**
 * The history without its widget requests, for a widget made again from nothing (Redo): told what the old widget was
 * asked to show, the model makes it again.
 */
export function withoutWidgetRequests(prompt: string): string {
  return prompt.split(REFINEMENT_MARK).filter((part: string, index: number): boolean =>
    index === 0 || !part.trim().startsWith(WIDGET_ASK_TEXT)).join(REFINEMENT_MARK)
}

/** "3 versions", "1 version", "No versions yet". */
export function versionCountText(count: number): string {
  if (count <= 0) { return 'No versions yet' }
  return count.toString() + (count === 1 ? ' version' : ' versions')
}
