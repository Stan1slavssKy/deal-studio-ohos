// The needs plan (NeedsPlan.ets): the plan the model writes without knowing the parts or the catalogue, and the Sketch the composer
// reads from it. Every recorded sketch is turned into a needs plan and back: the composer must read the same plan. No network.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const c = loadVera('VeraCompose')
const np = loadVera('NeedsPlan')

const dir = path.join(__dirname, 'compose')
const labels = fs.readdirSync(dir).filter(l => fs.existsSync(path.join(dir, l, 'sketch.json')))
assert.ok(labels.length >= 10, 'recorded sketches: ' + labels.length)

const {needsOf} = require('./needs-lib')

// What the composer reads of a Sketch: all of it that the later stages look at, as plain data.
const view = s => JSON.parse(JSON.stringify(s, (k, v) => typeof v === 'number' && Number.isNaN(v) ? 'NaN' : v instanceof Map ? [...v] : v))

for (const label of labels) {
  const text = fs.readFileSync(path.join(dir, label, 'sketch.json'), 'utf8')
  const was = c.parseSketch(text)
  assert.ok(was, label + ': the recorded sketch parses')
  const plan = np.parseNeedsPlan(JSON.stringify(needsOf(JSON.parse(text))))
  assert.ok(plan, label + ': the needs plan parses')
  const now = np.sketchFrom(plan)
  assert.ok(now, label + ': the composer reads the plan')
  // Needs are in the order the screen shows them, so what the composer keeps in lists keeps its order inside each list.
  assert.deepEqual(view(now), view(was), label + ': the same plan for the composer')
}
console.log('needs-plan: ' + labels.length + ' recorded sketches survive the round trip')

// The prompt names neither a part nor a section of the catalogue.
for (const word of ['READY', 'ready-made', 'section', 'catalogue', 'entryCount', 'entryTotal', 'part ']) {
  assert.ok(!np.NEEDS_PROMPT.includes(word), 'the needs prompt does not say "' + word + '"')
}
assert.ok(np.NEEDS_PROMPT.includes('entries.count') && np.NEEDS_PROMPT.includes('clock.remaining'))

// A figure's quantities are found, and an action keeps its moment.
{
  const plan = np.parseNeedsPlan(JSON.stringify({title: 'T', needs: [
    {type: 'entries', label: 'Meals', fields: []},
    {type: 'figure', id: 'avg', label: 'Average', means: 'mean', format: 'plain', formula: 'entries.total / entries.count'},
    {type: 'action', id: 'ping', when: 'when the countdown ends', what: 'beep', on: 'countdown_end'},
    {type: 'action', id: 'odd', when: 'x', what: 'y', on: 'nonsense'},
    {type: 'nonsense', what: 'dropped'}]}))
  assert.deepEqual(plan.needs.map(n => n.type), ['entries', 'figure', 'action', 'action'])
  assert.deepEqual([...plan.needs[1].reads].sort(), ['entries.count', 'entries.total'])
  assert.equal(plan.needs[2].on, 'countdown_end')
  assert.equal(plan.needs[3].on, 'other')
  const sketch = np.sketchFrom(plan)
  assert.equal(sketch.values[0].formula, 'entryTotal / entryCount')
  assert.equal(sketch.list.label, 'Meals')
}
// A second clock or list is not made twice: it goes to `other`, as the composer's own plan does.
{
  const sketch = np.sketchFrom(np.parseNeedsPlan(JSON.stringify({title: 'T', needs: [
    {type: 'countdown', label: 'A', length: 'x'}, {type: 'countdown', label: 'B', length: 'x'}, {type: 'stopwatch', label: 'C'},
    {type: 'entries', label: 'L1'}, {type: 'entries', label: 'L2'}]})))
  assert.equal(sketch.countdown, 'A')
  assert.ok(sketch.other.some(o => /second countdown/.test(o)) && sketch.other.some(o => /second list/.test(o)))
}
// Not a plan: nothing to read.
assert.equal(np.parseNeedsPlan('no json'), null)
assert.equal(np.parseNeedsPlan('{"title": '), null)
console.log('needs-plan-check ok')
