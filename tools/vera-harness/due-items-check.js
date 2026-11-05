// due_items (things that expire or fall due) driven in the real VM: the rows are always soonest first, each says how far off it is
// in words and in a tone, the summary counts what is expired and what is due soon, Done starts a repeating thing over from today,
// and the ports publish the counts and the names due soon. Nothing here says "food": the names are plain content values.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {composeProgram} = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const num = v => decodeRuntimeValue(['n', v])
const str = v => decodeRuntimeValue(['s', v])

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
function values(items) {
  const spec = fragments().find(f => f.kind === 'due_items'), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, c.fallback))
  m.set('__ITEMS_IDX__', items)
  return m
}
function build(items) {
  const r = compileVeraSource(composeProgram(['due_items'], globals, [values(items)]))
  return new VirtualMachine(deserializeVbc2(r.vbc2 !== undefined ? r.vbc2 : r), new UiHostEnvironment())
}
const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)) }
const nodes = (vm, st) => { const out = []; walk(decodeVeraUi(vm.execute('view', [st]))[0], n => out.push(n)); return out }
const rows = (vm, st) => nodes(vm, st).filter(n => n.kind === 'listitem').map(n => [n.text, n.value, n.style])
const stats = (vm, st) => nodes(vm, st).filter(n => n.kind === 'numberstat').map(n => [n.label, n.numberValue, n.style])
const text = (vm, st) => nodes(vm, st).flatMap(n => Object.values(n).filter(v => typeof v === 'string' && v !== '')).join('|')
const now = new Date()
const today = Math.floor((now.getTime() - now.getTimezoneOffset() * 60000) / 86400000)

{
  const vm = build('{name: "Milk", inDays: 1, lifeDays: 0},\n    {name: "Water filter", inDays: 40, lifeDays: 90},\n    {name: "Bread", inDays: -2, lifeDays: 0}')
  let st = vm.execute('init')
  // Soonest first, whatever order they came in; the words and tones say how far off each is.
  assert.deepEqual(rows(vm, st), [['Bread', 'Expired 2 days ago', 'danger'], ['Milk', 'Tomorrow', 'warning'], ['Water filter', 'In 40 days', 'default']])
  assert.deepEqual(stats(vm, st), [['Expired', 1, 'danger'], ['Due soon', 1, 'warning']])
  assert.match(text(vm, st), /every 90 days · 44% left/)
  // Done only on what comes round again.
  const done = nodes(vm, st).filter(n => n.kind === 'button' && n.text === 'Done')
  assert.equal(done.length, 1)
  // Added with a date three days off: within the soon window, between Milk and the filter.
  st = vm.execute('setName1', [st, str('  Yogurt ')])
  st = vm.execute('setDue1', [st, num(today + 3)])
  st = vm.execute('addItem1', [st, num(0)])
  assert.deepEqual(rows(vm, st).map(r => r[0]), ['Bread', 'Milk', 'Yogurt', 'Water filter'])
  assert.deepEqual(rows(vm, st)[2], ['Yogurt', 'In 3 days', 'warning'])
  assert.deepEqual(stats(vm, st), [['Expired', 1, 'danger'], ['Due soon', 2, 'warning']])
  // What is due soon (not what is past its date), soonest first, for a section that reads soon_names; it agrees with soon_count.
  assert.equal(vm.execute('soonNames1', [st]).value, 'Milk, Yogurt')
  assert.equal(vm.execute('soonCount1', [st]).value, 2)
  assert.equal(vm.execute('expiredCount1', [st]).value, 1)
  // A blank name adds nothing; the form is cleared after an add.
  const before = rows(vm, st).length
  st = vm.execute('addItem1', [st, num(0)])
  assert.equal(rows(vm, st).length, before)
  // Done: the filter (index 1 as added) starts over from today with its whole life left.
  st = vm.execute('renew1', [st, num(1)])
  assert.deepEqual(rows(vm, st)[3], ['Water filter', 'In 90 days', 'default'])
  assert.match(text(vm, st), /every 90 days · 100% left/)
  // Done on something that happens once changes nothing.
  const once = JSON.stringify(rows(vm, st))
  st = vm.execute('renew1', [st, num(0)])
  assert.equal(JSON.stringify(rows(vm, st)), once)
  // Remove Bread (index 2 as added): nothing expired.
  st = vm.execute('removeItem1', [st, num(2)])
  assert.deepEqual(rows(vm, st).map(r => r[0]), ['Milk', 'Yogurt', 'Water filter'])
  assert.deepEqual(stats(vm, st)[0], ['Expired', 0, 'default'])
  // A narrower window: three days off is no longer soon.
  st = vm.execute('setSoon1', [st, num(1)])
  assert.deepEqual(rows(vm, st)[1], ['Yogurt', 'In 3 days', 'default'])
  assert.deepEqual(stats(vm, st)[1], ['Due soon', 1, 'warning'])
  // Today is red.
  st = vm.execute('setName1', [st, str('Eggs')]); st = vm.execute('setDue1', [st, num(today)]); st = vm.execute('addItem1', [st, num(0)])
  assert.deepEqual(rows(vm, st)[0], ['Eggs', 'Today', 'danger'])
  // A repeating thing added through the form.
  st = vm.execute('setName1', [st, str('Smoke alarm battery')]); st = vm.execute('setDue1', [st, num(today + 10)])
  st = vm.execute('setLife1', [st, str('365')]); st = vm.execute('addItem1', [st, num(0)])
  assert.match(text(vm, st), /Smoke alarm battery/); assert.match(text(vm, st), /every 365 days/)
}

// Nothing named in the request: the person adds their own, and there is no summary of nothing.
{
  const vm = build('')
  const st = vm.execute('init')
  assert.deepEqual(rows(vm, st), [])
  assert.deepEqual(stats(vm, st), [])
  assert.match(text(vm, st), /Nothing tracked yet/)
}

// Ports: the counts and the names due soon, for a section beside it (dinner ideas from what is about to go off).
{
  const spec = fragments().find(f => f.kind === 'due_items')
  assert.deepEqual(spec.ports.map(p => p.name), ['soon_count', 'expired_count', 'soon_names', 'count'])
  assert.ok(spec.owns.length > 0)
  const src = composeProgram(['due_items'], globals, [values('{name: "Spinach", inDays: 0, lifeDays: 0},\n    {name: "Eggs", inDays: 2, lifeDays: 0},\n    {name: "Rice", inDays: 200, lifeDays: 0}')])
  assert.match(src, /function soonNames1\(state: AppState\): string/)
}
console.log('due-items-check: ok')
