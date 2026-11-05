// dose_schedule driven in the real VM with the clock held still: the doses the request names (times given as HH:MM), a Take on each
// that becomes Undo, "N of M taken today", late doses, a streak of days with every dose taken that grows day by day, breaks after a
// missed day and steps back on an undo; adding and removing a dose; the calendar calls and answers when the calendar is on. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {composeProgram} = loadVera('VeraSectionCompose')
const {expandListRows} = loadVera('VeraTemplateContent')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const num = v => decodeRuntimeValue(['n', v])
const str = v => decodeRuntimeValue(['s', v])

const RealDate = Date
let now = new RealDate(2026, 10, 3, 7, 0, 0)
global.Date = class extends RealDate { constructor(...a) { if (a.length === 0) { super(now.getTime()) } else { super(...a) } } }
const at = (h, m, dayShift = 0) => { now = new RealDate(2026, 10, 3 + dayShift, h, m, 0) }

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
const DOSES = [['Vitamin D', '08:00', 'with food'], ['Iron', '20:30', ''], ['Bad time', '99:99', '']]
function values(calendar, doses = DOSES) {
  const spec = fragments().find(f => f.kind === 'dose_schedule'), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.token === '__CALENDAR_IDX__' ? calendar : s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, c.fallback))
  spec.listFields.forEach(l => m.set(l.token, expandListRows(doses, l).text))
  return m
}
function build(calendar, doses) {
  const src = composeProgram(['dose_schedule'], globals, [values(calendar, doses)])
  const r = compileVeraSource(src)
  const env = new UiHostEnvironment()
  return {src, env, vm: new VirtualMachine(deserializeVbc2(r.vbc2 !== undefined ? r.vbc2 : r), env)}
}
const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)) }
const nodes = (h, st) => { const out = []; walk(decodeVeraUi(h.vm.execute('view', [st]))[0], n => out.push(n)); return out }
const text = (h, st) => nodes(h, st).flatMap(n => Object.values(n).filter(v => typeof v === 'string' && v !== '')).join('|')
function act(h, name, st, ...args) { h.env.effectsAllowed = true; h.env.pendingEffects = []; const next = h.vm.execute(name, [st, ...args]); h.env.effectsAllowed = false; return {st: next, effects: h.env.pendingEffects} }
const row = (h, st, name) => nodes(h, st).find(n => n.kind === 'listitem' && n.text === name)

const h = build('false')
at(7, 0)
let st = h.vm.execute('init')
let t = text(h, st)
assert.match(t, /0 of 3 taken today/); assert.match(t, /Vitamin D\|08:00 - with food/); assert.match(t, /Iron\|20:30/)
assert.match(t, /Bad time\|08:00/, 'a time that is not a time of day falls back to 08:00')
assert.match(t, /0 days\|Streak/)
// late: past its time and not taken
at(9, 0)
assert.equal(row(h, st, 'Vitamin D').style, 'warning'); assert.match(text(h, st), /Due 08:00 - late/)
assert.equal(row(h, st, 'Iron').style, 'default')
// take: "Taken 09:00", success, the button becomes Undo
st = act(h, 'takeDose1', st, num(0)).st
assert.equal(row(h, st, 'Vitamin D').style, 'success'); assert.equal(row(h, st, 'Vitamin D').value, 'Taken 09:00')
assert.match(text(h, st), /1 of 3 taken today/); assert.match(text(h, st), /Undo/)
// undo
st = act(h, 'takeDose1', st, num(0)).st
assert.match(text(h, st), /0 of 3 taken today/); assert.equal(row(h, st, 'Vitamin D').style, 'warning')
// remove the bad one, take both: the streak is one day
st = act(h, 'removeDose1', st, num(2)).st
assert.doesNotMatch(text(h, st), /Bad time/)
st = act(h, 'takeDose1', st, num(0)).st; at(21, 0); st = act(h, 'takeDose1', st, num(1)).st
assert.match(text(h, st), /2 of 2 taken today/); assert.match(text(h, st), /1 day\|Streak/)
assert.equal(nodes(h, st).find(n => n.kind === 'progress').style, 'success')
// undo the last of the day: the streak steps back; take it again: one day again
let undone = act(h, 'takeDose1', st, num(1)).st
assert.match(text(h, undone), /0 days\|Streak/)
assert.match(text(h, act(h, 'takeDose1', undone, num(1)).st), /1 day\|Streak/)
// the next day starts untaken; the streak of yesterday still shows, and grows when today is done
at(7, 0, 1)
assert.match(text(h, st), /0 of 2 taken today/); assert.match(text(h, st), /1 day\|Streak/)
st = act(h, 'takeDose1', st, num(0)).st; st = act(h, 'takeDose1', st, num(1)).st
assert.match(text(h, st), /2 days\|Streak/)
// a whole day missed: the streak is gone, and starts again at one
at(7, 0, 3)
assert.match(text(h, st), /0 days\|Streak/)
st = act(h, 'takeDose1', st, num(0)).st; st = act(h, 'takeDose1', st, num(1)).st
assert.match(text(h, st), /1 day\|Streak/)
// adding a dose: a name is needed; the time comes from the picker
assert.equal(text(h, act(h, 'addDose1', st, num(0)).st), text(h, st), 'no name adds nothing')
let s2 = act(h, 'setDoseName1', st, str('Omega 3')).st; s2 = act(h, 'setDoseTime1', s2, num(13 * 60 + 15)).st
s2 = act(h, 'addDose1', s2, num(0)).st
assert.match(text(h, s2), /Omega 3\|13:15/); assert.match(text(h, s2), /2 of 3 taken today/)

// no doses named: one plain line, no empty state
{
  const e = build('false', [])
  const s = e.vm.execute('init')
  assert.match(text(e, s), /No doses yet/); assert.ok(!nodes(e, s).some(n => n.kind === 'emptystate'))
}

// the calendar on: adding sends a daily event, the answer is shown on the row, a refusal is said; removing deletes the event
{
  at(7, 0)
  const c = build('true', [['Vitamin D', '08:00', '']])
  let s = c.vm.execute('init')
  let r = act(c, 'calendarDose1', s, num(0))
  assert.equal(r.effects.length, 1); assert.equal(r.effects[0].rawTarget, 'CalendarKit.Calendar.addEvent'); assert.equal(r.effects[0].resultHandler, 'onDoseAdded1')
  assert.deepEqual(Object.fromEntries(r.effects[0].values), {title: 'Take Vitamin D', hour: '8', minute: '0', durationMinutes: '15', remindBefore: '0',
    repeat: 'daily', description: 'Daily dose'})
  assert.match(text(c, r.st), /sending to calendar/)
  assert.equal(act(c, 'calendarDose1', r.st, num(0)).effects.length, 0, 'one call at a time')
  s = act(c, 'onDoseAdded1', r.st, str('777')).st
  assert.match(text(c, s), /in calendar/)
  assert.equal(act(c, 'calendarDose1', s, num(0)).effects.length, 0, 'already in the calendar')
  // a new dose goes to the calendar as it is added; a refusal is shown
  let s3 = act(c, 'setDoseName1', s, str('Iron')).st
  r = act(c, 'addDose1', s3, num(0)); assert.equal(r.effects.length, 1); assert.equal(r.effects[0].values.get('hour'), '8')
  s3 = act(c, 'onDoseAdded1', r.st, str('declined code=201')).st
  assert.match(text(c, s3), /Iron\|08:00 - not in calendar/); assert.match(text(c, s3), /The calendar said no\|declined code=201/)
  // removing the one in the calendar deletes its event
  r = act(c, 'removeDose1', s3, num(0))
  assert.equal(r.effects[0].rawTarget, 'CalendarKit.Calendar.deleteEvents'); assert.deepEqual(Object.fromEntries(r.effects[0].values), {ids: '777'})
}
// the calendar off: no calendar button, no call
{
  const o = build('false', [['A', '08:00', '']])
  const s = o.vm.execute('init')
  assert.ok(!nodes(o, s).some(n => n.kind === 'iconbutton' && n.icon === 'calendar'))
  let s4 = act(o, 'setDoseName1', s, str('B')).st
  assert.equal(act(o, 'addDose1', s4, num(0)).effects.length, 0)
}
assert.deepEqual(fragments().find(f => f.kind === 'dose_schedule').ports.map(p => p.name), ['taken_today', 'doses', 'streak'])
compileVeraSource(composeProgram(['dose_schedule', 'dose_schedule'], globals, [values('true'), values('false')]))
global.Date = RealDate
console.log('dose-schedule-check: ok')
