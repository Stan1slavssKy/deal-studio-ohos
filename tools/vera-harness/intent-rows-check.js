// fillIntentRows (VeraIntentPanel.ets): the model picks phone actions by candidate number, and every row is rebuilt from
// the registry. A number that is not a candidate, a repeat, a parameter the intent does not declare and anything that is
// not a string or a number are dropped; the target and the mode always come from the registry, never from the answer.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const reg = loadVera('VeraIntentRegistry')
const {fillIntentRows} = loadVera('VeraIntentPanel')
const {INTENT_CATALOG} = loadVera('VeraIntentCatalog')

function entry(bundle, intentName, modes, params) {
  const e = new reg.RegistryEntry()
  Object.assign(e, {target: bundle + '/entry/EntryAbility/' + intentName, bundle, intentName, modes, domain: 'system',
    params, paramHints: params.map(p => p + ': string'), words: 'torch flashlight note ' + intentName})
  return e
}
const REGISTRY = [
  entry('com.ohos.sceneboard', 'OpenFlashlight', 'background', []),
  entry('com.ohos.sceneboard', 'CloseFlashlight', 'background foreground', []),
  entry('com.huawei.hmos.notepad', 'CreateNote', 'foreground', ['content', 'title'])
]
reg.registryEntries = () => REGISTRY

let lastUser = ''
const asker = answer => async (system, user) => { lastUser = user; return typeof answer === 'string' ? answer : JSON.stringify(answer) }
const PROMPT = 'Torch: one button for the flashlight and one to put it out, and a note with the text I type'
const number = (name) => { const m = new RegExp('^(\\d+)\\. ' + name + '\\b', 'm').exec(lastUser); assert.ok(m, name + ' is offered'); return Number(m[1]) }

;(async () => {
  // no panel on the screen: nothing is asked
  let asked = false
  let fill = await fillIntentRows(PROMPT, ['checklist'], async () => { asked = true; return '' })
  assert.equal(asked, false); assert.equal(fill.bodies.size, 0)

  // a first call only to learn the candidate numbers the request gets
  await fillIntentRows(PROMPT, ['metrics', 'intent_panel'], asker({}))
  const on = number('OpenFlashlight'), off = number('CloseFlashlight'), note = number('CreateNote')
  assert.match(lastUser, /CreateNote.*content, title/s, 'declared parameters are shown')

  fill = await fillIntentRows(PROMPT, ['metrics', 'intent_panel'], asker({section2: [
    {n: on, label: 'Torch "on"'},
    {n: off, label: 'Torch off', target: 'com.evil/x/y/Z', mode: 'foreground'},
    {n: note, label: 'Save note', params: {content: '{input}', title: 'From\nVera', secret: 'x', bad: {a: 1}}},
    {n: on, label: 'Repeat'},
    {n: 999, label: 'Not a candidate'},
    {n: 'one', label: 'Not a number'}
  ]}))
  assert.equal(fill.rows, 3); assert.match(fill.note, /intents=3/)
  const body = fill.bodies.get('intentRows2')
  assert.ok(body, 'the body is keyed by the panel\'s slot')
  assert.match(body, /label: "Torch \\"on\\"", target: "com\.ohos\.sceneboard\/entry\/EntryAbility\/OpenFlashlight", params: "", mode: "background", input: false/)
  assert.match(body, /label: "Torch off", target: "com\.ohos\.sceneboard\/entry\/EntryAbility\/CloseFlashlight", params: "", mode: "background"/)
  assert.doesNotMatch(body, /com\.evil|Repeat|Not a/)
  assert.match(body, /label: "Save note", target: "com\.huawei\.hmos\.notepad\/entry\/EntryAbility\/CreateNote", params: "content\\n\{input\}\\ntitle\\nFrom Vera", mode: "foreground", input: true/)
  assert.doesNotMatch(body, /secret|bad/)

  // the label falls back to the intent's own name; at most 10 rows are kept
  fill = await fillIntentRows(PROMPT, ['intent_panel'], asker({section1: Array.from({length: 3}, () => ({n: on}))
    .concat(Array.from({length: 20}, (_, i) => ({n: i + 1, label: 'Row ' + i})))}))
  assert.match(fill.bodies.get('intentRows1'), /label: "OpenFlashlight"/)
  assert.ok(fill.rows <= 10)

  // a catalogue intent keeps its example value when the model gives none
  const music = INTENT_CATALOG.find(s => s.name === 'playMusicList')
  await fillIntentRows('play some music for the morning', ['intent_panel'], asker({}))
  const m = new RegExp('^(\\d+)\\. ' + music.name + '\\b', 'm').exec(lastUser)
  assert.ok(m, 'catalogue rows are candidates too')
  fill = await fillIntentRows('play some music for the morning', ['intent_panel'], asker({section1: [{n: Number(m[1]), label: 'Music'}]}))
  assert.match(fill.bodies.get('intentRows1'), /target: "com\.huawei\.hmsapp\.music\/phone\/MainAbility\/PlayMusicList", params: "sceneType\\n[^"\\]+", mode: "background"/)

  // unusable answers: no rows, and the note says why
  for (const raw of [null, 'not json', '{"section1": "x"}', '{"section1": []}']) {
    fill = await fillIntentRows(PROMPT, ['intent_panel'], async () => raw)
    assert.equal(fill.bodies.size, 0); assert.equal(fill.rows, 0); assert.match(fill.note, /intents=none/)
  }
  // nothing on this phone matches: the model is not asked
  asked = false
  fill = await fillIntentRows('zzqx', ['intent_panel'], async () => { asked = true; return '' })
  assert.equal(asked, false); assert.match(fill.note, /intents=none\(no candidates\)/)

  console.log('intent-rows-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
