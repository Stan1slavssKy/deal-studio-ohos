// buildFromTemplates with canned Jev, model and judge answers: template, complete (soft veto and judge),
// scratch (hard veto, did not compile) and cancelled. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const compose = loadVera('VeraSectionCompose')
const judge = loadVera('VeraCoverageJudge')
const content = loadVera('VeraTemplateContent')
const {deepseek} = loadVera('DeepSeekEngine')
const {settings} = loadVera('SettingsStore')
const {buildFromTemplates} = loadVera('VeraTemplatePipeline')

settings.getSelectorKey = () => 'test-key'
settings.hasExaKey = () => false
deepseek.extractTemplateContent = async () => JSON.stringify({title: 'Test', section1_items: [['Milk', '2 L'], ['Eggs', '12'], ['Bread', '']]})

function jev(sections, vetoes) {
  const answers = {}
  sections.forEach((k, i) => { answers['section' + (i + 1)] = {choice: k, confidence: 0.9} })
  for (const k of ['needs_integration', 'needs_real_data', 'needs_search_or_form', 'needs_live_ticking', 'needs_multiple_counters', 'needs_logic'])
    answers['veto.' + k] = {noul: (vetoes || {})[k] || 0}
  return compose.readSectionPick(JSON.stringify({answers}))
}
const run = async (outcome, covers, opts = {}) => {
  compose.selectSections = async () => outcome
  judge.judgeCoverage = async () => covers
  let cancelled = false
  const statuses = []
  const build = await buildFromTemplates('grocery', 'deepseek', s => { statuses.push(s) }, () => opts.cancelAfterJev ? true : cancelled)
  return {build, statuses}
}
;(async () => {
  let {build} = await run(jev(['checklist']), 0.9)
  assert.equal(build.action, 'template'); assert.match(build.note, /covers=0\.90/); assert.match(build.source, /label: "Milk", detail: "2 L"/); assert.ok(build.vbc2.length > 0)

  ;({build} = await run(jev(['checklist']), 0.03))
  assert.equal(build.action, 'template', 'the judge only reports; it does not start a model call'); assert.match(build.note, /covers=0\.03/); assert.ok(build.source.length > 0)

  ;({build} = await run(jev(['checklist']), -1))
  assert.equal(build.action, 'template', 'no judge answer never blocks')

  ;({build} = await run(jev(['checklist'], {needs_logic: 0.95}), 0.9))
  assert.equal(build.action, 'complete'); assert.match(build.status, /adding the logic/)

  ;({build} = await run(jev(['checklist'], {needs_integration: 0.97}), 0.9))
  assert.equal(build.action, 'scratch'); assert.match(build.note, /vetoed needs_integration/)

  ;({build} = await run(jev(['none', 'none']), 0.9))
  assert.equal(build.action, 'scratch')

  ;({build} = await run(jev(['checklist'], {needs_real_data: 0.9}), 0.9))
  assert.equal(build.action, 'scratch'); assert.match(build.note, /no search available/)

  ;({build} = await run(jev(['checklist']), 0.9, {cancelAfterJev: true}))
  assert.equal(build.action, 'cancelled')

  // a composition that compiles but cannot run must not reach the screen: break the checklist view for this run
  const templates = loadVera('VeraTemplates'), real = templates.fragments
  templates.fragments = () => real().map(f => {
    if (f.kind === 'checklist') f.viewBlock = f.viewBlock.replace('let count: number = state.itemsIDX.length();', 'let count: number = state.itemsIDX.length(); let boom: number = state.itemsIDX[99].detail.length();')
    return f
  })
  ;({build} = await run(jev(['checklist']), 0.9))
  templates.fragments = real
  assert.equal(build.action, 'scratch'); assert.match(build.note, /did not run/)
  // a filter beside a list: the model is asked for the match rule too, and an answer without it keeps the default
  {
    const saved = deepseek.extractTemplateContent
    const rowsAnswer = {title: 'Books', section2_items: [['Dune', 'Sand.'], ['Emma', 'Manners.'], ['Ulysses', 'Dublin.']]}
    const lower = 'return query.length() === 0 || strings.contains(strings.toLowerCase(label), strings.toLowerCase(query));'
    let calls = 0
    deepseek.extractTemplateContent = async () => { calls++; return JSON.stringify(Object.assign({holes: {rowMatches2: lower}}, rowsAnswer)) }
    ;({build} = await run(jev(['filter_box', 'master_list', 'detail_view']), 0.9))
    assert.equal(build.action, 'template'); assert.match(build.note, /holes=filled\(1\)/); assert.match(build.source, /strings\.toLowerCase\(label\)/)
    deepseek.extractTemplateContent = async () => JSON.stringify(rowsAnswer)
    ;({build} = await run(jev(['filter_box', 'master_list', 'detail_view']), 0.9))
    assert.equal(build.action, 'template'); assert.match(build.note, /holes=default\(unusable answer\)/); assert.match(build.source, /strings\.contains\(label, query\)/)
    // no filter: the model is not asked about holes at all
    calls = 0
    deepseek.extractTemplateContent = async () => { calls++; return JSON.stringify(rowsAnswer) }
    ;({build} = await run(jev(['master_list', 'detail_view']), 0.9))
    assert.equal(build.action, 'template'); assert.doesNotMatch(build.note, /holes=/)
    assert.equal(calls, 1, 'only the content call')
    deepseek.extractTemplateContent = saved
  }

  console.log('pipeline-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
