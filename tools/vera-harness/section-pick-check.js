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
const SLOTS = 4
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
assert.deepEqual(kinds(o), ['log_entries', 'bar_chart', 'checklist', 'timeline']); assert.equal(o.needsLogic, false)
console.log('section-pick-check: ok')
