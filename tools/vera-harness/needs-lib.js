// A recorded sketch (compose/<label>/sketch.json) as the needs plan the model would write for it (NeedsPlan.ets): the same facts,
// each under a type, the composer's quantities under their neutral names.
'use strict'
// The quantities under their neutral names, as the needs prompt asks the model to write them.
const NEUTRAL = [['remaining', 'clock.remaining'], ['elapsed', 'clock.elapsed'], ['duration', 'clock.duration'],
  ['entryCount', 'entries.count'], ['entryTotal', 'entries.total']]
const neutral = s => NEUTRAL.reduce((t, [from, to]) => t.replace(new RegExp('\\b' + from + '\\b', 'g'), to), s)

// A recorded sketch as a needs plan: the same facts, each under a type.
function needsOf(old) {
  const out = {title: old.title, eyebrow: old.eyebrow, subtitle: old.subtitle, inputs: old.inputs || [], constants: old.constants || [],
    questions: old.questions || [], needs: []}
  for (const v of old.values || []) {
    const n = {type: 'figure', ...v, formula: neutral(v.formula || '')}
    if (v.example && v.example.given) n.example = {...v.example, given: Object.fromEntries(Object.entries(v.example.given).map(([k, x]) => [neutral(k), x]))}
    out.needs.push(n)
  }
  if (old.countdown) out.needs.push({type: 'countdown', ...old.countdown})
  if (old.stopwatch) out.needs.push({type: 'stopwatch', ...old.stopwatch})
  if (old.list) out.needs.push({type: 'entries', ...old.list})
  for (const r of old.ready || []) { const what = typeof r === 'string' ? r : Object.values(r).join('. '); out.needs.push({type: 'content', what, from: what}) }
  for (const e of old.events || []) out.needs.push({type: 'action', ...e, from: e.when + ' ' + e.what, on: /\bends?\b|zero/.test(e.when) ? 'countdown_end' : /added/.test(e.when) ? 'entry_added' : /\btap/.test(e.when) ? 'row_tap' : 'other'})
  for (const o of old.other || []) out.needs.push({type: 'other', what: o})
  return out
}


module.exports = {needsOf, neutral}
