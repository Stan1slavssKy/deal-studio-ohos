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
  return prompt.indexOf(REFINEMENT_MARK) >= 0 ? note.trim() : ''
}

/** "3 versions", "1 version", "No versions yet". */
export function versionCountText(count: number): string {
  if (count <= 0) { return 'No versions yet' }
  return count.toString() + (count === 1 ? ' version' : ' versions')
}
