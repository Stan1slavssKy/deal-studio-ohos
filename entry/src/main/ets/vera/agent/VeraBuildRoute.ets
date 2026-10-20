/**
 * Which builder makes a new screen, the same for the Generate screen and the chat: the blocks
 * (VeraTemplatePipeline.ets) and the agent (VeraAgent.ets), in the order set below, and generation only when
 * neither serves. The caller turns the outcome into its own state; this file decides nothing about pages.
 *
 * A composition the blocks hand on to be completed by the model is kept until the agent has had its turn,
 * so the agent is always tried before anything is generated. Never throws.
 */

import { AgentHost } from './AgentHost'
import { AgentRequest, AgentResult, runAgent } from './VeraAgent'
import { buildFromTemplates, TemplateBuild, BUILD_TEMPLATE, BUILD_COMPLETE, BUILD_CANCELLED } from '../VeraTemplatePipeline'

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
      if (build.action === BUILD_TEMPLATE) { outcome.kind = OUTCOME_TEMPLATE; return outcome }
    }
  }
  outcome.kind = outcome.blocks !== null && outcome.blocks!.action === BUILD_COMPLETE ? OUTCOME_COMPLETE : OUTCOME_SCRATCH
  return outcome
}
