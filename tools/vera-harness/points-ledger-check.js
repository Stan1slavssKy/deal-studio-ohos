// points_ledger (points earned for tasks and spent on rewards) driven in the real VM: a task is one tap for the person picked, a
// reward costing more than the balance is dimmed and says what it still needs, redeeming takes the points off, Undo takes back the
// last entry, a task or a reward of one's own can be added, and the people and their balances are published under the names
// record_log uses, so series_chart draws them. Nothing here says "chores": the names are plain content values.
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

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
function values(kind, people) {
  const spec = fragments().find(f => f.kind === kind), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, c.token === '__UNIT_IDX__' ? 'stars' : c.fallback))
  spec.listFields.forEach(l => m.set(l.token, l.token === '__PEOPLE_IDX__' && people !== undefined
    ? people.map(n => '"' + n + '"').join(', ') : expandListRows(undefined, l).text))
  return m
}
function build(kinds, people) {
  const r = compileVeraSource(composeProgram(kinds, globals, kinds.map(k => values(k, people))))
  return new VirtualMachine(deserializeVbc2(r.vbc2 !== undefined ? r.vbc2 : r), new UiHostEnvironment())
}
const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)) }
const nodes = (vm, st) => { const out = []; walk(decodeVeraUi(vm.execute('view', [st]))[0], n => out.push(n)); return out }
const balances = (vm, st) => nodes(vm, st).filter(n => n.kind === 'numberstat').map(n => [n.label, n.numberValue])
const item = (vm, st, title) => nodes(vm, st).find(n => n.kind === 'listitem' && n.text === title)
const text = (vm, st) => nodes(vm, st).flatMap(n => Object.values(n).filter(v => typeof v === 'string' && v !== '')).join('|')
const button = (vm, st, label) => nodes(vm, st).find(n => n.kind === 'button' && n.text === label)

{
  const vm = build(['points_ledger'], ['Mia', 'Leo'])
  let st = vm.execute('init')
  assert.deepEqual(balances(vm, st), [['Mia', 0], ['Leo', 0]])
  assert.match(text(vm, st), /No points yet/)
  assert.equal(button(vm, st, 'Undo last').enabled, false)
  // Tasks of the content: Make the bed +1, Tidy up toys +2, Homework done +3; rewards: Extra story 5, Ice cream 10, Movie night 20.
  assert.equal(item(vm, st, 'Make the bed').value, '+1')
  assert.equal(item(vm, st, 'Extra story').enabled, false)
  assert.equal(item(vm, st, 'Extra story').label, 'needs 5 more')
  // Mia does homework twice: 6 stars, the story is within reach, the ice cream needs 4 more.
  st = vm.execute('award1', [st, num(2)]); st = vm.execute('award1', [st, num(2)])
  assert.deepEqual(balances(vm, st), [['Mia', 6], ['Leo', 0]])
  assert.equal(item(vm, st, 'Extra story').enabled, true)
  assert.equal(item(vm, st, 'Ice cream').label, 'needs 4 more')
  // Redeeming takes the points off; one she cannot afford changes nothing.
  st = vm.execute('redeem1', [st, num(0)])
  assert.deepEqual(balances(vm, st), [['Mia', 1], ['Leo', 0]])
  const before = JSON.stringify(balances(vm, st))
  st = vm.execute('redeem1', [st, num(2)])
  assert.equal(JSON.stringify(balances(vm, st)), before)
  // The history, newest first, says who and what, with the sign.
  const history = nodes(vm, st).filter(n => n.kind === 'listitem' && / · /.test(n.text)).map(n => [n.text, n.value])
  assert.deepEqual(history, [['Mia · Extra story', '-5'], ['Mia · Homework done', '+3'], ['Mia · Homework done', '+3']])
  // Leo is picked: his balance, his reach.
  st = vm.execute('setWho1', [st, num(1)])
  st = vm.execute('award1', [st, num(1)])
  assert.deepEqual(balances(vm, st), [['Mia', 1], ['Leo', 2]])
  assert.equal(item(vm, st, 'Extra story').label, 'needs 3 more')
  // Undo takes back the last entry only.
  st = vm.execute('undoLast1', [st, num(0)])
  assert.deepEqual(balances(vm, st), [['Mia', 1], ['Leo', 0]])
  // A task and a reward of one's own.
  st = vm.execute('setName1', [st, str('Walk the dog')]); st = vm.execute('setPoints1', [st, num(4)]); st = vm.execute('addTask1', [st, num(0)])
  assert.equal(item(vm, st, 'Walk the dog').value, '+4')
  st = vm.execute('setName1', [st, str('Late bedtime')]); st = vm.execute('setPoints1', [st, num(8)]); st = vm.execute('addReward1', [st, num(0)])
  assert.equal(item(vm, st, 'Late bedtime').label, 'needs 8 more')
  // A blank name adds nothing.
  const n = nodes(vm, st).filter(x => x.kind === 'listitem').length
  st = vm.execute('addTask1', [st, num(0)])
  assert.equal(nodes(vm, st).filter(x => x.kind === 'listitem').length, n)
  // Published under record_log's names.
  assert.deepEqual(vm.execute('points1', [st]).elements.map(v => v.value), [1, 0])
  assert.equal(vm.execute('pointsTotal1', [st]).value, 1)
}

// One person: no picker, no name in the history.
{
  const vm = build(['points_ledger'], ['Sam'])
  let st = vm.execute('init')
  assert.equal(nodes(vm, st).some(n => n.kind === 'select'), false)
  st = vm.execute('award1', [st, num(0)])
  assert.ok(item(vm, st, 'Make the bed'))
  assert.deepEqual(balances(vm, st), [['Sam', 1]])
}

// The ports record_log's readers take: a bar per person from series_chart.
{
  const spec = fragments().find(f => f.kind === 'points_ledger')
  assert.deepEqual(spec.ports.map(p => p.name), ['labels', 'totals', 'total', 'count'])
  assert.ok(spec.owns.length > 0)
  const vm = build(['points_ledger', 'series_chart'], ['Mia', 'Leo'])
  let st = vm.execute('init')
  st = vm.execute('award1', [st, num(2)])
  st = vm.execute('setWho1', [st, num(1)]); st = vm.execute('award1', [st, num(0)])
  let chart = null
  walk(decodeVeraUi(vm.execute('view', [st]))[0], n => { if (n.kind === 'sparkline') chart = n })
  assert.ok(chart, 'series_chart draws the points')
  assert.deepEqual(Array.from(chart.series), [3, 1])
  assert.deepEqual(Array.from(chart.categories), ['Mia', 'Leo'])
}
console.log('points-ledger-check: ok')
