/**
 * The agent's model calls through the dealer harness (libdealer.so, github.com/arkts-dev/dealer):
 * the plan, a written section and Jev. On with `--ps dealer 1` (SettingsStore.useDealer); then
 * AgentAppHost.ets sends askPlan, askCode and askJev here instead of DeepSeekEngine and askJev.
 *
 * Dealer builds each request, parses the SSE stream and keeps every turn in its own database
 * ({filesDir}/vera/dealer.db). The network stays here: dealer hands each HTTP request to send()
 * below, which answers through @kit.NetworkKit, so USB network keeps working. The request body is
 * the one DeepSeekEngine.buildBody sends (model, thinking, reasoning_effort, temperature,
 * max_tokens), and a reply cut at the token limit comes back with finish reason "length", as the
 * agent's repairs expect.
 */

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import {
  dealerAvailable, dealerInit, dealerRegisterProvider, dealerHead, dealerChunk, dealerFinish, dealerCancelled,
  dealerRun, dealerCancel, dealerDecide
} from 'libdealer.so'
import { settings } from './SettingsStore'
import { OperationCancellation, throwIfCancelled } from './OperationCancellation'

const TAG: string = 'VERA-DEALER'
const API_PATH: string = 'chat/completions'
const EVENT_STREAM: string = 'text/event-stream'

/** One reply: its text and why it ended ("stop", "length", ...). */
export class DealerReply {
  text: string = ''
  finishReason: string = ''
}

class Bridge {
  /** null before the first use; '' when ready; otherwise why dealer cannot be used. */
  private state: string | null = null
  private provider: string = ''
  private runs: number = 0

  /** '' when dealer is ready, else why not. Opens the database and registers the provider once. */
  ready(): string {
    if (this.state !== null) { return this.state }
    if (!dealerAvailable()) {
      this.state = 'this build has no dealer library'
    } else {
      let failure = dealerInit(settings.dir() + '/dealer.db', (id: number, request: string): void => this.send(id, request))
      this.state = failure.length > 0 ? failure : this.register()
    }
    console.info(TAG + ' ready: ' + (this.state.length > 0 ? this.state : 'yes, provider ' + this.provider))
    return this.state
  }

  private register(): string {
    let base = settings.getBaseUrl()
    let deepseek = base.indexOf('deepseek.com') >= 0
    // A provider id keeps its base URL for good in dealer's database, so another URL takes another id.
    this.provider = deepseek ? 'deepseek' : 'cloud-' + hash(base)
    let provider: Record<string, Object> = {}
    provider['id'] = this.provider
    provider['base_url'] = base.endsWith('/') ? base : base + '/'
    provider['path'] = API_PATH
    provider['dialect'] = deepseek ? 'deepseek' : 'bearer'
    provider['key'] = settings.getApiKey()
    return dealerRegisterProvider(JSON.stringify(provider))
  }

  /** What DeepSeekEngine.buildBody puts beside the messages, for dealer to send as is. */
  private generation(maxTokens: number, thinking: boolean, temperature: number): string {
    let options: Record<string, Object> = {}
    if (settings.isDeepSeek()) {
      let mode: Record<string, Object> = {}
      mode['type'] = thinking ? 'enabled' : 'disabled'
      options['thinking'] = mode
      if (thinking) { options['reasoning_effort'] = settings.getReasoningEffort() }
    } else if (thinking) {
      options['reasoning_effort'] = settings.getReasoningEffort()
    } else {
      options['enable_thinking'] = false
    }
    options['temperature'] = temperature
    let generation: Record<string, Object> = {}
    generation['provider'] = this.provider
    generation['model'] = settings.getModel()
    generation['reasoning'] = true
    generation['max_output_tokens'] = maxTokens
    generation['options'] = options
    return JSON.stringify(generation)
  }

  /** One system and one user message, streamed; onText gets the reply so far. */
  async ask(purpose: string, system: string, user: string, maxTokens: number, thinking: boolean, temperature: number,
      onText: (soFar: string) => void, cancellation?: OperationCancellation): Promise<DealerReply> {
    let failure = this.ready()
    if (failure.length > 0) { throw new Error('dealer: ' + failure) }
    throwIfCancelled(cancellation)
    let runId = ++this.runs
    let context: Record<string, Object> = {}
    context['system'] = system
    context['messages'] = [] as Object[]
    let part: Record<string, Object> = {}
    part['type'] = 'text'
    part['text'] = user
    let soFar = ''
    let started = Date.now()
    let stop = cancellation !== undefined ? cancellation.onCancel((): void => dealerCancel(runId)) : (): void => {}
    try {
      let result = await dealerRun(runId, 'vera-' + purpose + '-' + started.toString() + '-' + runId.toString(),
        this.generation(maxTokens, thinking, temperature), JSON.stringify(context), JSON.stringify([part]),
        (event: string): void => {
          let parsed = JSON.parse(event) as Record<string, Object>
          if (parsed['type'] === 'text') {
            soFar += parsed['text'] as string
            onText(soFar)
          }
        })
      let answer = JSON.parse(result) as Record<string, Object>
      let reply = new DealerReply()
      reply.text = answer['text'] as string
      reply.finishReason = (answer['finish_reason'] as string) || ''
      console.info(TAG + ' ' + purpose + ' ms=' + (Date.now() - started).toString() + ' finish=' + reply.finishReason +
        ' chars=' + reply.text.length.toString() + ' usage=' + JSON.stringify(answer['usage']))
      return reply
    } finally {
      stop()
    }
  }

  /** Jev's systemone endpoint through dealer: the request body in, Jev's answer body out. */
  async decide(endpoint: string, key: string, body: string): Promise<string> {
    let failure = this.ready()
    if (failure.length > 0) { throw new Error('dealer: ' + failure) }
    let started = Date.now()
    let answer = await dealerDecide(endpoint, key, body)
    console.info(TAG + ' decide ms=' + (Date.now() - started).toString() + ' chars=' + answer.length.toString())
    return answer
  }

  /**
   * Does dealer's HTTP request `id`. An event stream is passed on as it arrives; anything else (an
   * error body, a JSON answer) is kept until the status is known, because dealer reads the status
   * before the body and requestInStream gives it only at the end.
   */
  private send(id: number, requestJson: string): void {
    let request = JSON.parse(requestJson) as Record<string, Object>
    let header: Record<string, string> = {}
    let given = request['headers'] as Record<string, Object>
    Object.keys(given).forEach((name: string): void => { header[name] = String(given[name]) })
    let client = http.createHttp()
    let contentType = ''
    let streamed = false
    let kept: ArrayBuffer[] = []
    let decoder = util.TextDecoder.create('utf-8')
    client.on('headersReceive', (headers: Object): void => { contentType = contentTypeOf(headers) })
    client.on('dataReceive', (chunk: ArrayBuffer): void => {
      if (dealerCancelled(id)) {
        client.destroy()
        return
      }
      if (!streamed && kept.length === 0 && (contentType.indexOf(EVENT_STREAM) >= 0 ||
        decoder.decodeToString(new Uint8Array(chunk.slice(0, 5)), { stream: false }) === 'data:')) {
        streamed = true
        dealerHead(id, 200, '{"content-type": "' + EVENT_STREAM + '"}')
      }
      if (streamed) {
        dealerChunk(id, chunk)
      } else {
        kept.push(chunk)
      }
    })
    let options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(request['body']),
      connectTimeout: 15000,
      readTimeout: 300000
    }
    client.requestInStream(request['url'] as string, options).then((code: number): void => {
      if (streamed) {
        dealerFinish(id, code === 200, code === 200 ? '' : 'HTTP ' + code.toString() + ' after the stream began')
        return
      }
      let type = contentType.length > 0 ? contentType : 'application/json'
      let failure = dealerHead(id, code, JSON.stringify(headerOf('content-type', type)))
      if (failure.length > 0) {
        dealerFinish(id, false, failure)
        return
      }
      kept.forEach((chunk: ArrayBuffer): void => { dealerChunk(id, chunk) })
      dealerFinish(id, true, '')
    }).catch((e: Error): void => {
      dealerFinish(id, false, 'request failed: ' + e.message)
    }).finally((): void => {
      try { client.off('dataReceive') } catch (_e) {}
      try { client.off('headersReceive') } catch (_e) {}
      client.destroy()
    })
  }
}

function headerOf(name: string, value: string): Record<string, string> {
  let header: Record<string, string> = {}
  header[name] = value
  return header
}

function contentTypeOf(headers: Object): string {
  let all = headers as Record<string, Object>
  let found = ''
  Object.keys(all).forEach((name: string): void => {
    if (name.toLowerCase() === 'content-type') { found = String(all[name]) }
  })
  return found
}

/** A short stable name for a base URL (FNV-1a). */
function hash(text: string): string {
  let h = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    h = h ^ text.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return h.toString(16)
}

export const dealer: Bridge = new Bridge()
