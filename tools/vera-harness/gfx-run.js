#!/usr/bin/env node
// Play a program's ui.Surface on the host: init, view, then frames at a fixed step with scripted fingers, and
// draw chosen frames to SVG with the phone's own painter (VeraGfx.paintGfx into gfx-svg.js's recorder).
//
//   node tools/vera-harness/gfx-run.js program.vera --frames=240 --dt=16 --every=60 --out=/tmp/catch \
//     --events='[[10,"down",0,180,600],[11,"up",0,180,600]]' [--box=360x740] [--preset=clean] [--dark=true]
//
// An event is [frame, phase, id, x, y] in the surface's own units, delivered before that frame's step. Frames
// are deterministic -- the elapsed time is the step, not the clock -- so the same run draws the same pictures.
// Prints a JSON summary: frames played, shapes drawn per drawn frame, the files written, and the trap if one
// stopped it. Exit status 1 on a compile error or a trap.
'use strict'
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const {createRecorder} = require('./gfx-svg')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, VeraNumberValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const {decodeGfx, paintGfx, pointerValue, gfxFit} = loadVera('VeraGfx')
const {resolveTheme} = loadVera('VeraTheme')

function surfaces(node, out = []) {
  if (node.kind === 'surface') out.push(node)
  for (const c of node.children || []) surfaces(c, out)
  return out
}

function play(source, options = {}) {
  const frames = options.frames ?? 120
  const dt = options.dt ?? 16
  const every = options.every ?? 0
  const events = options.events ?? []
  const drawn = []
  const vm = new VirtualMachine(deserializeVbc2(compileVeraSource(source).vbc2), new UiHostEnvironment())
  let state = vm.execute('init')
  const root = decodeVeraUi(vm.execute('view', [state]))[0]
  const found = root ? surfaces(root) : []
  if (found.length === 0) throw Error('view() draws no ui.Surface')
  const s = found[0]
  const w = s.minimum, h = s.maximum
  const [boxW, boxH] = options.box ?? [w, h]
  const theme = resolveTheme(options.preset ?? (root.kind === 'apptheme' ? root.style : 'clean'),
    root.kind === 'apptheme' ? root.value : '', options.dark === true)
  const summary = {surface: {style: s.style, width: w, height: h, draw: s.label, frame: s.action, pointer: s.value},
    box: [boxW, boxH], fit: gfxFit(boxW, boxH, w, h), frames: 0, drawn: [], trap: ''}
  const render = i => {
    const ops = decodeGfx(vm.execute(s.label, [state]))
    const rec = createRecorder(boxW, boxH)
    paintGfx(rec.ctx, ops, theme, boxW, boxH, w, h)
    drawn.push({frame: i, svg: rec.svg()})
    summary.drawn.push({frame: i, shapes: ops.length, elements: rec.elements})
  }
  try {
    for (let i = 0; i <= frames; i++) {
      for (const e of events) {
        if (e[0] === i && s.value) state = vm.execute(s.value, [state, pointerValue(e[1], e[2], e[3], e[4])])
      }
      if (i > 0 && s.action) state = vm.execute(s.action, [state, new VeraNumberValue(dt)])
      summary.frames = i
      // Every frame is drawn, as on the phone: a trap in draw() is caught on the frame it happens.
      if (every > 0 && i % every === 0) render(i)
      else decodeGfx(vm.execute(s.label, [state]))
    }
    if (every > 0 && frames % every !== 0) render(frames)
  } catch (e) {
    summary.trap = (e.trapCode ? e.trapCode + ' ' : '') + e.message
  }
  summary.state = state
  return {summary, drawn}
}

/** The drawn frames side by side, labelled, as one SVG. */
function sheet(drawn, boxW, boxH, columns = 4) {
  const pad = 16, label = 22
  const rows = Math.ceil(drawn.length / columns)
  const cols = Math.min(columns, drawn.length)
  const W = pad + cols * (boxW + pad), H = pad + rows * (boxH + label + pad)
  const parts = drawn.map((d, k) => {
    const x = pad + (k % columns) * (boxW + pad), y = pad + Math.floor(k / columns) * (boxH + label + pad)
    const inner = d.svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>$/, '').replace(/id="c(\d+)"/g, `id="f${k}c$1"`)
      .replace(/url\(#c(\d+)\)/g, `url(#f${k}c$1)`)
    return `<text x="${x}" y="${y + 15}" font-family="sans-serif" font-size="13" fill="#333">frame ${d.frame}</text>` +
      `<g transform="translate(${x},${y + label})"><rect width="${boxW}" height="${boxH}" fill="none" stroke="#ccc"/>${inner}</g>`
  })
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">` +
    `<rect width="${W}" height="${H}" fill="#fafafa"/>${parts.join('')}</svg>`
}

module.exports = {play, sheet, surfaces}

if (require.main === module) {
  const args = Object.fromEntries(process.argv.slice(3).map(a => {
    const m = /^--([^=]+)=(.*)$/.exec(a)
    return m ? [m[1], m[2]] : [a, 'true']
  }))
  const file = process.argv[2]
  if (!file) { console.error('usage: gfx-run.js program.vera [--frames=N] [--dt=MS] [--every=N] [--events=JSON] [--out=DIR]'); process.exit(2) }
  const options = {
    frames: args.frames ? Number(args.frames) : 120,
    dt: args.dt ? Number(args.dt) : 16,
    every: args.every ? Number(args.every) : 30,
    events: args.events ? JSON.parse(args.events) : [],
    box: args.box ? args.box.split('x').map(Number) : undefined,
    preset: args.preset, dark: args.dark === 'true',
  }
  let result
  try {
    result = play(fs.readFileSync(file, 'utf8'), options)
  } catch (e) {
    console.error(e.diagnostics ? e.diagnostics.map(d => JSON.stringify(d)).join('\n') : e.message)
    process.exit(1)
  }
  const {summary, drawn} = result
  if (args.out) {
    fs.mkdirSync(args.out, {recursive: true})
    summary.files = []
    for (const d of drawn) {
      const f = path.join(args.out, 'frame-' + String(d.frame).padStart(4, '0') + '.svg')
      fs.writeFileSync(f, d.svg)
      summary.files.push(f)
    }
    const f = path.join(args.out, 'sheet.svg')
    fs.writeFileSync(f, sheet(drawn, summary.box[0], summary.box[1]))
    summary.files.push(f)
  }
  delete summary.state
  console.log(JSON.stringify(summary, null, 1))
  process.exit(summary.trap ? 1 : 0)
}
