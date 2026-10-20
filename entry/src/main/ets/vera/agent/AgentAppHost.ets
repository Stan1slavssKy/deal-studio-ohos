/** The app's AgentHost: the DeepSeek engine for the plan and the TypeSafe key for Jev. */

import { AgentHost } from './AgentHost'
import { askJev } from '../VeraCompose'
import { deepseek } from '../DeepSeekEngine'
import { settings } from '../SettingsStore'

export function appAgentHost(status: (text: string) => void, preview: (vbc2: string) => void,
    cancelled: () => boolean = (): boolean => false): AgentHost {
  let host = new AgentHost()
  host.askPlan = (system: string, user: string, onText: (soFar: string) => void): Promise<string | null> =>
    deepseek.extractSketch(system, user, onText)
  host.askJev = (body: string): Promise<string> => askJev(body, settings.getSelectorKey())
  host.status = status
  host.preview = preview
  host.cancelled = cancelled
  return host
}
