// A CanvasRenderingContext2D stand-in that records what VeraGfx.paintGfx draws as SVG.
//
// paintGfx is the code the phone runs; this implements just the part of the canvas it calls, so a host proof
// of a ui.Surface frame is the phone's own drawing replayed, not a second renderer's idea of it. Points are
// carried through the current transform as they are added (the transforms paintGfx makes are moves, turns and
// uniform scales, so a circle stays a circle), text and Path2D strings are placed with a transform attribute.
'use strict'

class Path2D {
  constructor(d) { this.d = String(d || '') }
}

function esc(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

// 'rgba(r,g,b,a)' -> ['#rrggbb', a]; anything else is passed through opaque.
function paint(colour) {
  const m = /^rgba\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*\)$/.exec(colour)
  if (!m) return [colour, 1]
  const hex = n => Math.round(Number(n)).toString(16).padStart(2, '0')
  return ['#' + hex(m[1]) + hex(m[2]) + hex(m[3]), Number(m[4])]
}

const n = v => Number.isFinite(v) ? Math.round(v * 100) / 100 : 0

// A canvas gradient as paintGfx makes one: its geometry in the units of the transform in force when it is used, its stops in order.
class Gradient {
  constructor(kind, coords) { this.kind = kind; this.coords = coords; this.stops = [] }
  addColorStop(offset, colour) { this.stops.push([offset, colour]) }
}

const BLENDS = {lighter: 'plus-lighter', screen: 'screen', multiply: 'multiply'}

function createRecorder(width, height) {
  const body = []
  const defs = []
  let clipCount = 0
  let state = {m: [1, 0, 0, 1, 0, 0], alpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1, lineCap: 'butt',
    lineJoin: 'miter', font: '14vp sans-serif', textAlign: 'left', textBaseline: 'alphabetic', opened: 0,
    shadowBlur: 0, shadowColor: 'rgba(0,0,0,0)', shadowOffsetX: 0, shadowOffsetY: 0, filter: 'none', composite: 'source-over'}
  let defCount = 0
  const stack = []
  let path = ''
  let cursor = null

  const apply = (x, y) => [state.m[0] * x + state.m[2] * y + state.m[4], state.m[1] * x + state.m[3] * y + state.m[5]]
  const scaleOf = () => Math.hypot(state.m[0], state.m[1])
  const matrix = () => 'matrix(' + state.m.map(n).join(' ') + ')'
  const mul = (a, b) => [a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1], a[0] * b[2] + a[2] * b[3],
    a[1] * b[2] + a[3] * b[3], a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5]]
  // A gradient becomes a def in user space, carried by the transform it is used under (as a canvas reads it); a colour is a colour.
  const ink = style => {
    if (!(style instanceof Gradient)) return paint(style)
    const id = 'g' + (++defCount)
    const stops = style.stops.map(([o, c]) => { const [h, a] = paint(c); return `<stop offset="${n(o)}" stop-color="${esc(h)}" stop-opacity="${n(a)}"/>` }).join('')
    const k = style.coords.map(n)
    defs.push(style.kind === 'linear'
      ? `<linearGradient id="${id}" gradientUnits="userSpaceOnUse" gradientTransform="${matrix()}" x1="${k[0]}" y1="${k[1]}" x2="${k[2]}" y2="${k[3]}">${stops}</linearGradient>`
      : `<radialGradient id="${id}" gradientUnits="userSpaceOnUse" gradientTransform="${matrix()}" cx="${k[0]}" cy="${k[1]}" r="${k[2]}">${stops}</radialGradient>`)
    return [`url(#${id})`, 1]
  }
  // The shadow, filter and composite in force, as attributes of the element drawn under them.
  const effects = () => {
    const parts = []
    const blur = /blur\(\s*([\d.]+)px\s*\)/.exec(state.filter || '')
    const [sc, sa] = paint(state.shadowColor)
    const shadowed = sa > 0 && (state.shadowBlur > 0 || state.shadowOffsetX !== 0 || state.shadowOffsetY !== 0)
    if (shadowed || blur) {
      const id = 'f' + (++defCount)
      // SVG 1.1 primitives (not feDropShadow), so every viewer of a proof draws the shadow.
      let inner = blur ? `<feGaussianBlur in="SourceGraphic" stdDeviation="${n(Number(blur[1]) / 2)}" result="shape"/>` : ''
      const shape = blur ? 'shape' : 'SourceGraphic'
      if (shadowed) {
        inner += `<feGaussianBlur in="${shape}" stdDeviation="${n(state.shadowBlur / 2)}"/>` +
          `<feOffset dx="${n(state.shadowOffsetX)}" dy="${n(state.shadowOffsetY)}" result="moved"/>` +
          `<feFlood flood-color="${esc(sc)}" flood-opacity="${n(sa)}"/><feComposite in2="moved" operator="in"/>` +
          `<feMerge><feMergeNode/><feMergeNode in="${shape}"/></feMerge>`
      }
      defs.push(`<filter id="${id}" x="-50%" y="-50%" width="200%" height="200%" filterUnits="objectBoundingBox">${inner}</filter>`)
      parts.push(`filter="url(#${id})"`)
    }
    if (BLENDS[state.composite]) parts.push(`style="mix-blend-mode:${BLENDS[state.composite]}"`)
    return parts.length ? ' ' + parts.join(' ') : ''
  }
  const fillAttrs = () => { const [c, a] = ink(state.fillStyle); return `fill="${esc(c)}" fill-opacity="${n(a * state.alpha)}"` + effects() }
  const strokeAttrs = width => {
    const [c, a] = ink(state.strokeStyle)
    return `fill="none" stroke="${esc(c)}" stroke-opacity="${n(a * state.alpha)}" stroke-width="${n(width)}" ` +
      `stroke-linecap="${state.lineCap}" stroke-linejoin="${state.lineJoin}"` + effects()
  }
  const lineTo = (x, y) => {
    const [px, py] = apply(x, y)
    path += (path ? ' L' : 'M') + n(px) + ' ' + n(py)
    cursor = [px, py]
  }

  const ctx = {
    get globalAlpha() { return state.alpha }, set globalAlpha(v) { state.alpha = v },
    get fillStyle() { return state.fillStyle }, set fillStyle(v) { state.fillStyle = v },
    get strokeStyle() { return state.strokeStyle }, set strokeStyle(v) { state.strokeStyle = v },
    get lineWidth() { return state.lineWidth }, set lineWidth(v) { state.lineWidth = v },
    get lineCap() { return state.lineCap }, set lineCap(v) { state.lineCap = v },
    get lineJoin() { return state.lineJoin }, set lineJoin(v) { state.lineJoin = v },
    get font() { return state.font }, set font(v) { state.font = v },
    get textAlign() { return state.textAlign }, set textAlign(v) { state.textAlign = v },
    get textBaseline() { return state.textBaseline }, set textBaseline(v) { state.textBaseline = v },
    get shadowBlur() { return state.shadowBlur }, set shadowBlur(v) { state.shadowBlur = v },
    get shadowColor() { return state.shadowColor }, set shadowColor(v) { state.shadowColor = v },
    get shadowOffsetX() { return state.shadowOffsetX }, set shadowOffsetX(v) { state.shadowOffsetX = v },
    get shadowOffsetY() { return state.shadowOffsetY }, set shadowOffsetY(v) { state.shadowOffsetY = v },
    get filter() { return state.filter }, set filter(v) { state.filter = v },
    get globalCompositeOperation() { return state.composite }, set globalCompositeOperation(v) { state.composite = v },
    createLinearGradient(x1, y1, x2, y2) { return new Gradient('linear', [x1, y1, x2, y2]) },
    createRadialGradient(x0, y0, r0, x1, y1, r1) { return new Gradient('radial', [x1, y1, r1]) },
    save() { stack.push(state); state = {...state, m: state.m.slice(), opened: 0} },
    restore() {
      for (let i = 0; i < state.opened; i++) body.push('</g>')
      if (stack.length) state = stack.pop()
    },
    translate(x, y) { state.m = mul(state.m, [1, 0, 0, 1, x, y]) },
    rotate(a) { const c = Math.cos(a), s = Math.sin(a); state.m = mul(state.m, [c, s, -s, c, 0, 0]) },
    scale(x, y) { state.m = mul(state.m, [x, 0, 0, y, 0, 0]) },
    clearRect() {},
    beginPath() { path = ''; cursor = null },
    closePath() { if (path) path += ' Z' },
    moveTo(x, y) { const [px, py] = apply(x, y); path += (path ? ' ' : '') + 'M' + n(px) + ' ' + n(py); cursor = [px, py] },
    lineTo,
    rect(x, y, w, h) {
      ctx.moveTo(x, y); lineTo(x + w, y); lineTo(x + w, y + h); lineTo(x, y + h); ctx.closePath()
    },
    arc(cx, cy, r, from, to, anticlockwise) {
      let sweep = to - from
      if (!anticlockwise && sweep < 0) sweep = sweep % (2 * Math.PI) + 2 * Math.PI
      if (anticlockwise && sweep > 0) sweep = sweep % (2 * Math.PI) - 2 * Math.PI
      if (Math.abs(sweep) >= 2 * Math.PI) sweep = sweep > 0 ? 2 * Math.PI : -2 * Math.PI
      lineTo(cx + r * Math.cos(from), cy + r * Math.sin(from))
      const R = r * scaleOf()
      // An arc of a whole turn has the same start and end, which SVG reads as nothing: draw it as two halves.
      const pieces = Math.abs(sweep) > Math.PI ? 2 : 1
      for (let i = 1; i <= pieces; i++) {
        const a = from + sweep * i / pieces
        const [px, py] = apply(cx + r * Math.cos(a), cy + r * Math.sin(a))
        path += ` A${n(R)} ${n(R)} 0 0 ${sweep > 0 ? 1 : 0} ${n(px)} ${n(py)}`
        cursor = [px, py]
      }
    },
    clip() {
      const id = 'c' + (++clipCount)
      defs.push(`<clipPath id="${id}"><path d="${path}"/></clipPath>`)
      body.push(`<g clip-path="url(#${id})">`)
      state.opened += 1
    },
    fillRect(x, y, w, h) {
      const saved = path
      ctx.beginPath(); ctx.rect(x, y, w, h)
      body.push(`<path d="${path}" ${fillAttrs()}/>`)
      path = saved
    },
    fill(p) {
      if (p instanceof Path2D) body.push(`<path d="${esc(p.d)}" transform="${matrix()}" ${fillAttrs()}/>`)
      else if (path) body.push(`<path d="${path}" ${fillAttrs()}/>`)
    },
    stroke(p) {
      if (p instanceof Path2D) body.push(`<path d="${esc(p.d)}" transform="${matrix()}" ${strokeAttrs(state.lineWidth)}/>`)
      else if (path) body.push(`<path d="${path}" ${strokeAttrs(state.lineWidth * scaleOf())}/>`)
    },
    fillText(text, x, y) {
      const m = /(bold|normal)?\s*([\d.]+)vp/.exec(state.font) || []
      const anchor = state.textAlign === 'center' ? 'middle' : state.textAlign === 'right' ? 'end' : 'start'
      body.push(`<text x="${n(x)}" y="${n(y)}" transform="${matrix()}" font-family="sans-serif" ` +
        `font-size="${n(Number(m[2] || 14))}" font-weight="${m[1] === 'bold' ? 700 : 400}" text-anchor="${anchor}" ` +
        `dominant-baseline="${state.textBaseline === 'middle' ? 'central' : 'alphabetic'}" ${fillAttrs()}>${esc(text)}</text>`)
    },
  }
  return {
    ctx,
    svg() {
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">` +
        `<defs>${defs.join('')}</defs>${body.join('')}</svg>`
    },
    get elements() { return body.length },
  }
}

// paintGfx calls `new Path2D(...)` as the ArkUI global; the host has none.
globalThis.Path2D = globalThis.Path2D || Path2D

module.exports = {createRecorder, Path2D, Gradient}
