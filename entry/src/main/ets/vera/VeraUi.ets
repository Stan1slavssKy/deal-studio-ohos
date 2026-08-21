/**
 * Dynamic-ArkTS port of the static VERA runtime in vera-static-hello.
 *
 * Same algorithm, same control flow; only the type system differs. The static
 * original could not be built for this device, so this measures the VERA
 * pipeline on the ArkTS runtime that will actually run -- see README for what
 * that does and does not establish.
 *
 * Conversions applied, all mechanical:
 *   'use static'        removed
 *   final class         -> class
 *   int / double        -> number
 *   Any                 -> BytecodeValue union
 *   x instanceof number -> typeof x === 'number'   (and string / boolean)
 *   Int.toDouble(a & b) -> a & b        JS bitwise already yields a number
 *   x.toInt()           -> Math.trunc(x) where an index is needed
 */


import { BytecodeArray, BytecodeFunction, BytecodeObject, BytecodeValue, RuntimeResult } from './VeraInterpreter'

const MAX_UI_NODES: number = 80
const MAX_UI_DEPTH: number = 8
const MAX_UI_CHILDREN: number = 20
const MAX_UI_TEXT: number = 2000

export class VeraUiNode {
  id: number
  kind: string
  style: string
  text: string = ''
  source: string = ''
  alt: string = ''
  action: string = ''
  eventValue: BytecodeValue = null
  enabled: boolean = true
  children: VeraUiNode[] = []

  constructor(id: number, kind: string, style: string) {
    this.id = id
    this.kind = kind
    this.style = style
  }
}

export class VeraUiError extends Error {
  path: string

  constructor(path: string, message: string) {
    super(path + ': ' + message)
    this.path = path
  }
}

class NodeCounter {
  value: number = 0
}

function stringField(record: BytecodeObject, field: string, path: string, required: boolean): string {
  let value = record.fields.get(field)
  if (value == undefined || value == null) {
    if (required) {
      throw new VeraUiError(path, `field '${field}' must be a non-empty string`)
    }
    return ''
  }
  if (!(typeof value === 'string')) {
    throw new VeraUiError(path, `field '${field}' must be a string`)
  }
  let text = value as string
  if (required && text.length == 0) {
    throw new VeraUiError(path, `field '${field}' must be a non-empty string`)
  }
  return text
}

function defaultStyle(kind: string): string {
  if (kind == 'card') return 'surface'
  if (kind == 'text') return 'body'
  if (kind == 'image') return 'hero'
  if (kind == 'spacer') return 'medium'
  if (kind == 'button') return 'primary'
  return 'default'
}

function validKind(kind: string): boolean {
  return kind == 'column' || kind == 'row' || kind == 'card' || kind == 'scroll' ||
    kind == 'text' || kind == 'image' || kind == 'spacer' || kind == 'button' || kind == 'cell'
}

function isContainer(kind: string): boolean {
  return kind == 'column' || kind == 'row' || kind == 'card' || kind == 'scroll'
}

function validStyle(kind: string, style: string): boolean {
  if (kind == 'column') {
    return style == 'default' || style == 'compact' || style == 'spacious' || style == 'center' || style == 'surface' || style == 'accent'
  }
  if (kind == 'row') {
    return style == 'default' || style == 'compact' || style == 'spacious' || style == 'center' || style == 'split' || style == 'surface' || style == 'accent'
  }
  if (kind == 'card') {
    return style == 'surface' || style == 'accent' || style == 'success' || style == 'warning' || style == 'danger'
  }
  if (kind == 'scroll') return style == 'default' || style == 'compact'
  if (kind == 'text') {
    return style == 'title' || style == 'heading' || style == 'body' || style == 'caption' || style == 'metric' ||
      style == 'muted' || style == 'success' || style == 'warning' || style == 'danger'
  }
  if (kind == 'image') return style == 'hero' || style == 'thumbnail' || style == 'avatar'
  if (kind == 'spacer') return style == 'small' || style == 'medium' || style == 'large'
  if (kind == 'button') return style == 'primary' || style == 'secondary' || style == 'success' || style == 'danger'
  if (kind == 'cell') return style == 'default' || style == 'accent' || style == 'success' || style == 'danger' || style == 'primary' || style == 'secondary'
  return false
}

function validField(kind: string, field: string): boolean {
  if (field == 'type' || field == 'style') return true
  if (kind == 'text') return field == 'text'
  if (kind == 'image') return field == 'src' || field == 'alt'
  if (kind == 'button' || kind == 'cell') {
    return field == 'text' || field == 'action' || field == 'value' || field == 'enabled'
  }
  if (isContainer(kind)) return field == 'children'
  return false
}

function decodeNode(
  value: BytecodeValue,
  path: string,
  depth: number,
  counter: NodeCounter,
  runtime: RuntimeResult
): VeraUiNode {
  if (!(value instanceof BytecodeObject)) {
    throw new VeraUiError(path, 'node must be an object')
  }
  if (depth > MAX_UI_DEPTH) {
    throw new VeraUiError(path, `tree exceeds depth ${MAX_UI_DEPTH}`)
  }
  counter.value += 1
  if (counter.value > MAX_UI_NODES) {
    throw new VeraUiError(path, `tree exceeds ${MAX_UI_NODES} nodes`)
  }

  let record = value as BytecodeObject
  let kind = stringField(record, 'type', path, true)
  if (!validKind(kind)) {
    throw new VeraUiError(path, `unsupported node type '${kind}'`)
  }
  for (let entry of record.fields) {
    if (!validField(kind, entry[0])) {
      throw new VeraUiError(path, `field '${entry[0]}' is not allowed on '${kind}'`)
    }
  }

  let style = stringField(record, 'style', path, false)
  if (style.length == 0) style = defaultStyle(kind)
  if (!validStyle(kind, style)) {
    throw new VeraUiError(path, `unsupported style '${style}' for '${kind}'`)
  }

  let node = new VeraUiNode(counter.value, kind, style)
  if (kind == 'text') {
    node.text = stringField(record, 'text', path, true)
    if (node.text.length > MAX_UI_TEXT) {
      throw new VeraUiError(path, `text exceeds ${MAX_UI_TEXT} characters`)
    }
    return node
  }
  if (kind == 'image') {
    node.source = stringField(record, 'src', path, true)
    node.alt = stringField(record, 'alt', path, false)
    if (node.source.length > 512 || !node.source.startsWith('https://')) {
      throw new VeraUiError(path, 'image src must be an HTTPS URL no longer than 512 characters')
    }
    if (node.alt.length > 200) {
      throw new VeraUiError(path, 'image alt exceeds 200 characters')
    }
    return node
  }
  if (kind == 'spacer') return node
  if (kind == 'button' || kind == 'cell') {
    // A board cell is legitimately blank until played, so only a button has to
    // carry a label. Keep this in sync with uiSchema.ts on the server.
    node.text = stringField(record, 'text', path, kind == 'button')
    node.action = stringField(record, 'action', path, true)
    if (node.text.length > 200) {
      throw new VeraUiError(path, 'control text exceeds 200 characters')
    }
    let handler = runtime.globals.get(node.action)
    if (!(handler instanceof BytecodeFunction) || (handler as BytecodeFunction).arity != 1) {
      throw new VeraUiError(path, `action '${node.action}' must name a one-argument VERA function`)
    }
    let payload = record.fields.get('value')
    if (!(typeof payload === 'string') && !(typeof payload === 'number') && !(typeof payload === 'boolean')) {
      throw new VeraUiError(path, `field 'value' must be a string, number, or boolean`)
    }
    node.eventValue = payload
    let enabled = record.fields.get('enabled')
    if (enabled != undefined && enabled != null) {
      if (!(typeof enabled === 'boolean')) {
        throw new VeraUiError(path, `field 'enabled' must be a boolean`)
      }
      node.enabled = enabled as boolean
    }
    return node
  }

  let childrenValue = record.fields.get('children')
  if (!(childrenValue instanceof BytecodeArray)) {
    throw new VeraUiError(path, `field 'children' must be an array`)
  }
  let children = (childrenValue as BytecodeArray).values
  if (children.length > MAX_UI_CHILDREN) {
    throw new VeraUiError(path, `node exceeds ${MAX_UI_CHILDREN} children`)
  }
  for (let index: number = 0; index < children.length; index += 1) {
    let child = children[index]
    if (child == undefined) {
      throw new VeraUiError(path, 'child must not be empty')
    }
    node.children.push(decodeNode(child, `${path}.children[${index}]`, depth + 1, counter, runtime))
  }
  return node
}

export function decodeVeraUi(runtime: RuntimeResult): VeraUiNode {
  let renderer = runtime.globals.get('render')
  if (!(renderer instanceof BytecodeFunction) || (renderer as BytecodeFunction).arity != 0) {
    throw new VeraUiError('render', 'program must declare a zero-argument render function')
  }
  let value = runtime.globals.get('ui')
  if (value == undefined || value == null) {
    throw new VeraUiError('ui', "program must expose a top-level global named 'ui'")
  }
  return decodeNode(value, 'ui', 1, new NodeCounter(), runtime)
}
