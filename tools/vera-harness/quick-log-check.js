// quick_log driven in the real VM with the clock held still: one tap adds the amount per tap, today's total fills the ring toward the
// goal, the count and "Last ... ago" follow, a preset adds its own amount, Undo takes back today's last, Remove takes one row, and
// a new day starts at zero with yesterday's count under it. The amount and the goal are settings at the foot. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {composeProgram} = loadVera('VeraSectionCompose')
const {expandListRows} = loadVera('VeraTemplateContent')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const num = v => decodeRuntimeValue(['n', v])
const str = v => decodeRuntimeValue(['s', v])

// The clock the program reads: a fixed local time, moved by hand.
const RealDate = Date
let now = new RealDate(2026, 10, 3, 9, 0, 0)
global.Date = class extends RealDate { constructor(...a) { if (a.length === 0) { super(now.getTime()) } else { super(...a) } } }
const at = (h, m, dayShift = 0) => { now = new RealDate(2026, 10, 3 + dayShift, h, m, 0) }

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
function values(over = {}, presets = undefined) {
  const spec = fragments().find(f => f.kind === 'quick_log'), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, over[c.token] !== undefined ? over[c.token] : c.fallback))
  spec.listFields.forEach(l => m.set(l.token, expandListRows(presets, l).text))
  return m
}
function build(over, presets) {
  const src = composeProgram(['quick_log'], globals, [values(over, presets)])
  const r = compileVeraSource(src)
  const env = new UiHostEnvironment()
  return {src, env, vm: new VirtualMachine(deserializeVbc2(r.vbc2 !== undefined ? r.vbc2 : r), env)}
}
const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)) }
const nodes = (h, st) => { const out = []; walk(decodeVeraUi(h.vm.execute('view', [st]))[0], n => out.push(n)); return out }
const text = (h, st) => nodes(h, st).flatMap(n => Object.values(n).filter(v => typeof v === 'string' && v !== '')).join('|')
const act = (h, name, st, ...args) => h.vm.execute(name, [st, ...args])

const water = {__BUTTON_IDX__: 'Add a glass', __AMOUNT_IDX__: '250', __UNIT_IDX__: 'ml', __GOAL_IDX__: '2000', __COUNT_LABEL_IDX__: 'Glasses'}
const h = build(water)
let st = h.vm.execute('init')
let t = text(h, st)
assert.match(t, /0 of 2,?000 ml/); assert.match(t, /0\|Glasses\|today/); assert.match(t, /nothing yet today/)
assert.ok(nodes(h, st).some(n => n.kind === 'progressring'), 'a ring toward the goal')
assert.ok(!nodes(h, st).some(n => n.kind === 'emptystate'), 'no empty state: the ring and the count say 0')
assert.doesNotMatch(t, /Undo/, 'nothing to undo yet')
// the settings are at the foot, after the button
const kinds = nodes(h, st).map(n => n.kind + ':' + (n.label || n.text || ''))
assert.ok(kinds.findIndex(k => k.includes('Add a glass')) < kinds.findIndex(k => k.includes('Amount per tap (ml)')), 'button before settings')
assert.ok(kinds.findIndex(k => k.includes('Daily goal (ml, 0 for none)')) > 0)

// three taps at 09:00, 09:30, 10:10
at(9, 0); st = act(h, 'addTap1', st, num(0))
at(9, 30); st = act(h, 'addTap1', st, num(0))
at(10, 10); st = act(h, 'addTap1', st, num(0))
at(10, 40); t = text(h, st)
assert.match(t, /750 of 2,?000 ml/); assert.match(t, /3\|Glasses\|today/); assert.match(t, /30 min ago\|Last/)
assert.match(t, /250 ml\|10:10.*250 ml\|09:30.*250 ml\|09:00/, 'newest first')
assert.match(t, /Undo/)
at(12, 0); assert.match(text(h, st), /1 h 50 min ago\|Last/)
// Undo takes back the last one; Remove takes the row asked for (index 0 is 09:00)
st = act(h, 'undoTap1', st, num(0)); t = text(h, st)
assert.match(t, /500 of 2,?000 ml/); assert.doesNotMatch(t, /10:10/)
st = act(h, 'removeTap1', st, num(0)); t = text(h, st)
assert.match(t, /250 of 2,?000 ml/); assert.doesNotMatch(t, /09:00/); assert.match(t, /09:30/)
assert.equal(text(h, act(h, 'removeTap1', st, num(9))), t, 'an index outside the list does nothing')
// the amount per tap and the goal are settings
st = act(h, 'setTapAmount1', st, str('330')); st = act(h, 'addTap1', st, num(0))
assert.match(text(h, st), /580 of 2,?000 ml/)
st = act(h, 'setTapGoal1', st, str('500')); assert.ok(nodes(h, st).some(n => n.kind === 'progressring' && n.style === 'success'), 'goal reached')
st = act(h, 'setTapAmount1', st, str('nonsense')); st = act(h, 'addTap1', st, num(0))
assert.match(text(h, st), /581 of 500 ml/, 'an amount that is not a number counts 1')

// a new day: today is zero, yesterday is under it, Undo does not reach into yesterday
at(8, 0, 1); t = text(h, st)
assert.match(t, /0 of 500 ml/); assert.match(t, /0\|Glasses\|today/); assert.match(t, /Yesterday: 3, 581 ml/); assert.doesNotMatch(t, /Undo/)
assert.equal(text(h, act(h, 'undoTap1', st, num(0))), t, 'undo on a new day before any tap changes nothing')

// no unit and no goal: each tap is one more, no ring, the row is named
{
  at(9, 0)
  const n = build({__BUTTON_IDX__: 'Log a nappy', __AMOUNT_IDX__: '1', __UNIT_IDX__: '', __GOAL_IDX__: '0', __COUNT_LABEL_IDX__: 'Nappies', __ENTRY_WORD_IDX__: 'Nappy change'})
  let s = n.vm.execute('init'); s = act(n, 'addTap1', s, num(0)); s = act(n, 'addTap1', s, num(0))
  const tt = text(n, s)
  assert.ok(!nodes(n, s).some(x => x.kind === 'progressring'), 'no goal: no ring')
  assert.match(tt, /2\|Nappies\|today/); assert.match(tt, /Nappy change\|09:00/); assert.doesNotMatch(tt, /Amount per tap/)
}
// presets: extra buttons, each adds its own amount
{
  at(9, 0)
  const p = build(water, [['Small', '150'], ['Large', '500']])
  let s = p.vm.execute('init')
  assert.match(text(p, s), /Add a glass\|.*Small.*Large/)
  s = act(p, 'addPreset1', s, num(1)); s = act(p, 'addPreset1', s, num(0)); s = act(p, 'addPreset1', s, num(7))
  assert.match(text(p, s), /650 of 2,?000 ml/)
}
// the published numbers
{
  const ports = fragments().find(f => f.kind === 'quick_log').ports.map(p => p.name)
  assert.deepEqual(ports, ['today_total', 'today_count', 'goal'])
}
// two blocks do not collide
compileVeraSource(composeProgram(['quick_log', 'quick_log'], globals, [values(water), values({})]))
global.Date = RealDate
console.log('quick-log-check: ok')
