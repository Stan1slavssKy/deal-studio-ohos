// What a screen is for comes first and is shown once. Settings the request does not state are folded under one row at the foot of the
// screen; a whole number is set the same way each time; a yes or a no is not shown as 1 or 0; every section says what it already has,
// so a section written beside it does not draw it again (Water reminder, Pantry expiry, Shared costs, Istanbul layover on the phone). No network.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const c = loadVera('VeraCompose')
const nc = loadVera('NeedsChoose')
const sp = loadVera('ScreenPlan')
const {fragments} = loadVera('VeraTemplates')
const {compileVeraSource} = loadVera('VeraCompiler')
const {smokeRun} = loadVera('VeraSmoke')

// A whole number over a short range is a stepper, over a long one or with a fraction it is typed; other kinds are left to Jev.
const input = (over) => Object.assign(new c.SketchInput(), {id: 'x', label: 'X', kind: 'count', min: 0, max: 100, value: 12}, over)
assert.equal(c.countWidget(input()), 'stepper')
assert.equal(c.countWidget(input({max: 5000, value: 2000})), 'typed_number')
assert.equal(c.countWidget(input({value: 2.5})), 'typed_number')
assert.equal(c.countWidget(input({kind: 'amount'})), '')

// A condition worked out as 1 or 0 is a yes or a no.
assert.ok(c.isYesNoFormula('currentTemp >= feverThreshold ? 1 : 0'))
assert.ok(c.isYesNoFormula('(a < b && c == 1) ? 0 : 1'))
assert.ok(!c.isYesNoFormula('total / goal'))
assert.ok(!c.isYesNoFormula('x > 3 ? 1 : 1'))

// Settings: marked by the plan or by their words, never when the request states their value.
const fixture = file => fs.readFileSync(path.join(__dirname, 'compose', 'pill-calendar', file), 'utf8')
const withInputs = () => {
  const s = c.parseSketch(fixture('sketch.json'))
  s.inputs.push(input({id: 'dailyGoal', label: 'Daily goal (ml)', max: 5000, value: 2000}))
  s.inputs.push(input({id: 'hoursBefore', label: 'Hours before flight', value: 12, setting: true}))
  s.inputs.push(input({id: 'doses', label: 'Doses a day', value: 3}))
  return s
}
{
  const s = withInputs()
  assert.deepEqual(nc.markSettings(s, 'a water tracker; I land with 12 hours before my flight'), ['Daily goal (ml)'])
  assert.deepEqual(s.inputs.map(i => i.setting), [true, false, false], 'the stated 12 is not a setting; "doses a day" is not one by its words')
}
// Folded at the foot of the screen, under the list and its sections, and it runs.
{
  const s = withInputs()
  nc.markSettings(s, 'a pill tracker')
  const comp = c.readComposition(fixture('jev-answer.json'), s, false)
  for (const i of s.inputs) comp.inputs.includes(i) || comp.inputs.push(i)
  assert.deepEqual(c.foldedSettings(comp), ['dailyGoal', 'hoursBefore'])
  const plan = c.screenPlan(comp, [])
  const source = sp.assemblePlan(plan, true)
  const at = t => source.indexOf(t)
  assert.ok(at('"Settings"') > 0, 'a Settings row')
  assert.ok(at('"Settings"') > at('state.entries'), 'after the list')
  assert.ok(at('"Doses a day"') < at('"Settings"'), 'what is not a setting stays above')
  assert.ok(at('"Daily goal (ml)"') > at('"Settings"'), 'the setting is under the row')
  assert.equal(smokeRun(compileVeraSource(source), false), '')
  // A screen of inputs alone keeps them: they are all it has.
  const bare = c.parseSketch(JSON.stringify({title: 'T', inputs: [{id: 'goal', label: 'Goal', kind: 'count', min: 0, max: 10, value: 3, setting: true}],
    values: [], events: [], other: []}))
  const alone = c.readComposition('{"answers": {}}', bare, false)
  assert.deepEqual(c.foldedSettings(alone), [])
}

// Every section that stands on a screen says what it already has, its buttons among it.
for (const kind of ['record_log', 'checklist', 'timer', 'number_strip', 'breakdown_table', 'settle_up', 'series_chart', 'progress_goal']) {
  const spec = fragments().find(f => f.kind === kind)
  assert.ok(spec.owns.length > 0, kind + ' says what it has')
}
assert.match(fragments().find(f => f.kind === 'record_log').owns, /Remove last.*Start over/)
console.log('screen-order-check: ok')

// A need that names a button the screen already draws is done by it.
{
  const {buttonsOnScreen} = loadVera('agent/AgentClaims')
  const screen = 'ui.Button("danger", "Start over", "clearRecordsIDX", 0, n > 0), ui.Button("secondary", "Remove last", "removeLastRecordIDX", 0, n > 0), ui.Button("primary", "Add", "addIDX", 0, true)'
  assert.deepEqual(buttonsOnScreen([
    'removes the most recently added payment from the list (the remove-last button is tapped)',
    'clears every payment (the start-over button is tapped)',
    'adds a payment (the add button is tapped)',
    'shows who should pay whom'], screen), [
    'removes the most recently added payment from the list (the remove-last button is tapped)',
    'clears every payment (the start-over button is tapped)'])
  // The plan's own words for the same buttons.
  assert.deepEqual(buttonsOnScreen(['removes the most recently added payment from the list (the remove button is tapped)',
    'clears all payments and resets the totals (the reset button is tapped)', 'removes a payment (its remove button is tapped)'], screen), [
    'removes the most recently added payment from the list (the remove button is tapped)',
    'clears all payments and resets the totals (the reset button is tapped)'])
  console.log('screen-order-check: buttons on the screen')
}

// A written section does not draw a button the rest of the screen already has, wrapped in a When or not.
{
  const {withoutRepeatedButtons} = loadVera('agent/AgentClaims')
  const rest = 'ui.Button("danger", "Start over", "clearRecordsIDX", 0, n > 0), ui.Button("secondary", "Remove last", "removeLastRecordIDX", 0, n > 0)'
  const view = '{\n  sections.push(ui.Section("content", "Paid", "", [ui.Text("body", "x"), ui.ActionBar("end", [ui.Button("secondary", "Remove last", "c_undo", 0, true), ' +
    'ui.When(state.n > 0, ui.Button("danger", "Start Over", "c_clear", 0, true)), ui.Button("primary", "Share", "c_share", 0, true)])]));\n}'
  const out = withoutRepeatedButtons(view, rest)
  assert.equal(out, '{\n  sections.push(ui.Section("content", "Paid", "", [ui.Text("body", "x"), ui.ActionBar("end", [ui.Button("primary", "Share", "c_share", 0, true)])]));\n}')
  // The last in a list takes the comma before it.
  assert.equal(withoutRepeatedButtons('[ui.Text("body", "a"), ui.Button("danger", "Start over", "c", 0, true)]', rest), '[ui.Text("body", "a")]')
  assert.equal(withoutRepeatedButtons(view, 'ui.Button("primary", "Add", "a", 0, true)'), view, 'one-word labels stay')
  // A button that sets the section's own state is its own action: a quiz's "Start over" restarts the quiz (review of #46).
  const quiz = '[ui.Text("body", "a"), ui.Button("danger", "Start over", "c", 0, true)]'
  const restarts = 'function c(state: AppState, ignored: number): AppState {\n  return {c_score: 0__PASSTHROUGH__};\n}'
  assert.equal(withoutRepeatedButtons(quiz, rest, restarts), quiz, 'own action stays')
  const clears = 'function c(state: AppState, ignored: number): AppState {\n  return {entries: []__PASSTHROUGH__};\n}'
  assert.equal(withoutRepeatedButtons(quiz, rest, clears), '[ui.Text("body", "a")]', 'the log\'s action again goes')
  console.log('screen-order-check: no button twice')
}

// Work and rest in turns is asked for in so many words; a plain countdown is not.
{
  const nc2 = loadVera('NeedsChoose')
  assert.ok(nc2.asksForRounds('Make a homework timer that splits a task into 15-minute focus blocks with real breaks in between.'))
  assert.ok(nc2.asksForRounds('interval training: 30 s work, 10 s rest, 8 rounds'))
  assert.ok(!nc2.asksForRounds('a 10 minute egg timer'))
  // Review of #46: the words alone are not a turn of work and rest.
  for (const p of ['Countdown for the rest of the day', 'A 25-minute countdown for the rest of my study session',
    'tea timer, steep 3 minutes then let it rest', 'sets of reminders', 'blocks of text', '轮胎气压']) {
    assert.ok(!nc2.asksForRounds(p), p)
  }
  assert.ok(nc2.asksForRounds('Pomodoro timer with breaks'))
  console.log('screen-order-check: rounds')
}

{
  const nc3 = loadVera('NeedsChoose')
  assert.ok(nc3.asksOneTap('Make a water tracker that logs a glass with one tap'))
  assert.ok(!nc3.asksOneTap('Make a feeding tracker for a newborn that logs amount and time'))
  console.log('screen-order-check: one tap')
}

// A number field answered as a JSON number is taken, not dropped for the fallback.
{
  const {parseContentResponse} = loadVera('VeraTemplateContent')
  const {ContentFieldSpec} = loadVera('VeraTemplates')
  const fields = [new ContentFieldSpec('__A__', 'amount', '1', 'h', 6, true), new ContentFieldSpec('__U__', 'unit', '', 'h', 8)]
  const r = parseContentResponse('{"amount": 250, "unit": "ml"}', fields)
  assert.equal(r.values.get('__A__'), '250')
  console.log('screen-order-check: numbers as numbers')
}

// Minutes since midnight are a time of day, whatever kind the plan wrote.
{
  const s = c.parseSketch(JSON.stringify({title: 'T', inputs: [
    {id: 'sleepStart', label: 'Sleep starts', kind: 'count', measure: 'minutes', unit: 'minutes since midnight', min: 0, max: 1439, value: 1320},
    {id: 'rest', label: 'Rest', kind: 'count', measure: 'minutes', unit: 'min', min: 1, max: 60, value: 5}], values: [], events: [], other: []}))
  assert.equal(s.inputs[0].kind, 'time')
  assert.equal(s.inputs[0].value, 1320)
  assert.equal(s.inputs[1].kind, 'count')
  console.log('screen-order-check: minutes since midnight')
}

// The person's own things are only those the request names; none named is an empty list, not the fallback.
{
  const {expandListRows} = loadVera('VeraTemplateContent')
  const {fragments: fr} = loadVera('VeraTemplates')
  const doses = fr().find(f => f.kind === 'dose_schedule').listFields[0]
  assert.equal(expandListRows([['Vitamin D', '08:00', ''], ['Blood pressure pill', '20:00', '']], doses, 'remind me to take my pills every day').rows, 0)
  const kept = expandListRows([['Metformin', '08:00', 'with food'], ['Vitamin D', '20:00', '']], doses, 'I take metformin at 8 with breakfast')
  assert.equal(kept.rows, 1)
  assert.match(kept.text, /Metformin/)
  console.log('screen-order-check: own rows')
}

// Work and rest in rounds: the interval timer takes the countdown, the plan's lengths and the figures worked out from them, and the
// break's second countdown; what is left is assembled and runs (an exception here left the phone on "Composing..." for good).
{
  const sketch = c.parseSketch(JSON.stringify({title: 'Focus', inputs: [
    {id: 'focusMinutes', label: 'Focus block', kind: 'choice', measure: 'minutes', value: 0, options: [{label: '15 min', value: 15}, {label: '25 min', value: 25}]},
    {id: 'breakMinutes', label: 'Break', kind: 'choice', measure: 'minutes', value: 0, options: [{label: '5 min', value: 5}]},
    {id: 'subject', label: 'Subject', kind: 'text', value: 0}],
    constants: [], countdown: {label: 'Focus block', length: 'focusMinutes'},
    values: [{id: 'blocks', label: 'Focus blocks', means: 'blocks', format: 'count', formula: 'ceil(60 / focusMinutes)', example: {given: {focusMinutes: 15}, result: 4}},
             {id: 'total', label: 'Total session', means: 't', format: 'minutes', formula: 'blocks * (focusMinutes + breakMinutes)', example: {given: {blocks: 4, focusMinutes: 15, breakMinutes: 5}, result: 80}}],
    events: [{id: 'switch', when: 'a focus block or a break runs out', what: 'the phone switches to the other phase and starts its countdown', asked: true}],
    other: ['a second countdown: Break']}))
  const comp = c.readComposition(JSON.stringify({answers: {'clock.part': {type: 'choice', choice: 'interval_timer', confidence: 1}}}), sketch, false)
  assert.deepEqual(comp.blocks, ['interval_timer'])
  assert.deepEqual(comp.sketch.inputs.map(i => i.id), ['subject'])
  assert.deepEqual(comp.sketch.values, [])
  assert.deepEqual(comp.custom, [], 'the break, the phase switch and the totals are the timer\'s')
  assert.deepEqual(comp.unbound, [], 'nothing left reads a figure the timer took')
  // A figure Jev could not bind is gone with the others, not left unbound with no name.
  const failing = c.readComposition(JSON.stringify({answers: {'clock.part': {type: 'choice', choice: 'interval_timer', confidence: 1}}}),
    c.parseSketch(JSON.stringify({...JSON.parse(JSON.stringify({title: 'F', inputs: [{id: 'focusMinutes', label: 'Focus block', kind: 'count', measure: 'minutes', min: 1, max: 60, value: 15}],
      constants: [], countdown: {label: 'Focus', length: 'focusMinutes'},
      values: [{id: 'odd', label: 'Odd', means: 'x', format: 'plain', formula: 'focusMinutes * 7 + 3', example: {given: {focusMinutes: 15}, result: 1}}],
      events: [], other: []}))})), false)
  assert.deepEqual(failing.unbound, [])
  assert.match(comp.replaced[0].detail, /Focus block 15 min/)
  const plan = c.screenPlan(comp, [])
  assert.equal(smokeRun(compileVeraSource(sp.assemblePlan(plan, true)), false), '')
  console.log('screen-order-check: rounds to the interval timer')
}

// Stars earned for tasks and spent on rewards: the ledger takes the list, the taps wired to it and a checklist of the same tasks.
{
  const nc4 = loadVera('NeedsChoose')
  assert.ok(nc4.asksPoints('Make a chore chart for two kids where stars are earned for tasks and redeemed for rewards we agree on.'))
  assert.ok(!nc4.asksPoints('a list of chores for the week'))
  assert.ok(!nc4.asksPoints('Track API tokens I spend'))
  assert.ok(nc4.asksPoints('points the kids spend on screen time'))
  const sketch = c.parseSketch(JSON.stringify({title: 'Stars', inputs: [{id: 'kidOne', label: 'First kid', kind: 'text', value: 0}], constants: [],
    list: {label: 'Stars earned', fields: [{id: 'task', label: 'Task', kind: 'text'}, {id: 'stars', label: 'Stars', kind: 'number'}]},
    ready: ['the chores the kids can do for stars'], values: [],
    events: [{id: 'redeem', when: 'a reward is tapped', what: "takes the reward's star cost off that kid's star balance", asked: true}], other: []}))
  const ans = {'list.part': {type: 'choice', choice: 'points_ledger', confidence: 1}, 'ready.0': {type: 'choice', choice: 'checklist', confidence: 0.9},
    'whose.0': {type: 'choice', choice: 'written', confidence: 0.9}}
  const comp = c.readComposition(JSON.stringify({answers: ans}), sketch, false)
  assert.deepEqual(comp.blocks, ['points_ledger'], comp.note)
  assert.ok(!comp.custom.some(n => /reward/.test(n)), comp.custom)
  assert.equal(comp.sketch.list, null)
  assert.equal(smokeRun(compileVeraSource(sp.assemblePlan(c.screenPlan(comp, []), true)), false), '')
  const deck = c.readComposition(JSON.stringify({answers: {...ans, 'ready.0': {type: 'choice', choice: 'idea_deck', confidence: 0.9}}}), sketch, false)
  assert.deepEqual(deck.blocks, ['points_ledger'], 'a deck of the same chores goes too')
  const table = c.readComposition(JSON.stringify({answers: {...ans, 'ready.0': {type: 'choice', choice: 'data_table', confidence: 0.9}}}), sketch, false)
  assert.deepEqual(table.blocks, ['points_ledger'], 'a table of the same chores goes too')
  assert.deepEqual(table.inputs.map(i => i.id), [], 'the ledger names its people')
  console.log('screen-order-check: points to the ledger')
}

// A reading the request gives, in a unit the list keeps: readings with a status, starting from it.
{
  const nc5 = loadVera('NeedsChoose')
  const s = c.parseSketch(JSON.stringify({title: 'Fever', inputs: [], constants: [],
    list: {label: 'Temperature readings', fields: [{id: 'temperature', label: 'Temperature', kind: 'number', unit: '°C'}, {id: 'note', label: 'Note', kind: 'text'}]},
    values: [], events: [{id: 'warn', when: 'a reading is added', what: 'checks whether it is a fever', asked: true}], other: []}))
  assert.ok(nc5.readsMeasure(s, 'My baby has a fever of 37.5°C.'))
  assert.ok(!nc5.readsMeasure(s, 'a baby care card'))
  nc5.seedFromRequest(s, 'My baby has a fever of 37.5°C.')
  const comp = c.readComposition(JSON.stringify({answers: {'list.part': {type: 'choice', choice: 'reading_status', confidence: 1}}}), s, false)
  assert.deepEqual(comp.blocks, ['reading_status'], comp.note)
  assert.match(comp.replaced[0].detail, /first reading of Temperature 37\.5/)
  console.log('screen-order-check: readings')
}

// From the review of PR 46.
{
  const nc6 = loadVera('NeedsChoose')
  const {withoutRepeatedButtons} = loadVera('agent/AgentClaims')
  // Fahrenheit is not Celsius.
  assert.deepEqual(nc6.requestedMeasures('a fever of 101 degrees Fahrenheit'), [[101, 'fahrenheit']])
  assert.equal(nc6.unitKey('Temperature (°F)'), 'fahrenheit')
  // A time or a length the request states, in its own words, is not a setting.
  const s = c.parseSketch(JSON.stringify({title: 'T', inputs: [
    {id: 'wake', label: 'Wake time', kind: 'time', measure: 'minutes', min: 0, max: 1439, value: 450},
    {id: 'gap', label: 'Reminder every', kind: 'count', measure: 'minutes', min: 1, max: 600, value: 120}], values: [], events: [], other: []}))
  assert.deepEqual(nc6.markSettings(s, 'wake me at 7:30 and remind me every 2 hours'), [])
  // A button that is not an element of a list stays: cut out, the code would not compile.
  const rest = 'ui.Button("secondary", "Remove last", "x", 0, true)'
  const pushed = 'buttons.push(ui.Button("secondary", "Remove last", "c_undo", 0, true));'
  assert.equal(withoutRepeatedButtons(pushed, rest), pushed)
  // Ready blocks keep their places when the ledger takes one of them.
  const sk = c.parseSketch(JSON.stringify({title: 'Stars', inputs: [], constants: [],
    list: {label: 'Stars earned', fields: [{id: 'task', label: 'Task', kind: 'text'}]},
    ready: ['facts about chores', 'the chores the kids can do for stars', 'a timeline of the week'], values: [], events: [], other: []}))
  const says = (k, p = 0.9) => ({type: 'choice', choice: k, confidence: p})
  const comp = c.readComposition(JSON.stringify({answers: {'list.part': says('points_ledger', 1), 'ready.0': says('key_facts'), 'whose.0': says('written'),
    'ready.1': says('checklist'), 'whose.1': says('written'), 'ready.2': says('timeline'), 'whose.2': says('written')}}), sk, false)
  const plan = c.screenPlan(comp, [])
  for (const slot of plan.slots.filter(x => x.id.startsWith('ready.') || x.id.startsWith('section.'))) {
    assert.ok(slot.by >= 0 && slot.by < plan.components.length && plan.components[slot.by].spec.kind === (slot.id.startsWith('section.') ? slot.id.slice(8) :
      comp.readyKinds[Number(slot.id.slice(6))]), slot.id + ' points at its own block')
  }
  // A refused ledger leaves the list and its events alone.
  const kept = c.parseSketch(JSON.stringify({title: 'Stars', inputs: [{id: 'kid', label: 'First kid', kind: 'text', value: 0}], constants: [],
    list: {label: 'Stars earned', fields: [{id: 'task', label: 'Task', kind: 'text'}]}, values: [],
    events: [{id: 'cal', when: 'a star is added', what: 'adds it to the calendar', asked: true}], other: []}))
  const refused = c.readComposition(JSON.stringify({answers: {'list.part': says('points_ledger', 1), 'effect.cal': says('calendar_add', 1),
    'moment.cal': says('entry_added', 1), 'arg.cal.calendar_add.title': says('entry.task', 1)}}), kept, false)
  if (refused.blocks.indexOf('points_ledger') < 0) { assert.ok(refused.inputs.some(i => i.id === 'kid'), 'nothing was handed over') }
  console.log('screen-order-check: review of PR 46')
  // A notice drawn under the title keeps the blocks' numbers: put first, it took block 1, and a section written against the
  // program before it existed read another block's names (review of #46, ScreenPlan.ets).
  {
    const hole = loadVera('agent/AgentHole')
    const before = sp.assemblePlan(plan, true)
    plan.components.push(new sp.PlanComponent(sp.FILL_REPORTED, hole.noticeBlock(true, 'This phone cannot do that.'), new Map()))
    const after = sp.assemblePlan(plan, true)
    const fields = src => src.slice(src.indexOf('class AppState {'), src.indexOf('}', src.indexOf('class AppState {')))
    assert.equal(fields(after), fields(before), 'the same state fields with and without the notice')
    // the header, then the notice, then the blocks
    const drawn = after.slice(after.indexOf('function view(')).split('\n').filter(l => /sections\.push\(/.test(l))
    assert.match(drawn[0], /ui\.Header\(/)
    assert.match(drawn[1], /InsetBanner\("warning", "Not available on this phone"/, drawn.slice(0, 3).join('\n'))
    compileVeraSource(after)
    plan.components.pop()
  }
}

// Beside an itinerary, a list of the stops reached is the itinerary's own check.
{
  const s = c.parseSketch(JSON.stringify({title: 'Layover', inputs: [], constants: [],
    list: {label: 'Stops reached', fields: [{id: 'stop', label: 'Stop', kind: 'text'}, {id: 'at', label: 'Reached at', kind: 'time', value: 540}]},
    ready: ['the day\'s stops in order'], values: [], events: [], other: []}))
  const comp = c.readComposition(JSON.stringify({answers: {'ready.0': {type: 'choice', choice: 'itinerary', confidence: 0.9},
    'whose.0': {type: 'choice', choice: 'written', confidence: 0.9}}}), s, false)
  assert.deepEqual(comp.blocks, ['itinerary'])
  assert.equal(comp.sketch.list, null)
  console.log('screen-order-check: stops reached are the itinerary\'s')
}

// Beside an itinerary, the times Jev reads as its own (a stop's time, the day's end and length, the minutes between stops) leave
// unclaimed: read against the screen by the plan's names, they came back as sections of their own (West Lake: "Lunch at", then
// "Walking time", then "Back at start"). One about something else stays the plan's (review of #46: "Time at the airport before
// boarding"), and so does the deadline.
{
  const yes = {type: 'choice', choice: 'yes', confidence: 0.9}, no = {type: 'choice', choice: 'no', confidence: 0.9}
  const sk = (values) => c.parseSketch(JSON.stringify({title: 'West Lake', inputs: [{id: 'start', label: 'Start time', kind: 'time', min: 0, max: 1439, value: 540}],
    constants: [], ready: ['the day\'s stops in order'], values, events: [], other: []}))
  const answers = {'ready.0': {type: 'choice', choice: 'itinerary', confidence: 0.9}, 'whose.0': {type: 'choice', choice: 'written', confidence: 0.9},
    'itinerary.value.lunch': yes, 'itinerary.value.walk': yes, 'itinerary.value.back': yes, 'itinerary.value.airport': no}
  const values = [{id: 'lunch', label: 'Lunch at', means: 'when the family has lunch', format: 'time_of_day'},
    {id: 'walk', label: 'Walking time', means: 'minutes walking between stops', format: 'minutes'},
    {id: 'back', label: 'Back at start', means: 'when they are back where they began', format: 'time_of_day'},
    {id: 'airport', label: 'Time at the airport before boarding', means: 'minutes from arriving at the airport to boarding', format: 'minutes'},
    {id: 'cost', label: 'Travel budget', means: 'money for the day', format: 'money'}]
  const comp = c.readComposition(JSON.stringify({answers}), sk(values), false)
  assert.deepEqual(comp.blocks, ['itinerary'])
  for (const label of ['Lunch at', 'Walking time', 'Back at start']) {
    assert.ok(comp.dropped.indexOf('value "' + label + '": the itinerary\'s own times') >= 0, label + ': ' + comp.dropped.join(' | '))
  }
  assert.ok(!comp.claimed.some(x => /Lunch|Walking|Back at start/.test(x)), 'none is read against the screen: ' + comp.claimed.join(' | '))
  assert.ok(!comp.dropped.some(d => /(Time at the airport|Travel budget).*(itinerary|a section shows it)/.test(d)), comp.dropped.join(' | '))
  // the questions: one per time the plan works out, none for money; none at all on a plan with no times
  const qs = JSON.parse(c.buildComposeRequest('a day out', sk(values))).questions
  assert.deepEqual(Object.keys(qs).filter(k => k.startsWith('itinerary.value.')).sort(),
    ['itinerary.value.airport', 'itinerary.value.back', 'itinerary.value.lunch', 'itinerary.value.walk'])
  const habits = c.parseSketch(JSON.stringify({title: 'Habits', inputs: [], constants: [], ready: ['tips for keeping a habit'], values: [], events: [],
    other: ['a streak', 'a weekly view', 'a reminder', 'a note', 'a badge', 'a goal']}))
  assert.equal(Object.keys(JSON.parse(c.buildComposeRequest('habit tracker', habits)).questions).filter(k => k.startsWith('itinerary.')).length, 0)
  // the time the stops must be over by is the itinerary's to read, not its own
  const flight = c.readComposition(JSON.stringify({answers: Object.assign({'deadline.dep': yes, 'itinerary.value.dep': yes}, answers)}),
    sk([{id: 'dep', label: 'Flight departs', means: 'when the flight leaves', format: 'time_of_day', formula: 'start + 600', example: {given: {start: 540}, result: 1140}}]), false)
  assert.ok(!flight.dropped.some(d => /Flight departs.*own times/.test(d)), flight.dropped.join(' | '))
  console.log('screen-order-check: an itinerary\'s own times are not read against the screen')
}
