// carryState (VeraStateCarry.ets): a refined program starts from its own init() with what the old program's state held
// carried in, field by field. Same name and same kind keeps the old value; a new field starts at init; a field whose kind
// changed starts fresh; entries are kept whole.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {carryState} = loadVera('VeraStateCarry')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue, encodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment} = loadVera('VeraUi')

const program = (stateFields, init, extra = '') => `import * as ui from "std/ui"

@jsonable
class Entry {
  amount: number;
}

@jsonable
class AppState {
${stateFields}
}

function init(): AppState {
  let none: Entry[] = [];
  return ${init};
}

function add(state: AppState, value: number): AppState {
  let out: Entry[] = [];
  for (let e: Entry of state.entries) { out.push(e); }
  let next: Entry = {amount: value};
  out.push(next);
  return {__ALL__};
}
${extra}
function view(state: AppState): ui.View {
  return ui.Column("default", [ui.Text("body", "n=" + ui.numberToString(state.entries.length()))]);
}
`
const vm = source => new VirtualMachine(deserializeVbc2(compileVeraSource(source).vbc2), new UiHostEnvironment())
const plain = value => encodeRuntimeValue(value)

// The old program: a goal typed as text, two entries, a note.
const oldSource = program('  goalText: string;\n  entries: Entry[];\n  note: string;', '{goalText: "8", entries: none, note: ""}')
  .replace('{__ALL__}', '{goalText: state.goalText, entries: out, note: state.note}')
const old = vm(oldSource)
let state = old.execute('init')
state = old.execute('add', [state, decodeRuntimeValue(['n', 1])])
state = old.execute('add', [state, decodeRuntimeValue(['n', 2])])
const typed = JSON.parse(JSON.stringify(plain(state)).replace('"8"', '"10"'))

// The refined program: the goal is still a string, the note became a number, and a glass size was added.
const newSource = program('  goalText: string;\n  entries: Entry[];\n  note: number;\n  glassSize: number;',
  '{goalText: "8", entries: none, note: 0, glassSize: 250}')
  .replace('{__ALL__}', '{goalText: state.goalText, entries: out, note: state.note, glassSize: state.glassSize}')
const refined = vm(newSource)
const carried = carryState(refined.execute('init'), decodeRuntimeValue(typed))
const fields = carried.fields
assert.equal(fields.get('goalText').value, '10', 'what was typed is kept')
assert.equal(fields.get('entries').elements.length, 2, 'the entries are kept')
assert.equal(fields.get('note').value, 0, 'a field whose kind changed starts fresh')
assert.equal(fields.get('glassSize').value, 250, 'a new field starts at init')
assert.deepEqual([...fields.keys()], ['goalText', 'entries', 'note', 'glassSize'], 'the new program\'s fields, in its order')
// The new program runs on it.
const after = refined.execute('add', [carried, decodeRuntimeValue(['n', 3])])
assert.equal(after.fields.get('entries').elements.length, 3)
refined.execute('view', [after])

// Nothing to carry from: an empty old list leaves the fresh one.
const empty = carryState(refined.execute('init'), old.execute('init'))
assert.equal(empty.fields.get('entries').elements.length, 0)

console.log('state-carry-check: ok')
