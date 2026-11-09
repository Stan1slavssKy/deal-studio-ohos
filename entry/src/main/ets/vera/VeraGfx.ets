/**
 * std/gfx: what a ui.Surface draws, and how it is drawn.
 *
 * Everything else a program shows is a tree of catalogue components that the
 * renderer lays out and the theme dresses. A surface is the one place that is
 * not true: the program owns every pixel of a box, in its own units, and says
 * what goes where each frame -- a game, a drawing tool, a simulation. So the
 * shapes here carry positions, sizes and colours, which nothing in std/ui does.
 *
 * One table (GFX_FUNCTIONS) is the module: the compiler's interface, the
 * colour check and the prompt's description are generated from it, the way
 * std/ui's are from VeraUiCatalog. Shapes are built by the host as the program
 * calls these functions, decoded into plain GfxOps once per frame, and painted
 * by paintGfx -- the same code on the phone (into an ArkUI Canvas) and on the
 * host (into an SVG recorder in tools/vera-harness), so a proof sheet shows
 * what the phone draws rather than a second opinion of it.
 *
 * Pure apart from paintGfx, which only calls the context it is handed.
 */

import { RuntimeValue, VeraNumberValue, VeraStringValue, VeraBooleanValue, VeraArrayValue, VeraObjectValue,
  RuntimeTrap } from './VeraInterpreter'
import { GfxOp, GFX_ROLES, isGfxColor, gfxColor, hex2 } from './GfxPaint'
export { GfxOp, GfxFit, GFX_ROLES, isGfxColor, gfxColor, gfxFit, gfxToSurface, gfxNaturalHeight, encodeGfxOps, decodeGfxOps, paintGfx } from './GfxPaint'

/** Class identities of the module's two types, as the compiler names them. */
export const GFX_SHAPE: string = 'std/gfx:Shape'
export const GFX_POINTER: string = 'std/gfx:Pointer'

/** The most shapes one frame may draw, counting the inside of every group. Past it the frame traps rather than stalls. */
export const MAX_GFX_SHAPES: number = 4000
/** Groups inside groups, at most. */
export const MAX_GFX_DEPTH: number = 12
/** The most numbers one polyline or polygon may hold: 1000 points. */
export const MAX_GFX_POINTS: number = 2000

export class GfxParam {
  name: string
  /** 'number' | 'string' | 'boolean' | 'number[]' | 'shapes' | 'color' */
  kind: string
  optional: boolean
  constructor(name: string, kind: string, optional: boolean = false) {
    this.name = name; this.kind = kind; this.optional = optional
  }
}

export class GfxFunction {
  name: string
  params: GfxParam[]
  /** 'shape' | 'string' | 'number' | 'boolean' */
  result: string
  summary: string
  constructor(name: string, params: GfxParam[], result: string, summary: string) {
    this.name = name; this.params = params; this.result = result; this.summary = summary
  }
}

function num(name: string): GfxParam { return new GfxParam(name, 'number') }
function color(): GfxParam { return new GfxParam('color', 'color') }

export const GFX_FUNCTIONS: GfxFunction[] = [
  new GfxFunction('rect', [num('x'), num('y'), num('width'), num('height'), color()], 'shape',
    'a filled rectangle; x, y is its top-left corner'),
  new GfxFunction('roundRect', [num('x'), num('y'), num('width'), num('height'), num('radius'), color()], 'shape',
    'a filled rectangle with rounded corners'),
  new GfxFunction('circle', [num('x'), num('y'), num('radius'), color()], 'shape',
    'a filled disc centred on x, y'),
  new GfxFunction('arc', [num('x'), num('y'), num('radius'), num('startDegrees'), num('sweepDegrees'), num('lineWidth'), color()],
    'shape', 'a stroked arc centred on x, y; 0 degrees is twelve o\'clock and angles run clockwise; sweep 360 is a ring'),
  new GfxFunction('line', [num('x1'), num('y1'), num('x2'), num('y2'), num('lineWidth'), color()], 'shape',
    'a straight line with round ends'),
  new GfxFunction('polyline', [new GfxParam('points', 'number[]'), num('lineWidth'), color()], 'shape',
    'a stroked open line through [x0, y0, x1, y1, ...]; for a graph, a trail, a drawn stroke'),
  new GfxFunction('polygon', [new GfxParam('points', 'number[]'), color()], 'shape',
    'a filled closed shape through [x0, y0, x1, y1, ...]; for a star, a ship, a mountain'),
  new GfxFunction('path', [new GfxParam('commands', 'string'), color()], 'shape',
    'a filled SVG path (M L C Q A Z, absolute) in surface units'),
  new GfxFunction('strokePath', [new GfxParam('commands', 'string'), num('lineWidth'), color()], 'shape',
    'an SVG path drawn as a line rather than filled'),
  new GfxFunction('text', [num('x'), num('y'), num('size'), new GfxParam('align', 'string'), color(),
    new GfxParam('text', 'string'), new GfxParam('bold', 'boolean', true)], 'shape',
    'one line of text; align is "left", "center" or "right" about x, and y is the middle of the line'),
  new GfxFunction('group', [num('x'), num('y'), num('rotation'), num('scale'), num('alpha'), new GfxParam('shapes', 'shapes')],
    'shape', 'shapes drawn around their own 0, 0, moved to x, y, turned clockwise by rotation degrees, scaled, and faded by alpha (0..1)'),
  new GfxFunction('rgb', [num('red'), num('green'), num('blue'), new GfxParam('alpha', 'number', true)], 'string',
    'a colour from 0..255 channels and an optional 0..1 alpha, for colours computed at run time'),
  new GfxFunction('distance', [num('x1'), num('y1'), num('x2'), num('y2')], 'number',
    'the distance between two points'),
  new GfxFunction('inside', [num('px'), num('py'), num('x'), num('y'), num('width'), num('height')], 'boolean',
    'whether point px, py lies in the rectangle x, y, width, height'),
]

/** The fields of gfx.Pointer, in the order the prompt lists them. */
export const GFX_POINTER_FIELDS: string[][] = [
  ['phase', 'string'], ['id', 'number'], ['x', 'number'], ['y', 'number'],
]

export const POINTER_PHASES: string[] = ['down', 'move', 'up', 'cancel']

export function gfxFunction(name: string): GfxFunction | null {
  for (let f of GFX_FUNCTIONS) { if (f.name === name) { return f } }
  return null
}

/** A shape as the VM carries it: an object of class gfx.Shape with nothing in it a program can read. */
export class GfxShapeValue extends VeraObjectValue {
  op: GfxOp
  constructor(op: GfxOp) {
    super(GFX_SHAPE, new Map<string, RuntimeValue>())
    this.op = op
  }
}

function asNum(args: RuntimeValue[], i: number, fallback: number = 0): number {
  if (i >= args.length) { return fallback }
  let v = args[i]
  if (v instanceof VeraNumberValue) { return (v as VeraNumberValue).value }
  throw new RuntimeTrap('R0020', 'expected number argument')
}

function asStr(args: RuntimeValue[], i: number, fallback: string = ''): string {
  if (i >= args.length) { return fallback }
  let v = args[i]
  if (v instanceof VeraStringValue) { return (v as VeraStringValue).value }
  throw new RuntimeTrap('R0020', 'expected string argument')
}

function asBool(args: RuntimeValue[], i: number, fallback: boolean = false): boolean {
  if (i >= args.length) { return fallback }
  let v = args[i]
  if (v instanceof VeraBooleanValue) { return (v as VeraBooleanValue).value }
  throw new RuntimeTrap('R0020', 'expected boolean argument')
}

function asNumbers(args: RuntimeValue[], i: number): number[] {
  if (i >= args.length) { return [] }
  let v = args[i]
  if (!(v instanceof VeraArrayValue)) { throw new RuntimeTrap('R0020', 'expected array argument') }
  let items = (v as VeraArrayValue).elements
  if (items.length > MAX_GFX_POINTS) {
    throw new RuntimeTrap('R0028', 'a polyline or polygon holds at most ' + (MAX_GFX_POINTS / 2).toString() +
      ' points; got ' + Math.floor(items.length / 2).toString())
  }
  let out: number[] = []
  for (let item of items) {
    if (item instanceof VeraNumberValue) { out.push((item as VeraNumberValue).value) }
  }
  return out
}

/** The shapes in an array, each once; anything that is not a shape is not drawn. */
function shapesIn(value: RuntimeValue): GfxOp[] {
  let out: GfxOp[] = []
  if (!(value instanceof VeraArrayValue)) { return out }
  for (let item of (value as VeraArrayValue).elements) {
    if (item instanceof GfxShapeValue) { out.push((item as GfxShapeValue).op) }
  }
  return out
}

function shape(op: GfxOp): RuntimeValue {
  return new GfxShapeValue(op)
}

function op(kind: string, colour: string): GfxOp {
  let o = new GfxOp()
  o.kind = kind
  o.color = colour
  return o
}

/** The host side of `import * as gfx from "std/gfx"`. */
export function invokeStdGfx(name: string, args: RuntimeValue[]): RuntimeValue {
  switch (name) {
    case 'rect':
    case 'roundRect': {
      let round = name === 'roundRect'
      let o = op(name, asStr(args, round ? 5 : 4))
      o.x = asNum(args, 0); o.y = asNum(args, 1); o.w = asNum(args, 2); o.h = asNum(args, 3)
      o.r = round ? asNum(args, 4) : 0
      return shape(o)
    }
    case 'circle': {
      let o = op('circle', asStr(args, 3))
      o.x = asNum(args, 0); o.y = asNum(args, 1); o.r = asNum(args, 2)
      return shape(o)
    }
    case 'arc': {
      let o = op('arc', asStr(args, 6))
      o.x = asNum(args, 0); o.y = asNum(args, 1); o.r = asNum(args, 2)
      o.start = asNum(args, 3); o.sweep = asNum(args, 4); o.lineWidth = asNum(args, 5)
      return shape(o)
    }
    case 'line': {
      let o = op('line', asStr(args, 5))
      o.x = asNum(args, 0); o.y = asNum(args, 1); o.w = asNum(args, 2); o.h = asNum(args, 3)
      o.lineWidth = asNum(args, 4)
      return shape(o)
    }
    case 'polyline': {
      let o = op('polyline', asStr(args, 2))
      o.points = asNumbers(args, 0); o.lineWidth = asNum(args, 1)
      return shape(o)
    }
    case 'polygon': {
      let o = op('polygon', asStr(args, 1))
      o.points = asNumbers(args, 0)
      return shape(o)
    }
    case 'path': {
      let o = op('path', asStr(args, 1))
      o.text = asStr(args, 0)
      return shape(o)
    }
    case 'strokePath': {
      let o = op('strokePath', asStr(args, 2))
      o.text = asStr(args, 0); o.lineWidth = asNum(args, 1)
      return shape(o)
    }
    case 'text': {
      let o = op('text', asStr(args, 4))
      o.x = asNum(args, 0); o.y = asNum(args, 1); o.size = asNum(args, 2)
      let align = asStr(args, 3)
      o.align = align === 'center' || align === 'right' ? align : 'left'
      o.text = asStr(args, 5)
      o.bold = asBool(args, 6)
      return shape(o)
    }
    case 'group': {
      let o = op('group', '')
      o.x = asNum(args, 0); o.y = asNum(args, 1); o.start = asNum(args, 2)
      o.r = asNum(args, 3, 1); o.size = Math.max(0, Math.min(1, asNum(args, 4, 1)))
      o.children = args.length > 5 ? shapesIn(args[5]) : []
      let count = 1
      let depth = 0
      for (let c of o.children) {
        count += c.count
        if (c.depth + 1 > depth) { depth = c.depth + 1 }
      }
      if (depth > MAX_GFX_DEPTH) {
        throw new RuntimeTrap('R0028', 'groups nest at most ' + MAX_GFX_DEPTH.toString() + ' deep')
      }
      if (count > MAX_GFX_SHAPES) {
        throw new RuntimeTrap('R0028', 'one frame draws at most ' + MAX_GFX_SHAPES.toString() + ' shapes')
      }
      o.count = count
      o.depth = depth
      return shape(o)
    }
    case 'rgb': {
      let a = Math.max(0, Math.min(1, asNum(args, 3, 1)))
      let text = '#' + hex2(asNum(args, 0)) + hex2(asNum(args, 1)) + hex2(asNum(args, 2))
      return new VeraStringValue(a >= 1 ? text : text + hex2(a * 255))
    }
    case 'distance': {
      let dx = asNum(args, 2) - asNum(args, 0)
      let dy = asNum(args, 3) - asNum(args, 1)
      return new VeraNumberValue(Math.sqrt(dx * dx + dy * dy))
    }
    case 'inside': {
      let px = asNum(args, 0)
      let py = asNum(args, 1)
      let x = asNum(args, 2)
      let y = asNum(args, 3)
      return new VeraBooleanValue(px >= x && py >= y && px <= x + asNum(args, 4) && py <= y + asNum(args, 5))
    }
    default:
      throw new RuntimeTrap('R0015', `unknown std/gfx function: ${name}`)
  }
}

/** A gfx.Pointer for a handler: where a finger is, in the surface's own units. */
export function pointerValue(phase: string, id: number, x: number, y: number): RuntimeValue {
  let fields = new Map<string, RuntimeValue>()
  fields.set('phase', new VeraStringValue(phase))
  fields.set('id', new VeraNumberValue(id))
  fields.set('x', new VeraNumberValue(x))
  fields.set('y', new VeraNumberValue(y))
  return new VeraObjectValue(GFX_POINTER, fields)
}

/** What a draw function returned, as the shapes to paint, back to front. */
export function decodeGfx(value: RuntimeValue): GfxOp[] {
  let ops = shapesIn(value)
  let count = 0
  for (let o of ops) { count += o.count }
  if (count > MAX_GFX_SHAPES) {
    throw new RuntimeTrap('R0028', 'one frame draws at most ' + MAX_GFX_SHAPES.toString() + ' shapes; this one drew ' +
      count.toString())
  }
  return ops
}

function paramText(p: GfxParam): string {
  return p.optional ? '[' + p.name + ']' : p.name
}

/** std/gfx for the model's prompt: every function, the pointer, and the colours. Generated, so it cannot drift. */
export function describeGfxForPrompt(): string {
  let lines: string[] = []
  lines.push('std/gfx (always available as gfx; every function returning gfx.Shape is drawn by a ui.Surface):')
  for (let f of GFX_FUNCTIONS) {
    let args: string[] = []
    for (let p of f.params) { args.push(paramText(p)) }
    let result = f.result === 'shape' ? 'gfx.Shape' : f.result
    lines.push('  gfx.' + f.name + '(' + args.join(', ') + '): ' + result + '  -- ' + f.summary)
  }
  let fields: string[] = []
  for (let pair of GFX_POINTER_FIELDS) { fields.push(pair[0] + ': ' + pair[1]) }
  lines.push('  class gfx.Pointer { ' + fields.join('; ') + ' }  -- phase is ' + POINTER_PHASES.map((p: string): string => '"' + p + '"').join(', ') +
    '; id tells two fingers apart; x, y are in surface units')
  lines.push('  A colour is a role -- ' + GFX_ROLES.join(' ') + ' -- or "#rrggbb" / "#rrggbbaa", or gfx.rgb(...).')
  lines.push('  Roles follow the app\'s theme and dark mode; prefer them, and use your own colours for the things in the scene.')
  return lines.join('\n')
}
