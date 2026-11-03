// interval_timer: focus and break in rounds, driven tick by tick in the real VM: the clock counts down, a block ends into a break,
// the break into the next round, the last round into "All rounds done" with the focus time; the phone vibrates at each change when
// the slot says so (read from the host's pending effects), and not when it does not. No network, no model.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {composeProgram} = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const {smokeRun} = loadVera('VeraSmoke')
const num = v => decodeRuntimeValue(['n', v])

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
function build(content = {}, signal = 'true') {
  const spec = fragments().find(f => f.kind === 'interval_timer'), m = new Map()
  spec.slots.forEach(s => m.set(s.token, signal))
  spec.contentFields.forEach(c => m.set(c.token, content[c.key] !== undefined ? content[c.key] : c.fallback))
  const src = composeProgram(['interval_timer'], globals, [m])
  const compiled = compileVeraSource(src)
  assert.equal(smokeRun(compiled, false), '', 'every handler runs')
  const env = new UiHostEnvironment()
  return {env, vm: new VirtualMachine(deserializeVbc2(compiled.vbc2 !== undefined ? compiled.vbc2 : compiled), env)}
}
const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)) }
const nodes = (h, st) => { const out = []; walk(decodeVeraUi(h.vm.execute('view', [st]))[0], n => out.push(n)); return out }
const texts = (h, st) => nodes(h, st).flatMap(n => Object.values(n).filter(v => typeof v === 'string' && v !== ''))
const badge = (h, st) => nodes(h, st).find(n => n.kind === 'badge').text
const clock = (h, st) => nodes(h, st).find(n => n.kind === 'text' && n.style === 'display').text
const round = (h, st) => nodes(h, st).find(n => n.kind === 'progress').label
function act(h, name, st, ...args) {
  h.env.effectsAllowed = true; h.env.pendingEffects = []
  const next = h.vm.execute(name, [st, ...args])
  const effects = h.env.pendingEffects
  h.env.effectsAllowed = false
  return {st: next, effects}
}
const tick = (h, st, ms) => act(h, 'onCycleTick1', st, num(ms))

// 15 minutes of focus, 5 of break, 2 rounds.
{
  const h = build({work_seconds: '900', rest_seconds: '300', rounds: '2', work_label: 'Focus', rest_label: 'Break'})
  let st = h.vm.execute('init')
  assert.equal(badge(h, st), 'Focus')
  assert.equal(clock(h, st), '15:00')
  assert.equal(round(h, st), 'Round 1 of 2')
  assert.ok(texts(h, st).includes('Start'))
  assert.ok(texts(h, st).includes('Focus (minutes)'), 'the settings are in minutes')
  // Not running: a tick does nothing.
  assert.equal(JSON.stringify(tick(h, st, 1000).st), JSON.stringify(st))
  st = act(h, 'toggleCycle1', st, num(0)).st
  assert.ok(texts(h, st).includes('Pause'))
  assert.equal(nodes(h, st).find(n => n.kind === 'ticker').checked, true, 'the ticker runs')
  let r = tick(h, st, 60000)
  st = r.st
  assert.equal(clock(h, st), '14:00')
  assert.equal(r.effects.length, 0, 'no signal mid-block')
  // The block ends: a break, with a vibration.
  r = tick(h, st, 840000); st = r.st
  assert.equal(badge(h, st), 'Break')
  assert.equal(clock(h, st), '5:00')
  assert.equal(r.effects.length, 1)
  assert.equal(r.effects[0].rawTarget, 'SensorServiceKit.vibrator.vibrate')
  // The break ends: round 2.
  r = tick(h, st, 300000); st = r.st
  assert.equal(badge(h, st), 'Focus')
  assert.equal(round(h, st), 'Round 2 of 2')
  assert.equal(r.effects.length, 1)
  // Skip the second block: all rounds done, the clock stops.
  r = act(h, 'skipPhase1', st, num(0)); st = r.st
  r = tick(h, st, 1000); st = r.st
  assert.ok(texts(h, st).includes('All rounds done'))
  assert.equal(clock(h, st), '15:00', 'the focus time of the one block run to its end')
  assert.ok(texts(h, st).includes('Start again'))
  assert.equal(nodes(h, st).find(n => n.kind === 'ticker').checked, false, 'the ticker is off')
  // Start again starts over and runs.
  st = act(h, 'toggleCycle1', st, num(0)).st
  assert.equal(round(h, st), 'Round 1 of 2')
  assert.ok(texts(h, st).includes('Pause'))
  // Reset stops it at the start.
  st = act(h, 'resetCycle1', tick(h, st, 5000).st, num(0)).st
  assert.equal(clock(h, st), '15:00')
  assert.ok(texts(h, st).includes('Start'))
}

// Short intervals are set in seconds; a last round ends without a break; no vibration when the slot says no.
{
  const h = build({work_seconds: '30', rest_seconds: '10', rounds: '1'}, 'false')
  let st = h.vm.execute('init')
  assert.equal(clock(h, st), '0:30')
  assert.ok(texts(h, st).some(t => /\(seconds\)$/.test(t)), 'the settings are in seconds')
  st = act(h, 'toggleCycle1', st, num(0)).st
  const r = tick(h, st, 31000)
  assert.ok(texts(h, r.st).includes('All rounds done'), 'one round: no break after it')
  assert.equal(r.effects.length, 0, 'no vibration when the slot says no')
  // A setting: 45 seconds of work.
  st = act(h, 'setWork1', h.vm.execute('init'), num(45)).st
  assert.equal(clock(h, st), '0:45')
  st = act(h, 'setRounds1', st, num(3)).st
  assert.equal(round(h, st), 'Round 1 of 3')
}

// Content out of range falls back: 25 minutes, 5, 4 rounds.
{
  const h = build({work_seconds: '0', rest_seconds: '-5', rounds: '0'})
  const st = h.vm.execute('init')
  assert.equal(clock(h, st), '25:00')
  assert.equal(round(h, st), 'Round 1 of 4')
}
console.log('interval-timer-check: ok')
