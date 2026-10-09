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
import { GenerateRequest } from './LlamaEngine'
import { compileVeraSource, CompileError } from './VeraCompiler'
import { deepseek, extractVeraSource } from './DeepSeekEngine'
import { settings } from './SettingsStore'

const APP_OPEN: string = '<<app:'
const APP_CLOSE: string = '>>'
const MAX_ATTEMPTS: number = 3

const CHAT_SYSTEM_PROMPT: string =
  'You are the assistant in a phone chat. Answer briefly, in plain text with no markdown.\n' +
  'When a small interactive widget would help the person more than a paragraph would -- a calculator, ' +
  'converter, split-the-bill, timer, planner, tracker, checklist, quiz, picker, form -- finish your reply ' +
  'with one last line of exactly this shape:\n' +
  '<<app: one or two sentences describing the widget in English, with the concrete numbers and names from the conversation>>\n' +
  'A widget can also act on the phone itself -- flashlight, alarms, timers, navigation, calendar, opening other apps -- ' +
  'so when the person wants the phone to do something, never say you cannot: offer a widget and name those actions in the line ' +
  'as real buttons (for example "buttons that turn the flashlight on and off").\n' +
  'The widget is built from that line alone, so put everything it needs in it. At most one per reply. ' +
  'Never for something a sentence answers. Never mention the line or the widget machinery in the text.'

export class ChatTurn {
  role: string = 'user'
  text: string = ''
}

/** What a reply came to once the marker is taken out of it. */
export class ParsedReply {
  text: string = ''
  /** Empty when the reply asked for no widget. */
  appDescription: string = ''
}

export class MiniApp {
  vbc2: string = ''
  source: string = ''
  /** Empty on success; otherwise the last compiler or request error. */
  error: string = ''
  attempts: number = 0
}

export function parseReply(raw: string): ParsedReply {
  let out = new ParsedReply()
  let open = raw.lastIndexOf(APP_OPEN)
  if (open < 0) {
    out.text = raw.trim()
    return out
  }
  let close = raw.indexOf(APP_CLOSE, open)
  let end = close < 0 ? raw.length : close
  out.appDescription = raw.substring(open + APP_OPEN.length, end).trim()
  out.text = (raw.substring(0, open) + (close < 0 ? '' : raw.substring(close + APP_CLOSE.length))).trim()
  return out
}

function plain(role: string, content: string): Record<string, Object> {
  let m: Record<string, Object> = {}
  m['role'] = role
  m['content'] = content
  return m
}

/** One non-streaming chat turn. Throws with a readable message on failure. */
export async function chatReply(history: ChatTurn[]): Promise<string> {
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
  let thinking: Record<string, Object> = {}
  thinking['type'] = 'disabled'
  payload['thinking'] = thinking
  payload['temperature'] = 0.7
  payload['max_tokens'] = 1024

  let client = http.createHttp()
  try {
    let header: Record<string, string> = {}
    header['Content-Type'] = 'application/json'
    header['Authorization'] = 'Bearer ' + key
    let resp = await client.request(settings.getBaseUrl() + '/chat/completions', {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(payload),
      connectTimeout: 15000,
      readTimeout: 120000
    })
    if (resp.responseCode !== 200) {
      throw new Error('HTTP ' + resp.responseCode.toString() + ' ' + String(resp.result).substring(0, 200))
    }
    let body = JSON.parse(resp.result as string) as Record<string, Object>
    let choices = body['choices'] as Object[]
    let first = choices[0] as Record<string, Object>
    let message = first['message'] as Record<string, Object>
    return (message['content'] as string) || ''
  } finally {
    client.destroy()
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
        '\n\nFix these errors and return the complete program.'
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
      errors = 'The previous attempt was cut off at the output token limit, so it did not parse. Write a shorter program.\n' + errors
    }
    failedSource = text
    feedback = errors
    result.error = errors
  }
  return result
}
