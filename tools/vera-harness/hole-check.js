// Holes: the model writes function bodies, the compiler settles them. A fake model stands in for DeepSeek.
// Good body is used and drives the filter in the VM; a body with a type error is repaired from the
// {hole, message} report; hopeless bodies and no answer fall back to the default; the line map points at the hole.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {expandListRows} = loadVera('VeraTemplateContent')
const {composeProgram} = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {holesOf, holeValues, holeSpans, mapDiagnostics, fillHoles, parseHoleAnswer} = loadVera('VeraHoles')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const str = v => decodeRuntimeValue(['s', v])

const kinds = ['filter_box', 'master_list', 'detail_view']
const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
const rows = [['Pasta', 'Boil eight minutes.'], ['Soup', 'Simmer for an hour.'], ['Salad', 'Toss and serve.']]
function base(kind) {
  const spec = fragments().find(f => f.kind === kind), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, c.fallback))
  spec.listFields.forEach(l => m.set(l.token, expandListRows(kind === 'master_list' ? rows : undefined, l).text))
  return m
}
const build = bodies => {
  const extra = holeValues(kinds, bodies)
  return composeProgram(kinds, globals, kinds.map((k, i) => { const m = base(k); extra[i].forEach((v, t) => m.set(t, v)); return m }))
}
const vmOf = src => { const r = compileVeraSource(src); return new VirtualMachine(deserializeVbc2(r.vbc2 !== undefined ? r.vbc2 : r), new UiHostEnvironment()) }
const texts = n => [n.text, n.label, n.value].filter(Boolean).concat((n.children || []).flatMap(texts))
const shown = (vm, st) => texts(decodeVeraUi(vm.execute('view', [st]))[0]).join('|')

const holes = holesOf(kinds)
assert.deepEqual(holes.map(h => h.key), ['rowMatches2'])

// defaults compile and filter by substring
{
  const vm = vmOf(build(new Map()))
  let st = vm.execute('init')
  assert.match(shown(vm, st), /Pasta/)
  st = vm.execute('setFilter1', [st, str('soup')])
  assert.doesNotMatch(shown(vm, st), /Soup/, 'default is case sensitive')
  st = vm.execute('setFilter1', [st, str('Soup')])
  assert.match(shown(vm, st), /Soup/); assert.doesNotMatch(shown(vm, st), /Pasta/)
}

const answer = body => JSON.stringify({holes: {rowMatches2: body}})
const lower = 'return query.length() === 0 || strings.contains(strings.toLowerCase(label), strings.toLowerCase(query));'

;(async () => {
  // 1. a good body is used and changes behaviour
  let asked = []
  let fill = await fillHoles('recipes', kinds, async (s, u) => { asked.push(u); return answer(lower) }, build)
  assert.equal(asked.length, 1); assert.match(fill.note, /holes=filled\(1\)/); assert.equal(fill.repairs, 0)
  {
    const vm = vmOf(build(fill.bodies)); let st = vm.execute('init')
    st = vm.execute('setFilter1', [st, str('soup')])
    assert.match(shown(vm, st), /Soup/); assert.doesNotMatch(shown(vm, st), /Pasta/)
    // the detail of a filtered row is still the right entry (index is into the full list)
    st = vm.execute('select2', [st, decodeRuntimeValue(['n', 1])])
    assert.match(shown(vm, st), /Simmer for an hour/)
  }

  // 2. a type error is reported as {hole, message} and repaired
  asked = []
  fill = await fillHoles('recipes', kinds, async (s, u) => { asked.push(u); return asked.length === 1 ? answer('return label;') : answer(lower) }, build)
  assert.equal(asked.length, 2); assert.equal(fill.repairs, 1); assert.match(fill.note, /repaired=1/)
  assert.match(asked[1], /"hole": "rowMatches2"/); assert.match(asked[1], /Compiler errors/); assert.match(asked[1], /return label;/)

  // 3. never fixed: two repairs, then the default
  asked = []
  fill = await fillHoles('recipes', kinds, async (s, u) => { asked.push(u); return answer('return label;') }, build)
  assert.equal(asked.length, 3); assert.equal(fill.bodies.size, 0); assert.match(fill.note, /holes=default/)
  assert.doesNotThrow(() => compileVeraSource(build(fill.bodies)))

  // 4. no answer, unusable answer, a body with a function header
  fill = await fillHoles('recipes', kinds, async () => null, build)
  assert.match(fill.note, /no answer/)
  fill = await fillHoles('recipes', kinds, async () => 'sorry', build)
  assert.match(fill.note, /unusable/)
  fill = await fillHoles('recipes', kinds, async () => answer('function x(): boolean { return true; }'), build)
  assert.match(fill.note, /unusable/)

  // 5. no holes in the chosen kinds: nothing asked
  fill = await fillHoles('x', ['checklist'], async () => { throw Error('must not ask') }, build)
  assert.equal(fill.note, '')

  // 6. line map: a broken body is found by the markers, a broken block outside them is not
  const bad = new Map([['rowMatches2', '  return label;']])
  let src = build(bad), diags
  try { compileVeraSource(src) } catch (e) { diags = e.diagnostics }
  let mapped = mapDiagnostics(holeSpans(src), diags)
  assert.ok(mapped.inside.length > 0 && mapped.inside.every(e => e.hole === 'rowMatches2')); assert.equal(mapped.outside, 0)
  src = build(new Map()).replace('let q: string = state.query1;', 'let q: string = nope;')
  try { compileVeraSource(src); assert.fail('should not compile') } catch (e) { diags = e.diagnostics }
  mapped = mapDiagnostics(holeSpans(src), diags)
  assert.equal(mapped.inside.length, 0); assert.ok(mapped.outside > 0)
  fill = await fillHoles('x', kinds, async () => answer(lower), () => src)
  assert.match(fill.note, /outside the holes/)

  // answers: fenced, indented, with a marker or without a return are cleaned or refused
  assert.equal(parseHoleAnswer(answer('```\nreturn true;\n```'), holes).get('rowMatches2'), '  return true;')
  assert.equal(parseHoleAnswer(answer('return true; //@hole x end'), holes).size, 0)
  assert.equal(parseHoleAnswer(answer('let x = 1;'), holes).size, 0)
  console.log('hole-check ok')
})().catch(e => { console.error(e); process.exit(1) })
