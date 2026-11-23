import { AgentHost, HoleRecord, checkAgent, agentCancellation } from './AgentHost'
import { BlockRequest, BlockFill, fillSections } from '../SectionFill'
import { appBlockCalls } from '../SectionFillApp'
import { askJev } from '../VeraCompose'
import { deepseek, discoveryToolResult, extractVeraSource } from '../DeepSeekEngine'
import { dealer } from '../DealerBridge'
import { settings } from '../SettingsStore'
import { trace, traceLookup } from '../VeraTiming'
import { OperationCancellation } from '../OperationCancellation'
import { checkWidgetProgramOffMain } from './WidgetCheckTask'

export function appAgentHost(status: (text: string) => void, preview: (vbc2: string) => void,
    cancelled: () => boolean = (): boolean => false, language: string = '', surfaceGuide: string = '',
    cancellation?: OperationCancellation): AgentHost {
  let host = new AgentHost()
  host.cancellation = cancellation
  host.cancelled = (): boolean => cancelled() || (cancellation !== undefined && cancellation.isCancelled())
  let operation = cancellation !== undefined ? cancellation : agentCancellation(host)
  host.askPlan = async (system: string, user: string, onText: (soFar: string) => void, think: boolean): Promise<string | null> => {
    checkAgent(host)
    try {
      if (settings.useDealer()) {
        // As extractSketch: temperature 0, 12000 tokens when thinking and 3000 when not, null on a failure.
        try {
          let reply = await dealer.ask('plan', system, user, think ? 12000 : 3000, think, 0, (text: string): void => {
            if (!host.cancelled()) { onText(text) }
          }, operation)
          return reply.text
        } catch (e) {
          checkAgent(host)
          console.warn('VERA-DEALER plan failed: ' + (e as Error).message)
          return null
        }
      }
      return await deepseek.extractSketch(system, user, (text: string): void => {
        if (!host.cancelled()) { onText(text) }
      }, think, operation)
    } finally {
      checkAgent(host)
    }
  }
  host.askJev = async (body: string): Promise<string> => {
    checkAgent(host)
    try {
      return await askJev(body, settings.getSelectorKey(), operation)
    } finally {
      checkAgent(host)
    }
  }
  host.fillBlocks = async (request: BlockRequest): Promise<BlockFill> => {
    checkAgent(host)
    try {
      return await fillSections(request, appBlockCalls(settings.hasExaKey(), host.status, host.cancelled, operation))
    } finally {
      checkAgent(host)
    }
  }
  host.language = language
  // Make widget plays the app's clock to check the card: off the UI thread, or a game that never rests freezes the app.
  host.checkWidget = checkWidgetProgramOffMain
  host.surfaceGuide = surfaceGuide
  host.askCode = async (system: string, user: string, budget: number, think: boolean): Promise<string | null> => {
    checkAgent(host)
    try {
      if (settings.useDealer()) {
        // As extractTemplateAnswer: temperature 0.2, the program out of any fence, null on a failure.
        try {
          let reply = await dealer.ask('code', system, user, budget, think, 0.2, (_text: string): void => {}, operation)
          host.lastCodeFinish = reply.finishReason
          return extractVeraSource(reply.text)
        } catch (e) {
          checkAgent(host)
          console.warn('VERA-DEALER code failed: ' + (e as Error).message)
          host.lastCodeFinish = ''
          return null
        }
      }
      let answer = await deepseek.extractTemplateAnswer(system, user, budget,
        think ? 'A section of its own, thinking' : 'A section of its own', think, operation)
      host.lastCodeFinish = answer.finishReason
      return answer.text
    } finally {
      checkAgent(host)
    }
  }
  host.lookup = async (need: string): Promise<string> => {
    checkAgent(host)
    let asked = need.substring(0, 300)
    try {
      let intent = await discoveryToolResult('find_intent_function', asked, 0, true, operation)
      traceLookup('find_intent_function', asked, true, intent)
      checkAgent(host)
      let sdk = await discoveryToolResult('find_sdk_function', asked, 0, false, operation)
      traceLookup('find_sdk_function', asked, false, sdk)
      return 'find_intent_function:\n' + intent + '\nfind_sdk_function:\n' + sdk
    } finally {
      checkAgent(host)
    }
  }
  host.onHole = (r: HoleRecord): void => {
    if (host.cancelled()) { return }
    let fields: Record<string, Object> = {}
    fields['prompt'] = r.prompt
    fields['origin'] = r.origin
    fields['whole'] = r.whole
    fields['needs'] = r.needs
    fields['phone'] = r.phone
    fields['outcome'] = r.outcome
    fields['attempts'] = r.attempts
    fields['thought'] = r.thought
    fields['ms'] = r.ms
    fields['missed'] = r.missed
    fields['why'] = r.why
    fields['code'] = r.code
    fields['lookup'] = r.lookup
    trace('hole', fields)
  }
  host.status = (text: string): void => { if (!host.cancelled()) { status(text) } }
  host.preview = (vbc2: string): void => { if (!host.cancelled()) { preview(vbc2) } }
  return host
}
