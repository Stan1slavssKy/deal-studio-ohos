/**
 * Which builder makes a new screen, the same for the Generate screen and the chat: the blocks
 * (VeraTemplatePipeline.ets) and the agent (VeraAgent.ets), in the order set below, and generation only when
 * neither serves. The caller turns the outcome into its own state; this file decides nothing about pages.
 *
 * A composition the blocks hand on to be completed -- the right sections, but the request needs more than they do -- is
 * kept until the agent has had its turn, so the agent is always tried first. Then its layout stays and what it lacks is
 * written into it as one section (AgentHole.ets), as the agent fills what nothing ready does; only when that cannot be
 * done does the model finish the whole program. What the agent's plan asks the phone to do and could not bind is
 * something the blocks' layout lacks too: a pick of sections that does not do it is not a finished screen. Never throws.
 */

import { AgentHost } from './AgentHost'
import { AgentRequest, AgentResult, runAgent } from './VeraAgent'
import { CustomResult } from './AgentCustom'
import { writeHole } from './AgentHole'
import { buildFromTemplates, TemplateBuild, BUILD_TEMPLATE, BUILD_COMPLETE, BUILD_CANCELLED } from '../VeraTemplatePipeline'
import { assemblePlan, PlanSlot } from '../ScreenPlan'
import { compileVeraSource, CompileError } from '../VeraCompiler'
import { ROUTE_BLOCKS_MODEL } from '../VeraRoute'

/** The agent's program is the result. */
export const OUTCOME_AGENT: string = 'agent'
/** The blocks' program is the result. */
export const OUTCOME_TEMPLATE: string = 'template'
/** The blocks' program is the base for the model to finish (`blocks.source`), and the fallback if it cannot. */
export const OUTCOME_COMPLETE: string = 'complete'
/** Neither served: generate, with `plan` when there is one. */
export const OUTCOME_SCRATCH: string = 'scratch'
export const OUTCOME_CANCELLED: string = 'cancelled'

export const ORDER_AGENT_FIRST: string = 'agent-first'
export const ORDER_BLOCKS_FIRST: string = 'blocks-first'

/** Agent first until the blocks' pick is cheap enough to put in front of every request; `--ps veraOrder blocks-first` swaps them. */
let order: string = ORDER_AGENT_FIRST
export function setRouteOrder(next: string): void { order = next === ORDER_BLOCKS_FIRST ? ORDER_BLOCKS_FIRST : ORDER_AGENT_FIRST }
export function routeOrder(): string { return order }

export class RouteRequest {
  /** What the agent builds from; null when the agent is not to be tried. */
  agent: AgentRequest | null = null
  /** What the blocks build from; '' when they are not to be tried. */
  blocksPrompt: string = ''
  /** The Generate screen's generation mode; the chat is always 'deepseek'. */
  mode: string = 'deepseek'
}

export class RouteOutcome {
  kind: string = OUTCOME_SCRATCH
  /** The agent's answer when it ran, served or not. */
  agent: AgentResult | null = null
  /** The blocks' answer when they ran, served or not. */
  blocks: TemplateBuild | null = null
  /** The agent's plan for a generation to keep to; '' when there is none. */
  plan: string = ''
  /** What writing the blocks' missing part did, when the blocks asked for one; null otherwise. */
  hole: CustomResult | null = null
}

/**
 * What the agent's plan asks the phone to do that it could not bind, as slots of the blocks' plan to be written: the
 * sections Jev picked do not do it either. A finished template that lacks it is then one to be completed.
 */
function addAgentNeeds(build: TemplateBuild, agent: AgentResult | null): void {
  if (agent === null || build.plan === null) { return }
  let plan = build.plan!
  let needs = agent.composed.unboundNeeds
  let added: string[] = []
  for (let i = 0; i < needs.length; i++) {
    let id = 'asked.' + i.toString()
    if (plan.slots.some((s: PlanSlot): boolean => s.id === id)) { continue }
    plan.addToWrite(id, needs[i])
    added.push(needs[i])
  }
  if (added.length > 0 && build.action === BUILD_TEMPLATE) {
    build.action = BUILD_COMPLETE
    build.route.route = ROUTE_BLOCKS_MODEL
    build.note += '; the plan also asks: ' + added.join('; ')
    build.status = 'Composed ' + build.kinds.join('+') + ', adding what the request asks the phone to do...'
  }
}

/**
 * The blocks' layout with what it lacks written into it: true when the program is now whole, and `build` then holds
 * it as a finished template; false leaves `build` as it was.
 */
async function finishBlocks(build: TemplateBuild, prompt: string, host: AgentHost, outcome: RouteOutcome): Promise<boolean> {
  let plan = build.plan
  if (plan === null || plan.toWrite().length === 0) { return false }
  host.status('Writing what the sections do not do...')
  let written = await writeHole(plan, prompt, [], host)
  outcome.hole = written
  if (written === null || written.section === null) {
    build.note += '; ' + (written !== null ? written.failed : 'nothing to write')
    return false
  }
  let source = assemblePlan(plan)
  try {
    build.vbc2 = compileVeraSource(source).vbc2
  } catch (e) {
    build.note += '; written section: ' + (e instanceof CompileError ? (e as CompileError).message : (e as Error).message)
    return false
  }
  build.source = source
  build.action = BUILD_TEMPLATE
  // The composition record has no place for a written section: a structural edit would drop it, so there is none.
  build.composition = ''
  build.note += '; written section in ' + written.attempts.toString() + ' attempt(s)'
  build.status = 'Composed ' + build.kinds.join('+') + ' with a section written for the rest'
  return true
}

export async function buildScreen(request: RouteRequest, host: AgentHost): Promise<RouteOutcome> {
  let outcome = new RouteOutcome()
  let steps: string[] = order === ORDER_BLOCKS_FIRST ? ['blocks', 'agent'] : ['agent', 'blocks']
  for (let step of steps) {
    if (host.cancelled()) { outcome.kind = OUTCOME_CANCELLED; return outcome }
    if (step === 'agent' && request.agent !== null) {
      let result = await runAgent(request.agent!, host)
      outcome.agent = result
      outcome.plan = result.plan
      if (host.cancelled()) { outcome.kind = OUTCOME_CANCELLED; return outcome }
      if (result.vbc2.length > 0) { outcome.kind = OUTCOME_AGENT; return outcome }
    }
    if (step === 'blocks' && request.blocksPrompt.length > 0) {
      let build = await buildFromTemplates(request.blocksPrompt, request.mode, host.status, host.cancelled)
      outcome.blocks = build
      if (build.action === BUILD_CANCELLED) { outcome.kind = OUTCOME_CANCELLED; return outcome }
      addAgentNeeds(build, outcome.agent)
      if (build.action === BUILD_TEMPLATE) { outcome.kind = OUTCOME_TEMPLATE; return outcome }
    }
  }
  if (outcome.blocks !== null && outcome.blocks!.action === BUILD_COMPLETE) {
    addAgentNeeds(outcome.blocks!, outcome.agent)
    // The section is DeepSeek's to write; another generation mode finishes the program its own way.
    if (request.mode === 'deepseek' && await finishBlocks(outcome.blocks!, request.blocksPrompt, host, outcome)) {
      outcome.kind = host.cancelled() ? OUTCOME_CANCELLED : OUTCOME_TEMPLATE
      return outcome
    }
    if (host.cancelled()) { outcome.kind = OUTCOME_CANCELLED; return outcome }
    outcome.kind = OUTCOME_COMPLETE
    return outcome
  }
  outcome.kind = OUTCOME_SCRATCH
  return outcome
}
