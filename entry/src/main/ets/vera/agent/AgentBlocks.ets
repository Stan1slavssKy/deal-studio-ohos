/**
 * Filling the catalogue's sections the plan asked for, as the blocks path fills them (VeraTemplatePipeline.ets): one
 * search when their content needs real data, the content call, then the holes, settled against the whole program.
 * The network calls come from the host (BlockCalls), so the app and the host harness fill sections the same way.
 */

import { BlockRequest, BlockFill } from './AgentHost'
import { fillSectionsContent, blockDefaults, ContentAsk } from '../VeraTemplateContent'
import { fillHoles, holesOf, holeValues, HoleInstance, HoleAsk } from '../VeraHoles'

export class BlockCalls {
  /** A web search for the request: the results as text, '' when there is no search to make. */
  search: ((query: string) => Promise<string>) | null = null
  /** The content model. */
  content: ContentAsk = async (_system: string, _user: string, _budget: number): Promise<string | null> => null
  /** The model that writes hole bodies. */
  hole: HoleAsk = async (_system: string, _user: string): Promise<string | null> => null
  /** The phone functions found for the request, for a hole that may call the phone. */
  sdkContext: (prompt: string) => Promise<string> = async (_prompt: string): Promise<string> => ''
}

/** Per-section copies of `values` with `extra` merged in; the maps given are not changed. */
function merged(values: Map<string, string>[], extra: Map<string, string>[]): Map<string, string>[] {
  let out: Map<string, string>[] = []
  for (let i = 0; i < values.length; i++) {
    let m: Map<string, string> = new Map<string, string>()
    values[i].forEach((v: string, k: string) => { m.set(k, v) })
    if (i < extra.length) { extra[i].forEach((v: string, k: string) => { m.set(k, v) }) }
    out.push(m)
  }
  return out
}

/**
 * Real data with no search to ground it is refused, as the blocks path refuses it: a screen of invented places or
 * prices is not what was asked for.
 */
export async function fillBlocksWith(request: BlockRequest, calls: BlockCalls): Promise<BlockFill> {
  let fill = new BlockFill()
  let searchText = ''
  if (request.realData) {
    if (calls.search === null) { fill.failed = 'sections need real data and no search is available'; return fill }
    let searchStart = Date.now()
    searchText = await calls.search!(request.prompt)
    fill.searchMs = Date.now() - searchStart
  }
  let contentStart = Date.now()
  let content = await fillSectionsContent(request.kinds, request.prompt, 'deepseek', searchText, calls.content)
  fill.contentMs = Date.now() - contentStart
  let values: Map<string, string>[] = []
  for (let kind of request.kinds) { values.push(blockDefaults(kind)) }
  values = merged(values, content.instanceValues)
  let notes: string[] = [content.note]
  if (fill.searchMs >= 0) { notes.push('search=' + (searchText.startsWith('Web results') ? 'ok' : 'empty')) }

  // Holes count slots across the whole screen: the composition's own blocks come first.
  let kinds: string[] = []
  let padded: Map<string, string>[] = []
  for (let i = 0; i < request.offset; i++) { kinds.push('none'); padded.push(new Map<string, string>()) }
  kinds = kinds.concat(request.kinds)
  padded = padded.concat(values)
  let holes = holesOf(kinds, padded)
  if (holes.some((h: HoleInstance): boolean => h.spec.byModel)) {
    let holesStart = Date.now()
    let sdkContext = holes.some((h: HoleInstance): boolean => h.spec.usesSdk) ? await calls.sdkContext(request.prompt) : ''
    let filled = await fillHoles(request.prompt, kinds, calls.hole,
      (bodies: Map<string, string>): string => request.compose(merged(values, holeValues(kinds, bodies).slice(request.offset))),
      padded, sdkContext)
    values = merged(values, holeValues(kinds, filled.bodies).slice(request.offset))
    fill.holesMs = Date.now() - holesStart
    if (filled.note.length > 0) { notes.push(filled.note) }
  }
  fill.values = values
  fill.note = notes.join(' ')
  return fill
}
