// Two things a program can do while it runs that it could not before: ask the model for words written from what the person entered
// (Vera.Ask.text, VeraAsk.ets), and show a notification (VeraNotifySdk.ets). No network: the model is not reached without a key.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const ask = loadVera('VeraAsk')
const {compileVeraSource} = loadVera('VeraCompiler')
const {sdkContract} = loadVera('VeraSdkContracts')
const {isSdkTargetImplemented} = loadVera('VeraSdkBackend')

// The compiler lets the app's own function through.
const program = target => `import * as ui from "std/ui"
import * as sdk from "std/sdk"
class AppState { text: string; }
function init(): AppState { return {text: ""}; }
function go(state: AppState, ignored: number): AppState { sdk.call("${target}", ["prompt", "two dinners from spinach and eggs", "maxWords", "60"], "onText"); return state; }
function onText(state: AppState, value: string): AppState { return {text: value}; }
function view(state: AppState): ui.View { return ui.Column("default", [ui.Button("primary", "Ideas", "go", 0, true), ui.Text("body", state.text)]); }
`
compileVeraSource(program(ask.ASK_TARGET))
assert.ok(isSdkTargetImplemented(ask.ASK_TARGET))

// No key, no call; an empty prompt is refused before anything else.
;(async () => {
  ask.resetAsk()
  assert.match(await ask.askText(new Map([['prompt', '']])), /^error: nothing was asked/)
  assert.match(await ask.askText(new Map([['prompt', 'two dinners']])), /^error/)
  // At most ASK_PER_MINUTE calls a minute go out.
  ask.resetAsk()
  const t = 1000000
  for (let i = 0; i < ask.ASK_PER_MINUTE; i++) assert.ok(ask.askAllowed(t + i))
  assert.ok(!ask.askAllowed(t + 100))
  assert.ok(ask.askAllowed(t + 61000))

  // The notification functions have contracts find_sdk_function shows, with a complete call to copy.
  for (const target of ['NotificationKit.notificationManager.publish',
    'NotificationKit.notificationManager.requestEnableNotification']) {
    const c = sdkContract(target)
    assert.ok(c !== undefined, target)
    assert.match(c.call, new RegExp('sdk\\.call\\("' + target.replace(/\./g, '\\.') + '"'))
    assert.ok(isSdkTargetImplemented(target), target)
  }
  // A reminder at a later time is not offered: this phone gives the app none (VeraNotifySdk.ets).
  assert.ok(!isSdkTargetImplemented('BackgroundTasksKit.reminderAgentManager.publishReminder'))
  console.log('ask-notify-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
