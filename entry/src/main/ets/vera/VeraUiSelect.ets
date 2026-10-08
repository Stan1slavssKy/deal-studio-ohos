/**
 * Which std/ui components the system prompt describes for a request.
 *
 *   full     all of them (null: describeCatalogForPrompt with no selection)
 *   phrases  an LLM lists the UI parts the request needs, each phrase is
 *            searched in VeraUiIndex, the two best per phrase are kept
 *   prompt   the whole request is one query against VeraUiIndex, the K best
 *            are kept
 *
 * `phrases` and `prompt` then add what the previous program already uses and
 * the closure VeraUiCatalog.selectUiComponents applies. Anything that goes
 * wrong -- no key, no embedding model -- answers null: the whole catalogue.
 * Scored against docs/ui-gold.json by tools/eval-ui-selection.py.
 */

import { deepseek } from './DeepSeekEngine'
import { findUiComponentsByEmbedding } from './VeraUiIndex'
import { selectUiComponents, componentsUsedIn } from './VeraUiCatalog'

/**
 * Said in the skill only when the prompt describes part of the catalogue: with
 * everything described there is nothing to look up, and the tool only costs a
 * round trip that resends the whole prompt.
 */
export const UI_TOOL_NOTE: string = 'The list above is what this app is likely to need. Before writing a ui.*\nconstructor that is not in it, call find_ui_component with what it must show or\ndo; never write one you were not shown.\n'

export const UI_SELECT_FULL = 'full'
export const UI_SELECT_PHRASES = 'phrases'
export const UI_SELECT_PROMPT = 'prompt'

const PER_PHRASE = 2
const PROMPT_TOP_K = 5

export async function selectUiForPrompt(mode: string, userPrompt: string,
    previousSource: string): Promise<Set<string> | null> {
  let picked: string[] = []
  if (mode === UI_SELECT_PHRASES) {
    let needs = await deepseek.extractUiNeeds(userPrompt)
    if (needs === null) { return null }
    for (let need of needs) {
      let found = await findUiComponentsByEmbedding(need, PER_PHRASE)
      if (found === null) { return null }
      for (let name of found) { picked.push(name) }
    }
  } else if (mode === UI_SELECT_PROMPT) {
    let found = await findUiComponentsByEmbedding(userPrompt, PROMPT_TOP_K)
    if (found === null) { return null }
    for (let name of found) { picked.push(name) }
  } else {
    return null
  }
  for (let name of componentsUsedIn(previousSource)) { picked.push(name) }
  return selectUiComponents(picked)
}
