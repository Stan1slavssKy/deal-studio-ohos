// Runs every fragment (and a 4-section composition) through the real VM: init(), view(), decode. Then drives
// log_entries' handlers (type a note and an amount, add, remove) and checks the numbers on screen change.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {expandListRows} = loadVera('VeraTemplateContent')
const {composeProgram} = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
// Handler arguments are VM values, in the same tagged form run.js takes for a state.
const str = v => decodeRuntimeValue(['s', v])
const int = v => decodeRuntimeValue(['i', v])
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
function values(kind) {
  const spec = fragments().find(f => f.kind === kind), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, c.fallback))
  spec.listFields.forEach(l => m.set(l.token, expandListRows(undefined, l).text))
  return m
}
function build(kinds) {
  const src = composeProgram(kinds, globals, kinds.map(values))
  const result = compileVeraSource(src)
  const vm = new VirtualMachine(deserializeVbc2(result.vbc2 !== undefined ? result.vbc2 : result), new UiHostEnvironment())
  return vm
}
const view = (vm, state) => decodeVeraUi(vm.execute('view', [state]))[0]
const texts = node => [node.text, node.label, node.value].filter(Boolean).concat((node.children || []).flatMap(texts))
const kindsIn = node => [node.kind].concat((node.children || []).flatMap(kindsIn))

for (const f of fragments()) {
  const vm = build([f.kind])
  const tree = view(vm, vm.execute('init'))
  assert.ok(tree && (tree.children || []).length > 0, f.kind + ': empty tree')
}
const all = build(['log_entries', 'bar_chart', 'checklist', 'timeline'])
const t0 = view(all, all.execute('init'))
assert.ok(kindsIn(t0).includes('sparkline') && kindsIn(t0).includes('timeline'))

// log_entries: the form actually works
const vm = build(['log_entries'])
let state = vm.execute('init')
const call = (name, ...args) => { state = vm.execute(name, [state, ...args]) }
const names = (() => { const t = view(vm, state); return texts(t).join('|') })()
assert.match(names, /Nothing yet/)
call('setNote1', str('Lunch')); call('setAmount1', int(12)); call('addEntry1', int(0))
call('setNote1', str('Taxi')); call('setAmount1', int(30)); call('addEntry1', int(0))
let shown = texts(view(vm, state)).join('|')
assert.match(shown, /\|42\|/, 'total 42'); assert.match(shown, /Taxi/); assert.match(shown, /Lunch/)
assert.ok(shown.indexOf('Taxi') < shown.indexOf('Lunch'), 'newest first')
call('removeLast1', int(0))
shown = texts(view(vm, state)).join('|')
assert.match(shown, /\|12\|/); assert.doesNotMatch(shown, /Taxi/)
// the judge must see a chart's numbers, not only its caption
{
  const bars = values('bar_chart'), spec = fragments().find(f => f.kind === 'bar_chart').listFields[0]
  bars.set(spec.token, expandListRows([['Bananas', '40'], ['Apples', '20'], ['Pineapple', '50']], spec).text)
  const sum = loadVera('VeraSmokeRun').smokeRun(compileVeraSource(composeProgram(['bar_chart'], globals, [bars])).vbc2).summary
  assert.match(sum, /chart Bananas=40, Apples=20, Pineapple=50/, sum)
}
// smokeRun and the judge's request/answer helpers
const {smokeRun} = loadVera('VeraSmokeRun')
const {buildJudgeRequest, readJudgeAnswer} = loadVera('VeraCoverageJudge')
for (const f of fragments()) {
  const src = composeProgram([f.kind], globals, [values(f.kind)])
  const r = smokeRun(compileVeraSource(src).vbc2)
  assert.ok(r.ok, f.kind + ': ' + r.error); assert.ok(r.nodes >= 2); assert.match(r.summary, /^components: /); assert.ok(r.summary.length <= 700)
}
const trap = `import * as ui from "std/ui"

@jsonable
class AppState {
  items: int[];
}

function init(): AppState {
  let empty: int[] = [];
  return {items: empty};
}

function view(state: AppState): ui.View {
  let v: int = state.items[3];
  return ui.Column("default", [ui.Text("body", ui.intToString(v))]);
}`
const bad = smokeRun(compileVeraSource(trap).vbc2)
assert.equal(bad.ok, false); assert.ok(bad.error.length > 0)
const req = JSON.parse(buildJudgeRequest('grocery list for 10 people', 'components: list'))
assert.equal(req.questions.covers.type, 'noul'); assert.match(req.state, /grocery list for 10 people/)
assert.equal(readJudgeAnswer('{"answers":{"covers":{"noul":0.12}}}'), 0.12)
assert.equal(readJudgeAnswer('{"answers":{}}'), -1); assert.equal(readJudgeAnswer('nope'), -1); assert.equal(readJudgeAnswer('{"answers":{"covers":{"noul":7}}}'), -1)
console.log('template-run-check: ok (' + fragments().length + ' fragments)')
