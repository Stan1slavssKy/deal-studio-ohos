// idea_deck: one idea featured at a time, Another cycles through those that fit the filters, Done marks it for today and moves on,
// the filters by time and level narrow both the featured idea and the list under it. Driven in the real VM. No network, no model.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {expandListRows} = loadVera('VeraTemplateContent')
const {composeProgram} = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const {smokeRun} = loadVera('VeraSmoke')
const num = v => decodeRuntimeValue(['n', v])

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
const IDEAS = [
  ['Read a few pages', '10', 'low', 'A light book.'],
  ['Slow breathing', '3', 'low', 'In for four, out for six.'],
  ['Push-ups', '5', 'high', 'Ten, slowly.'],
  ['Tidy a drawer', '15', 'medium', 'Keep what you use.'],
  ['Long bath', '40', 'low', 'Warm, not hot.'],
  ['Plan tomorrow', '5', 'medium', 'Three things.']
]
function build(rows = IDEAS) {
  const spec = fragments().find(f => f.kind === 'idea_deck'), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, c.key === 'level_label' ? 'Energy' : c.fallback))
  spec.listFields.forEach(l => m.set(l.token, expandListRows(rows, l).text))
  const src = composeProgram(['idea_deck'], globals, [m])
  const compiled = compileVeraSource(src)
  assert.equal(smokeRun(compiled, false), '', 'every handler runs')
  return new VirtualMachine(deserializeVbc2(compiled.vbc2 !== undefined ? compiled.vbc2 : compiled), new UiHostEnvironment())
}
const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)) }
const nodes = (vm, st) => { const out = []; walk(decodeVeraUi(vm.execute('view', [st]))[0], n => out.push(n)); return out }
const texts = (vm, st) => nodes(vm, st).flatMap(n => Object.values(n).filter(v => typeof v === 'string' && v !== ''))
// The featured idea is the "title" text inside the accent card.
const featured = (vm, st) => { const card = nodes(vm, st).find(n => n.kind === 'card'); if (!card) return null; let t = null; walk(card, n => { if (n.kind === 'text' && n.style === 'title') t = n.text }); return t }
const listed = (vm, st) => nodes(vm, st).filter(n => n.kind === 'listitem').map(n => n.text)

const vm = build()
let st = vm.execute('init')
assert.equal(featured(vm, st), 'Read a few pages')
assert.ok(texts(vm, st).some(t => t === '10 min · low'), 'the meta line: ' + texts(vm, st))
assert.ok(!texts(vm, st).some(t => /of \d+ done/.test(t)), 'no checklist header')
assert.equal(listed(vm, st).length, 5, 'the others under it')

// Another cycles through every idea and comes back.
const seen = []
for (let i = 0; i < 6; i++) { seen.push(featured(vm, st)); st = vm.execute('anotherIdea1', [st, num(0)]) }
assert.deepEqual(seen, IDEAS.map(r => r[0]))
assert.equal(featured(vm, st), 'Read a few pages', 'back to the first')

// Up to 5 minutes: only the three short ones, the featured one moves to one that fits.
st = vm.execute('setIdeaTime1', [st, num(1)])
assert.equal(featured(vm, st), 'Slow breathing')
assert.deepEqual(listed(vm, st).sort(), ['Plan tomorrow', 'Push-ups'])
st = vm.execute('anotherIdea1', [st, num(0)])
assert.equal(featured(vm, st), 'Push-ups')
st = vm.execute('anotherIdea1', [st, num(0)])
assert.equal(featured(vm, st), 'Plan tomorrow')
st = vm.execute('anotherIdea1', [st, num(0)])
assert.equal(featured(vm, st), 'Slow breathing', 'cycles within the filter')

// Level: the select lists Any and the levels found, in order; "medium" with up to 5 minutes leaves one.
const levelSelect = nodes(vm, st).find(n => n.kind === 'select' && n.label === 'Energy')
assert.deepEqual(levelSelect.options, ['Any', 'low', 'high', 'medium'])
st = vm.execute('setIdeaLevel1', [st, num(3)])
assert.equal(featured(vm, st), 'Plan tomorrow')
assert.deepEqual(listed(vm, st), [])
st = vm.execute('setIdeaLevel1', [st, num(2)])
st = vm.execute('setIdeaTime1', [st, num(1)])
assert.equal(featured(vm, st), 'Push-ups')

// Done marks it for today, moves to the next not done, and counts.
st = vm.execute('init')
st = vm.execute('doneIdea1', [st, num(0)])
assert.equal(featured(vm, st), 'Slow breathing')
assert.ok(texts(vm, st).includes('1 done today'))
assert.ok(nodes(vm, st).some(n => n.kind === 'listitem' && n.text === 'Read a few pages' && n.icon === 'check'), 'a done idea shows a check')
st = vm.execute('pickIdea1', [st, num(0)])
assert.equal(featured(vm, st), 'Read a few pages')
assert.ok(texts(vm, st).some(t => t === '10 min · low · done today'))
assert.ok(nodes(vm, st).some(n => n.kind === 'button' && n.text === 'Done' && n.enabled === false), 'Done is off for one done today')

// Nothing fits: no featured idea, an empty state.
{
  const short = build([['A', '40', 'low', ''], ['B', '50', 'high', ''], ['C', '45', 'low', ''], ['D', '60', 'low', ''], ['E', '35', 'high', ''], ['F', '90', 'low', '']])
  let s2 = short.execute('init')
  s2 = short.execute('setIdeaTime1', [s2, num(1)])
  assert.equal(featured(short, s2), null)
  assert.ok(texts(short, s2).includes('Nothing fits'))
  const before = JSON.stringify(s2)
  s2 = short.execute('doneIdea1', [s2, num(0)])
  assert.equal(JSON.stringify(s2), before, 'Done with nothing featured changes nothing')
}
console.log('idea-deck-check: ok')
