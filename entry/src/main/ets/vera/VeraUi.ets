import {
  RuntimeValue,
  VeraIntValue,
  VeraNumberValue,
  VeraStringValue,
  VeraBooleanValue,
  VeraNullValue,
  VeraArrayValue,
  VeraObjectValue,
  NULL_VALUE,
  HostEnvironment,
  RuntimeTrap,
} from './VeraInterpreter'

export class VeraUiNode {
  id: number = 0
  kind: string = ''
  style: string = ''
  text: string = ''
  source: string = ''
  alt: string = ''
  action: string = ''
  eventValue: number = 0
  enabled: boolean = true
  children: VeraUiNode[] = []
}

function asString(v: RuntimeValue): string {
  if (v instanceof VeraStringValue) { return (v as VeraStringValue).value }
  throw new RuntimeTrap('R0020', 'expected string argument')
}

function asInt(v: RuntimeValue): number {
  if (v instanceof VeraIntValue) { return (v as VeraIntValue).value }
  throw new RuntimeTrap('R0020', 'expected int argument')
}

function asBool(v: RuntimeValue): boolean {
  if (v instanceof VeraBooleanValue) { return (v as VeraBooleanValue).value }
  throw new RuntimeTrap('R0020', 'expected boolean argument')
}

function asArray(v: RuntimeValue): VeraArrayValue {
  if (v instanceof VeraArrayValue) { return v as VeraArrayValue }
  throw new RuntimeTrap('R0020', 'expected array argument')
}

function viewNode(type: string, fields: Array<[string, RuntimeValue]>): VeraObjectValue {
  let map = new Map<string, RuntimeValue>()
  map.set('type', new VeraStringValue(type))
  for (let pair of fields) {
    map.set(pair[0], pair[1])
  }
  return new VeraObjectValue('std/ui:View', map)
}

function containerNode(type: string, args: RuntimeValue[]): RuntimeValue {
  return viewNode(type, [
    ['style', new VeraStringValue(asString(args[0]))],
    ['children', asArray(args[1])],
  ])
}

export class UiHostEnvironment extends HostEnvironment {
  invoke(module: string, name: string, args: RuntimeValue[], awaited: boolean): RuntimeValue {
    if (module !== 'std/ui') {
      throw new RuntimeTrap('R0015', `external function unavailable: ${module}.${name}`)
    }
    switch (name) {
      case 'Column': return containerNode('column', args)
      case 'Row': return containerNode('row', args)
      case 'Card': return containerNode('card', args)
      case 'Scroll': return containerNode('scroll', args)
      case 'Text':
        return viewNode('text', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['text', new VeraStringValue(asString(args[1]))],
        ])
      case 'Spacer':
        return viewNode('spacer', [
          ['style', new VeraStringValue(asString(args[0]))],
        ])
      case 'Image':
        return viewNode('image', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['src', new VeraStringValue(asString(args[1]))],
          ['alt', new VeraStringValue(asString(args[2]))],
        ])
      case 'Button':
        return viewNode('button', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['text', new VeraStringValue(asString(args[1]))],
          ['action', new VeraStringValue(asString(args[2]))],
          ['value', new VeraIntValue(asInt(args[3]))],
          ['enabled', new VeraBooleanValue(asBool(args[4]))],
        ])
      case 'Cell':
        return viewNode('cell', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['text', new VeraStringValue(asString(args[1]))],
          ['action', new VeraStringValue(asString(args[2]))],
          ['value', new VeraIntValue(asInt(args[3]))],
          ['enabled', new VeraBooleanValue(asBool(args[4]))],
        ])
      case 'When':
        if (asBool(args[0])) { return args[1] }
        return viewNode('spacer', [['style', new VeraStringValue('none')]])
      case 'intToString':
        return new VeraStringValue(asInt(args[0]).toString())
      case 'numberToString': {
        if (!(args[0] instanceof VeraNumberValue)) { throw new RuntimeTrap('R0020', 'expected number argument') }
        return new VeraStringValue((args[0] as VeraNumberValue).value.toString())
      }
      case 'booleanToString':
        return new VeraStringValue(asBool(args[0]) ? 'true' : 'false')
      default:
        throw new RuntimeTrap('R0015', `unknown std/ui function: ${name}`)
    }
  }
}

let nextNodeId: number = 0

export function decodeVeraUi(value: RuntimeValue): VeraUiNode[] {
  nextNodeId = 0
  if (value instanceof VeraObjectValue) {
    return [decodeNode(value as VeraObjectValue, 0)]
  }
  return []
}

function decodeNode(obj: VeraObjectValue, depth: number): VeraUiNode {
  if (depth > 8) { throw new RuntimeTrap('R0021', 'view tree too deep (max 8)') }
  let node = new VeraUiNode()
  node.id = nextNodeId
  nextNodeId += 1
  let typeVal = obj.fields.get('type')
  if (typeVal != undefined && typeVal instanceof VeraStringValue) {
    node.kind = (typeVal as VeraStringValue).value
  }
  let styleVal = obj.fields.get('style')
  if (styleVal != undefined && styleVal instanceof VeraStringValue) {
    node.style = (styleVal as VeraStringValue).value
  }
  let textVal = obj.fields.get('text')
  if (textVal != undefined && textVal instanceof VeraStringValue) {
    node.text = (textVal as VeraStringValue).value
  }
  let srcVal = obj.fields.get('src')
  if (srcVal != undefined && srcVal instanceof VeraStringValue) {
    node.source = (srcVal as VeraStringValue).value
  }
  let altVal = obj.fields.get('alt')
  if (altVal != undefined && altVal instanceof VeraStringValue) {
    node.alt = (altVal as VeraStringValue).value
  }
  let actionVal = obj.fields.get('action')
  if (actionVal != undefined && actionVal instanceof VeraStringValue) {
    node.action = (actionVal as VeraStringValue).value
  }
  let valueVal = obj.fields.get('value')
  if (valueVal != undefined && valueVal instanceof VeraIntValue) {
    node.eventValue = (valueVal as VeraIntValue).value
  }
  let enabledVal = obj.fields.get('enabled')
  if (enabledVal != undefined && enabledVal instanceof VeraBooleanValue) {
    node.enabled = (enabledVal as VeraBooleanValue).value
  }
  let childrenVal = obj.fields.get('children')
  if (childrenVal != undefined && childrenVal instanceof VeraArrayValue) {
    let arr = childrenVal as VeraArrayValue
    for (let child of arr.elements) {
      if (child instanceof VeraObjectValue) {
        node.children.push(decodeNode(child as VeraObjectValue, depth + 1))
      }
    }
  }
  return node
}
