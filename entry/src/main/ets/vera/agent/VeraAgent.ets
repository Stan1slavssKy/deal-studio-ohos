/**
 * The agent: the slow path for a request the blocks do not serve. It plans the screen (DeepSeek, no thinking,
 * a JSON plan), has Jev choose how each part of the plan is built, assembles the program and checks it --
 * compiled, then run once with every handler tapped (VeraSmoke.ets) -- before anything is shown.
 *
 * The plan is VeraCompose.ets's sketch; Jev's choices bind each of its parts, and pick a section of the catalogue
 * (VeraTemplates.ets) for each need the plan says one handles whole, whose content and holes the host fills. What
 * neither does is one custom section the model writes (AgentCustom.ets). Callers see only runAgent and AgentResult,
 * so those can change behind it. Never throws.
 */

import { AgentHost, BlockRequest, BlockFill } from './AgentHost'
import { CustomRequest, CustomResult, writeSection } from './AgentCustom'
import { AgentQuestion, Asked, askBlocking } from './AgentQuestions'
import { FragmentSpec } from '../VeraTemplates'
import { composeWith, composePlanEnabled, provisionalProgram, sketchPlan, assembleProgram, screenPlan, partCount, customInputs, ComposeResult, Composition, Sketch } from '../VeraCompose'
import { ScreenPlan } from '../ScreenPlan'
import { compileVeraSource, CompileError } from '../VeraCompiler'
import { smokeRun } from '../VeraSmoke'

export class AgentRequest {
  /** What to build, in the person's words (or the chat's request for them). */
  prompt: string = ''
  /** A widget inside a chat reply rather than a whole screen. */
  widget: boolean = false
}

export class AgentResult {
  /** The checked program; empty when the agent could not build one. */
  source: string = ''
  vbc2: string = ''
  /** One line for the trace: what was built, or why not. */
  note: string = ''
  /** Why the assembled program was not served: compile or runtime diagnostics, '' when it was or when nothing was assembled. */
  errors: string = ''
  /** The plan and Jev's answers, with their timings. */
  composed: ComposeResult = new ComposeResult()
  /** The plan in words for a generation to keep to, '' when there is none or plans are off. */
  plan: string = ''
  /** The catalogue's sections on the screen, in order; empty when it has none. */
  blocks: string[] = []
  /** What filling them did, when there were any. */
  blockFill: BlockFill | null = null
  /** What writing the custom section did, when the composition needed one. */
  custom: CustomResult | null = null
  /** The questions put to the person, with their answers. */
  asked: Asked[] = []
  /** The screen's plan (ScreenPlan.ets) as far as it got: every slot and what fills it; null when Jev chose nothing. */
  screen: ScreenPlan | null = null
  firstPreviewMs: number = 0
  previews: number = 0
  checkMs: number = 0
  ms: number = 0
}

export async function runAgent(request: AgentRequest, host: AgentHost): Promise<AgentResult> {
  let result = new AgentResult()
  let started = Date.now()
  host.status(request.widget ? 'Sketching the widget...' : 'Composing...')
  let composed = await composeWith(request.prompt, host.askPlan, host.askJev, (partial: Sketch): void => {
    if (host.cancelled()) { return }
    let source = provisionalProgram(partial, request.widget)
    if (source.length === 0) { return }
    try {
      host.preview(compileVeraSource(source).vbc2)
      result.previews++
      if (result.firstPreviewMs === 0) { result.firstPreviewMs = Date.now() - started }
    } catch (_e) {
      // A partial plan that does not compile is skipped; the next one replaces it.
    }
  }, request.widget, async (sketch: Sketch): Promise<string> => {
    if (host.cancelled()) { return '' }
    let settled = await askBlocking(request.prompt, sketch.questions, host.askJev, (q: AgentQuestion): Promise<number | null> => {
      host.status('Waiting for your answer...')
      return host.ask(q)
    }, result.asked)
    if (settled.length > 0) { host.status('Planning again with your answer...') }
    return settled
  })
  result.composed = composed
  result.note = composed.note
  result.plan = composed.parsed !== null && composePlanEnabled() ? sketchPlan(composed.parsed!) : ''
  // Sections of the catalogue: their content written for the request (from a search when it needs real data), and
  // their holes, before the program is assembled.
  if (composed.composition !== null && !host.cancelled()) {
    let comp: Composition = composed.composition!
    let values: Map<string, string>[] = []
    let ready = true
    if (comp.blocks.length > 0) {
      host.status(comp.realData ? 'Looking up real data...' : 'Filling in the sections...')
      let blocks = new BlockRequest()
      blocks.kinds = comp.blocks
      blocks.prompt = request.prompt
      blocks.realData = comp.realData
      blocks.offset = partCount(comp)
      blocks.compose = (filled: Map<string, string>[]): string => assembleProgram(comp, filled)
      let fill = await host.fillBlocks(blocks)
      result.blocks = comp.blocks
      result.blockFill = fill
      result.note += '; ' + (fill.failed.length > 0 ? fill.failed : fill.note)
      ready = fill.failed.length === 0
      values = fill.values
    }
    // What nothing else does: one section the model writes into the program the rest makes.
    let custom: FragmentSpec | null = null
    if (ready && comp.custom.length > 0 && !host.cancelled()) {
      if (host.askCode === null || host.language.length === 0) {
        result.note += '; no model to write a custom section'
        ready = false
      } else {
        host.status('Writing the rest...')
        let asked = new CustomRequest()
        asked.needs = comp.custom
        asked.prompt = request.prompt
        asked.inputs = customInputs(comp)
        asked.compose = (section: FragmentSpec | null): string => assembleProgram(comp, values, section)
        asked.verify = host.askJev
        let written = await writeSection(asked, host.language, host.askCode!)
        result.custom = written
        custom = written.section
        ready = custom !== null
        result.note += '; ' + (custom !== null ? 'custom section in ' + written.attempts.toString() + ' attempt(s)' : written.failed)
      }
    }
    result.screen = screenPlan(comp, values, custom)
    if (ready) { composed.source = assembleProgram(comp, values, custom) }
  }
  if (composed.source.length > 0) {
    let checkStart = Date.now()
    try {
      let compiled = compileVeraSource(composed.source)
      result.errors = smokeRun(compiled)
      if (result.errors.length === 0) {
        result.source = composed.source
        result.vbc2 = compiled.vbc2
      }
    } catch (e) {
      result.errors = e instanceof CompileError ? (e as CompileError).message : (e as Error).message
    }
    result.checkMs = Date.now() - checkStart
    if (result.errors.length > 0) { result.note += '; ' + result.errors }
  }
  result.ms = Date.now() - started
  return result
}
