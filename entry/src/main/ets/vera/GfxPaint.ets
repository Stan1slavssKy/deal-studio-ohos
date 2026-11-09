/**
 * std/gfx's painting and its plain data, apart from the VM: the shapes a frame is made of (GfxOp), how they are carried in a card's
 * binding (encodeGfxOps), where a surface sits in its box (gfxFit) and the one painter (paintGfx) the phone's Canvas, the home-screen card and
 * the host's SVG recorder all use. Nothing here imports the interpreter, so a card that draws a picture loads this and the theme, not the VM.
 * VeraGfx re-exports all of it.
 */

import { ResolvedTheme } from './VeraTheme'

/**
 * Colours a program names instead of writing one. The theme decides what each
 * is, light and dark, so a surface drawn in roles follows the app's preset and
 * the phone's dark mode the way the rest of the screen does.
 */
export const GFX_ROLES: string[] = ['ink', 'soft', 'muted', 'accent', 'accentFill', 'onAccent', 'background', 'surface',
  'line', 'success', 'warning', 'danger', 'white', 'black', 'clear']

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

export function hex2(n: number): string {
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

function packGfxOp(o: GfxOp): Object {
  let r: Record<string, Object> = {}
  r['k'] = o.kind
  if (o.x !== 0) { r['x'] = o.x }
  if (o.y !== 0) { r['y'] = o.y }
  if (o.w !== 0) { r['w'] = o.w }
  if (o.h !== 0) { r['h'] = o.h }
  if (o.r !== 0) { r['r'] = o.r }
  if (o.start !== 0) { r['a'] = o.start }
  if (o.sweep !== 0) { r['s'] = o.sweep }
  if (o.lineWidth !== 0) { r['l'] = o.lineWidth }
  if (o.size !== 0) { r['z'] = o.size }
  if (o.color.length > 0) { r['c'] = o.color }
  if (o.text.length > 0) { r['t'] = o.text }
  if (o.align !== 'left') { r['n'] = o.align }
  if (o.bold) { r['b'] = true }
  if (o.points.length > 0) { r['p'] = o.points }
  if (o.children.length > 0) { r['o'] = o.children.map((c: GfxOp): Object => packGfxOp(c)) }
  return r
}

function unpackGfxOp(item: Object): GfxOp {
  let r = item as Record<string, Object>
  let o = new GfxOp()
  o.kind = typeof r['k'] === 'string' ? r['k'] as string : ''
  o.x = packedNumber(r, 'x'); o.y = packedNumber(r, 'y'); o.w = packedNumber(r, 'w'); o.h = packedNumber(r, 'h')
  o.r = packedNumber(r, 'r'); o.start = packedNumber(r, 'a'); o.sweep = packedNumber(r, 's')
  o.lineWidth = packedNumber(r, 'l'); o.size = packedNumber(r, 'z')
  o.color = typeof r['c'] === 'string' ? r['c'] as string : ''
  o.text = typeof r['t'] === 'string' ? r['t'] as string : ''
  o.align = typeof r['n'] === 'string' ? r['n'] as string : 'left'
  o.bold = r['b'] === true
  if (Array.isArray(r['p'])) {
    o.points = (r['p'] as Object[]).map((v: Object): number => typeof v === 'number' ? v as number : 0)
  }
  if (Array.isArray(r['o'])) {
    o.children = (r['o'] as Object[]).map((c: Object): GfxOp => unpackGfxOp(c))
  }
  return o
}

function packedNumber(r: Record<string, Object>, key: string): number {
  return typeof r[key] === 'number' ? r[key] as number : 0
}

/** The shapes a card carries, in the binding: only what each one sets, so a picture of a dozen shapes stays a few hundred characters. */
export function encodeGfxOps(ops: GfxOp[]): string {
  return JSON.stringify(ops.map((o: GfxOp): Object => packGfxOp(o)))
}

/** What encodeGfxOps wrote, back to shapes paintGfx can draw. A text that is not that gives no shapes. */
export function decodeGfxOps(text: string): GfxOp[] {
  try {
    let items = JSON.parse(text) as Object[]
    return Array.isArray(items) ? items.map((item: Object): GfxOp => unpackGfxOp(item)) : []
  } catch (_e) {
    return []
  }
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
 * surface's w x h units are fitted into it (gfxFit), and the shapes are drawn back to front, clipped to the surface.
 *
 * `pathScale` is the pixels in a vp on the screen drawn to: ArkUI reads a path string (gfx.path, gfx.strokePath) in
 * pixels whatever the canvas's own unit, so a path is drawn under that much more scale -- without it a signature pad's
 * frame came out a third of its size on a phone of density 3.4. The host's SVG recorder draws in one unit and passes 1.
 *
 * A shape with a non-finite number is skipped rather than drawn wrong: a NaN from a division by zero would
 * otherwise leave the canvas in a state the rest of the frame inherits.
 */
export function paintGfx(ctx: CanvasRenderingContext2D, ops: GfxOp[], t: ResolvedTheme,
    boxW: number, boxH: number, w: number, h: number, pathScale: number = 1): void {
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
  for (let o of ops) { paintOp(ctx, o, t, pathScale) }
  ctx.restore()
}

function paintOp(ctx: CanvasRenderingContext2D, o: GfxOp, t: ResolvedTheme, pathScale: number): void {
  if (!finite(o)) { return }
  if (o.kind === 'group') {
    ctx.save()
    ctx.translate(o.x, o.y)
    if (o.start !== 0) { ctx.rotate(o.start * RAD) }
    if (o.r !== 1) { ctx.scale(o.r, o.r) }
    ctx.globalAlpha = ctx.globalAlpha * o.size
    for (let c of o.children) { paintOp(ctx, c, t, pathScale) }
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
    if (o.kind === 'strokePath' && o.lineWidth <= 0) { return }
    // The path string is read in pixels (see paintGfx): scaled up by as many pixels as a vp has, it lands in units.
    let p = new Path2D(o.text)
    ctx.save()
    ctx.scale(pathScale, pathScale)
    if (o.kind === 'path') {
      ctx.fillStyle = c
      ctx.fill(p)
    } else {
      ctx.strokeStyle = c
      ctx.lineWidth = o.lineWidth / pathScale
      ctx.stroke(p)
    }
    ctx.restore()
  } else if (o.kind === 'text') {
    if (o.size <= 0 || o.text.length === 0) { return }
    ctx.font = (o.bold ? 'bold ' : 'normal ') + o.size.toString() + 'vp sans-serif'
    ctx.textAlign = o.align === 'center' ? 'center' : o.align === 'right' ? 'right' : 'left'
    ctx.textBaseline = 'middle'
    ctx.fillStyle = c
    ctx.fillText(o.text, o.x, o.y)
  }
}

