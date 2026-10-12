/**
 * A static picture of a chat widget drawn while its program is still being
 * written.
 *
 * Widget mode asks for the program in this order: imports, classes, helpers,
 * init(), view(), and only then the handlers. Once init() and view() are both
 * complete, the source so far is a program the renderer can draw -- every
 * button names a handler that has not arrived yet, which the compiler accepts
 * under CompileOptions.allowMissingHandlers and the renderer never calls while
 * the preview is up. The chat shows that picture, with taps switched off, until
 * the finished program compiles and replaces it.
 *
 * Kept free of anything that needs a device, so it runs under node on the host
 * with the compiler.
 */

import { compileVeraSource, CompileOptions, CompileError } from './VeraCompiler'

/** At most this many compiles per program: one per closed declaration after view(). */
const MAX_TRIES: number = 8

export class PreviewStep {
  /** A declaration has just been completed, so the list of them changed. */
  changed: boolean = false
  /** Bytecode for a preview newly compiled by this token; empty otherwise. */
  vbc2: string = ''
}

export class WidgetPreviewTracker {
  private text: string = ''
  /** Everything before this index has been read line by line. */
  private scanned: number = 0
  /** The top-level declaration whose body is still arriving; empty between declarations. */
  private open: string = ''
  private closed: string[] = []
  private tries: number = 0
  private shown: boolean = false

  /** Names of the top-level classes and functions completed so far, in order. */
  declarations(): string[] { return this.closed }

  /** Feed the next piece of streamed program text. */
  feed(token: string): PreviewStep {
    let step = new PreviewStep()
    this.text += token
    let nl = this.text.indexOf('\n', this.scanned)
    while (nl >= 0) {
      this.readLine(this.text.substring(this.scanned, nl), this.scanned, step)
      this.scanned = nl + 1
      nl = this.text.indexOf('\n', this.scanned)
    }
    return step
  }

  /**
   * A top-level declaration ends at a closing brace in column 0, or -- for one
   * written on a single line -- where the next declaration starts. Only lines
   * that begin in column 0 are looked at; everything inside a body is indented.
   */
  private readLine(line: string, start: number, step: PreviewStep): void {
    let name = declarationName(line)
    if (name.length > 0) {
      if (this.open.length > 0) { this.close(start, step) }
      this.open = name
      // A one-line declaration is complete on the line it starts.
      if (line.trimEnd().endsWith('}') && balanced(line)) { this.close(start + line.length, step) }
    } else if (line.startsWith('}') && this.open.length > 0) {
      this.close(start + line.length, step)
    }
  }

  private close(end: number, step: PreviewStep): void {
    this.closed.push(this.open)
    this.open = ''
    step.changed = true
    if (this.shown || this.tries >= MAX_TRIES) { return }
    if (this.closed.indexOf('init') < 0 || this.closed.indexOf('view') < 0) { return }
    this.tries++
    let source = withoutFence(this.text.substring(0, end))
    let options = new CompileOptions()
    options.allowMissingHandlers = true
    try {
      step.vbc2 = compileVeraSource(source, '<preview>', options).vbc2
      this.shown = true
    } catch (e) {
      // The usual reason is a helper view() calls that comes later in the
      // source; the next closed declaration may be it.
      let message = e instanceof CompileError ? e.message : (e as Error).message
      console.info('VERA-PREVIEW not yet, after ' + this.closed.join(',') + ': ' + message.split('\n')[0])
    }
  }
}

function declarationName(line: string): string {
  let rest = line
  if (rest.startsWith('async ')) { rest = rest.substring(6) }
  let keyword = rest.startsWith('function ') ? 'function ' : rest.startsWith('class ') ? 'class ' : ''
  if (keyword.length === 0) { return '' }
  rest = rest.substring(keyword.length).trimStart()
  let n = 0
  while (n < rest.length && isNameChar(rest.charAt(n))) { n++ }
  return rest.substring(0, n)
}

function isNameChar(c: string): boolean {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c === '_'
}

/** Braces outside string literals balance on this line. */
function balanced(line: string): boolean {
  let depth = 0
  let quote = ''
  for (let i = 0; i < line.length; i++) {
    let c = line.charAt(i)
    if (quote.length > 0) {
      if (c === '\\') { i++ }
      else if (c === quote) { quote = '' }
    } else if (c === '"' || c === "'") { quote = c }
    else if (c === '{') { depth++ }
    else if (c === '}') { depth-- }
  }
  return depth === 0
}

/** A reply that opened with a markdown fence: drop the fence line. */
function withoutFence(text: string): string {
  let trimmed = text.trimStart()
  if (!trimmed.startsWith('```')) { return text }
  let nl = trimmed.indexOf('\n')
  return nl < 0 ? '' : trimmed.substring(nl + 1)
}
