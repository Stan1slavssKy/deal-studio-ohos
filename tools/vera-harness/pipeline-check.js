// buildFromTemplates with canned Jev and model answers: template, complete (soft veto, a screen of placeholder
// buttons only), scratch (hard veto, did not compile) and cancelled. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const compose = loadVera('VeraSectionCompose')
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
const run = async (outcome, opts = {}) => {
  compose.selectSections = async () => outcome
  let cancelled = false
  const statuses = []
  const build = await buildFromTemplates('grocery', 'deepseek', s => { statuses.push(s) }, () => opts.cancelAfterJev ? true : cancelled)
  return {build, statuses}
}
;(async () => {
  let {build} = await run(jev(['checklist']))
  assert.equal(build.action, 'template'); assert.match(build.source, /label: "Milk", detail: "2 L"/); assert.ok(build.vbc2.length > 0)
  // no coverage judge: its scores did not separate good screens from bad ones, and nothing read them
  assert.doesNotMatch(build.note, /covers=/); assert.equal('covers' in build, false)

  // buttons that only note which one was tapped are not a finished screen: the model has to make them do something
  ;({build} = await run(jev(['actions'])))
  assert.equal(build.action, 'complete'); assert.match(build.note, /placeholder buttons only/); assert.ok(build.source.length > 0); assert.ok(build.vbc2.length > 0)
  ;({build} = await run(jev(['metrics', 'actions'])))
  assert.equal(build.action, 'template', 'actions beside a real block stays a template')

  ;({build} = await run(jev(['checklist'], {needs_logic: 0.95})))
  assert.equal(build.action, 'complete'); assert.match(build.status, /adding the logic/)

  ;({build} = await run(jev(['checklist'], {needs_integration: 0.97})))
  assert.equal(build.action, 'scratch'); assert.match(build.note, /vetoed needs_integration/)

  ;({build} = await run(jev(['none', 'none'])))
  assert.equal(build.action, 'scratch')

  ;({build} = await run(jev(['checklist'], {needs_real_data: 0.9})))
  assert.equal(build.action, 'scratch'); assert.match(build.note, /no search available/)

  ;({build} = await run(jev(['checklist']), {cancelAfterJev: true}))
  assert.equal(build.action, 'cancelled')

  // a composition that compiles but cannot run must not reach the screen: break the checklist view for this run
  const templates = loadVera('VeraTemplates'), real = templates.fragments
  templates.fragments = () => real().map(f => {
    if (f.kind === 'checklist') f.viewBlock = f.viewBlock.replace('let count: number = state.itemsIDX.length();', 'let count: number = state.itemsIDX.length(); let boom: number = state.itemsIDX[99].detail.length();')
    return f
  })
  ;({build} = await run(jev(['checklist'])))
  templates.fragments = real
  assert.equal(build.action, 'scratch'); assert.match(build.note, /did not run/)
  // a filter beside a list: the model is asked for the match rule too, and an answer without it keeps the default
  {
    const saved = deepseek.extractTemplateContent
    const rowsAnswer = {title: 'Books', section2_items: [['Dune', 'Sand.'], ['Emma', 'Manners.'], ['Ulysses', 'Dublin.']]}
    const lower = 'return query.length() === 0 || strings.contains(strings.toLowerCase(label), strings.toLowerCase(query));'
    let calls = 0
    deepseek.extractTemplateContent = async () => { calls++; return JSON.stringify(Object.assign({holes: {rowMatches2: lower}}, rowsAnswer)) }
    ;({build} = await run(jev(['filter_box', 'master_list', 'detail_view'])))
    assert.equal(build.action, 'template'); assert.match(build.note, /holes=filled\(1\)/); assert.match(build.source, /strings\.toLowerCase\(label\)/)
    deepseek.extractTemplateContent = async () => JSON.stringify(rowsAnswer)
    ;({build} = await run(jev(['filter_box', 'master_list', 'detail_view'])))
    assert.equal(build.action, 'template'); assert.match(build.note, /holes=default\(unusable answer\)/); assert.match(build.source, /strings\.contains\(label, query\)/)
    // no filter: the model is not asked about holes at all
    calls = 0
    deepseek.extractTemplateContent = async () => { calls++; return JSON.stringify(rowsAnswer) }
    ;({build} = await run(jev(['master_list', 'detail_view'])))
    assert.equal(build.action, 'template'); assert.doesNotMatch(build.note, /holes=/)
    assert.equal(calls, 1, 'only the content call')
    deepseek.extractTemplateContent = saved
  }

  // an intent panel: its rows come from a call of their own, made beside the content call; with no usable row the
  // panel is only a base for the model, never a finished screen
  {
    const reg = loadVera('VeraIntentRegistry'), saved = deepseek.extractTemplateContent, savedReg = reg.registryEntries
    const torch = new reg.RegistryEntry()
    Object.assign(torch, {target: 'com.ohos.sceneboard/entry/EntryAbility/OpenFlashlight', bundle: 'com.ohos.sceneboard',
      intentName: 'OpenFlashlight', modes: 'background', domain: 'system', params: [], paramHints: [], words: 'grocery torch'})
    reg.registryEntries = () => [torch]
    let rowsAnswer = JSON.stringify({section1: [{n: 1, label: 'Torch on'}]})
    deepseek.extractTemplateContent = async (system) => /phone actions/.test(system) ? rowsAnswer : JSON.stringify({title: 'Torch'})
    ;({build} = await run(jev(['intent_panel'])))
    assert.equal(build.action, 'template'); assert.match(build.note, /intents=1\/1/)
    assert.match(build.source, /target: "com\.ohos\.sceneboard\/entry\/EntryAbility\/OpenFlashlight"/)
    assert.match(build.composition, /OpenFlashlight/, 'the record keeps the rows')
    rowsAnswer = 'no'
    ;({build} = await run(jev(['intent_panel'])))
    assert.equal(build.action, 'complete'); assert.match(build.note, /intents=none/); assert.match(build.status, /phone actions/)
    deepseek.extractTemplateContent = saved
    reg.registryEntries = savedReg
  }

  console.log('pipeline-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
