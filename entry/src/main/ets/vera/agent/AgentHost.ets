/**
 * What the agent needs from whoever runs it: the two model calls, and where its progress goes. The Generate
 * screen and the chat each make one (appAgentHost in AgentAppHost.ets); the host harness makes its own with
 * fetch, so the agent itself imports no UI and no network client and runs under node unchanged.
 */

import { SketchAsk, JevAsk } from '../VeraCompose'
import { blockDefaults } from '../VeraTemplateContent'
import { CodeAsk } from './AgentCustom'
import { AgentQuestion } from './AgentQuestions'

/** Sections of the catalogue the plan asked for, to have their content (and their holes) filled for this request. */
export class BlockRequest {
  /** The sections' kinds, in screen order. */
  kinds: string[] = []
  prompt: string = ''
  /** Their content has to come from a search: real places, prices or facts. */
  realData: boolean = false
  /** How many blocks of its own the screen puts before them: the first section's slot number, less one. */
  offset: number = 0
  /** The whole program for the sections' values (in `kinds` order), for holes to be checked against the compiler. */
  compose: (values: Map<string, string>[]) => string = (_values: Map<string, string>[]): string => ''
}

export class BlockFill {
  /** Each section's slot, content and hole values, in `kinds` order. */
  values: Map<string, string>[] = []
  /** One line for the trace. */
  note: string = ''
  /** Why the sections cannot be served (real data asked for and no search), '' when they can. */
  failed: string = ''
  /** -1 when no search was made. */
  searchMs: number = -1
  contentMs: number = 0
  holesMs: number = 0
}

/** The catalogue's defaults for every section: what a host with no model to ask gives. */
export async function defaultBlockFill(request: BlockRequest): Promise<BlockFill> {
  let fill = new BlockFill()
  for (let kind of request.kinds) { fill.values.push(blockDefaults(kind)) }
  fill.note = 'content=default'
  return fill
}

export class AgentHost {
  /** The plan: DeepSeek with no thinking, one JSON object. */
  askPlan: SketchAsk = async (_system: string, _user: string, _onText: (soFar: string) => void): Promise<string | null> => null
  /** Jev's choices for a plan. */
  askJev: JevAsk = async (_body: string): Promise<string> => ''
  /** One line for the person: what the agent is doing now. */
  status: (text: string) => void = (_text: string): void => {}
  /** A compiled picture of the screen while it is being made. */
  preview: (vbc2: string) => void = (_vbc2: string): void => {}
  /** The content, real data and holes of the sections the plan asked for. */
  fillBlocks: (request: BlockRequest) => Promise<BlockFill> = defaultBlockFill
  /** The model that writes a custom section, null when there is none to ask: then a need nothing does refuses the screen. */
  askCode: CodeAsk | null = null
  /** The language as generation is shown it (the skill prompt with the UI catalogue), for the custom section. */
  language: string = ''
  /** Asks the person a blocking question: the answer's index, or null for the default (the default host never asks). */
  ask: (question: AgentQuestion) => Promise<number | null> = async (_question: AgentQuestion): Promise<number | null> => null
  /** True once the person has asked to stop. */
  cancelled: () => boolean = (): boolean => false
}
