// What the request itself says shows on the screen it asked for. A reading it names ("my baby has a fever of 37.5°C") is the
// list's first entry, not a form to fill in under "No reading yet"; and a refusal that says what is offered instead is a quiet
// line after the rest, not a warning above everything that works (Baby fever, Water reminder on the phone). No network.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const c = loadVera('VeraCompose')
const nc = loadVera('NeedsChoose')
const hole = loadVera('agent/AgentHole')
const sp = loadVera('ScreenPlan')
const {compileVeraSource} = loadVera('VeraCompiler')
const {smokeRun} = loadVera('VeraSmoke')

// Numbers with a unit, each once; a length of time is not a measure (startOnRequested has it).
assert.deepEqual(nc.requestedMeasures('My baby has a fever of 37.5°C. Create a baby fever care card.'), [[37.5, 'celsius']])
assert.deepEqual(nc.requestedMeasures('drink 250 ml every 2 hours, 2000 ml a day'), [[250, 'ml'], [2000, 'ml']])
assert.deepEqual(nc.requestedMeasures('a 10 minute timer'), [])
assert.equal(nc.unitKey('°C'), 'celsius')
assert.equal(nc.unitKey('Temperature'), 'celsius')

// The pill list with a temperature field: the request's reading becomes the first entry.
const fixture = file => fs.readFileSync(path.join(__dirname, 'compose', 'pill-calendar', file), 'utf8')
const sketchWith = unit => {
  const s = c.parseSketch(fixture('sketch.json'))
  const f = new c.ListField()
  f.id = 'temperature'; f.label = 'Temperature'; f.kind = 'number'; f.unit = unit
  s.list.fields.splice(1, 0, f)
  return s
}
{
  const s = sketchWith('°C')
  assert.equal(nc.seedFromRequest(s, 'My baby has a fever of 37.5°C.'), 'Temperature starts with 37.5')
  assert.equal(s.list.fields[1].seed, 37.5)
  const comp = c.readComposition(fixture('jev-answer.json'), s, false)
  const source = c.assembleProgram(comp)
  assert.match(source, /let firstEntries: LogEntry\[\] = \[\{[^}]*temperature: 37\.5/)
  assert.match(source, /entries: firstEntries/)
  const compiled = compileVeraSource(source)
  assert.equal(smokeRun(compiled, false), '')
}
// Two readings in the same unit, or no field in it: nothing is guessed.
{
  const s = sketchWith('°C')
  assert.equal(nc.seedFromRequest(s, 'it went from 37.5°C to 38.2°C'), '')
  assert.ok(Number.isNaN(s.list.fields[1].seed))
  const t = sketchWith('kg')
  assert.equal(nc.seedFromRequest(t, 'a fever of 37.5°C'), '')
  // A goal or the size of a tap is no reading (review of #46).
  const w = sketchWith('kg')
  assert.equal(nc.seedFromRequest(w, 'help me get down to 70 kg'), '')
  assert.equal(nc.seedFromRequest(sketchWith('ml'), 'Water tracker, log 250 ml with one tap'), '')
}

// "cannot X, so Y instead" is done differently: an info line, after the rest.
assert.ok(hole.offersInstead('This app cannot post a notification on your phone by itself, so it can only check whether notifications are allowed.'))
assert.ok(hole.offersInstead('Sending a text is not possible; the message is copied instead.'))
assert.ok(!hole.offersInstead('This phone has no target that creates a Clock alarm.'))
{
  const instead = hole.noticeBlock(true, 'This app cannot open the dialler, so it shows the number to call.')
  assert.match(instead.viewBlock, /InsetBanner\("default", "Done differently"/)
  assert.match(instead.viewBlock, /"info"\)/)
  const refused = hole.noticeBlock(true, 'This phone has no target that creates a Clock alarm.')
  assert.match(refused.viewBlock, /InsetBanner\("warning", "Not available on this phone"/)
  // Order on the screen: the refusal under the title, the rest, then what is done differently.
  const plan = new sp.ScreenPlan()
  const body = new (loadVera('VeraTemplates').FragmentSpec)('body', '', '', [], '', '', '', '{\n  sections.push(ui.Section("content", "", "", [ui.Text("body", "BODY")]));\n}', [], [])
  body.indexed = false
  plan.components.push(new sp.PlanComponent(sp.FILL_REPORTED, instead, new Map()))
  plan.components.push(new sp.PlanComponent('part', body, new Map()))
  plan.components.push(new sp.PlanComponent(sp.FILL_REPORTED, refused, new Map()))
  const source = sp.assemblePlan(plan, true)
  const at = s => source.indexOf(s)
  assert.ok(at('Not available on this phone') >= 0 && at('BODY') >= 0 && at('Done differently') >= 0, source)
  assert.ok(at('Not available on this phone') < at('BODY') && at('BODY') < at('Done differently'), 'refusal, body, instead')
  assert.equal(smokeRun(compileVeraSource(source), false), '')
}
console.log('request-seed-check: ok')
