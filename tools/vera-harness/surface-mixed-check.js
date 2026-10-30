// A surface as one block of an ordinary screen (examples/surface-roulette.vera): the bank, the stake, the bet and the
// history are form components, the wheel is a ui.Surface between them, and both halves share one AppState. The
// screen keeps its form around the surface, passes the pre-serve checks, a Spin button and a tap on the wheel throw
// the same ball, the pocket the ball is drawn in is the number that is paid, the bank adds up over many spins, and
// the form's handlers keep working while the wheel turns.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const {play} = require('./gfx-run')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, VeraNumberValue, VeraStringValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const {pointerValue} = loadVera('VeraGfx')
const {smokeRun} = loadVera('VeraSmoke')
const {playSurface} = loadVera('VeraSurfacePlay')

const source = fs.readFileSync(path.join(__dirname, 'examples/surface-roulette.vera'), 'utf8')
const compiled = compileVeraSource(source)
assert.equal(smokeRun(compiled), '', 'the screen passes the smoke run')
assert.equal(playSurface(compiled, true), '', 'and the play check')

const vm = new VirtualMachine(deserializeVbc2(compiled.vbc2), new UiHostEnvironment())
const num = n => new VeraNumberValue(n)
const str = s => new VeraStringValue(s)
const get = (s, k) => { const v = s.fields.get(k); return v.value !== undefined ? v.value : v }
const wheel = (s, k) => get(get(s, 'wheel'), k)
const kinds = node => [node.kind].concat(...(node.children || []).map(kinds))
const frames = (s, n) => { for (let i = 0; i < n; i++) s = vm.execute('onFrame', [s, num(16)]); return s }
const button = (tree, text) => {
  const found = []
  const walk = n => { if (n.kind === 'button' && n.text === text) found.push(n); (n.children || []).forEach(walk) }
  walk(tree)
  return found[0]
}

// The surface sits among the form, not in place of it.
let state = vm.execute('init')
let tree = decodeVeraUi(vm.execute('view', [state]))[0]
const all = kinds(tree)
for (const k of ['surface', 'metricgroup', 'select', 'field', 'actionbar', 'section'])
  assert.ok(all.includes(k), 'the screen has a ' + k)
assert.ok(all.indexOf('metricgroup') < all.indexOf('surface') && all.indexOf('surface') < all.indexOf('select'),
  'the wheel is between the figures and the bet')

// The Spin button: the stake leaves the bank, the button is off while the ball runs, and a second spin is refused.
state = vm.execute('spin', [state, num(0)])
assert.equal(get(state, 'bank'), 490)
assert.equal(wheel(state, 'phase'), 'spinning')
state = frames(state, 30)
assert.equal(button(decodeVeraUi(vm.execute('view', [state]))[0], 'Spin').enabled, false, 'Spin is off while the ball runs')
assert.equal(get(vm.execute('spin', [state, num(0)]), 'bank'), 490, 'a spin while spinning takes nothing')

// The form keeps working under a moving wheel, but the ball is settled on the bet it was thrown with: on the phone a
// stake typed during the spin (10 became 1025) was paid out as if it had been staked.
state = vm.execute('setStake', [state, str('1025')])
state = vm.execute('setKind', [state, num(1)])
assert.equal(get(state, 'stakeText'), '1025')
assert.equal(wheel(state, 'phase'), 'spinning', 'typing does not stop the wheel')

// The ball drops into a pocket within ten seconds and the pocket it is drawn in is the number paid.
let settledAt = -1
for (let i = 0; i < 600 && settledAt < 0; i++) {
  state = frames(state, 1)
  if (wheel(state, 'phase') === 'settled') settledAt = i
}
assert.ok(settledAt > 60, 'the ball runs for a while before it drops: ' + settledAt)
const order = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9,
  22, 18, 29, 7, 28, 12, 35, 3, 26]
const n = wheel(state, 'pocket')
assert.equal(order[Math.round(wheel(state, 'ball') / (360 / 37)) % 37], n, 'the ball rests in the pocket of the number paid')
const last = get(state, 'history').elements[0]
assert.equal(last.fields.get('number').value, n)
const red = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36].includes(n)
assert.equal(get(state, 'bank'), 490 + (red ? 20 : 0), 'the $10 on red that was thrown is what is paid')
state = vm.execute('setKind', [vm.execute('setStake', [state, str('10')]), num(0)])
assert.ok(get(state, 'message').startsWith(String(n) + ' '), 'the banner names the number')
const turning = wheel(state, 'angle')
state = frames(state, 30)
assert.notEqual(wheel(state, 'angle'), turning, 'the wheel keeps turning with the ball in it')

// A tap on the wheel throws the ball too; a tap outside it does not.
state = frames(state, 3000)
assert.equal(wheel(state, 'phase'), 'idle', 'the wheel comes to rest')
const bank = get(state, 'bank')
assert.equal(wheel(vm.execute('onPointer', [state, pointerValue('up', 0, 2, 2)]), 'phase'), 'idle', 'a corner is not the wheel')
state = vm.execute('onPointer', [state, pointerValue('down', 0, 180, 120)])
state = vm.execute('onPointer', [state, pointerValue('up', 0, 180, 120)])
assert.equal(wheel(state, 'phase'), 'spinning', 'a tap on the wheel spins it')
assert.equal(get(state, 'bank'), bank - 10)

// Many spins on one number: every pocket is reachable, and the bank is the sum of what was staked and paid.
state = vm.execute('setKind', [frames(state, 800), num(6)])
state = vm.execute('setPick', [state, num(17)])
state = vm.execute('setStake', [state, str('1')])
const seen = new Set()
let expected = get(state, 'bank')
for (let i = 0; i < 400; i++) {
  state = vm.execute('spin', [state, num(0)])
  expected -= 1
  for (let f = 0; f < 900 && wheel(state, 'phase') !== 'settled'; f++) state = frames(state, 1)
  assert.equal(wheel(state, 'phase'), 'settled', 'spin ' + i + ' ends in a pocket')
  const p = wheel(state, 'pocket')
  seen.add(p)
  if (p === 17) expected += 36
  assert.equal(get(state, 'bank'), expected, 'spin ' + i + ': the bank adds up')
}
assert.ok(seen.size >= 33, 'the pockets are spread: ' + seen.size + ' of 37 in 400 spins')

// Out of money: the bank cannot be overdrawn, and the refill button appears.
state = vm.execute('setStake', [frames(state, 2000), str('100000')])
const broke = vm.execute('spin', [state, num(0)])
assert.equal(get(broke, 'bank'), get(state, 'bank'), 'a stake above the bank is refused')
assert.ok(get(broke, 'message').startsWith('The bank holds'))

// Frames for the eye: a spin from a tap, drawn with the phone's painter.
const out = process.argv[2]
const run = play(source, {frames: 420, dt: 16, every: 35, events: [[2, 'down', 0, 180, 100], [3, 'up', 0, 180, 100]]})
assert.equal(run.summary.trap, '')
assert.equal(run.summary.state.fields.get('wheel').fields.get('phase').value, 'settled')
if (out) {
  const {sheet} = require('./gfx-run')
  fs.mkdirSync(out, {recursive: true})
  fs.writeFileSync(path.join(out, 'roulette-sheet.svg'), sheet(run.drawn, 360, 360, 4))
}
console.log('surface-mixed-check: ok (' + seen.size + ' pockets in 400 spins, settled after ' + settledAt + ' frames)')
