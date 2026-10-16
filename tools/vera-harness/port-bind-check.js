// Port binding between fragments: master_list publishes items+selected, detail_view reads them.
// Checks the bindings, the composed program in the real VM (tap a row, the detail follows), the
// order-independence, and the unbound fallback. No device, no Jev call.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {expandListRows} = loadVera('VeraTemplateContent')
const {composeProgram, bindPorts} = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const int = v => decodeRuntimeValue(['n', v])

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
function values(kind, rows) {
  const spec = fragments().find(f => f.kind === kind), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, c.fallback))
  spec.listFields.forEach(l => m.set(l.token, expandListRows(rows, l).text))
  return m
}
const rows = [['Pasta', 'Boil eight minutes.'], ['Soup', 'Simmer for an hour.'], ['Salad', 'Toss and serve.']]
function build(kinds) {
  const src = composeProgram(kinds, globals, kinds.map(k => values(k, k === 'master_list' ? rows : undefined)))
  const result = compileVeraSource(src)
  return {src, vm: new VirtualMachine(deserializeVbc2(result.vbc2 !== undefined ? result.vbc2 : result), new UiHostEnvironment())}
}
const texts = node => [node.text, node.label, node.value].filter(Boolean).concat((node.children || []).flatMap(texts))
const shown = (vm, state) => texts(decodeVeraUi(vm.execute('view', [state]))[0]).join('|')

// bindings: the reader of slot 2 points at slot 1's fields, and the other way round
let b = bindPorts(['master_list', 'detail_view'])
assert.equal(b[1].get('__PORT_selected__'), 'state.selected1')
assert.equal(b[1].get('__PORT_items__'), 'state.items1')
b = bindPorts(['detail_view', 'master_list'])
assert.equal(b[0].get('__PORT_selected__'), 'state.selected2')
// no publisher chosen: the port's fallback
b = bindPorts(['detail_view'])
assert.equal(b[0].get('__PORT_selected__'), '-1')
assert.equal(b[0].get('__PORT_items__'), '[]')
// a type mismatch must not bind: nothing else publishes "selected" as a string
assert.equal(bindPorts(['checklist', 'detail_view'])[1].get('__PORT_selected__'), '-1')

for (const order of [['master_list', 'detail_view'], ['detail_view', 'master_list'], ['master_list', 'checklist', 'detail_view']]) {
  const {vm} = build(order)
  let state = vm.execute('init')
  let s = shown(vm, state)
  assert.match(s, /Nothing selected/, order + ': starts with nothing selected')
  assert.match(s, /Pasta/)
  const sel = order.indexOf('master_list') + 1
  state = vm.execute('select' + sel, [state, int(1)])
  s = shown(vm, state)
  assert.match(s, /Simmer for an hour\./, order + ': detail follows the tap')
  assert.doesNotMatch(s, /Nothing selected/)
  state = vm.execute('select' + sel, [state, int(2)])
  assert.match(shown(vm, state), /Toss and serve\./, order + ': and the next tap')
}
// alone, the detail view compiles and says nothing is selected
const alone = build(['detail_view'])
assert.match(shown(alone.vm, alone.vm.execute('init')), /Nothing selected/)

// every block's ports are real: a reads token occurs in its text, a writes ref is one of its own state fields
for (const f of fragments()) {
  const text = f.initStatements + f.initEntries + f.functions + f.viewBlock
  for (const port of f.ports) {
    if (port.dir === 'reads') {
      assert.ok(text.includes(port.ref), f.kind + ': reads token ' + port.ref + ' is not used')
      assert.ok(port.fallback.length > 0, f.kind + ': reads port ' + port.name + ' needs a fallback')
    } else {
      if (port.computed) { assert.ok(port.ref.includes('state') || port.ref.includes('IDX'), f.kind + ': computed port ' + port.name + ' has no expression'); continue }
      const field = f.stateFields.find(x => x.name === port.ref)
      assert.ok(field, f.kind + ': writes ' + port.name + ' names no state field ' + port.ref)
      assert.equal(field.type, port.type, f.kind + ': writes ' + port.name + ' type differs from its field')
    }
  }
}

// metrics from a checklist: the summary follows the ticks
{
  const kinds = ['list_summary', 'checklist']
  assert.equal(bindPorts(kinds)[0].get('__PORT_done__'), 'doneCount2(state)')
  assert.equal(bindPorts(kinds)[0].get('__PORT_total__'), 'state.items2.length()')
  const {vm} = build(kinds)
  let state = vm.execute('init')
  const stats = () => { const nums = []; (function walk(n) { if (n.kind === 'numberstat') nums.push(n.numberValue); (n.children || []).forEach(walk) })(decodeVeraUi(vm.execute('view', [state]))[0]); return nums }
  assert.deepEqual(stats(), [0, 3, 3])
  state = vm.execute('toggle2', [state, int(0)]); state = vm.execute('toggle2', [state, int(2)])
  assert.deepEqual(stats(), [2, 3, 1])
  // alone, the summary falls back to zeros and still runs
  const alone = build(['list_summary'])
  decodeVeraUi(alone.vm.execute('view', [alone.vm.execute('init')]))
}
console.log('port-bind-check ok')
