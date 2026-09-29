/**
 * DeepSeek chat-completions client.
 *
 * Same shape as LlamaEngine, so GeneratePage.runAttempt drives either provider:
 * generate() takes a GenerateRequest and streams tokens through a callback. The
 * difference is that the model is remote, so the call is a Promise. Everything
 * downstream -- compiling with VeraCompiler, feeding diagnostics back, retrying
 * -- still happens on the device.
 *
 * The API is OpenAI-compatible: POST {baseUrl}/chat/completions with a Bearer
 * key. Responses stream as Server-Sent Events, one 'data: {...}' line per
 * chunk, terminated by 'data: [DONE]'.
 *
 * Unlike llama.cpp there is no GBNF grammar to constrain decoding, so vera.gbnf
 * is unused here and the output goes through extractVeraSource() in case the
 * model wraps the program in a markdown fence anyway.
 *
 * Two tools (docs/selector-design.md): find_sdk_function, backed by
 * VeraSdkIndex's local search over interface_sdk-js; and
 * find_intent_function, backed by VeraIntentIndex's local search over the
 * curated intent catalogue and the raw device registry -- the same
 * treatment, for the same reason: either source spliced into the prompt
 * ahead of generation (as the registry's JevSelector pick, or its lexical
 * fallback, used to be) sits there as ready text before the model starts
 * reasoning, and wins over a tool result it has to synthesize even when
 * that result is correct. One discovery mechanism for both removes that
 * asymmetry. Both are DeepSeek-only, not extended to LlamaEngine's on-device
 * path -- that path decodes under a GBNF grammar with no tool-call support,
 * and building one there is a materially bigger change than this selector
 * question. A round of tool_calls is answered locally (by name) and the
 * conversation continues; the loop is bounded (MAX_TOOL_ROUNDS) across both
 * tools so a model that keeps asking can't hang a generation. The result the
 * caller sees is unchanged either way: one GenerateResult -- runAttempt does
 * not know or care how many requests, or which tool, it took.
 */

import http from '@ohos.net.http'
import util from '@ohos.util'
import { GenerateRequest, GenerateResult, TokenCallback } from './LlamaEngine'
import { settings } from './SettingsStore'
import { findSdkFunctionFromCache, SdkEntry } from './VeraSdkIndex'
import { findIntentFunction, IntentEntry } from './VeraIntentIndex'

const SDK_TOOL_NAME = 'find_sdk_function'
const SDK_SEARCH_LIMIT = 8
const INTENT_TOOL_NAME = 'find_intent_function'
const INTENT_SEARCH_LIMIT = 8
/**
 * How many tool-call round trips one generation tolerates, across both
 * tools. Each round is a full request-response cycle against DeepSeek, so
 * this bounds latency and cost, not just correctness. Seen live at 4: a
 * model still legitimately refining its search on the last allowed round --
 * generate() forces one final, tools-off request in that case rather than
 * ending with nothing, so this bounds cost without risking "produced empty
 * output" the way just stopping cold would.
 */
const MAX_TOOL_ROUNDS = 4

/** One function call as it streams in: id and name arrive once, arguments in fragments. */
class ToolCallAccumulator {
  id: string = ''
  name: string = ''
  arguments: string = ''
}

/** What one HTTP request/response cycle produced. */
class StreamTurn {
  content: string = ''
  finishReason: string = ''
  toolCalls: ToolCallAccumulator[] = []
  inputTokens: number = 0
  outputTokens: number = 0
  cacheHitTokens: number = 0
}

function plainMessage(role: string, content: string): Record<string, Object> {
  let m: Record<string, Object> = {}
  m['role'] = role
  m['content'] = content
  return m
}

/** The assistant turn that asked for tools, replayed so the model sees its own request. */
function assistantToolCallMessage(toolCalls: ToolCallAccumulator[]): Record<string, Object> {
  let calls: Record<string, Object>[] = []
  for (let tc of toolCalls) {
    let fn: Record<string, Object> = {}
    fn['name'] = tc.name
    fn['arguments'] = tc.arguments
    let call: Record<string, Object> = {}
    call['id'] = tc.id
    call['type'] = 'function'
    call['function'] = fn
    calls.push(call)
  }
  let m: Record<string, Object> = {}
  m['role'] = 'assistant'
  m['content'] = ''
  m['tool_calls'] = calls
  return m
}

function toolResultMessage(toolCallId: string, content: string): Record<string, Object> {
  let m: Record<string, Object> = {}
  m['role'] = 'tool'
  m['tool_call_id'] = toolCallId
  m['content'] = content
  return m
}

function needParameter(description: string): Record<string, Object> {
  let need: Record<string, Object> = {}
  need['type'] = 'string'
  need['description'] = description
  let properties: Record<string, Object> = {}
  properties['need'] = need
  let parameters: Record<string, Object> = {}
  parameters['type'] = 'object'
  parameters['properties'] = properties
  parameters['required'] = ['need']
  return parameters
}

/** The two tools DeepSeek is offered, each describing itself well enough to be found without a system-prompt mention. */
function toolSchemas(): Record<string, Object>[] {
  let sdkFn: Record<string, Object> = {}
  sdkFn['name'] = SDK_TOOL_NAME
  sdkFn['description'] = 'Looks up a platform SDK function by what it needs to do, out of thousands the phone offers with no built-in catalogue. Returns a few candidates with their target, parameters, return type and description. Never invent a target string: only use one returned by this tool.'
  sdkFn['parameters'] = needParameter('Plain-language description of the platform capability needed, e.g. "read the free internal storage space".')
  let sdkTool: Record<string, Object> = {}
  sdkTool['type'] = 'function'
  sdkTool['function'] = sdkFn

  let intentFn: Record<string, Object> = {}
  intentFn['name'] = INTENT_TOOL_NAME
  intentFn['description'] = 'Looks up how to reach another app on the phone: a typed intent.<name> call from the checked catalogue when one fits, or a raw sdk.call target otherwise. Returns a few candidates with a ready-to-adapt call. Never invent a target: only use one returned by this tool.'
  intentFn['parameters'] = needParameter('Plain-language description of what another app needs to do, e.g. "start navigation to a place" or "send a text message".')
  let intentTool: Record<string, Object> = {}
  intentTool['type'] = 'function'
  intentTool['function'] = intentFn

  return [sdkTool, intentTool]
}

/** find_sdk_function's answer, in the shape handed back as the tool result. */
function sdkResultsJson(entries: SdkEntry[]): string {
  let body: Record<string, Object> = {}
  if (entries.length === 0) {
    body['results'] = []
    body['note'] = 'No sdk function matched. Try a different, more specific phrasing, or if nothing this specific exists, use what std/ui, std/intent or std/calendar already offer instead.'
    return JSON.stringify(body)
  }
  let items: Record<string, Object>[] = []
  for (let e of entries) {
    let item: Record<string, Object> = {}
    item['target'] = e.kit + '.' + e.module + '.' + e.name
    item['params'] = e.params
    item['returnType'] = e.returnType
    item['description'] = e.description
    items.push(item)
  }
  body['results'] = items
  return JSON.stringify(body)
}

/** find_intent_function's answer, in the shape handed back as the tool result. */
function intentResultsJson(entries: IntentEntry[]): string {
  let body: Record<string, Object> = {}
  if (entries.length === 0) {
    body['results'] = []
    body['note'] = 'No intent matched. Try a different, more specific phrasing, or if this app does not need to reach another app, it may not need this tool at all.'
    return JSON.stringify(body)
  }
  let items: Record<string, Object>[] = []
  for (let e of entries) {
    let item: Record<string, Object> = {}
    item['kind'] = e.kind
    item['description'] = e.description
    item['call'] = e.callHint
    items.push(item)
  }
  body['results'] = items
  return JSON.stringify(body)
}

function httpErrorMessage(code: number, body: string): string {
  let detail = ''
  try {
    let obj = JSON.parse(body) as Record<string, Object>
    let err = obj['error'] as Record<string, Object>
    if (err !== null && err !== undefined) {
      let msg = err['message']
      if (typeof msg === 'string') { detail = msg as string }
    }
  } catch (_e) {
    detail = body.substring(0, 200)
  }
  let prefix = ''
  if (code === 401) {
    prefix = 'API key rejected (401). Re-send it with: aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey <key>'
  } else if (code === 402) {
    prefix = 'DeepSeek account out of balance (402)'
  } else if (code === 429) {
    prefix = 'Rate limited (429), retry in a moment'
  } else if (code === 400) {
    prefix = 'Request rejected (400)'
  } else if (code >= 500) {
    prefix = 'DeepSeek server error (' + code + ')'
  } else {
    prefix = 'HTTP ' + code
  }
  return detail.length > 0 ? prefix + ' -- ' + detail : prefix
}

/**
 * Pull the program out of a model reply. A well-behaved reply is already bare
 * source; this only earns its keep when the model adds a markdown fence.
 */
export function extractVeraSource(text: string): string {
  let trimmed = text.trim()
  let fence = trimmed.indexOf('```')
  if (fence < 0) { return trimmed }
  let afterOpen = trimmed.indexOf('\n', fence)
  if (afterOpen < 0) { return trimmed }
  let rest = trimmed.substring(afterOpen + 1)
  let close = rest.indexOf('```')
  if (close < 0) { return rest.trim() }
  return rest.substring(0, close).trim()
}

export class DeepSeekEngine {
  private client: http.HttpRequest | null = null
  private generating: boolean = false
  private cancelled: boolean = false
  private buffer: string = ''
  private rawBody: string = ''
  private text: string = ''
  private inputTokens: number = 0
  private outputTokens: number = 0
  private cacheHitTokens: number = 0
  private finishReason: string = ''
  private thinking: boolean = false
  // Reasoning arrives as its own delta field and is billed as output, so a
  // thinking model looks like a long silence followed by an impossibly fast
  // stream unless the two are timed apart.
  private startedAt: number = 0
  private firstAnyAt: number = 0
  private firstContentAt: number = 0

  /**
   * Thinking is on by default for this model and is billed and capped as
   * output tokens, so a modest max_tokens gets spent reasoning and the program
   * is cut off mid-statement. Callers turn it on only when it is worth paying
   * for.
   */
  setThinking(enabled: boolean): void { this.thinking = enabled }

  isGenerating(): boolean { return this.generating }
  isReady(): boolean { return settings.hasApiKey() }
  lastCacheHitTokens(): number { return this.cacheHitTokens }
  /** Time until the model said anything at all -- reading the prompt. */
  lastPrefillMs(): number {
    return this.firstAnyAt > 0 ? this.firstAnyAt - this.startedAt : 0
  }
  /** Time spent reasoning before the first line of the program appeared. */
  lastThinkMs(): number {
    if (this.firstContentAt === 0 || this.firstAnyAt === 0) { return 0 }
    return this.firstContentAt - this.firstAnyAt
  }
  lastFinishReason(): string { return this.finishReason }

  async generate(request: GenerateRequest, onToken: TokenCallback): Promise<GenerateResult> {
    let key = settings.getApiKey()
    if (key.length === 0) {
      throw new Error('No DeepSeek API key. Send one with: aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey <key>')
    }

    this.text = ''
    this.inputTokens = 0
    this.outputTokens = 0
    this.cacheHitTokens = 0
    this.finishReason = ''
    this.cancelled = false
    this.generating = true
    this.startedAt = Date.now()
    this.firstAnyAt = 0
    this.firstContentAt = 0

    let messages: Record<string, Object>[] = []
    if (request.systemPrompt.length > 0) {
      messages.push(plainMessage('system', request.systemPrompt))
    }
    // Mirrors LlamaEngine.buildPrompt: an existing program is replayed as the
    // assistant's own last turn, so the model edits it instead of restarting.
    if (request.previousSource.length > 0) {
      messages.push(plainMessage('assistant', request.previousSource))
      messages.push(plainMessage('user', 'Refine the program above: ' + request.userPrompt))
    } else {
      messages.push(plainMessage('user', request.userPrompt))
    }

    let round = 0
    let turn: StreamTurn = new StreamTurn()
    let stillAsking = false
    while (round < MAX_TOOL_ROUNDS) {
      round++
      try {
        turn = await this.streamOnce(messages, request.temperature, request.maxTokens, onToken, true)
      } catch (e) {
        this.generating = false
        throw e as Error
      }
      this.inputTokens = this.inputTokens + turn.inputTokens
      this.outputTokens = this.outputTokens + turn.outputTokens
      this.cacheHitTokens = turn.cacheHitTokens
      this.finishReason = turn.finishReason
      if (this.cancelled) { break }
      if (turn.finishReason !== 'tool_calls' || turn.toolCalls.length === 0) {
        this.text += turn.content
        stillAsking = false
        break
      }
      stillAsking = true
      messages.push(assistantToolCallMessage(turn.toolCalls))
      for (let call of turn.toolCalls) {
        let need = ''
        try {
          let args = JSON.parse(call.arguments) as Record<string, Object>
          let n = args['need']
          if (typeof n === 'string') { need = n as string }
        } catch (_e) {
          // Malformed arguments: search with nothing, which finds nothing --
          // the tool result below tells the model that plainly rather than
          // dropping its call silently.
        }
        if (call.name === INTENT_TOOL_NAME) {
          let results = findIntentFunction(need, INTENT_SEARCH_LIMIT)
          console.info('VERA-INTENT-TOOL round=' + round.toString() + ' need="' + need +
            '" found=' + results.length.toString() +
            (results.length > 0 ? ' top=' + results[0].kind + ':' + results[0].name : ''))
          messages.push(toolResultMessage(call.id, intentResultsJson(results)))
        } else {
          let results = findSdkFunctionFromCache(need, SDK_SEARCH_LIMIT)
          console.info('VERA-SDK-TOOL round=' + round.toString() + ' need="' + need +
            '" found=' + results.length.toString() +
            (results.length > 0 ? ' top=' + results[0].kit + '.' + results[0].module + '.' + results[0].name : ''))
          messages.push(toolResultMessage(call.id, sdkResultsJson(results)))
        }
      }
    }

    // MAX_TOOL_ROUNDS was reached while the model was still asking for more:
    // without this, its last round of tool results are computed and pushed
    // to `messages` but never sent back, and the generation ends with
    // nothing -- "produced empty output" -- even though good answers were
    // sitting right there. One last request, tools left off so it cannot
    // ask again, forces a real answer out of what it already has.
    if (stillAsking && !this.cancelled) {
      try {
        let final = await this.streamOnce(messages, request.temperature, request.maxTokens, onToken, false)
        this.inputTokens = this.inputTokens + final.inputTokens
        this.outputTokens = this.outputTokens + final.outputTokens
        this.finishReason = final.finishReason
        this.text += final.content
      } catch (e) {
        this.generating = false
        throw e as Error
      }
    }

    this.generating = false
    let result = new GenerateResult()
    result.text = extractVeraSource(this.text)
    result.inputTokens = this.inputTokens
    result.outputTokens = this.outputTokens
    return result
  }

  stop(): void {
    if (!this.generating) { return }
    this.cancelled = true
    let client = this.client
    if (client !== null) {
      try { client!.destroy() } catch (_e) {}
    }
    this.generating = false
  }

  private cleanup(client: http.HttpRequest): void {
    try { client.off('dataReceive') } catch (_e) {}
    try { client.destroy() } catch (_e) {}
    this.client = null
  }

  /** One request/response cycle: sends `messages`, returns what streamed back. */
  private async streamOnce(messages: Record<string, Object>[], temperature: number,
      maxTokens: number, onToken: TokenCallback, allowTools: boolean): Promise<StreamTurn> {
    let key = settings.getApiKey()
    this.buffer = ''
    this.rawBody = ''
    let turn = new StreamTurn()
    let pending: Map<number, ToolCallAccumulator> = new Map<number, ToolCallAccumulator>()

    let client = http.createHttp()
    this.client = client
    let decoder = util.TextDecoder.create('utf-8')

    client.on('dataReceive', (chunk: ArrayBuffer): void => {
      let piece = ''
      try {
        piece = decoder.decodeToString(new Uint8Array(chunk), { stream: true })
      } catch (e) {
        console.error('DeepSeek decode failed: ' + (e as Error).message)
        return
      }
      this.rawBody += piece
      this.feed(piece, turn, pending, onToken)
    })

    let code = 0
    try {
      let header: Record<string, string> = {}
      header['Content-Type'] = 'application/json'
      header['Accept'] = 'text/event-stream'
      header['Authorization'] = 'Bearer ' + key
      code = await client.requestInStream(settings.getBaseUrl() + '/chat/completions', {
        method: http.RequestMethod.POST,
        header: header,
        extraData: this.buildBody(messages, temperature, maxTokens, allowTools),
        connectTimeout: 15000,
        readTimeout: 300000
      })
    } catch (e) {
      if (this.cancelled) {
        // stop() destroyed the client mid-flight; keep whatever streamed in.
        code = 200
      } else {
        this.cleanup(client)
        throw new Error('DeepSeek request failed: ' + (e as Error).message)
      }
    }
    this.cleanup(client)
    if (code !== 200) {
      throw new Error(httpErrorMessage(code, this.rawBody))
    }

    let toolCalls: ToolCallAccumulator[] = []
    pending.forEach((tc: ToolCallAccumulator) => { toolCalls.push(tc) })
    turn.toolCalls = toolCalls
    return turn
  }

  private buildBody(messages: Record<string, Object>[], temperature: number,
      maxTokens: number, allowTools: boolean): string {
    let payload: Record<string, Object> = {}
    payload['model'] = settings.getModel()
    payload['messages'] = messages
    payload['stream'] = true
    // Without this the streamed response carries no token counts at all.
    let streamOptions: Record<string, Object> = {}
    streamOptions['include_usage'] = true
    payload['stream_options'] = streamOptions
    let thinking: Record<string, Object> = {}
    thinking['type'] = this.thinking ? 'enabled' : 'disabled'
    payload['thinking'] = thinking
    payload['temperature'] = temperature
    payload['max_tokens'] = maxTokens
    // Left off on the forced final round (generate()) so a model that would
    // otherwise keep asking has no way to -- it must answer with whatever
    // tool results it already has.
    if (allowTools) { payload['tools'] = toolSchemas() }
    return JSON.stringify(payload)
  }

  /**
   * Accumulate stream text and hand over every complete line. A chunk can end
   * mid-line, so the tail stays in the buffer until the next chunk arrives.
   */
  private feed(piece: string, turn: StreamTurn, pending: Map<number, ToolCallAccumulator>,
      onToken: TokenCallback): void {
    this.buffer += piece
    let nl = this.buffer.indexOf('\n')
    while (nl >= 0) {
      let line = this.buffer.substring(0, nl)
      this.buffer = this.buffer.substring(nl + 1)
      this.handleLine(line.trim(), turn, pending, onToken)
      nl = this.buffer.indexOf('\n')
    }
  }

  private handleLine(line: string, turn: StreamTurn, pending: Map<number, ToolCallAccumulator>,
      onToken: TokenCallback): void {
    if (line.length === 0 || !line.startsWith('data:')) { return }
    let payload = line.substring(5).trim()
    if (payload.length === 0 || payload === '[DONE]') { return }
    let obj: Record<string, Object>
    try {
      obj = JSON.parse(payload) as Record<string, Object>
    } catch (_e) {
      // A non-SSE body (an error JSON) also arrives here; rawBody keeps it.
      return
    }

    let choices = obj['choices'] as Object[]
    if (choices !== null && choices !== undefined && choices.length > 0) {
      let choice = choices[0] as Record<string, Object>
      let delta = choice['delta'] as Record<string, Object>
      if (delta !== null && delta !== undefined) {
        let reasoning = delta['reasoning_content']
        if (typeof reasoning === 'string' && (reasoning as string).length > 0) {
          if (this.firstAnyAt === 0) { this.firstAnyAt = Date.now() }
        }
        let content = delta['content']
        if (typeof content === 'string') {
          let token = content as string
          if (token.length > 0) {
            if (this.firstAnyAt === 0) { this.firstAnyAt = Date.now() }
            if (this.firstContentAt === 0) { this.firstContentAt = Date.now() }
            turn.content += token
            onToken(token)
          }
        }
        // A tool call streams in fragments keyed by index: id and name once,
        // arguments piece by piece, reassembled here before it's ever parsed.
        let toolCalls = delta['tool_calls'] as Object[]
        if (toolCalls !== null && toolCalls !== undefined) {
          if (this.firstAnyAt === 0) { this.firstAnyAt = Date.now() }
          for (let raw of toolCalls) {
            let tc = raw as Record<string, Object>
            let index = tc['index'] as number
            let acc = pending.get(index)
            if (acc === undefined) {
              acc = new ToolCallAccumulator()
              pending.set(index, acc!)
            }
            let id = tc['id']
            if (typeof id === 'string' && (id as string).length > 0) { acc!.id = id as string }
            let fn = tc['function'] as Record<string, Object>
            if (fn !== null && fn !== undefined) {
              let name = fn['name']
              if (typeof name === 'string' && (name as string).length > 0) { acc!.name = name as string }
              let args = fn['arguments']
              if (typeof args === 'string') { acc!.arguments = acc!.arguments + (args as string) }
            }
          }
        }
      }
      let reason = choice['finish_reason']
      if (typeof reason === 'string') { turn.finishReason = reason as string }
    }

    let usage = obj['usage'] as Record<string, Object>
    if (usage !== null && usage !== undefined) {
      let input = usage['prompt_tokens']
      if (typeof input === 'number') { turn.inputTokens = input as number }
      let output = usage['completion_tokens']
      if (typeof output === 'number') { turn.outputTokens = output as number }
      let cached = usage['prompt_cache_hit_tokens']
      if (typeof cached === 'number') { turn.cacheHitTokens = cached as number }
    }
  }
}

export const deepseek: DeepSeekEngine = new DeepSeekEngine()
