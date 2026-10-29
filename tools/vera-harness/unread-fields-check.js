// A field of the app's state that no code reads is something a person can set that changes nothing they can see. The compiler lists
// those (CompileResult.unreadFields); handing a field on under its own name ({a: state.a}) is not a read. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {compileVeraSource} = loadVera('VeraCompiler')
const {fragments} = loadVera('VeraTemplates')
const {composeProgram} = loadVera('VeraSectionCompose')
const {expandListRows} = loadVera('VeraTemplateContent')

const head = 'import * as ui from "std/ui"\n@jsonable\nclass AppState { shown: number; hidden: number; }\nfunction init(): AppState { return {shown: 1, hidden: 2}; }\n'
const set = 'function set_hidden(state: AppState, v: number): AppState { return {shown: state.shown, hidden: v}; }\n'
const view = body => 'function view(state: AppState): ui.View { ' + body + ' }\n'
const input = 'ui.NumberField("default", "n", state.shown, 0, 9, "set_hidden")'
const screen = (inner, pre = '') => pre + 'return ui.AppTheme("clean", "", [ui.Section("content", "", "", [' + inner + '])]);'

// An input writes `hidden` and nothing reads it.
assert.deepEqual(compileVeraSource(head + set + view(screen(input))).unreadFields, ['hidden'])
// Read in view(): not listed.
assert.deepEqual(compileVeraSource(head + set + view(screen(input + ', ui.Text("body", "n is " + ui.numberToString(state.hidden))'))).unreadFields, [])
// Read in a condition, in a formula, in another handler, in a helper called from view().
assert.deepEqual(compileVeraSource(head + set + view(screen(input + ', ui.When(state.hidden > 3, ui.Text("body", "big"))'))).unreadFields, [])
assert.deepEqual(compileVeraSource(head + set + 'function twice(state: AppState): number { return state.hidden * 2; }\n' +
  view(screen(input + ', ui.Text("body", ui.numberToString(twice(state)))'))).unreadFields, [])
assert.deepEqual(compileVeraSource(head + set + 'function bump(state: AppState, v: number): AppState { return {shown: state.hidden + v, hidden: state.hidden}; }\n' +
  view(screen(input + ', ui.Button("primary", "go", "bump", 0, true)'))).unreadFields, [])
// Only handing the field on under its own name is not a read: a program whose handlers all just pass `hidden` along has it unread.
assert.deepEqual(compileVeraSource(head + 'function nudge(state: AppState, v: number): AppState { return {shown: v, hidden: state.hidden}; }\n' +
  view(screen('ui.NumberField("default", "n", state.shown, 0, 9, "nudge")'))).unreadFields, ['hidden'])
// An entry built from a draft field of the same name reads it: only a new state hands fields on.
{
  const draft = 'import * as ui from "std/ui"\n@jsonable\nclass Item { title: string; done: boolean; }\n' +
    '@jsonable\nclass AppState { title: string; items: Item[]; }\n' +
    'function init(): AppState { let none: Item[] = []; return {title: "", items: none}; }\n' +
    'function set_title(state: AppState, v: string): AppState { return {title: v, items: state.items}; }\n' +
    'function add(state: AppState, v: number): AppState { let item: Item = {title: state.title, done: false}; let out: Item[] = []; ' +
    'for (let e: Item of state.items) { out.push(e); } out.push(item); return {title: "", items: out}; }\n'
  assert.deepEqual(compileVeraSource(draft + view(screen('ui.TextField("default", "t", "", "set_title"), ' +
    'ui.Button("primary", "Add", "add", 0, true), ui.Text("body", ui.numberToString(state.items.length()))'))).unreadFields, [])
}
// Handed on under another name, it is read.
assert.deepEqual(compileVeraSource(head + 'function swap(state: AppState, v: number): AppState { return {shown: state.hidden, hidden: v}; }\n' +
  view(screen('ui.NumberField("default", "n", state.shown, 0, 9, "swap")'))).unreadFields, [])

// Every block of the catalogue, alone: none keeps a field nothing reads.
const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'T']])
const values = kind => {
  const spec = fragments().find(f => f.kind === kind), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0])); spec.contentFields.forEach(c => m.set(c.token, c.fallback))
  spec.listFields.forEach(l => m.set(l.token, expandListRows(undefined, l).text))
  return m
}
for (const f of fragments()) {
  assert.deepEqual(compileVeraSource(composeProgram([f.kind], globals, [values(f.kind)])).unreadFields, [], f.kind + ' keeps a field nothing reads')
}
console.log('unread-fields-check: ok (' + fragments().length + ' blocks)')
