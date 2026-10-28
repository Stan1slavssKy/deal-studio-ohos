// An action a component names has to be a handler it can call: it exists and takes (state, value). A component that is tapped hands a
// number, so a Button, a row, an icon button, a banner or a snackbar that names a function that is missing or takes something else
// is a compile error (E2106), not a control that does nothing when it is tapped. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {compileVeraSource} = loadVera('VeraCompiler')

const head = 'import * as ui from "std/ui"\n@jsonable\nclass AppState { n: number; }\nfunction init(): AppState { return {n: 0}; }\n'
const view = call => 'function view(state: AppState): ui.View { return ui.AppTheme("clean", "", [' + call + ']); }\n'
const handlers = {
  right: 'function go(state: AppState, v: number): AppState { return {n: v}; }\n',
  stateOnly: 'function go(state: AppState): AppState { return {n: 1}; }\n',
  wrongValue: 'function go(state: AppState, v: string): AppState { return {n: 1}; }\n',
  missing: '',
}
// Every component that is tapped, with an action that names `go`.
const tapped = {
  Button: 'ui.Button("primary", "Go", "go", 0, true)',
  Cell: 'ui.Cell("default", "x", "go", 0, true)',
  ListItem: 'ui.ListItem("default", "t", "", "", "go", 0, true, "pin")',
  NumberListItem: 'ui.NumberListItem("default", "t", "", 1, "", "", 0, "go", 0, true, "pin")',
  TimelineItem: 'ui.TimelineItem("default", "t", "", "", "go", 0, true, "pin")',
  IconButton: 'ui.IconButton("default", "pin", "go", "go", 0, true)',
  InsetBanner: 'ui.InsetBanner("default", "t", "m", "Go", "go", "info")',
  EmptyState: 'ui.EmptyState("default", "t", "m", "Go", "go", "pin")',
  Snackbar: 'ui.Snackbar("default", "m", "Go", "go")',
}
const compiles = src => { try { compileVeraSource(src); return true } catch (e) { assert.ok((e.diagnostics || []).some(d => d.code === 'E2106' || /E2106/.test(String(d.code || d))), 'only E2106 is expected: ' + JSON.stringify(e.diagnostics)); return false } }
for (const [name, call] of Object.entries(tapped)) {
  assert.ok(compiles(head + handlers.right + view(call)), name + ' with a handler of (state, value: number) compiles')
  for (const bad of ['stateOnly', 'wrongValue', 'missing']) assert.ok(!compiles(head + handlers[bad] + view(call)), name + ' with a ' + bad + ' handler is refused')
}
// Nothing to tap: a banner or an empty state with no action compiles with no handler at all.
assert.ok(compiles(head + view('ui.InsetBanner("default", "t", "m", "", "", "info")')), 'a banner with no action')
assert.ok(compiles(head + view('ui.EmptyState("default", "t", "m", "", "", "pin")')), 'an empty state with no action')
console.log('handler-signature-check: ok (' + Object.keys(tapped).length + ' tapped components)')
