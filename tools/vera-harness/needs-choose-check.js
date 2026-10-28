// NeedsChoose.ets: the plan of needs and Jev's choice of a section or a part for each need, through runAgent with a host that
// answers from recorded plans (tools/vera-harness/compose/). The choices Jev gives are put in by hand. No network.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const {needsOf} = require('./needs-lib')
const {AgentHost, defaultBlockFill} = loadVera('agent/AgentHost')
const {AgentRequest, runAgent} = loadVera('agent/VeraAgent')
const nc = loadVera('NeedsChoose')
const np = loadVera('NeedsPlan')
const align = loadVera('agent/AgentAlign')

const fixture = (label, file) => fs.readFileSync(path.join(__dirname, 'compose', label, file), 'utf8')
const says = (choice, confidence = 0.9) => ({type: 'choice', choice, confidence})

// Runs the agent on a recorded sketch, written as a needs plan. `edit(sketchJson)` changes the recorded plan first; `choices` is
// what Jev answers to the choice call (null: nothing, twice). Returns what was asked of Jev, in order.
async function run(label, choices, edit = null) {
  const sketchJson = JSON.parse(fixture(label, 'sketch.json'))
  const rest = JSON.parse(fixture(label, 'jev-answer.json'))
  if (edit) edit(sketchJson, rest.answers)
  for (const key of Object.keys(rest.answers)) if (/^(clock\.part|list\.part|ready\.|whose\.|real_data)/.test(key)) delete rest.answers[key]
  const h = new AgentHost()
  const asked = []
  h.askPlan = async (system, user, onText) => {
    assert.match(system, /JSON plan of what the app needs/)
    const t = JSON.stringify(needsOf(sketchJson)); onText(t); return t
  }
  h.askJev = async body => {
    const q = JSON.parse(body).questions
    const isChoice = Object.keys(q).every(k => /^(clock\.part|list\.part|ready\.|whose\.|real_data)/.test(k))
    asked.push({keys: Object.keys(q), q})
    if (isChoice) return choices === null ? '' : JSON.stringify({answers: choices})
    return JSON.stringify(rest)
  }
  h.fillBlocks = async request => defaultBlockFill(request)
  const r = await runAgent(Object.assign(new AgentRequest(), {prompt: 'x'}), h)
  return {r, asked}
}
const isChoice = a => a.keys.every(k => /^(clock\.part|list\.part|ready\.|whose\.|real_data)/.test(k))
const settledKeys = a => a.keys.filter(k => /^(clock\.part|list\.part|ready\.|whose\.|real_data)/.test(k))
// A countdown of one fixed time and nothing wired to it: the case the `timer` section may take (merge-check.js's).
const fixedLength = (s, a) => {
  s.constants = [{id: 'brewTime', label: 'Brew time', value: 240, measure: 'seconds'}]
  s.countdown.length = 'brewTime'; s.events = []; s.inputs = []
  if (a) { delete a['effect.notifyDone']; delete a['moment.notifyDone']; a['countdown.length'] = says('brewTime', 1) }
}

;(async () => {
  nc.setNeedsEnabled(true)
  align.setAlignEnabled(false)

  // The plan's facts decide what is offered, before anyone is asked.
  {
    const plan = n => np.parseNeedsPlan(JSON.stringify(needsOf(n)))
    const egg = JSON.parse(fixture('soft-egg', 'sketch.json'))
    assert.equal(nc.timerMayTakeCountdown(plan(egg)), false, 'a length the person sets keeps the part')
    fixedLength(egg)
    assert.equal(nc.timerMayTakeCountdown(plan(egg)), true)
    egg.events = [{id: 'done', when: 'the countdown reaches zero', what: 'beep', asked: true}]
    assert.equal(nc.timerMayTakeCountdown(plan(egg)), false, 'something at the end keeps the part')
    const pill = JSON.parse(fixture('pill', 'sketch.json'))
    assert.deepEqual(nc.listSectionsFor(plan({...pill, events: [{id: 'a', when: 'when an entry is added', what: 'x', asked: true}]})), [])
    const log = JSON.parse(fixture('expenses', 'sketch.json'))
    log.values = [{id: 'sum', label: 'Sum', means: 'sum', format: 'plain', formula: 'entryTotal', example: {given: {entryTotal: 1}, result: 1}}]
    assert.deepEqual(nc.listSectionsFor(plan(log)), ['record_log'], 'a figure over the entries is only for the log to publish')
  }

  // A countdown of one fixed time: Jev is asked once, with the part and the section; the second call does not ask it again.
  {
    const {r, asked} = await run('soft-egg', {'clock.part': says('timer')}, fixedLength)
    assert.ok(isChoice(asked[0]) && !isChoice(asked[1]), 'the choice, then the rest')
    assert.deepEqual(asked[0].keys, ['clock.part'])
    assert.deepEqual(Object.keys(asked[0].q['clock.part'].criteria).sort(), ['part', 'timer'])
    assert.ok(!asked[1].keys.includes('clock.part'))
    assert.deepEqual(r.blocks, ['timer'], r.note)
    assert.equal(r.errors, '', r.note)
  }
  // The same, when Jev prefers the part: the part stays and nothing else changes.
  {
    const {r, asked} = await run('soft-egg', {'clock.part': says('part')}, fixedLength)
    assert.deepEqual(r.blocks || [], [], r.note)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.ok(isChoice(asked[0]) && !isChoice(asked[1]))
  }
  // A length the person sets: the section is not offered, so nobody is asked, and the second call does not ask it either.
  {
    const {r, asked} = await run('soft-egg', {})
    assert.ok(!isChoice(asked[0]) && !asked[0].keys.includes('clock.part'), 'no choice call')
    assert.deepEqual(r.blocks || [], [])
    assert.ok(r.vbc2.length > 0, r.note)
  }
  // A list the person fills in: the part, the log and the reminders side by side; the log takes it.
  {
    const {r, asked} = await run('expenses', {'list.part': says('record_log')})
    assert.deepEqual(Object.keys(asked[0].q['list.part'].criteria).sort(), ['part', 'record_log', 'reminders'])
    assert.ok(!asked[1].keys.includes('list.part'))
    assert.deepEqual(r.blocks, ['record_log'], r.note)
  }
  // Something happens as an entry is added: only the part can do it, so the question is not asked.
  {
    const {asked} = await run('pill', {}, s => { s.events = [{id: 'a', when: 'when an entry is added', what: 'beep', asked: true}] })
    assert.ok(asked.every(a => !a.keys.includes('list.part')))
  }
  // Content written for the request: which section, whose data it is and whether it needs a search are asked once, first.
  {
    const {r, asked} = await run('sections-beach', {'ready.0': says('checklist'), 'whose.0': says('written'), real_data: says('false')})
    assert.ok(isChoice(asked[0]))
    assert.ok(asked[0].keys.includes('ready.0') && asked[0].keys.includes('whose.0') && asked[0].keys.includes('real_data'))
    assert.deepEqual(settledKeys(asked[1]), [], 'the second call asks none of them')
    assert.deepEqual(r.blocks, ['checklist'], r.note)
  }
  // Jev gives no choice: the composer asks them itself in the second call, as before the plan of needs.
  {
    const {asked} = await run('sections-beach', null)
    assert.ok(asked.length >= 3 && isChoice(asked[0]) && isChoice(asked[1]))
    assert.ok(settledKeys(asked.find(a => !isChoice(a))).includes('ready.0'), 'the second call asks them')
  }
  nc.setNeedsEnabled(false)
  align.setAlignEnabled(true)
  console.log('needs-choose-check ok')
})().catch(e => { console.error(e); process.exit(1) })
