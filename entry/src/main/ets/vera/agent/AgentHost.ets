/**
 * What the agent needs from whoever runs it: the two model calls, and where its progress goes. The Generate
 * screen and the chat each make one (appAgentHost in AgentAppHost.ets); the host harness makes its own with
 * fetch, so the agent itself imports no UI and no network client and runs under node unchanged.
 */

import { SketchAsk, JevAsk } from '../VeraCompose'

export class AgentHost {
  /** The plan: DeepSeek with no thinking, one JSON object. */
  askPlan: SketchAsk = async (_system: string, _user: string, _onText: (soFar: string) => void): Promise<string | null> => null
  /** Jev's choices for a plan. */
  askJev: JevAsk = async (_body: string): Promise<string> => ''
  /** One line for the person: what the agent is doing now. */
  status: (text: string) => void = (_text: string): void => {}
  /** A compiled picture of the screen while it is being made. */
  preview: (vbc2: string) => void = (_vbc2: string): void => {}
  /** True once the person has asked to stop. */
  cancelled: () => boolean = (): boolean => false
}
