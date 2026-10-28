// LastRun.ets: the record of the last run that the Metrics tab shows after a restart: what is kept, what is read back, what is
// said about it, and that a damaged or foreign record is no record.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const last = loadVera('LastRun')

const run = Object.assign(new last.LastRun(), {at: Date.UTC(2026, 9, 23, 18, 35), prompt: 'I want app that will help me to remember good places', via: 'agent',
  ms: 12200, waitedMs: 6600, sketchMs: 4300, jevMs: 300, searchMs: -1, contentMs: 1750, holesMs: 0, checkMs: 40, attempts: 1,
  kinds: ['itinerary'], note: 'composed: 0 inputs, 1 values, list'})

// Kept and read back as it was.
const back = last.lastRunFromJson(last.lastRunToJson(run))
assert.notEqual(back, null)
for (const k of Object.keys(run)) assert.deepEqual(back[k], run[k], k)

// Said: the app's time and the person's apart, and only the stages that ran.
const lines = last.describeLastRun(run)
assert.match(lines[0], /^Last run, before this session \(2026-10-23 18:35 UTC\)$/)
assert.equal(lines[1], run.prompt)
assert.equal(lines[2], 'agent in 5.6 s, and 6.6 s waiting for the person')
assert.equal(lines[3], 'plan 4.3 s · Jev 300 ms · text 1.8 s · check 40 ms', 'no search, no holes')
assert.ok(lines.includes('sections: itinerary') && lines.includes('1 attempt(s)'))
const plain = last.describeLastRun(Object.assign(new last.LastRun(), run, {waitedMs: 0, kinds: [], attempts: 0, note: '', prompt: 'x'.repeat(200)}))
assert.equal(plain[1].length, 93); assert.equal(plain[2], 'agent in 12.2 s')
assert.ok(plain.every(l => !/sections:|attempt/.test(l)))

// Damaged, empty, from another version, or with no way noted: nothing.
for (const bad of ['', 'not json', '{}', '{"v":2,"via":"agent"}', '{"v":1}', '[]', 'null'])
  assert.equal(last.lastRunFromJson(bad), null, JSON.stringify(bad))
// Missing or wrong-typed fields are the defaults.
const odd = last.lastRunFromJson('{"v":1,"via":"model","ms":"slow","kinds":["a",3,"b"],"searchMs":null}')
assert.equal(odd.ms, 0); assert.deepEqual(odd.kinds, ['a', 'b']); assert.equal(odd.searchMs, -1)

// Before the app has a folder, nothing is written and nothing is read, and neither fails.
assert.doesNotThrow(() => last.saveLastRun(run))
assert.equal(last.loadLastRun(), null)
// The page reads it only once the settings have the app's folder: read before, it finds none (on the phone it did, and the Metrics
// tab said "No run yet" over a record that was there). The order in aboutToAppear is what this holds.
{
  const src = require('node:fs').readFileSync(require('node:path').join(__dirname, '../../entry/src/main/ets/pages/GeneratePage.ets'), 'utf8')
  const body = src.slice(src.indexOf('aboutToAppear(): void {'), src.indexOf('onPageShow(): void {'))
  assert.ok(body.includes('loadLastRun()') && body.includes('settings.init('))
  assert.ok(body.indexOf('settings.init(') < body.indexOf('loadLastRun()'), 'the record is read after the settings are initialised')
}
console.log('last-run-check: ok')
