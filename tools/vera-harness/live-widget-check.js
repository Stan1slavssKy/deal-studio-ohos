const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { loadVera } = require('./source-loader')
const { compileVeraSource } = loadVera('VeraCompiler')
const { WidgetSession } = loadVera('VeraLiveWidget')
const { veraStateStamp } = loadVera('VeraStateStamp')
const source = fs.readFileSync(path.join(__dirname, 'examples/widget-counter.vera'), 'utf8')
const code = compileVeraSource(source).vbc2
const session = new WidgetSession(code, 'v1', '')
const frame = s => s.frame('p1', 'Widget counter', '🔢')
const texts = nodes => nodes.flatMap(n => [n.text, ...texts(n.children)])
let first = frame(session)
assert(texts(first.nodes).includes('0'))
session.tap(first, first.token, 'change', 1)
assert(texts(frame(session).nodes).includes('1'))
assert.throws(() => session.tap(frame(session), first.token, 'change', 1), /changed/)
assert.throws(() => session.tap(frame(session), frame(session).token, 'arbitrary', 1), /not available/)
assert.throws(() => session.tap(frame(session), frame(session).token, 'change', 999), /not available/)
const restored = new WidgetSession(code, 'v1', session.encodedState())
assert(texts(frame(restored).nodes).includes('1'))
let next = frame(restored)
restored.tap(next, next.token, 'change', -1)
assert(texts(frame(restored).nodes).includes('0'))
assert.equal(veraStateStamp(code), code.length + ':' + code.substring(0,64))
const old = compileVeraSource(source.replace('function widget(', 'function compact(').replace('return widget(state);', 'return compact(state);')).vbc2
assert.equal(new WidgetSession(old, 'v2', '').frame('p1','Old','📱').live, false)
const unsafe = compileVeraSource(source.replace('ui.Text("caption", "COUNTER")', 'ui.Image("default", "https://example.com/test.png", "test")')).vbc2
assert.throws(() => frame(new WidgetSession(unsafe, 'v3', '')), /Not card-safe: image/)
const over = compileVeraSource(source.replace('ui.Text("caption", "COUNTER")', 'ui.Text("caption", "' + 'x'.repeat(257) + '")')).vbc2
assert.throws(() => frame(new WidgetSession(over, 'v4', '')), /256/)
const nested = source.replace('ui.Text("caption", "COUNTER")', 'ui.Column("default", [ui.Column("default", [ui.Column("default", [ui.Text("body", "deep")])])])')
assert.throws(() => frame(new WidgetSession(compileVeraSource(nested).vbc2, 'deep', '')), /depth/)
const many = source.replace('ui.Text("caption", "COUNTER")', Array(41).fill('ui.Text("body", "node")').join(','))
assert.throws(() => frame(new WidgetSession(compileVeraSource(many).vbc2, 'many', '')), /40 nodes/)
const effectSource = 'import * as sdk from "std/sdk"\n' + source.replace('return { count: state.count + value };',
  'sdk.call("fixture/phone/Ability/action", [], "answer", "foreground"); return { count: state.count + value };') +
  '\nfunction answer(state: AppState, result: string): AppState { return state; }'
const effect = new WidgetSession(compileVeraSource(effectSource).vbc2, 'effect', '')
const beforeEffect = effect.encodedState(), effectFrame = frame(effect)
assert.throws(() => effect.tap(effectFrame, effectFrame.token, 'change', 1), /phone action required/)
assert.equal(effect.encodedState(), beforeEffect)
// Dynamic repeated rows without extending the renderer subset. Payloads identify items, not positions.
const listSource = `
@jsonable class AppState { ids: number[]; }
function init(): AppState { return { ids: [11, 22, 33] }; }
function remove(state: AppState, value: number): AppState {
  let remaining: number[] = [];
  for (let id: number of state.ids) { if (id !== value) { remaining.push(id); } }
  return { ids: remaining };
}
function widget(state: AppState): ui.View {
  let rows: ui.View[] = [];
  for (let id: number of state.ids) {
    rows.push(ui.Row("default", [ui.NumberText("body", id, "Item ", "", 1), ui.Button("secondary", "Done", "remove", id, true)]));
  }
  return ui.Column("default", rows);
}
function view(state: AppState): ui.View { return widget(state); }
`
const listCode = compileVeraSource(listSource).vbc2, list = new WidgetSession(listCode,'list','')
const listBefore = frame(list)
list.tap(listBefore,listBefore.token,'remove',22)
const listAfter = frame(list)
assert.equal(listAfter.nodes[0].children.length,2)
assert.deepEqual(listAfter.nodes[0].children.map(row=>row.children[1].value),[11,33])
assert.throws(()=>list.tap(listAfter,listBefore.token,'remove',33),/changed/)
assert.throws(()=>list.tap(listAfter,listAfter.token,'remove',22),/not available/)
list.tap(listAfter,listAfter.token,'remove',33)
assert.deepEqual(frame(list).nodes[0].children.map(row=>row.children[1].value),[11])
const card = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/widget/pages/LiveCard.ets'), 'utf8')
const view = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/widget/CardView.ets'), 'utf8')
assert.match(card, /handler: action/, 'the card posts the handler a button or shape reports')
assert.match(card, /handler: handler, x: x, y: y/, 'and the point a picture reports')
assert.match(card, /frameKey: this.token \+ this.seq/, 'the nodes are made again for every frame: the token and seq are in their key')
assert.match(view, /node.key \+ this.frameKey/)
// The token does not grow with the app's data: a log of 400 entries still fits the card, and a different log is a different token.
{
  const log = 'import * as ui from "std/ui"\n@jsonable class Entry { note: string; amount: number; }\n' +
    '@jsonable class AppState { entries: Entry[]; }\n' +
    'function init(): AppState { let e: Entry[] = []; let i: number = 0; while (i < 400) { e.push({note: "coffee at the corner shop", amount: i}); i = i + 1; } return {entries: e}; }\n' +
    'function add(state: AppState, value: number): AppState { let e: Entry[] = []; for (let x: Entry of state.entries) { e.push(x); } e.push({note: "tea", amount: value}); return {entries: e}; }\n' +
    'function view(state: AppState): ui.View { return ui.Column("default", [ui.NumberText("metric", state.entries.length(), "", " entries", 1)]); }\n' +
    'function widget(state: AppState): ui.View { return ui.Column("default", [ui.NumberText("metric", state.entries.length(), "", " entries", 1), ui.Button("primary", "+", "add", 1, true)]); }\n'
  const big = new WidgetSession(compileVeraSource(log).vbc2, 'v1', '')
  assert(big.encodedState().length > 10000, 'the state alone is over the card budget')
  const before = frame(big)
  assert(before.live && before.token.length < 120, 'token ' + before.token.length)
  big.tap(before, before.token, 'add', 1)
  const after = frame(big)
  assert.notEqual(after.token, before.token)
  assert.throws(() => big.tap(after, before.token, 'add', 1), /changed/)
}
// A tappable shape: a drum on the card. Its path is carried to the card, a tap on it runs the handler, a plain one is refused.
{
  const drumSource = fs.readFileSync(path.join(__dirname, 'examples/widget-drum.vera'), 'utf8')
  const drum = new WidgetSession(compileVeraSource(drumSource).vbc2, 'drum', '')
  const f = frame(drum)
  const shape = f.nodes[0].children[0]
  assert.equal(shape.kind, 'path')
  assert(shape.commands.startsWith('M50 12'), 'path data reaches the card')
  assert.equal(shape.action, 'hit')
  assert(JSON.stringify(f).length < 2000, 'a drum is small: ' + JSON.stringify(f).length)
  drum.tap(f, f.token, 'hit', 1)
  assert(texts(frame(drum).nodes).includes('1 hits'))
  assert.throws(() => drum.tap(frame(drum), frame(drum).token, 'hit', 5), /not available/)
  const still = compileVeraSource(drumSource.replace('0, "hit", 1)', '0)')).vbc2
  const plain = new WidgetSession(still, 'plain', '')
  assert.equal(frame(plain).nodes[0].children[0].action, '')
  assert.throws(() => plain.tap(frame(plain), frame(plain).token, 'hit', 1), /not available/)
  const long = drumSource.replace('M50 12', 'M50 12 ' + 'L1 1 '.repeat(130))
  assert.throws(() => frame(new WidgetSession(compileVeraSource(long).vbc2, 'long', '')), /shape exceeds/)
}
// A Motion on the card: a drum that jumps when it is hit. The frame carries the preset and the trigger, the trigger moves with
// the count, a style a card cannot play, a second Motion and a Motion that is not a number are refused.
{
  const motionSource = fs.readFileSync(path.join(__dirname, 'examples/widget-drum-motion.vera'), 'utf8')
  const drum = new WidgetSession(compileVeraSource(motionSource).vbc2, 'drum-motion', '')
  const f = frame(drum)
  const motion = f.nodes[0].children[0]
  assert.equal(motion.kind, 'motion')
  assert.equal(motion.style, 'pop')
  assert.equal(motion.trigger, 0)
  assert.equal(motion.children[0].kind, 'path')
  assert.equal(motion.children[0].action, 'hit')
  drum.tap(f, f.token, 'hit', 1)
  const g = frame(drum)
  assert.equal(g.nodes[0].children[0].trigger, 1, 'the trigger follows the count')
  assert.notEqual(g.token, f.token)
  assert(JSON.stringify(g).length < 2000, 'a Motion drum is small: ' + JSON.stringify(g).length)
  for (const style of loadVera('VeraMotion').MOTION_PRESETS) {
    const ok = motionSource.replace('"pop"', '"' + style + '"')
    assert.equal(frame(new WidgetSession(compileVeraSource(ok).vbc2, 'ok', '')).nodes[0].children[0].style, style)
  }
  // Three Motions at most; each touch plays the Motion its node sits under (slot), not all of them.
  const widgetAt = motionSource.indexOf('function widget(')
  const withMotions = n => motionSource.substring(0, widgetAt) + motionSource.substring(widgetAt).replace('ui.NumberText("metric", state.hits, "", " hits", 1)',
    Array.from({length: n}, (_, i) => 'ui.Motion("fade", state.hits, [ui.Text("caption", "m' + i + '")])').join(', '))
  const three = frame(new WidgetSession(compileVeraSource(withMotions(2)).vbc2, 'three', ''))
  const slots = []
  const walk = (nodes) => nodes.forEach(n => { if (n.kind === 'motion') slots.push(n.slot); walk(n.children) })
  walk(three.nodes)
  assert.deepEqual(slots, [0, 1, 2], 'the drum and two more: slots in order')
  assert.equal(loadVera('VeraLiveWidget').LIVE_MAX_MOTIONS, 5, 'five Motions at most')
  const drumPath = three.nodes[0].children[0].children[0]
  assert.equal(drumPath.kind, 'path'); assert.equal(drumPath.slot, 0, 'the drum sits under Motion 0')
  assert.equal(three.nodes[0].children[1].children[0].slot, 1, 'a text under the second Motion carries its slot')
  assert.throws(() => frame(new WidgetSession(compileVeraSource(withMotions(5)).vbc2, 'four', '')), /at most 5 ui\.Motion/)
  const nested = motionSource.replace('ui.Path(', 'ui.Motion("fade", 0, [ui.Path(').replace(', 0, "hit", 1)', ', 0, "hit", 1)])')
  assert.throws(() => compileVeraSource(nested), /E2107/, 'the compiler refuses a Motion inside a Motion')
}
// A picture on the card: ui.Surface drawn once for the state, its shapes carried in the frame (a few hundred characters), a tap on it
// calling the pointer handler with the finger down and up at that point. No frame loop, one picture, a few dozen shapes.
{
  const { encodeGfxOps, decodeGfxOps, decodeGfx } = loadVera('VeraGfx')
  const pandaSource = fs.readFileSync(path.join(__dirname, 'examples/widget-panda.vera'), 'utf8')
  const panda = new WidgetSession(compileVeraSource(pandaSource).vbc2, 'panda', '')
  const f = frame(panda)
  const motion = f.nodes[0].children[0]
  const picture = motion.children[0]
  assert.equal(picture.kind, 'surface')
  assert.equal(picture.w, 100)
  assert.equal(picture.h, 100)
  assert.equal(picture.pointer, 'pandaTouch')
  assert.equal(picture.size, 80, 'one figure under it leaves room for the full picture')
  assert.equal(f.preset, 'playful')
  const shapes = decodeGfxOps(picture.ops)
  assert.equal(shapes.length, 9, 'the nine shapes the program drew')
  assert.equal(shapes[2].kind, 'circle'); assert.equal(shapes[2].r, 36); assert.equal(shapes[2].color, '#FFFFFF')
  assert.equal(shapes[8].kind, 'arc'); assert.equal(shapes[8].start, 110); assert.equal(shapes[8].sweep, 140)
  assert.equal(encodeGfxOps(shapes), picture.ops, 'what is carried is what was drawn')
  assert(JSON.stringify(f).length < 2500, 'a panda is small: ' + JSON.stringify(f).length)
  assert.deepEqual(decodeGfxOps('not json'), [])
  panda.tapSurface(f, f.token, 'pandaTouch', 50, 50)
  const g = frame(panda)
  assert.equal(g.nodes[0].children[0].trigger, 1, 'one tap is one hop: down counts, up does not')
  assert(texts(g.nodes).includes('1 hops'))
  assert.throws(() => panda.tapSurface(frame(panda), f.token, 'pandaTouch', 50, 50), /changed/, 'a tap from an older frame')
  assert.throws(() => panda.tapSurface(g, g.token, 'init', 50, 50), /not available/, 'only the picture\'s own handler')
  assert.throws(() => panda.tapSurface(g, g.token, 'pandaTouch', NaN, 5), /not available/)
  assert.throws(() => panda.tap(g, g.token, 'pandaTouch', 0), /not available/, 'a number tap is not a picture tap')
  // No frame loop on a card, one picture, a few dozen shapes.
  const looping = (pandaSource + 'function pandaTick(state: AppState, elapsedMs: number): AppState { return state; }')
    .replace('"panda", "", "pandaTouch"', '"panda", "pandaTick", "pandaTouch"')
  assert.throws(() => frame(new WidgetSession(compileVeraSource(looping).vbc2, 'loop', '')), /no frames/)
  // Three pictures at most; they are numbered, and pictures side by side share the card's width.
  const cut = pandaSource.indexOf('function widget(')
  const withPictures = (n, inRow) => {
    const extra = Array.from({length: n}, () => 'ui.Surface("default", 100, 100, "panda", "", "")').join(', ')
    return pandaSource.substring(0, cut) + pandaSource.substring(cut).replace('ui.NumberText("metric", state.hops, "", " hops", 1)',
      inRow ? 'ui.Row("default", [' + extra + '])' : extra)
  }
  const column = frame(new WidgetSession(compileVeraSource(withPictures(2, false)).vbc2, 'two', ''))
  const pics = []
  const gather = (nodes) => nodes.forEach(n => { if (n.kind === 'surface') pics.push(n); gather(n.children) })
  gather(column.nodes)
  assert.deepEqual(pics.map(n => n.pic), [0, 1, 2], 'the first is the panda, the others follow')
  const row = frame(new WidgetSession(compileVeraSource(withPictures(2, true)).vbc2, 'row', ''))
  const inRow = []
  const gatherRow = (nodes) => nodes.forEach(n => { if (n.kind === 'surface') inRow.push(n); gatherRow(n.children) })
  gatherRow(row.nodes)
  assert(inRow.every(n => n.size <= 59), 'two pictures in a row, and the one above, fit the width: ' + inRow.map(n => n.size))
  assert.throws(() => frame(new WidgetSession(compileVeraSource(withPictures(3, false)).vbc2, 'four', '')), /at most 3 ui\.Surface/)
  const many = pandaSource.replace('  return shapes;', '  shapes.push(gfx.circle(1, 50, 2, "#1F1F1F"));\n'.repeat(60) + '  return shapes;')
  assert.throws(() => frame(new WidgetSession(compileVeraSource(many).vbc2, 'many', '')), /at most 60 shapes/)
  // The picture takes the room the rest leaves: more text under it, a smaller picture (never under 40).
  const cutAt = pandaSource.indexOf('function widget(')
  const crowded = pandaSource.substring(0, cutAt) + pandaSource.substring(cutAt).replace('ui.NumberText("metric", state.hops, "", " hops", 1)',
    'ui.NumberText("metric", state.hops, "", " hops", 1), ui.Text("caption", "best"), ui.Text("caption", "more")')
  const smaller = frame(new WidgetSession(compileVeraSource(crowded).vbc2, 'crowded', '')).nodes[0].children[0].children[0]
  assert(smaller.size < 80 && smaller.size >= 40, 'a crowded card shrinks the picture: ' + smaller.size)
  const still = compileVeraSource(pandaSource.replace('"panda", "", "pandaTouch"', '"panda", "", ""')).vbc2
  const looked = new WidgetSession(still, 'still', '')
  assert.equal(frame(looked).nodes[0].children[0].children[0].pointer, '')
  assert.throws(() => looked.tapSurface(frame(looked), frame(looked).token, '', 5, 5), /not available/)
}
// Two pictures side by side, each under its own Motion (examples/widget-two-pictures.vera): each touch is counted for its own Motion's slot.
{
  const two = new WidgetSession(compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/widget-two-pictures.vera'), 'utf8')).vbc2, 'two-pictures', '')
  const f = frame(two)
  const [left, right] = f.nodes[0].children[0].children
  assert.deepEqual([left.slot, right.slot], [0, 1])
  assert.deepEqual([left.children[0].pic, right.children[0].pic], [0, 1])
  assert.deepEqual([left.children[0].pointer, right.children[0].pointer], ['touchLeft', 'touchRight'])
  assert(left.children[0].size <= 59 && right.children[0].size <= 59, 'side by side, each takes half the width')
  two.tapSurface(f, f.token, 'touchRight', 50, 50)
  assert(texts(frame(two).nodes).includes('1'), 'one touch counted')
}
// The theme's roles reach the card (CardStyle): sizes, weights, families, tones, panels, alignment, and only what differs from the default is in the frame.
{
  const styled = new WidgetSession(compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/widget-styles.vera'), 'utf8')).vbc2, 'styles', '')
  const f = frame(styled)
  const [eyebrow, title, panel, row] = f.nodes[0].children
  assert.equal(eyebrow.size, 10); assert.equal(eyebrow.spacing, 2); assert(eyebrow.weight >= 500, 'an eyebrow is not light')
  assert.equal(title.size, 22); assert.equal(title.weight, 700); assert.equal(title.family, 'Noto Serif', 'editorial headings are serif')
  assert.equal(panel.panel !== undefined, true); assert(panel.pad > 0 && panel.radius > 0, 'a panel has a fill, padding and a radius')
  assert.equal(row.align, 'split'); assert.equal(row.children[1].color, '#9B2226', 'danger is the theme\'s danger ink')
  assert.equal(row.children[0].weight, undefined, 'a body text at the default weight carries no weight')
  assert.equal(f.nodes[0].align, undefined, 'a centred column carries no alignment')
  assert(!JSON.stringify(f).includes('"gap"'), 'no gap in the frame when it is the default')
  assert(JSON.stringify(f).length < 2400, 'styles stay small: ' + JSON.stringify(f).length)
}
// Icons, badges, progress, stats and a sparkline on the card (examples/widget-water.vera, widget-metrics.vera).
{
  const { decodeGfxOps } = loadVera('VeraGfx')
  const water = new WidgetSession(compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/widget-water.vera'), 'utf8')).vbc2, 'water', '')
  const f = frame(water)
  const ring = f.nodes[0].children[0]
  assert.equal(ring.kind, 'ring'); assert.equal(ring.val, 3); assert.equal(ring.max, 8); assert.equal(ring.sub, '38%'); assert.equal(ring.text, 'Water')
  assert.equal(ring.size, 52); assert.match(ring.color, /^#[0-9A-Fa-f]{6}$/); assert.notEqual(ring.color, '#172033', 'the ring takes the theme\'s accent, not the default ink')
  const [minus, plus] = f.nodes[0].children[1].children
  assert.equal(minus.kind, 'iconbutton'); assert(minus.commands.length > 0, 'an icon button carries its icon\'s path')
  assert.notEqual(minus.fill, plus.fill, 'secondary and primary differ'); assert.equal(plus.color, '#FFFFFF', 'the ink on a primary button is the theme\'s onPrimary')
  water.tap(f, f.token, 'add', 1)
  assert.equal(frame(water).nodes[0].children[0].val, 4, 'an icon button runs its handler')
  assert.throws(() => water.tap(frame(water), frame(water).token, 'add', 5), /not available/)
  const metrics = new WidgetSession(compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/widget-metrics.vera'), 'utf8')).vbc2, 'metrics', '')
  const m = frame(metrics)
  const kinds = []; const walk = n => { kinds.push(n.kind); n.children.forEach(walk) }; m.nodes.forEach(walk)
  assert.deepEqual(kinds.slice(0, 4), ['column', 'row', 'badge', 'icon'])
  assert(kinds.includes('numbertext') && kinds.includes('surface'), 'a stat is a labelled figure; a sparkline is a picture')
  const chart = []; const find = n => { if (n.kind === 'surface') chart.push(n); n.children.forEach(find) }; m.nodes.forEach(find)
  const shapes = decodeGfxOps(chart[0].ops)
  assert(shapes.some(o => o.kind === 'polyline') && shapes.some(o => o.kind === 'circle'), 'a line and its last point')
  assert.equal(chart[0].pointer, '', 'a sparkline is not tappable'); assert.equal(chart[0].pic, 0)
  assert(JSON.stringify(m).length < 4200, 'the metrics widget stays small: ' + JSON.stringify(m).length)
  const unknownIcon = fs.readFileSync(path.join(__dirname, 'examples/widget-metrics.vera'), 'utf8').replace('"star"', '"nonesuch"')
  assert.throws(() => frame(new WidgetSession(compileVeraSource(unknownIcon).vbc2, 'bad-icon', '')), /unknown icon/)
}
// A timer that runs by itself (ui.Timer): the frame carries the moment and the direction, the platform's TextTimer does the ticking.
{
  const timerSource = fs.readFileSync(path.join(__dirname, 'examples/widget-timer.vera'), 'utf8')
  const timer = new WidgetSession(compileVeraSource(timerSource).vbc2, 'timer', '')
  const f = frame(timer)
  const [up, down] = f.nodes[0].children
  assert.equal(up.kind, 'timer'); assert.equal(up.max, 0, 'counts up'); assert.equal(up.pic, 0)
  assert.equal(down.kind, 'timer'); assert.equal(down.max, 1, 'counts down'); assert.equal(down.pic, 1)
  assert(Math.abs(up.val - Date.now()) < 60000, 'the moment is milliseconds since 1970: ' + up.val)
  assert(down.val - up.val > 5000000, 'the second one ends an hour and a half later')
  assert.equal(up.size, 30); assert.equal(down.size, 18); assert.equal(up.family, 'monospace', 'the technical theme\'s metric font')
  assert(!up.text, 'a timer carries no text: the platform draws it')
  const four = timerSource.replace('ui.Timer("heading", state.endsAt, true),', 'ui.Timer("heading", state.endsAt, true), ui.Timer("caption", state.endsAt, true), ui.Timer("caption", state.endsAt, true),')
  assert.throws(() => frame(new WidgetSession(compileVeraSource(four).vbc2, 'many-timers', '')), /at most 3 ui\.Timer/)
}
// The card's size: the frame is fitted to it, a widget that takes the size draws differently, and the limits grow with it.
{
  const { cardSize } = loadVera('VeraLiveWidget')
  assert.deepEqual([2, 3, 4].map(d => cardSize(d).label), ['2x2', '2x4', '4x4'])
  assert.deepEqual([2, 3, 4].map(d => cardSize(d).maxButtons), [2, 4, 6]); assert.deepEqual([cardSize(7).dimension, cardSize(0).label], [2, '2x2'], 'an unknown size is 2x2')
  const sized = new WidgetSession(compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/widget-sizes.vera'), 'utf8')).vbc2, 'sizes', '')
  assert.equal(sized.takesSize(), true)
  const counts = [2, 3, 4].map(d => { const f = sized.frame('p', 'A', '', d); assert.equal(f.dimension, d); let n = 0; const walk = x => { n++; x.children.forEach(walk) }; f.nodes.forEach(walk); return n })
  assert(counts[0] < counts[1] && counts[1] < counts[2], 'a bigger card, more on it: ' + counts)
  assert.equal(new WidgetSession(compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/widget-counter.vera'), 'utf8')).vbc2, 'one', '').takesSize(), false)
  // The 41st node is refused on a 2x2 card and taken on a 4x4 one.
  const tens = n => Array.from({length: n}, (_, i) => 'ui.Text("body", "t' + i + '")').join(', ')
  const manyAt = (d) => { const src = fs.readFileSync(path.join(__dirname, 'examples/widget-sizes.vera'), 'utf8').replace('rows.push(ui.Text("title", "Plan"));', 'rows.push(ui.Column("default", [' + tens(5) + ']));'.repeat(1) + '\n  rows.push(ui.Column("default", [' + tens(5) + ']));\n  rows.push(ui.Column("default", [' + tens(5) + ']));\n  rows.push(ui.Column("default", [' + tens(5) + ']));\n  rows.push(ui.Column("default", [' + tens(5) + ']));\n  rows.push(ui.Column("default", [' + tens(5) + ']));\n  rows.push(ui.Column("default", [' + tens(5) + ']));\n  rows.push(ui.Column("default", [' + tens(5) + ']));'); return new WidgetSession(compileVeraSource(src).vbc2, 'many', '').frame('p', 'A', '', d) }
  assert.throws(() => manyAt(2), /widget exceeds 40 nodes/)
  assert.equal(manyAt(4).live, true)
}
// The frame goes into the binding compact (only what differs from a default node) and the card gives the defaults back: the same nodes, in about half the characters.
{
  const { compactFrame, normalizeNodes } = loadVera('VeraLiveWidget')
  for (const name of ['widget-metrics', 'widget-styles', 'widget-panda', 'widget-water', 'widget-two-pictures']) {
    const f = new WidgetSession(compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/' + name + '.vera'), 'utf8')).vbc2, name, '').frame('p', 'A', '')
    const compact = JSON.parse(JSON.stringify(compactFrame(f)))
    assert.deepEqual(JSON.parse(JSON.stringify(normalizeNodes(compact.nodes))), JSON.parse(JSON.stringify(f.nodes)), name + ': what the card restores is what was sent')
    assert(JSON.stringify(compact).length < JSON.stringify(f).length * 0.7, name + ' is smaller compact: ' + JSON.stringify(compact).length + ' of ' + JSON.stringify(f).length)
    assert.equal(compact.dimension, 2); assert.equal(compact.live, true)
  }
}
// Switches: a toggle and a checkbox are taps that say on or off; a stale token or an unknown handler is refused.
{
  const sw = new WidgetSession(compileVeraSource(fs.readFileSync(path.join(__dirname, 'examples/widget-switch.vera'), 'utf8')).vbc2, 'sw', '')
  const f0 = sw.frame('p', 'A', ''); const col = f0.nodes[0].children
  assert.deepEqual(col.slice(1).map(n => [n.kind, n.val, n.action]), [['toggle', 0, 'setFocus'], ['checkbox', 0, 'setDone']])
  assert(col[2].commands.length > 0, 'a checkbox carries its check mark')
  sw.tapSwitch(f0, f0.token, 'setFocus', true); sw.tapSwitch(f0, f0.token, 'setDone', true)
  const f1 = sw.frame('p', 'A', ''); assert.deepEqual(f1.nodes[0].children.slice(1).map(n => n.val), [1, 1])
  assert.throws(() => sw.tapSwitch(f1, 'stale', 'setFocus', false), /Widget changed/)
  assert.throws(() => sw.tapSwitch(f1, f1.token, 'nope', false), /not available/)
}
console.log('PASS live counter: +/−, restore, stale/forged taps, fallback, unsafe kinds, depth/node/text caps, effects, transport, redraw, stamp')
