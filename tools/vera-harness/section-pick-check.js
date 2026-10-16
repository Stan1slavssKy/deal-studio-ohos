// readSectionPick against hand-built Jev answers: soft vetoes keep the sections and set needsLogic,
// a hard veto still drops them, a repeated kind is dropped. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {readSectionPick} = loadVera('VeraSectionCompose')
function body(sections, vetoes) {
  const answers = {}
  sections.forEach((k, i) => { answers['section' + (i + 1)] = {choice: k, confidence: 0.9} })
  const keys = ['needs_integration', 'needs_real_data', 'needs_search_or_form', 'needs_live_ticking', 'needs_multiple_counters', 'needs_logic']
  keys.forEach(k => { answers['veto.' + k] = {noul: vetoes[k] === undefined ? 0 : vetoes[k]} })
  return JSON.stringify({answers})
}
const SLOTS = 6
const pad = a => a.concat(Array(SLOTS - a.length).fill('none'))
const kinds = o => o.sections ? o.sections.map(s => s.kind) : null
let o = readSectionPick(body(['checklist', 'checklist'], {}))
assert.deepEqual(kinds(o), pad(['checklist', 'none'])); assert.equal(o.needsLogic, false); assert.match(o.note, /duplicate checklist/)
o = readSectionPick(body(['checklist', 'none'], {needs_logic: 0.85}))
assert.deepEqual(kinds(o), pad(['checklist', 'none'])); assert.equal(o.needsLogic, true); assert.match(o.note, /logic=needs_logic=0\.85/)
o = readSectionPick(body(['checklist', 'none'], {needs_search_or_form: 0.9}))
assert.equal(o.needsLogic, true)
o = readSectionPick(body(['checklist', 'none'], {needs_logic: 0.75}))
assert.equal(o.needsLogic, false)
o = readSectionPick(body(['checklist', 'none'], {needs_search_or_form: 0.65}))
assert.equal(o.needsLogic, false); assert.equal(o.sections !== null, true)
o = readSectionPick(body(['checklist', 'none'], {needs_integration: 0.6}))
assert.equal(o.needsLogic, true)
o = readSectionPick(body(['checklist', 'none'], {needs_integration: 0.95}))
assert.equal(o.sections, null); assert.match(o.note, /vetoed needs_integration=0\.95/)
o = readSectionPick(body(['none', 'none'], {needs_logic: 0.85}))
assert.equal(o.sections, null)
o = readSectionPick(body(['checklist', 'none'], {needs_real_data: 0.9}))
assert.equal(o.needsRealData, true); assert.equal(o.needsLogic, false)
o = readSectionPick(body(['search_list', 'none'], {needs_search_or_form: 0.95}))
assert.deepEqual(kinds(o), pad(['search_list', 'none'])); assert.equal(o.needsLogic, false)
o = readSectionPick(body(['search_list', 'none'], {needs_search_or_form: 0.95, needs_logic: 0.9}))
assert.equal(o.needsLogic, true); assert.doesNotMatch(o.note, /needs_search_or_form/)
o = readSectionPick(body(['log_entries', 'bar_chart', 'checklist', 'timeline'], {}))
assert.deepEqual(kinds(o), pad(['log_entries', 'bar_chart', 'checklist', 'timeline'])); assert.equal(o.needsLogic, false)
// layouts: master_detail puts the list first and the detail second whatever order Jev gave
const withLayout = (sections, layout, conf = 0.9) => {
  const b = JSON.parse(body(sections, {}))
  b.answers.__LAYOUT__ = {choice: layout, confidence: conf}
  return JSON.stringify(b)
}
o = readSectionPick(withLayout(['detail_view', 'metrics', 'master_list', 'none'], 'master_detail'))
assert.deepEqual(kinds(o), ['master_list', 'detail_view', 'metrics']); assert.equal(o.layout, 'master_detail')
// a required slot empty but a free section left: the detail is added after the list
o = readSectionPick(withLayout(['master_list', 'metrics', 'none', 'none'], 'master_detail'))
assert.deepEqual(kinds(o), ['master_list', 'detail_view', 'metrics']); assert.equal(o.layout, 'master_detail')
// too many in 'extra' (max 2): rejected
o = readSectionPick(withLayout(['master_list', 'detail_view', 'metrics', 'timer'], 'master_detail'))
assert.equal(o.layout, 'master_detail')
o = readSectionPick(withLayout(['master_list', 'detail_view', 'metrics', 'timer'], 'master_detail', 0.1))
assert.equal(o.layout, 'stack')   // below the confidence bar: no layout
o = readSectionPick(withLayout(['checklist', 'none', 'none', 'none'], 'none'))
assert.equal(o.layout, 'stack')
// Jev named the layout but answered master_list twice: the missing detail_view is filled in
o = readSectionPick(withLayout(['master_list', 'master_list', 'none', 'none'], 'master_detail'))
assert.deepEqual(kinds(o), ['master_list', 'detail_view']); assert.equal(o.layout, 'master_detail'); assert.match(o.note, /\+detail_view/)
// no empty section left to put it in: rejected, as before
o = readSectionPick(withLayout(['master_list', 'metrics', 'timer', 'checklist'], 'master_detail'))
assert.equal(o.layout, 'stack')
o = readSectionPick(withLayout(['checklist', 'none', 'none', 'none'], 'progress_list'))
assert.deepEqual(kinds(o), ['list_summary', 'checklist']); assert.equal(o.layout, 'progress_list')
o = readSectionPick(body(['filter_box', 'master_list', 'detail_view', 'none'], {needs_search_or_form: 0.95}))
assert.equal(o.needsLogic, false, 'a filter box is the search the veto asks for')
// search_list picked on its own, then a master_detail layout: the search becomes the filter wired to the list
o = readSectionPick(withLayout(['search_list', 'none', 'none', 'none'], 'master_detail'))
assert.deepEqual(kinds(o), ['filter_box', 'master_list', 'detail_view']); assert.equal(o.layout, 'master_detail')
assert.equal(o.needsLogic, false)
// log_report: the blocks of the shared-costs example, the vetoes its blocks cover, and the one they do not
const LOG = ['record_log', 'number_strip', 'breakdown_table', 'series_chart', 'settle_up']
const withVetoes = (sections, layout, vetoes) => {
  const b = JSON.parse(body(sections, vetoes))
  if (layout) b.answers.__LAYOUT__ = {choice: layout, confidence: 0.9}
  return JSON.stringify(b)
}
const costs = {needs_logic: 0.99, needs_search_or_form: 0.94, needs_multiple_counters: 0.9}
o = readSectionPick(withVetoes(['settle_up', 'series_chart', 'record_log', 'number_strip', 'breakdown_table'], 'log_report', costs))
assert.deepEqual(kinds(o), ['record_log', 'number_strip', 'series_chart', 'breakdown_table', 'settle_up'], 'by slot; inside a slot, Jev\'s order'); assert.equal(o.layout, 'log_report'); assert.equal(o.needsLogic, false, 'the blocks cover the logic, the form and the counters')
o = readSectionPick(withVetoes(['settle_up', 'none'], 'log_report', costs))
assert.deepEqual(kinds(o), ['record_log', 'settle_up']); assert.match(o.note, /\+record_log/)
o = readSectionPick(withVetoes(['record_log', 'bar_chart'], '', Object.assign({needs_live_ticking: 0.9}, costs)))
assert.equal(o.needsLogic, true); assert.match(o.note, /needs_live_ticking/); assert.doesNotMatch(o.note, /needs_logic/)
o = readSectionPick(withVetoes(['checklist', 'none'], '', {needs_logic: 0.99}))
assert.equal(o.needsLogic, true, 'a block that covers nothing leaves the veto in force')
// independent "does the request ask for this part" answers, applied once a layout is chosen
const withIncludes = (sections, layout, includes, vetoes = {}) => {
  const b = JSON.parse(body(sections, vetoes))
  if (layout) b.answers.__LAYOUT__ = {choice: layout, confidence: 1}
  for (const [k, v] of Object.entries(includes)) b.answers['include.' + k] = {noul: v}
  return JSON.stringify(b)
}
o = readSectionPick(withIncludes(['record_log', 'none', 'none'], 'log_report', {record_log: 0.9, number_strip: 0.8, breakdown_table: 0.7, series_chart: 0.6, settle_up: 0.95, master_list: 0.1, detail_view: 0.05}, costs))
assert.deepEqual(kinds(o), ['record_log', 'number_strip', 'breakdown_table', 'series_chart', 'settle_up'], 'low section confidence no longer loses the parts the request asks for')
assert.equal(o.layout, 'log_report'); assert.equal(o.needsLogic, false)
o = readSectionPick(withIncludes(['none', 'none'], 'log_report', {record_log: 0.9, settle_up: 0.3, series_chart: 0.49}))
assert.deepEqual(kinds(o), ['record_log'], 'below the bar they are not added')
o = readSectionPick(withIncludes(['checklist', 'none'], '', {settle_up: 0.99}))
assert.deepEqual(kinds(o), pad(['checklist']), 'no layout, no include answers read')
o = readSectionPick(withIncludes(['record_log', 'settle_up', 'none'], 'log_report', {settle_up: 0.9}))
assert.deepEqual(kinds(o), ['record_log', 'settle_up'], 'a part Jev already put in a section is not added twice')
// a slot that changes what a block shows needs a surer answer than a cosmetic one
{
  const slotAnswer = noul => { const b = JSON.parse(body(['number_strip', 'none'], {})); b.answers['section1.number_strip.show_count'] = {noul}; b.answers['section1.bar_chart.bar_style'] = {choice: 'accent', confidence: 0.3}; return JSON.stringify(b) }
  o = readSectionPick(slotAnswer(0.4)); assert.equal(o.sections[0].slotValues.get('__SHOW_COUNT_IDX__'), 'false')
  o = readSectionPick(slotAnswer(0.7)); assert.equal(o.sections[0].slotValues.get('__SHOW_COUNT_IDX__'), 'true')
}
const {arrangeInLayout} = loadVera('VeraLayouts')
assert.equal(arrangeInLayout('master_detail', ['master_list', 'detail_view', 'a', 'b', 'c']), null)   // 3 extras > max 2
assert.equal(arrangeInLayout('nope', ['master_list']), null)
assert.deepEqual(arrangeInLayout('master_detail', ['none', 'detail_view', 'master_list']), [2, 1])

console.log('section-pick-check: ok')
