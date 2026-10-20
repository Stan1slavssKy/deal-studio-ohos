/**
 * The agent: the slow path for a request the blocks do not serve. It plans the screen (DeepSeek, no thinking,
 * a JSON plan), has Jev choose how each part of the plan is built, assembles the program and checks it --
 * compiled, then run once with every handler tapped (VeraSmoke.ets) -- before anything is shown.
 *
 * Today the plan is VeraCompose.ets's sketch and the build is its composer; questions to the person, holes the
 * model fills and one component format shared with the blocks come next. Callers see only runAgent and
 * AgentResult, so those can change behind it. Never throws.
 */

import { AgentHost } from './AgentHost'
import { composeWith, composePlanEnabled, provisionalProgram, sketchPlan, ComposeResult, Sketch } from '../VeraCompose'
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
  }, request.widget)
  result.composed = composed
  result.note = composed.note
  result.plan = composed.parsed !== null && composePlanEnabled() ? sketchPlan(composed.parsed!) : ''
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
