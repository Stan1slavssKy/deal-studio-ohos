// A countdown's length is worked out before the clock runs, so a figure it is made of is not offered the clock's own numbers: the
// phone once took "round length" as the countdown's duration over the rounds, for a countdown whose duration is the rounds' total,
// and the composer, seeing the circle, put up a five-minute length of its own. The plan is the one the model wrote for
// "interval timer: work 30 s, rest 10 s, 8 rounds" (needs-plans/interval-rounds.json). No network.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const c = loadVera('VeraCompose')
const np = loadVera('NeedsPlan')

const text = fs.readFileSync(path.join(__dirname, 'needs-plans', 'interval-rounds.json'), 'utf8')
const sketchOf = edit => { const plan = JSON.parse(text); if (edit) edit(plan); return np.sketchFrom(np.parseNeedsPlan(JSON.stringify(plan))) }
const keys = (sketch, id) => { const out = []; c.expressionsFor(sketch, sketch.values.findIndex(v => v.id === id)).forEach((_d, k) => out.push(k)); return out }
const clockOperands = list => list.filter(k => /\b(duration|remaining|elapsed)\b/.test(k.split(':').slice(1).join(' ')))

const sketch = sketchOf()
assert.equal(sketch.countdownLength, 'totalLength')
for (const id of ['roundLength', 'totalLength']) {
  assert.ok(keys(sketch, id).length > 0, id + ' still has expressions')
  assert.deepEqual(clockOperands(keys(sketch, id)), [], id + ' is offered the clock: ' + clockOperands(keys(sketch, id)))
}
assert.ok(keys(sketch, 'roundLength').includes('add:workSeconds:restSeconds'), 'the round length can still be work plus rest')

// A figure the length is not made of keeps the clock's numbers.
const other = sketchOf(p => p.needs.push({type: 'figure', id: 'perRound', label: 'Per round', means: 'the whole time over the rounds', format: 'seconds',
  unit: 's', formula: 'clock.duration / rounds', example: {given: {'clock.duration': 320, rounds: 8}, result: 40}}))
assert.ok(clockOperands(keys(other, 'perRound')).length > 0, 'a figure the length does not depend on reads the clock')

// With Jev's answer the round length is work plus rest, the countdown runs for the total and no length of its own is made up.
const says = (choice, confidence = 0.9) => ({type: 'choice', choice, confidence})
const body = JSON.stringify({answers: {theme: says('technical'), 'expr.roundLength': says('add:workSeconds:restSeconds'), 'steps.roundLength': says('one'),
  'expr.totalLength': says('multiply:roundLength:rounds'), 'steps.totalLength': says('one'), 'countdown.length': says('totalLength')}})
const comp = c.readComposition(body, sketch, false)
assert.equal(comp.countdownFrom, 'totalLength')
assert.equal(comp.countdownUnit, 'seconds')
assert.ok(!comp.sketch.inputs.some(i => i.id === 'countdownLength'), 'no length of its own: ' + comp.sketch.inputs.map(i => i.id))
console.log('length-feeders-check ok')
