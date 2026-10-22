/**
 * The app's AgentHost: the DeepSeek engine for the plan and the sections, the TypeSafe key for Jev, Exa for searches, and
 * the phone's own lookups (the find_intent_function and find_sdk_function tools generation uses) for what the phone does.
 */

import { AgentHost, BlockRequest, BlockFill } from './AgentHost'
import { BlockCalls, fillBlocksWith } from './AgentBlocks'
import { askJev } from '../VeraCompose'
import { deepseek, discoveryToolResult } from '../DeepSeekEngine'
import { settings } from '../SettingsStore'
import { webSearch } from '../VeraWebSearch'

/** `language` is the skill prompt the page generates with (UI catalogue spliced in), for a custom section; '' for none. */
export function appAgentHost(status: (text: string) => void, preview: (vbc2: string) => void,
    cancelled: () => boolean = (): boolean => false, language: string = ''): AgentHost {
  let host = new AgentHost()
  host.askPlan = (system: string, user: string, onText: (soFar: string) => void): Promise<string | null> =>
    deepseek.extractSketch(system, user, onText)
  host.askJev = (body: string): Promise<string> => askJev(body, settings.getSelectorKey())
  host.fillBlocks = (request: BlockRequest): Promise<BlockFill> => fillBlocksWith(request, appBlockCalls())
  host.language = language
  host.askCode = (system: string, user: string, budget: number, think: boolean): Promise<string | null> =>
    deepseek.extractTemplateContent(system, user, budget, think ? 'A section of its own, thinking' : 'A section of its own', think)
  host.lookup = async (need: string): Promise<string> => {
    let asked = need.substring(0, 300)
    return 'find_intent_function:\n' + (await discoveryToolResult('find_intent_function', asked, 0)) +
      '\nfind_sdk_function:\n' + (await discoveryToolResult('find_sdk_function', asked, 0))
  }
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
