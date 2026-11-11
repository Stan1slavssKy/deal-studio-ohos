// ui.Surface and std/gfx on the host: the module compiles from its table, literal colours and the surface's three
// functions are checked, shapes decode within their limits, colours resolve through the theme, the fit and the
// finger mapping invert each other, the smoke run draws surfaces, and the sample game (examples/surface-catch.vera)
// plays -- a finger that follows the stars scores, one that does not loses its lives -- and paints with the phone's
// own painter.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const {createRecorder} = require('./gfx-svg')
const {play} = require('./gfx-run')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, VeraNumberValue, VeraArrayValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const G = loadVera('VeraGfx')
const {resolveTheme} = loadVera('VeraTheme')
const {smokeRun} = loadVera('VeraSmoke')
const {playSurface} = loadVera('VeraSurfacePlay')
const {describeCatalogForPrompt, describeComponents, selectUiComponents, catalogKinds} = loadVera('VeraUiCatalog')

const sample = fs.readFileSync(path.join(__dirname, 'examples/surface-catch.vera'), 'utf8')

const codes = src => {
  try { compileVeraSource(src); return [] } catch (e) { return (e.diagnostics || []).map(d => d.code + ' ' + d.message) }
}
const program = (drawBody, extra = '', surface = 'ui.Surface("default", 100, 100, "draw", "", "")') => `
@jsonable class AppState { n: number; }
function init(): AppState { return {n: 0}; }
${extra}
function draw(state: AppState): gfx.Shape[] {
  let shapes: gfx.Shape[] = [];
  ${drawBody}
  return shapes;
}
function view(state: AppState): ui.View { return ui.AppTheme("clean", "", [${surface}]); }
`

// The module is its table: every function compiles with its arity, and needs no import.
const calls = G.GFX_FUNCTIONS.map(f => {
  const args = f.params.filter(p => !p.optional).map(p =>
    p.kind === 'number' ? '1' : p.kind === 'number[]' ? '[0, 0, 10, 10]' : p.kind === 'shapes' ? '[gfx.rect(0, 0, 1, 1, "ink")]'
      : p.kind === 'color' ? '"accent"' : p.kind === 'colors' ? '["white", "accent"]' : p.kind === 'boolean' ? 'true'
      : p.name === 'align' ? '"center"' : p.name === 'mode' ? '"add"' : '"M0 0 L10 10 Z"')
  const call = 'gfx.' + f.name + '(' + args.join(', ') + ')'
  return f.result === 'shape' ? `shapes.push(${call});` : f.result === 'string' ? `let s${f.name}: string = ${call};`
    : f.result === 'number' ? `let n${f.name}: number = ${call};` : `let b${f.name}: boolean = ${call};`
})
assert.deepEqual(codes(program(calls.join('\n  '))), [], 'every std/gfx function compiles from the table')
assert.deepEqual(codes('import * as gfx from "std/gfx"\n' + program('shapes.push(gfx.circle(5, 5, 5, "ink"));')), [],
  'an explicit import still works')

// Literal colours and aligns are held to their sets.
for (const good of ['ink', 'accent', 'clear', '#abc', '#a1b2c3', '#a1b2c380']) {
  assert.deepEqual(codes(program(`shapes.push(gfx.rect(0, 0, 1, 1, "${good}"));`)), [], good + ' is a colour')
}
for (const bad of ['red', '#12', '#ggggggg', 'Accent', '']) {
  const found = codes(program(`shapes.push(gfx.rect(0, 0, 1, 1, "${bad}"));`))
  assert.ok(found.some(c => c.startsWith('E2112') && c.includes('unknown colour')), JSON.stringify(bad) + ' is refused: ' + found)
}
assert.ok(codes(program('shapes.push(gfx.text(0, 0, 10, "middle", "ink", "x"));')).some(c => c.startsWith('E2112')),
  'an align outside left/center/right is refused')
assert.deepEqual(codes(program('let c: string = "nonsense"; shapes.push(gfx.rect(0, 0, 1, 1, c));')), [],
  'a computed colour is not checked at compile time')

// The surface's three functions.
const surfaceCodes = (surface, extra) => codes(program('', extra, surface))
assert.deepEqual(surfaceCodes('ui.Surface("fill", 360, 640, "draw", "tick", "touch")',
  'function tick(state: AppState, ms: number): AppState { return state; }\nfunction touch(state: AppState, p: gfx.Pointer): AppState { return {n: p.x + p.y + p.id}; }'), [],
  'draw, a frame handler and a pointer handler with the right signatures compile')
const e2106 = (surface, extra, why) => assert.ok(surfaceCodes(surface, extra).some(c => c.startsWith('E2106')), why)
e2106('ui.Surface("default", 1, 1, "", "", "")', '', 'a surface needs a draw function')
e2106('ui.Surface("default", 1, 1, "missing", "", "")', '', 'a draw function that does not exist is refused')
e2106('ui.Surface("default", 1, 1, "bad", "", "")', 'function bad(state: AppState): ui.View { return ui.Text("body", "x"); }',
  'draw must return gfx.Shape[]')
e2106('ui.Surface("default", 1, 1, "draw", "tick", "")', 'function tick(state: AppState, v: string): AppState { return state; }',
  'a frame handler takes a number')
e2106('ui.Surface("default", 1, 1, "draw", "", "touch")', 'function touch(state: AppState, v: number): AppState { return state; }',
  'a pointer handler takes a gfx.Pointer')

// Colours resolve through the theme, light and dark.
const light = resolveTheme('clean', '', false), dark = resolveTheme('clean', '', true)
assert.equal(G.gfxColor(light, 'accent'), light.primary)
assert.equal(G.gfxColor(dark, 'surface'), dark.surface)
assert.notEqual(G.gfxColor(light, 'background'), G.gfxColor(dark, 'background'), 'a role follows dark mode')
assert.equal(G.gfxColor(light, '#abc'), '#aabbcc')
assert.equal(G.gfxColor(light, '#FF000080'), 'rgba(255,0,0,0.502)')
assert.equal(G.gfxColor(light, 'nonsense'), light.ink, 'an unknown colour is drawn in ink')
const ev = (name, ...args) => G.invokeStdGfx(name, args.map(a => typeof a === 'number' ? new VeraNumberValue(a) : a))
assert.equal(ev('rgb', 255, 128, 0).value, '#ff8000')
assert.equal(ev('rgb', 300, -4, 0, 0.5).value, '#ff000080', 'channels are clamped and alpha appended')
assert.equal(ev('distance', 0, 0, 3, 4).value, 5)
assert.equal(ev('inside', 5, 5, 0, 0, 10, 10).value, true)
assert.equal(ev('inside', 11, 5, 0, 0, 10, 10).value, false)

// Fit, the finger mapping and the natural height.
const fit = G.gfxFit(360, 740, 360, 640)
assert.deepEqual([fit.scale, fit.offsetX, fit.offsetY], [1, 0, 50], 'a tall box letterboxes top and bottom')
const wide = G.gfxFit(800, 400, 100, 100)
assert.deepEqual([wide.scale, wide.offsetX, wide.offsetY], [4, 200, 0], 'a wide box letterboxes left and right')
assert.deepEqual(G.gfxToSurface(wide, 200 + 4 * 25, 4 * 75), [25, 75], 'a finger maps back to surface units')
assert.equal(G.gfxNaturalHeight(360, 360, 640), 640)
assert.equal(G.gfxFit(0, 100, 10, 10).scale, 1, 'an unmeasured box does not divide by zero')

// Shapes decode within their limits.
const rect = G.invokeStdGfx('rect', [0, 0, 1, 1].map(n => new VeraNumberValue(n)).concat([new (loadVera('VeraInterpreter').VeraStringValue)('ink')]))
const group = shapes => G.invokeStdGfx('group', [0, 0, 0, 1, 1].map(n => new VeraNumberValue(n)).concat([new VeraArrayValue(shapes)]))
assert.equal(G.decodeGfx(new VeraArrayValue([rect, group([rect, rect])])).length, 2)
assert.equal(group([rect, group([rect])]).op.count, 4, 'a group counts itself and everything in it')
assert.throws(() => G.decodeGfx(new VeraArrayValue(Array(G.MAX_GFX_SHAPES + 1).fill(rect))), e => e.trapCode === 'R0028', 'too many shapes traps')
let deep = rect
for (let i = 0; i <= G.MAX_GFX_DEPTH; i++) {
  if (i === G.MAX_GFX_DEPTH) { assert.throws(() => group([deep]), e => e.trapCode === 'R0028', 'groups too deep trap'); break }
  deep = group([deep])
}

// The renderer and the catalogue agree, and the prompt describes std/gfx whenever it describes a Surface.
assert.ok(catalogKinds().includes('surface'))
const prompt = describeCatalogForPrompt(selectUiComponents(['Surface']))
assert.ok(prompt.includes('ui.Surface(style, width, height, draw, frame, pointer)') && prompt.includes('gfx.polygon(points, color)') &&
  prompt.includes('class gfx.Pointer'), 'the prompt carries the surface and std/gfx')
assert.ok(!describeCatalogForPrompt(selectUiComponents([])).includes('gfx.rect'), 'and leaves std/gfx out when there is no surface')
assert.ok(describeComponents(['Surface']).includes('gfx.text('), 'find_ui_component for Surface answers with std/gfx too')

// The smoke run draws surfaces and hands the pointer handler a finger.
const compiled = compileVeraSource(sample)
assert.equal(compiled.handlers.get('onPointer'), 'pointer')
assert.equal(compiled.handlers.get('onFrame'), 'number')
assert.equal(smokeRun(compiled), '', 'the sample passes the smoke run')
const trapping = compileVeraSource(program('let empty: number[] = []; shapes.push(gfx.circle(empty[3], 0, 1, "ink"));'))
assert.ok(/stopped when the program starts/.test(smokeRun(trapping)), 'a draw() that traps is caught before it is served')

// The sample game. Untouched, the stars fall past and the round ends; a finger kept under the lowest star scores.
const untouched = play(sample, {frames: 60 * 40, dt: 16, events: [[1, 'down', 0, 180, 600], [2, 'up', 0, 180, 600]]})
assert.equal(untouched.summary.trap, '')
const lost = untouched.summary.state.fields
assert.equal(lost.get('phase').value, 'over', 'left alone, the round ends')
assert.equal(lost.get('lives').value, 0)
assert.equal(lost.get('best').value, lost.get('score').value, 'the best score is kept')

const vm = new VirtualMachine(deserializeVbc2(compiled.vbc2), new UiHostEnvironment())
let state = vm.execute('onPointer', [vm.execute('init'), G.pointerValue('down', 0, 180, 590)])
for (let i = 0; i < 60 * 30; i++) {
  let target = null
  for (const star of state.fields.get('stars').elements) {
    if (target === null || star.fields.get('y').value > target.fields.get('y').value) target = star
  }
  if (target !== null) state = vm.execute('onPointer', [state, G.pointerValue('move', 0, target.fields.get('x').value, 590)])
  state = vm.execute('onFrame', [state, new VeraNumberValue(16)])
}
const played = state.fields
assert.ok(played.get('score').value >= 20, 'a finger that follows the stars scores: ' + played.get('score').value)
assert.ok(played.get('basketX').value >= 50 && played.get('basketX').value <= 310, 'the basket stays on the surface')

// It paints with the phone's own painter: the title on the first frame, the stars and the score later.
const drawn = play(sample, {frames: 120, dt: 16, every: 60, box: [360, 740],
  events: [[1, 'down', 0, 180, 600], [2, 'up', 0, 180, 600]]})
assert.equal(drawn.drawn.length, 3)
assert.ok(drawn.drawn[0].svg.includes('>Star Catch<'), 'the first frame shows the title')
assert.ok(drawn.drawn[2].svg.includes('>Score 0<') && !drawn.drawn[2].svg.includes('Star Catch'), 'playing, the title is gone')
assert.ok(drawn.drawn.every(d => d.svg.includes('clip-path')), 'every frame is clipped to the surface')
const rec = createRecorder(100, 100)
G.paintGfx(rec.ctx, [rect.op], light, 100, 100, 10, 10)
assert.ok(rec.svg().includes('fill="' + light.ink.toLowerCase()) || rec.svg().includes('fill="' + light.ink), 'a shape is painted in its colour')
const nan = G.invokeStdGfx('circle', [NaN, 0, 5].map(n => new VeraNumberValue(n)).concat([new (loadVera('VeraInterpreter').VeraStringValue)('ink')]))
const blank = createRecorder(100, 100)
G.paintGfx(blank.ctx, [nan.op], light, 100, 100, 10, 10)
assert.equal((blank.svg().match(/<path [^>]*fill="#/g) || []).length, 1, 'a shape with a NaN is skipped: only the background is painted')

// A frame handler may ask the phone for something, as a ticker's handler may (a vibration on each breath): on the phone it
// is run as a handler, and the play check runs it the same way. Only draw() is refused.
const buzzing = `
@jsonable class AppState { n: number; buzzes: number; }
function init(): AppState { return {n: 0, buzzes: 0}; }
function onBuzzed(state: AppState, answer: string): AppState { return {n: state.n, buzzes: state.buzzes + 1}; }
function onFrame(state: AppState, ms: number): AppState {
  if (state.n === 30) { sdk.call("com.example.buzz/entry/EntryAbility/Buzz", [], "onBuzzed"); }
  return {n: state.n + 1, buzzes: state.buzzes};
}
function draw(state: AppState): gfx.Shape[] { return [gfx.circle(10 + state.n % 60, 50, 10, "accent")]; }
function view(state: AppState): ui.View { return ui.AppTheme("clean", "", [ui.Surface("default", 100, 100, "draw", "onFrame", "")]); }
`
assert.equal(playSurface(compileVeraSource(buzzing)), '', 'a frame handler that asks the phone for something plays')
const drawBuzz = buzzing.replace('function draw(state: AppState): gfx.Shape[] {', 'function draw(state: AppState): gfx.Shape[] {\n  if (state.n === 30) { sdk.call("com.example.buzz/entry/EntryAbility/Buzz", [], "onBuzzed"); }')
assert.match(playSurface(compileVeraSource(drawBuzz)), /sdk\.call may only be called from a handler/, 'draw() still may not')
// A circle that only grows and shrinks is a scene that moves (a breathing guide), not one that never changes.
const breathing = buzzing.replace('if (state.n === 30) { sdk.call("com.example.buzz/entry/EntryAbility/Buzz", [], "onBuzzed"); }', '')
  .replace('return [gfx.circle(10 + state.n % 60, 50, 10, "accent")];', 'return [gfx.circle(50, 50, 10 + state.n % 30, "accent")];')
assert.equal(playSurface(compileVeraSource(breathing)), '', 'a circle that only changes its size counts as moving')

// Gradients are colours: gfx.linear / gfx.radial write a short string a shape takes in place of a colour, and the painter
// turns it into a canvas gradient in the units the shape is drawn in.
const {VeraStringValue} = loadVera('VeraInterpreter')
const str = s => new VeraStringValue(s)
const nums = list => list.map(v => new VeraNumberValue(v))
const colours = list => new VeraArrayValue(list.map(str))
const sky = G.invokeStdGfx('linear', nums([0, 0, 0, 100]).concat([colours(['white', '#0f172a'])])).value
assert.equal(sky, 'lin:0,0,0,100:white|#0f172a', 'gfx.linear writes its points and colours')
assert.equal(G.invokeStdGfx('radial', nums([40.004, 40, 30]).concat([colours(['white', 'accent'])])).value, 'rad:40,40,30:white|accent',
  'gfx.radial rounds its numbers so a card frame stays short')
for (const [body, why] of [
  ['shapes.push(gfx.circle(5, 5, 5, gfx.linear(0, 0, 1, 1, ["white", "red"])));', 'an unknown colour in a gradient'],
  ['shapes.push(gfx.circle(5, 5, 5, gfx.radial(0, 0, 1, ["white"])));', 'a gradient of one colour'],
  ['shapes.push(gfx.blend("lighten", [gfx.circle(5, 5, 5, "ink")]));', 'a blend mode outside the set'],
]) {
  assert.ok(codes(program(body)).some(c => c.startsWith('E2112')), why + ' is refused')
}
const ball = G.invokeStdGfx('circle', nums([50, 50, 20]).concat([str(G.invokeStdGfx('radial', nums([44, 44, 26]).concat([colours(['white', 'accent'])])).value)]))
const ballRec = createRecorder(100, 100)
G.paintGfx(ballRec.ctx, [ball.op], light, 100, 100, 100, 100)
assert.match(ballRec.svg(), /<radialGradient id="g\d+" gradientUnits="userSpaceOnUse"[^>]* cx="44" cy="44" r="26">/, 'a radial colour is a radial gradient')
assert.match(ballRec.svg(), /fill="url\(#g\d+\)"/, 'the shape is filled with it')
const broken = G.invokeStdGfx('circle', nums([50, 50, 20]).concat([str('lin:1,2:white|accent')]))
const brokenRec = createRecorder(100, 100)
G.paintGfx(brokenRec.ctx, [broken.op], light, 100, 100, 100, 100)
assert.ok(brokenRec.svg().includes('fill="#ffffff"') && !brokenRec.svg().includes('Gradient'), 'a gradient that does not read is drawn in its first colour')

// Effects hold shapes like a group: a glow or shadow is a drop shadow, a blur a gaussian blur, a blend the element's mix mode.
// Their sizes are in surface units, so a glow inside a group scaled twice is twice as wide.
const disc = () => G.invokeStdGfx('circle', nums([10, 10, 5]).concat([str('accent')]))
const fx = (name, args) => G.invokeStdGfx(name, args)
const svgOf = (ops, scale = 1) => { const r = createRecorder(100 * scale, 100 * scale); G.paintGfx(r.ctx, ops, light, 100 * scale, 100 * scale, 100, 100); return r.svg() }
const glow = fx('glow', nums([4]).concat([str('#22d3ee'), new VeraArrayValue([disc()])]))
assert.match(svgOf([glow.op]), /stdDeviation="2"\/><feOffset dx="0" dy="0" result="moved"\/><feFlood flood-color="#22d3ee"/, 'a glow is a soft shadow with no offset')
assert.match(svgOf([glow.op], 2), /stdDeviation="4"/, 'and is as wide relative to the picture on a box twice the size')
const grouped = G.invokeStdGfx('group', nums([0, 0, 0, 2, 1]).concat([new VeraArrayValue([glow])]))
assert.match(svgOf([grouped.op]), /stdDeviation="4"/, 'a glow in a group scaled by 2 is twice as wide')
const shadow = fx('shadow', nums([1, 3, 2]).concat([str('#00000066'), new VeraArrayValue([disc()])]))
assert.match(svgOf([shadow.op]), /stdDeviation="1"\/><feOffset dx="1" dy="3" result="moved"\/><feFlood flood-color="#000000" flood-opacity="0.4"/, 'a shadow is moved and soft')
assert.match(svgOf([fx('blur', nums([3]).concat([new VeraArrayValue([disc()])])).op]), /<feGaussianBlur in="SourceGraphic" stdDeviation="1.5" result="shape"\/>/, 'a blur blurs')
assert.match(svgOf([fx('blend', [str('add'), new VeraArrayValue([disc()])]).op]), /mix-blend-mode:plus-lighter/, 'add is a lighter blend')
const plain = svgOf([fx('blend', [str('nonsense'), new VeraArrayValue([disc()])]).op])
assert.ok(!plain.includes('mix-blend-mode') && plain.includes('fill="#'), 'an unknown mode draws its shapes plain')
const back = G.decodeGfxOps(G.encodeGfxOps([shadow.op]))
assert.equal(back[0].kind, 'fx'); assert.equal(back[0].fx, 'shadow'); assert.equal(back[0].children.length, 1)
assert.equal(back[0].w, 1); assert.equal(back[0].h, 3); assert.equal(back[0].lineWidth, 2)
assert.equal(shadow.op.count, 2, 'an effect counts itself and its shapes against the frame limit')

// The example of all of them (examples/widget-rich.vera) compiles and paints them, in under a card's shape limit.
const rich = compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/widget-rich.vera'), 'utf8'))
const richVm = new VirtualMachine(deserializeVbc2(rich.vbc2), new UiHostEnvironment())
const richOps = G.decodeGfx(richVm.execute('scene', [richVm.execute('init')]))
const richSvg = svgOf(richOps)
for (const part of ['<linearGradient', '<radialGradient', '<feOffset', '<feGaussianBlur', 'mix-blend-mode:plus-lighter']) {
  assert.ok(richSvg.includes(part), 'the rich example draws ' + part)
}
assert.ok(richOps.reduce((sum, o) => sum + o.count, 0) <= 60, 'within a card picture\'s 60 shapes')
fs.mkdirSync(path.join(__dirname, 'proofs'), {recursive: true})
fs.writeFileSync(path.join(__dirname, 'proofs/widget-rich.svg'), svgOf(richOps, 3))

console.log('gfx-check ok')
