/**
 * The chat behind pages/ChatPage: one assistant that answers in prose and, when
 * a widget would serve better than a paragraph, asks for one.
 *
 * Two model calls, kept apart on purpose. The chat turn is a plain
 * chat-completion with no tools and no program in it, so it stays quick and the
 * words arrive first. When the reply ends in an app marker, the description in
 * it goes through the same pipeline the Generate screen uses -- the skill
 * prompt, find_sdk_function and find_intent_function, the compiler with its
 * retries -- and comes back as bytecode the renderer can draw inside the
 * conversation. A program therefore never has to be written by the same call
 * that is talking to the person.
 */

import http from '@ohos.net.http'
import util from '@ohos.util'
import { GenerateRequest } from './LlamaEngine'
import { compileVeraSource, CompileError } from './VeraCompiler'
import { deepseek, extractVeraSource } from './DeepSeekEngine'
import { settings } from './SettingsStore'

const APP_OPEN: string = '<<app:'
const APP_CLOSE: string = '>>'
const MAX_ATTEMPTS: number = 3

const CHAT_SYSTEM_PROMPT: string =
  "You are the assistant in a phone chat. Answer briefly in plain text, without markdown.\n" +
  "Answer directly when text is sufficient. Offer one widget when editable inputs, calculations, or controls materially help the request.\n" +
  "If an essential detail is missing and has no safe default, ask one concise question before requesting the widget.\n" +
  "For a widget, include exactly one complete marker on its own line, with this shape:\n" +
  "<<app: one or two self-contained English sentences describing the widget, its controls, starting values, units, and constraints>>\n" +
  "Copy the concrete numbers and names from the conversation into the description. The widget builder receives only that description. " +
  "Do not refer to \"the above\" or omit details that appear elsewhere in the reply. " +
  "Place a brief complete sentence before the marker. Any text after it must also contain complete sentences. " +
  "Use no nested markers or additional markers. Do not show program code.\n" +
  "For a phone action, offer a button that requests the action and shows its returned result. " +
  "Support depends on discovered capabilities, available adapters, permissions, and device behavior. " +
  "Do not promise universal support or claim that this chat reply executed an action. " +
  "An accepted request does not verify the device outcome. Do not promise durable widget state or background alarms.\n" +
  "Do not mention the marker or generation machinery in the visible answer."

export class ChatTurn {
  role: string = 'user'
  text: string = ''
}

/**
 * A reply, split around its widget line. `before` and `after` are the text on
 * either side of it; with no widget line everything is in `before`.
 */
export class ParsedReply {
  before: string = ''
  after: string = ''
  /** Empty until the line is closed with >>. */
  appDescription: string = ''
  /** The line has started but not finished: the widget is still being described. */
  describing: boolean = false
}

export class MiniApp {
  vbc2: string = ''
  source: string = ''
  /** Empty on success; otherwise the last compiler or request error. */
  error: string = ''
  attempts: number = 0
}

/**
 * Works on a reply that may still be arriving: a half-written marker is held
 * back from the text rather than shown, and the widget line counts as complete
 * only once its closing >> is in.
 */
export function parseReply(raw: string): ParsedReply {
  let out = new ParsedReply()
  let open = raw.indexOf(APP_OPEN)
  if (open < 0) {
    out.before = withoutPartialMarker(raw).trim()
    return out
  }
  out.before = raw.substring(0, open).trim()
  let close = raw.indexOf(APP_CLOSE, open)
  if (close < 0) {
    out.describing = true
    return out
  }
  out.appDescription = raw.substring(open + APP_OPEN.length, close).trim()
  let rest = raw.substring(close + APP_CLOSE.length)
  // At most one widget per reply: a second line is dropped, not shown.
  let again = rest.indexOf(APP_OPEN)
  if (again >= 0) { rest = rest.substring(0, again) }
  out.after = rest.trim()
  return out
}

/** "...<<ap" at the end of the text so far is the start of a marker, not text. */
function withoutPartialMarker(text: string): string {
  let longest = Math.min(APP_OPEN.length - 1, text.length)
  for (let n = longest; n > 0; n--) {
    if (text.endsWith(APP_OPEN.substring(0, n))) {
      return text.substring(0, text.length - n)
    }
  }
  return text
}

function plain(role: string, content: string): Record<string, Object> {
  let m: Record<string, Object> = {}
  m['role'] = role
  m['content'] = content
  return m
}

/**
 * One chat turn, streamed. `onText` receives everything said so far, each time
 * more arrives. Throws with a readable message on failure.
 */
export async function chatReply(history: ChatTurn[], onText: (soFar: string) => void): Promise<string> {
  let key = settings.getApiKey()
  if (key.length === 0) {
    throw new Error('No DeepSeek API key. Send one with: aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey <key>')
  }
  let messages: Record<string, Object>[] = [plain('system', CHAT_SYSTEM_PROMPT)]
  for (let t of history) {
    messages.push(plain(t.role, t.text))
  }
  let payload: Record<string, Object> = {}
  payload['model'] = settings.getModel()
  payload['messages'] = messages
  payload['stream'] = true
  let thinking: Record<string, Object> = {}
  thinking['type'] = 'disabled'
  payload['thinking'] = thinking
  payload['temperature'] = 0.7
  payload['max_tokens'] = 1024

  let reply = ''
  let buffer = ''
  let body = ''
  let client = http.createHttp()
  let decoder = util.TextDecoder.create('utf-8')
  client.on('dataReceive', (chunk: ArrayBuffer): void => {
    let piece = ''
    try {
      piece = decoder.decodeToString(new Uint8Array(chunk), { stream: true })
    } catch (_e) {
      return
    }
    body += piece
    buffer += piece
    let nl = buffer.indexOf('\n')
    while (nl >= 0) {
      let line = buffer.substring(0, nl).trim()
      buffer = buffer.substring(nl + 1)
      let delta = contentDelta(line)
      if (delta.length > 0) {
        reply += delta
        onText(reply)
      }
      nl = buffer.indexOf('\n')
    }
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
      extraData: JSON.stringify(payload),
      connectTimeout: 15000,
      readTimeout: 120000
    })
  } catch (e) {
    throw new Error('Chat request failed: ' + (e as Error).message)
  } finally {
    try { client.off('dataReceive') } catch (_e) {}
    try { client.destroy() } catch (_e) {}
  }
  if (code !== 200) {
    throw new Error('HTTP ' + code.toString() + ' ' + body.substring(0, 200))
  }
  return reply
}

/** The text of one SSE line, or '' for anything that carries none. */
function contentDelta(line: string): string {
  if (!line.startsWith('data:')) { return '' }
  let data = line.substring(5).trim()
  if (data.length === 0 || data === '[DONE]') { return '' }
  try {
    let obj = JSON.parse(data) as Record<string, Object>
    let choices = obj['choices'] as Object[]
    if (choices === null || choices === undefined || choices.length === 0) { return '' }
    let delta = (choices[0] as Record<string, Object>)['delta'] as Record<string, Object>
    if (delta === null || delta === undefined) { return '' }
    let content = delta['content']
    return typeof content === 'string' ? content as string : ''
  } catch (_e) {
    return ''
  }
}

/**
 * Turns a widget description into bytecode, retrying with the compiler's
 * diagnostics the way the Generate screen does. `systemPrompt` is the skill with
 * the UI catalogue already spliced in. Calls must not overlap: the engine is a
 * singleton with one generation in flight.
 */
export async function buildMiniApp(systemPrompt: string, description: string,
    onStatus: (status: string) => void): Promise<MiniApp> {
  let result = new MiniApp()
  let failedSource = ''
  let feedback = ''
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    result.attempts = attempt
    onStatus(attempt === 1 ? 'Building a widget...' : 'Fixing the widget (' + attempt.toString() + '/' + MAX_ATTEMPTS.toString() + ')...')
    let request = new GenerateRequest()
    request.systemPrompt = systemPrompt
    request.uiTool = false
    request.temperature = 0.2
    request.maxTokens = attempt > 1 ? 32768 : 8192
    if (feedback.length > 0) {
      request.previousSource = failedSource
      request.userPrompt = description +
        '\n\nThe program above is your previous attempt and it failed to compile:\n' + feedback +
        '\n\nRepair the failed source against these diagnostics. Preserve requested behavior and compatible state field names and types. ' +
        'Return the complete replacement program as source only, not a patch or continuation. ' +
        'If output was truncated, shorten optional content while preserving required behavior.'
    } else {
      request.userPrompt = description
    }
    deepseek.setThinking(attempt > 1)
    let text = ''
    try {
      let gen = await deepseek.generate(request, (_t: string): void => {})
      text = extractVeraSource(gen.text)
    } catch (e) {
      result.error = (e as Error).message
      return result
    }
    let errors = ''
    try {
      result.vbc2 = compileVeraSource(text).vbc2
      result.source = text
      result.error = ''
      return result
    } catch (e) {
      errors = e instanceof CompileError ? e.message : (e as Error).message
    }
    if (deepseek.lastFinishReason() === 'length') {
      errors = 'The previous attempt was cut off at the output token limit. Return a shorter complete replacement program, not a continuation.\n' + errors
    }
    failedSource = text
    feedback = errors
    result.error = errors
  }
  return result
}
