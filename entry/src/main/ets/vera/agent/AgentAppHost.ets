/** The app's AgentHost: the DeepSeek engine for the plan and the sections, the TypeSafe key for Jev, Exa for searches. */

import { AgentHost, BlockRequest, BlockFill } from './AgentHost'
import { BlockCalls, fillBlocksWith } from './AgentBlocks'
import { askJev } from '../VeraCompose'
import { deepseek, discoveryToolResult } from '../DeepSeekEngine'
import { settings } from '../SettingsStore'
import { webSearch } from '../VeraWebSearch'

export function appAgentHost(status: (text: string) => void, preview: (vbc2: string) => void,
    cancelled: () => boolean = (): boolean => false): AgentHost {
  let host = new AgentHost()
  host.askPlan = (system: string, user: string, onText: (soFar: string) => void): Promise<string | null> =>
    deepseek.extractSketch(system, user, onText)
  host.askJev = (body: string): Promise<string> => askJev(body, settings.getSelectorKey())
  host.fillBlocks = (request: BlockRequest): Promise<BlockFill> => fillBlocksWith(request, appBlockCalls())
  host.status = status
  host.preview = preview
  host.cancelled = cancelled
  return host
}

function appBlockCalls(): BlockCalls {
  let calls = new BlockCalls()
  if (settings.hasExaKey()) { calls.search = (query: string): Promise<string> => webSearch(query) }
  calls.content = (system: string, user: string, budget: number): Promise<string | null> => deepseek.extractTemplateContent(system, user, budget)
  calls.hole = (system: string, user: string): Promise<string | null> =>
    deepseek.extractTemplateContent(system, user, 500, 'Function bodies for the blocks')
  calls.sdkContext = async (prompt: string): Promise<string> =>
    (await discoveryToolResult('find_sdk_function', prompt.substring(0, 300), 0)).substring(0, 2500)
  return calls
}
