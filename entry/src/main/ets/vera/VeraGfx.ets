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
import { ResolvedTheme } from './VeraTheme'

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

/**
 * Colours a program names instead of writing one. The theme decides what each
 * is, light and dark, so a surface drawn in roles follows the app's preset and
 * the phone's dark mode the way the rest of the screen does.
 */
export const GFX_ROLES: string[] = ['ink', 'soft', 'muted', 'accent', 'accentFill', 'onAccent', 'background', 'surface',
  'line', 'success', 'warning', 'danger', 'white', 'black', 'clear']

export function gfxFunction(name: string): GfxFunction | null {
  for (let f of GFX_FUNCTIONS) { if (f.name === name) { return f } }
  return null
}

function isHexDigits(s: string): boolean {
  return /^[0-9a-fA-F]+$/.test(s)
}

/** A role or a #rgb / #rrggbb / #rrggbbaa colour: what the compiler accepts as a literal colour. */
export function isGfxColor(c: string): boolean {
  if (GFX_ROLES.indexOf(c) >= 0) { return true }
  if (c.length === 0 || c.charAt(0) !== '#') { return false }
  let digits = c.substring(1)
  return (digits.length === 3 || digits.length === 6 || digits.length === 8) && isHexDigits(digits)
}

function channel(hex: string): number {
  return parseInt(hex, 16)
}

function css(r: number, g: number, b: number, a: number): string {
  if (a >= 1) {
    return '#' + hex2(r) + hex2(g) + hex2(b)
  }
  return 'rgba(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ',' + (Math.round(a * 1000) / 1000).toString() + ')'
}

function hex2(n: number): string {
  let v = Math.max(0, Math.min(255, Math.round(n)))
  return (v < 16 ? '0' : '') + v.toString(16)
}

/** A theme value, which ArkUI writes as #RRGGBB or #AARRGGBB, as a colour a canvas and an SVG both read. */
function themeColor(value: string): string {
  if (value.length === 9 && value.charAt(0) === '#') {
    let a = channel(value.substring(1, 3)) / 255
    return css(channel(value.substring(3, 5)), channel(value.substring(5, 7)), channel(value.substring(7, 9)), a)
  }
  return value
}

/**
 * What a colour the program wrote is on screen. A hex colour is the program's own, in CSS order (#rrggbbaa); a
 * role is the theme's. Anything else is drawn in ink -- a misspelt colour should still show the shape.
 */
export function gfxColor(t: ResolvedTheme, c: string): string {
  if (c.length > 0 && c.charAt(0) === '#' && isGfxColor(c)) {
    let d = c.substring(1)
    if (d.length === 3) {
      return css(channel(d.charAt(0) + d.charAt(0)), channel(d.charAt(1) + d.charAt(1)), channel(d.charAt(2) + d.charAt(2)), 1)
    }
    let a = d.length === 8 ? channel(d.substring(6, 8)) / 255 : 1
    return css(channel(d.substring(0, 2)), channel(d.substring(2, 4)), channel(d.substring(4, 6)), a)
  }
  if (c === 'soft') { return themeColor(t.inkSoft) }
  if (c === 'muted') { return themeColor(t.inkMuted) }
  if (c === 'accent') { return themeColor(t.primary) }
  if (c === 'accentFill') { return themeColor(t.primaryFill) }
  if (c === 'onAccent') { return themeColor(t.onPrimary) }
  if (c === 'background') { return themeColor(t.background) }
  if (c === 'surface') { return themeColor(t.surface) }
  if (c === 'line') { return themeColor(t.line) }
  if (c === 'success') { return themeColor(t.success) }
  if (c === 'warning') { return themeColor(t.warning) }
  if (c === 'danger') { return themeColor(t.danger) }
  if (c === 'white') { return '#ffffff' }
  if (c === 'black') { return '#000000' }
  if (c === 'clear') { return 'rgba(0,0,0,0)' }
  return themeColor(t.ink)
}

/** One thing to draw, as the program asked for it. Plain data: built by the host functions, read by paintGfx. */
export class GfxOp {
  /** rect | roundRect | circle | arc | line | polyline | polygon | path | strokePath | text | group */
  kind: string = ''
  x: number = 0
  y: number = 0
  /** width, or x2 for a line */
  w: number = 0
  /** height, or y2 for a line */
  h: number = 0
  /** radius; for a group its scale */
  r: number = 0
  /** arc start, group rotation, in degrees */
  start: number = 0
  sweep: number = 0
  lineWidth: number = 0
  /** text size, or a group's alpha */
  size: number = 0
  color: string = ''
  text: string = ''
  align: string = 'left'
  bold: boolean = false
  points: number[] = []
  children: GfxOp[] = []
  /** Shapes in this one, itself included; the frame limit counts these. */
  count: number = 1
  depth: number = 0
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

/**
 * How a surface of w x h units sits in a box of boxW x boxH vp: as large as fits whole, centred. The program's
 * units never change with the phone, so a ball at 50, 50 is at the same place on every screen.
 */
export class GfxFit {
  scale: number = 1
  offsetX: number = 0
  offsetY: number = 0
}

export function gfxFit(boxW: number, boxH: number, w: number, h: number): GfxFit {
  let fit = new GfxFit()
  if (!(w > 0) || !(h > 0) || !(boxW > 0) || !(boxH > 0)) { return fit }
  fit.scale = Math.min(boxW / w, boxH / h)
  fit.offsetX = (boxW - w * fit.scale) / 2
  fit.offsetY = (boxH - h * fit.scale) / 2
  return fit
}

/** A point in the box, in vp, as surface units: [x, y]. Outside the surface it is outside 0..w, 0..h, not clamped. */
export function gfxToSurface(fit: GfxFit, x: number, y: number): number[] {
  return [(x - fit.offsetX) / fit.scale, (y - fit.offsetY) / fit.scale]
}

/** How tall a surface of w x h units is drawn when it is as wide as the box and its style does not fill the screen. */
export function gfxNaturalHeight(boxW: number, w: number, h: number): number {
  if (!(w > 0) || !(h > 0) || !(boxW > 0)) { return 0 }
  return boxW * h / w
}

function finite(o: GfxOp): boolean {
  return isFinite(o.x) && isFinite(o.y) && isFinite(o.w) && isFinite(o.h) && isFinite(o.r) &&
    isFinite(o.start) && isFinite(o.sweep) && isFinite(o.lineWidth) && isFinite(o.size)
}

const RAD: number = Math.PI / 180

/**
 * Draw one frame of a surface into a box of boxW x boxH vp. The box is filled with the theme's background, the
 * surface's w x h units are fitted into it (gfxFit) and filled with the theme's surface colour, and the shapes are
 * drawn back to front, clipped to the surface.
 *
 * A shape with a non-finite number is skipped rather than drawn wrong: a NaN from a division by zero would
 * otherwise leave the canvas in a state the rest of the frame inherits.
 */
export function paintGfx(ctx: CanvasRenderingContext2D, ops: GfxOp[], t: ResolvedTheme,
    boxW: number, boxH: number, w: number, h: number): void {
  let fit = gfxFit(boxW, boxH, w, h)
  ctx.save()
  ctx.clearRect(0, 0, boxW, boxH)
  ctx.globalAlpha = 1
  ctx.fillStyle = themeColor(t.background)
  ctx.fillRect(0, 0, boxW, boxH)
  ctx.translate(fit.offsetX, fit.offsetY)
  ctx.scale(fit.scale, fit.scale)
  ctx.beginPath()
  ctx.rect(0, 0, w, h)
  // No card of its own: a surface among a screen's sections stands on the page like they do, and one that wants a
  // panel draws it (gfx.rect in "surface").
  ctx.clip()
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  for (let o of ops) { paintOp(ctx, o, t) }
  ctx.restore()
}

function paintOp(ctx: CanvasRenderingContext2D, o: GfxOp, t: ResolvedTheme): void {
  if (!finite(o)) { return }
  if (o.kind === 'group') {
    ctx.save()
    ctx.translate(o.x, o.y)
    if (o.start !== 0) { ctx.rotate(o.start * RAD) }
    if (o.r !== 1) { ctx.scale(o.r, o.r) }
    ctx.globalAlpha = ctx.globalAlpha * o.size
    for (let c of o.children) { paintOp(ctx, c, t) }
    ctx.restore()
    return
  }
  let c = gfxColor(t, o.color)
  if (o.kind === 'rect') {
    ctx.fillStyle = c
    ctx.fillRect(o.x, o.y, o.w, o.h)
  } else if (o.kind === 'roundRect') {
    let r = Math.max(0, Math.min(o.r, Math.abs(o.w) / 2, Math.abs(o.h) / 2))
    ctx.beginPath()
    ctx.moveTo(o.x + r, o.y)
    ctx.lineTo(o.x + o.w - r, o.y)
    ctx.arc(o.x + o.w - r, o.y + r, r, -Math.PI / 2, 0, false)
    ctx.lineTo(o.x + o.w, o.y + o.h - r)
    ctx.arc(o.x + o.w - r, o.y + o.h - r, r, 0, Math.PI / 2, false)
    ctx.lineTo(o.x + r, o.y + o.h)
    ctx.arc(o.x + r, o.y + o.h - r, r, Math.PI / 2, Math.PI, false)
    ctx.lineTo(o.x, o.y + r)
    ctx.arc(o.x + r, o.y + r, r, Math.PI, Math.PI * 1.5, false)
    ctx.closePath()
    ctx.fillStyle = c
    ctx.fill()
  } else if (o.kind === 'circle') {
    if (o.r <= 0) { return }
    ctx.beginPath()
    ctx.arc(o.x, o.y, o.r, 0, Math.PI * 2, false)
    ctx.closePath()
    ctx.fillStyle = c
    ctx.fill()
  } else if (o.kind === 'arc') {
    if (o.r <= 0 || o.sweep === 0 || o.lineWidth <= 0) { return }
    let sweep = Math.max(-360, Math.min(360, o.sweep))
    let from = (o.start - 90) * RAD
    ctx.beginPath()
    ctx.arc(o.x, o.y, o.r, from, from + sweep * RAD, sweep < 0)
    ctx.strokeStyle = c
    ctx.lineWidth = o.lineWidth
    ctx.stroke()
  } else if (o.kind === 'line') {
    if (o.lineWidth <= 0) { return }
    ctx.beginPath()
    ctx.moveTo(o.x, o.y)
    ctx.lineTo(o.w, o.h)
    ctx.strokeStyle = c
    ctx.lineWidth = o.lineWidth
    ctx.stroke()
  } else if (o.kind === 'polyline' || o.kind === 'polygon') {
    if (o.points.length < 4) { return }
    ctx.beginPath()
    ctx.moveTo(o.points[0], o.points[1])
    for (let i = 2; i + 1 < o.points.length; i += 2) { ctx.lineTo(o.points[i], o.points[i + 1]) }
    if (o.kind === 'polygon') {
      ctx.closePath()
      ctx.fillStyle = c
      ctx.fill()
    } else {
      if (o.lineWidth <= 0) { return }
      ctx.strokeStyle = c
      ctx.lineWidth = o.lineWidth
      ctx.stroke()
    }
  } else if (o.kind === 'path' || o.kind === 'strokePath') {
    if (o.text.length === 0) { return }
    let p = new Path2D(o.text)
    if (o.kind === 'path') {
      ctx.fillStyle = c
      ctx.fill(p)
    } else {
      if (o.lineWidth <= 0) { return }
      ctx.strokeStyle = c
      ctx.lineWidth = o.lineWidth
      ctx.stroke(p)
    }
  } else if (o.kind === 'text') {
    if (o.size <= 0 || o.text.length === 0) { return }
    ctx.font = (o.bold ? 'bold ' : 'normal ') + o.size.toString() + 'vp sans-serif'
    ctx.textAlign = o.align === 'center' ? 'center' : o.align === 'right' ? 'right' : 'left'
    ctx.textBaseline = 'middle'
    ctx.fillStyle = c
    ctx.fillText(o.text, o.x, o.y)
  }
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
