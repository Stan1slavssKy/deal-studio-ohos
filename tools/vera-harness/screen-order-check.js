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
  console.log('screen-order-check: no button twice')
}

// Work and rest in turns is asked for in so many words; a plain countdown is not.
{
  const nc2 = loadVera('NeedsChoose')
  assert.ok(nc2.asksForRounds('Make a homework timer that splits a task into 15-minute focus blocks with real breaks in between.'))
  assert.ok(nc2.asksForRounds('interval training: 30 s work, 10 s rest, 8 rounds'))
  assert.ok(!nc2.asksForRounds('a 10 minute egg timer'))
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
