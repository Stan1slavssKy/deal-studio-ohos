// ui.DateField and ui.dateToString through the real compiler, VM and decoder: the field holds the day number
// time.daysSinceEpoch() returns, hands the handler a number, and the date reads the same in the field and in text.
// Also checks the catalogue offers it to the prompt and the renderer lists it. No network.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera, sourceRoot} = require('./source-loader')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi, formatVeraDate} = loadVera('VeraUi')
const {CORE_COMPONENTS, describeCatalogForPrompt} = loadVera('VeraUiCatalog')

// The epoch, a leap day, today's shape, and the end of a year.
assert.equal(formatVeraDate(0), '1 Jan 1970')
assert.equal(formatVeraDate(19782), '29 Feb 2024')
assert.equal(formatVeraDate(20756), '30 Oct 2026')
assert.equal(formatVeraDate(20818), '31 Dec 2026')
assert.equal(formatVeraDate(NaN), '1 Jan 1970')

const src = 'import * as ui from "std/ui"\nimport * as time from "std/time"\n' +
  '@jsonable\nclass AppState { due: number; }\n' +
  'function init(): AppState { return {due: time.daysSinceEpoch()}; }\n' +
  'function setDue(state: AppState, value: number): AppState { return {due: value}; }\n' +
  'function view(state: AppState): ui.View { return ui.AppTheme("clean", "", [ui.Section("content", "", "", [' +
  'ui.DateField("default", "Due", state.due, "setDue"), ' +
  'ui.Text("body", "Due " + ui.dateToString(state.due) + ", in " + ui.numberToString(state.due - time.daysSinceEpoch()) + " days")])]); }\n'
const result = compileVeraSource(src)
const vm = new VirtualMachine(deserializeVbc2(result.vbc2 !== undefined ? result.vbc2 : result), new UiHostEnvironment())
const find = (node, kind) => node.kind === kind ? node : (node.children || []).map(c => find(c, kind)).find(Boolean)

const now = new Date(), today = Math.floor((now.getTime() - now.getTimezoneOffset() * 60000) / 86400000)
let state = vm.execute('init')
let tree = decodeVeraUi(vm.execute('view', [state]))[0]
let field = find(tree, 'datefield')
assert.ok(field, 'the field is in the tree')
assert.equal(field.label, 'Due')
assert.equal(field.numberValue, today, 'it starts at today')
assert.equal(field.action, 'setDue')

state = vm.execute('setDue', [state, decodeRuntimeValue(['n', 20818])])
tree = decodeVeraUi(vm.execute('view', [state]))[0]
assert.equal(find(tree, 'datefield').numberValue, 20818)
assert.equal(find(tree, 'text').text, 'Due 31 Dec 2026, in ' + (20818 - today) + ' days')

// Wrong argument types are compile errors, as for every other component.
assert.throws(() => compileVeraSource(src.replace('state.due, "setDue"', '"tomorrow", "setDue"')), e => (e.diagnostics || []).length > 0)

assert.ok(CORE_COMPONENTS.includes('DateField'), 'always described, like TimeField')
const prompt = describeCatalogForPrompt()
assert.match(prompt, /ui\.DateField\(/)
assert.match(prompt, /ui\.dateToString\(day\)/)
const renderer = fs.readFileSync(path.join(sourceRoot, 'components/VeraPreview.ets'), 'utf8')
assert.ok(renderer.includes("'datefield'") && renderer.includes("node.kind === 'datefield'"), 'the renderer draws it')
assert.ok(renderer.includes('showDatePickerDialog({'), 'through the phone\'s own date dialog')
console.log('date-field-check: ok')
