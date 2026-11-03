// reading_status: readings read against bands written for the request. A first reading from the request is there at once with its
// band; added readings move the status from normal to watch to urgent, draw a line from the second one, list newest first and can
// be removed; the bands are explained under it; the ports say the latest, the level and the count. No network, no model.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments, FragmentSpec} = loadVera('VeraTemplates')
const {expandListRows} = loadVera('VeraTemplateContent')
const {composeProgram} = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const {smokeRun} = loadVera('VeraSmoke')
const num = v => decodeRuntimeValue(['n', v])
const str = v => decodeRuntimeValue(['s', v])

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
const FEVER = [['38', 'Normal', 'success', 'Keep an eye on it.'], ['39', 'Fever', 'warning', 'Fluids and light clothes.'],
  ['0', 'High fever', 'danger', 'Call a doctor.']]
function build(content = {}, bands = FEVER) {
  const spec = fragments().find(f => f.kind === 'reading_status'), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, content[c.key] !== undefined ? content[c.key] : c.fallback))
  spec.listFields.forEach(l => m.set(l.token, expandListRows(bands, l).text))
  const src = composeProgram(['reading_status'], globals, [m])
  const compiled = compileVeraSource(src)
  assert.equal(smokeRun(compiled, false), '', 'every handler runs')
  return new VirtualMachine(deserializeVbc2(compiled.vbc2 !== undefined ? compiled.vbc2 : compiled), new UiHostEnvironment())
}
const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)) }
const nodes = (vm, st) => { const out = []; walk(decodeVeraUi(vm.execute('view', [st]))[0], n => out.push(n)); return out }
const texts = (vm, st) => nodes(vm, st).flatMap(n => Object.values(n).filter(v => typeof v === 'string' && v !== ''))
const big = (vm, st) => { const t = nodes(vm, st).find(n => n.kind === 'text' && n.style === 'display'); return t ? t.text : null }
const status = (vm, st) => { const card = nodes(vm, st).find(n => n.kind === 'card'); if (!card) return null; let b = null; walk(card, n => { if (n.kind === 'badge') b = [n.text, n.style] }); return [card.style].concat(b) }
const add = (vm, st, typed) => vm.execute('addReading1', [vm.execute('setReadingDraft1', [st, str(typed)]), num(0)])
const C = {reading_label: 'Temperature', unit: '°C', unit_suffix: ' °C', decimals: '1'}

// The request's own reading is there from the start, with its band.
{
  const vm = build(Object.assign({first_reading: '37.5'}, C))
  const st = vm.execute('init')
  assert.equal(big(vm, st), '37.5 °C')
  assert.deepEqual(status(vm, st), ['success', 'Normal', 'success'])
  assert.ok(texts(vm, st).includes('Keep an eye on it.'))
  assert.ok(texts(vm, st).includes('Temperature (°C)'), 'the form names the unit')
  // The guide under it: ranges from the bands.
  const guide = nodes(vm, st).filter(n => n.kind === 'listitem' && ['Normal', 'Fever', 'High fever'].includes(n.text))
  assert.deepEqual(guide.map(n => n.value), ['Under 38.0 °C', '38.0 °C to 39.0 °C', '39.0 °C or more'])
  assert.equal(nodes(vm, st).filter(n => n.kind === 'sparkline').length, 0, 'one reading: no line yet')
}

// No first reading: one plain line, no card; then readings move the status and draw the line.
{
  const vm = build(Object.assign({first_reading: ''}, C))
  let st = vm.execute('init')
  assert.equal(big(vm, st), null)
  assert.ok(texts(vm, st).includes('Add a reading to see what it means.'))
  assert.ok(!nodes(vm, st).some(n => n.kind === 'emptystate'), 'no empty-state block')
  // Not a number: nothing added.
  assert.equal(JSON.stringify(add(vm, st, 'abc')), JSON.stringify(vm.execute('setReadingDraft1', [st, str('abc')])))
  st = add(vm, st, '38.4')
  assert.equal(big(vm, st), '38.4 °C')
  assert.deepEqual(status(vm, st), ['warning', 'Fever', 'warning'])
  assert.equal(vm.execute('statusLevel1', [st]).value, 1)
  st = add(vm, st, '39.2')
  assert.deepEqual(status(vm, st), ['danger', 'High fever', 'danger'])
  assert.equal(vm.execute('statusLevel1', [st]).value, 2)
  assert.equal(vm.execute('latest1', [st]).value, 39.2)
  const line = nodes(vm, st).find(n => n.kind === 'sparkline')
  assert.ok(line, 'two readings: a line')
  // Newest first, each with its band.
  const rows = nodes(vm, st).filter(n => n.kind === 'listitem' && /°C$/.test(n.text))
  assert.deepEqual(rows.map(n => [n.text, n.value]), [['39.2 °C', 'High fever'], ['38.4 °C', 'Fever']])
  // Remove the newest (index 1): the status goes back.
  st = vm.execute('removeReading1', [st, num(1)])
  assert.deepEqual(status(vm, st), ['warning', 'Fever', 'warning'])
  assert.equal(nodes(vm, st).filter(n => n.kind === 'sparkline').length, 0)
  st = add(vm, st, '36.9')
  assert.deepEqual(status(vm, st), ['success', 'Normal', 'success'])
  assert.equal(vm.execute('statusLevel1', [st]).value, 0)
}

// A low band first: under 70 is low (warning), the last band is open.
{
  const vm = build({reading_label: 'Pulse', unit: 'bpm', unit_suffix: ' bpm', decimals: '0', first_reading: '62'},
    [['70', 'Low', 'warning', 'Sit and rest.'], ['100', 'Normal', 'success', 'All fine.'], ['0', 'High', 'danger', 'Call a doctor.']])
  let st = vm.execute('init')
  assert.equal(big(vm, st), '62 bpm')
  assert.deepEqual(status(vm, st), ['warning', 'Low', 'warning'])
  st = add(vm, st, '120')
  assert.deepEqual(status(vm, st), ['danger', 'High', 'danger'])
}

// The ports a reader can take.
{
  const spec = fragments().find(f => f.kind === 'reading_status')
  assert.deepEqual(spec.ports.map(p => p.dir + ' ' + p.name), ['writes latest', 'writes status_level', 'writes count'])
  assert.ok(spec.owns.length > 0)
}
console.log('reading-status-check: ok')
