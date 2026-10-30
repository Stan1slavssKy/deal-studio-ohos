// A scene as one block of a screen the agent builds: the classifier answers whole, part or none; a part goes to the agent
// with its scene, which the plan of needs makes a need of its own; the scene skips the parts' and the catalogue's questions
// and Align, and goes to the section hole, whose writer is shown the scene guide and whose section is played before it is
// served -- fingers on the surface, then each button pressed. A fake model stands in for DeepSeek.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const {compileVeraSource} = loadVera('VeraCompiler')
const {playSurface} = loadVera('VeraSurfacePlay')
const {smokeRun} = loadVera('VeraSmoke')
const c = loadVera('VeraCompose')
const N = loadVera('NeedsPlan')
const {sceneNote} = loadVera('NeedsChoose')
const S = loadVera('agent/AgentSurface')
const {SCENE_EXAMPLE, SCENE_GUIDE, SCENE_TOKENS} = loadVera('agent/AgentScene')
const {CustomRequest, writeSection, parseSection} = loadVera('agent/AgentCustom')
const {alignCandidates, alignReaderCandidates} = loadVera('agent/AgentAlign')

const fixture = (...p) => fs.readFileSync(path.join(__dirname, 'compose', ...p), 'utf8')
const comp = c.readComposition(fixture('tip', 'jev-answer.json'), c.parseSketch(fixture('tip', 'sketch.json')))
const program = section => c.assembleProgram(comp, [], section)

;(async () => {
  // The classifier's three answers; the old true and false still read.
  const brief = o => S.parseSurfaceBrief(JSON.stringify(o))
  assert.equal(brief({surface: 'whole', title: 'T', design: 'd'}).kind, S.SURFACE_WHOLE)
  assert.equal(brief({surface: true, title: 'T', design: 'd'}).kind, S.SURFACE_WHOLE)
  const part = brief({surface: 'part', title: '', design: '', scene: 'a roulette wheel that spins and lands on a number'})
  assert.equal(part.kind, S.SURFACE_PART)
  assert.match(part.scene, /roulette/)
  assert.equal(brief({surface: 'part', scene: ''}), null, 'a part with no scene is no answer')
  assert.equal(brief({surface: false}).kind, S.SURFACE_NONE)
  assert.equal(brief({surface: 'none'}).kind, S.SURFACE_NONE)
  for (const p of ['virtual casino roulette', 'a prize wheel for my class', 'dice roller with a score sheet',
    'delivery form with a signature', '轮盘赌'])
    assert.ok(S.looksLikeSurface(p), p + ' is asked about')
  assert.ok(!S.looksLikeSurface('a todo list'))
  assert.match(sceneNote('a wheel'), /need of type scene: a wheel/)

  // The plan of needs: a scene is its own type, carried to the composer as a marked item of other.
  const plan = N.parseNeedsPlan(JSON.stringify({title: 'Roulette', inputs: [{id: 'stake', label: 'Stake', kind: 'amount', measure: 'money', min: 1, max: 500, value: 10}],
    needs: [{type: 'scene', what: 'a roulette wheel the ball spins on, landing on a number that pays the bet into the bank', from: 'roulette'},
      {type: 'other', what: 'rules'}]}))
  assert.deepEqual(plan.needs.map(n => n.type), ['scene', 'other'])
  assert.equal(plan.needs[0].from, 'roulette')
  const sketch = N.sketchFrom(plan)
  assert.equal(sketch.other.length, 2)
  assert.ok(c.isScene(sketch.other[0]) && !c.isScene(sketch.other[1]))
  assert.match(N.NEEDS_PROMPT, /"type": "scene"/)

  // The composer asks Jev nothing about a scene and sends it to the written section; Align never offers it a section.
  const questions = JSON.parse(c.buildComposeRequest('roulette', sketch)).questions
  assert.ok(!('covers.0' in questions) && !('asked.other.0' in questions), 'no question about the scene')
  assert.ok('covers.1' in questions, 'the other item is still asked about')
  const composed = c.readComposition(JSON.stringify({answers: {}}), sketch)
  assert.ok(composed.custom.some(n => c.isScene(n)), 'the scene is for the written section: ' + composed.custom)
  assert.ok(!alignCandidates(composed).some(n => c.isScene(n)) && !alignReaderCandidates(composed).some(n => c.isScene(n)))

  // The guide's own example is a section that composes into a program, passes the smoke run and plays.
  const example = parseSection(SCENE_EXAMPLE)
  assert.ok(example !== null, 'the example is in the section form')
  const compiled = compileVeraSource(program(example))
  assert.equal(smokeRun(compiled), '')
  assert.equal(playSurface(compiled, true, true), '', 'the example plays')
  assert.ok(SCENE_GUIDE.includes(SCENE_EXAMPLE))

  // Played with buttons: a scene only a button sets moving is found moving; without the buttons it is not.
  const buttonOnly = SCENE_EXAMPLE.replace('"c_draw", "c_frame", "c_tap"', '"c_draw", "c_frame", ""')
  const pressed = compileVeraSource(program(parseSection(buttonOnly)))
  assert.equal(playSurface(pressed, true, true), '', 'the Spin button sets it moving')
  assert.match(playSurface(pressed, true, false), /nothing on the surface changed/)
  // A scene nothing sets moving is sent back.
  const still = SCENE_EXAMPLE.replace('c_speed: 540 + math.randomBelow(seed, 360)', 'c_speed: 0')
  assert.match(playSurface(compileVeraSource(program(parseSection(still))), true, true), /nor after pressing each button/)

  // The writer: a scene need brings the guide and its budget; a still scene is quoted back and the next try served.
  const asks = []
  const request = Object.assign(new CustomRequest(), {needs: [c.SCENE_MARK + 'a prize wheel that spins and adds the prize to a total'],
    prompt: 'tip calculator with a prize wheel', compose: s => program(s)})
  const replies = [still, SCENE_EXAMPLE]
  const r = await writeSection(request, 'LANGUAGE', async (system, user, budget, think) => { asks.push({system, user, budget, think}); return replies.shift() })
  assert.ok(r.section !== null, r.failed)
  assert.equal(r.attempts, 2)
  assert.ok(asks[0].system.includes('A SCENE IN THIS SECTION'))
  assert.equal(asks[0].budget, SCENE_TOKENS)
  assert.match(asks[1].user, /nothing on the surface changed/)
  // A section with no scene is not shown the guide.
  const plain = Object.assign(new CustomRequest(), {needs: ['a counter'], prompt: 'p', compose: s => program(s)})
  const plainAsks = []
  await writeSection(plain, 'LANGUAGE', async (system, user, budget) => { plainAsks.push({system, budget}); return SCENE_EXAMPLE })
  assert.ok(!plainAsks[0].system.includes('A SCENE IN THIS SECTION'))

  console.log('scene-hole-check ok')
})().catch(e => { console.error(e); process.exit(1) })
