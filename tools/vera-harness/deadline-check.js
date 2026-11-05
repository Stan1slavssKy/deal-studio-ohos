// A time of day that ends the plan's list of stops (a flight to catch): the itinerary shows only the stops that fit before it, and the
// counts follow. Through runAgent and the program's own VM, with the plan and Jev's answers given. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {AgentHost, defaultBlockFill} = loadVera('agent/AgentHost')
const {AgentRequest, runAgent} = loadVera('agent/VeraAgent')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const nc = loadVera('NeedsChoose')
const align = loadVera('agent/AgentAlign')

const says = (choice, confidence = 0.95) => ({type: 'choice', choice, confidence})
const REQUEST = 'stops to see in the city'

// A plan whose figure "Leave at" is the start plus the minutes available: 09:00 + span.
const plan = span => ({title: 'City day', eyebrow: 'DAY', subtitle: 'What fits before you leave',
  inputs: [{id: 'beginAt', label: 'Start', kind: 'time', measure: 'minutes', value: 540},
           {id: 'span', label: 'Minutes available', kind: 'amount', measure: 'minutes', min: 0, max: 900, value: span}],
  needs: [{type: 'figure', id: 'leaveAt', label: 'Leave at', means: 'the time of day by which the stops must be over', format: 'time_of_day',
           formula: 'beginAt + span', example: {given: {beginAt: 540, span}, result: 540 + span}},
          {type: 'content', what: 'a list of stops to see in the city', from: REQUEST}]})

async function build(span, answers) {
  const h = new AgentHost()
  h.askPlan = async (system, user, onText) => { const t = JSON.stringify(plan(span)); onText(t); return t }
  h.askJev = async body => JSON.stringify({answers})
  h.fillBlocks = async request => defaultBlockFill(request)
  const r = await runAgent(Object.assign(new AgentRequest(), {prompt: REQUEST}), h)
  return r
}
const base = {'ready.0': says('itinerary'), 'whose.0': says('written'), real_data: says('false'), 'show.leaveAt': says('stat'),
  'written.leaveAt': says('right', 0.9), 'asked.value.leaveAt': says('asked')}

function screen(source) {
  const compiled = compileVeraSource(source)
  const vm = new VirtualMachine(deserializeVbc2(compiled.vbc2), new UiHostEnvironment())
  const texts = []
  const walk = n => { for (const k of Object.keys(n)) { const v = n[k]; if (typeof v === 'string' && v.length) texts.push(v); else if (Array.isArray(v)) v.forEach(c => c && typeof c === 'object' && walk(c)); else if (v && typeof v === 'object') walk(v) } }
  decodeVeraUi(vm.execute('view', [vm.execute('init')])).forEach(walk)
  return texts
}

;(async () => {
align.setAlignEnabled(false)
  // The default stops are five of an hour each, the first at 09:00 with 15 minutes between: they end at 10:00, 11:15, 12:30, 13:45, 15:00.
  for (const [span, shown, label] of [[800, 5, 'a day'], [270, 3, '09:00 + 270 min = 13:30'], [150, 2, '09:00 + 150 min = 11:30'], [30, 0, 'nothing fits']]) {
    const r = await build(span, Object.assign({'deadline.leaveAt': says('yes')}, base))
    assert.equal(r.errors, '', label + ': ' + r.note)
    assert.ok(r.source.length > 0, label + ' (no program): ' + r.note + ' // ' + r.errors)
    const texts = screen(r.source)
    const stops = texts.filter(t => /^Stop \d$/.test(t))
    assert.equal(stops.length, shown, label + ': ' + stops.join(', '))
    assert.equal(texts.some(t => /would run past/.test(t)), shown < 5, label + ' banner')
    assert.equal(texts.some(t => /Nothing fits before/.test(t)), shown === 0, label + ' empty')
  }
  // Jev unsure (below the bar, 0.4): nothing is hidden.
  {
    const r = await build(30, Object.assign({'deadline.leaveAt': says('yes', 0.3)}, base))
    assert.equal(screen(r.source).filter(t => /^Stop \d$/.test(t)).length, 5)
  }
  // Without Jev naming the figure, nothing is hidden: the section stands alone as before.
  {
    const r = await build(30, Object.assign({'deadline.leaveAt': says('no')}, base))
    const texts = screen(r.source)
    assert.equal(texts.filter(t => /^Stop \d$/.test(t)).length, 5)
    assert.ok(!texts.some(t => /would run past|Nothing fits/.test(t)))
  }
  // The itinerary still stands alone: it takes no value it needs from another block.
  {
    const {fragments} = loadVera('VeraTemplates')
    const itinerary = fragments().find(f => f.kind === 'itinerary')
    const reads = itinerary.ports.filter(p => p.dir === 'reads')
    // Both optional: the time the stops must be over by, and the start the screen's own form sets (VeraCompose.ets's dayStart).
    assert.deepEqual(reads.map(p => [p.name, p.optional]), [['deadline', true], ['start', true]])
    assert.ok(align.alignKinds().includes('itinerary'))
  }
  // The one time input is the flight, after the deadline worked out from it: it is not the day's start (review of #46). The
  // itinerary keeps its own start (09:00) and its Day starts field; the stops before 19:00 all fit. (The first plan above, whose
  // start the deadline is worked out from and which comes before it, still starts the day: its stops end at 10:00, 11:15...)
  {
    const flight = {title: 'Layover', eyebrow: 'DAY', subtitle: 'What fits before the flight',
      inputs: [{id: 'flightAt', label: 'Flight departs', kind: 'time', measure: 'minutes', min: 0, max: 1439, value: 1260}],
      needs: [{type: 'figure', id: 'backBy', label: 'Back at the airport by', means: 'the time of day by which the stops must be over',
               format: 'time_of_day', formula: 'flightAt - 120', example: {given: {flightAt: 1260}, result: 1140}},
              {type: 'content', what: 'a list of stops to see in the city', from: REQUEST}]}
    const h = new AgentHost()
    h.askPlan = async (system, user, onText) => { const t = JSON.stringify(flight); onText(t); return t }
    h.askJev = async body => JSON.stringify({answers: {'ready.0': says('itinerary'), 'whose.0': says('written'), real_data: says('false'),
      'show.backBy': says('stat'), 'written.backBy': says('right', 0.9), 'asked.value.backBy': says('asked'), 'deadline.backBy': says('yes')}})
    h.fillBlocks = async request => defaultBlockFill(request)
    const r = await runAgent(Object.assign(new AgentRequest(), {prompt: REQUEST}), h)
    assert.equal(r.errors, '', r.note)
    const texts = screen(r.source)
    assert.equal(texts.filter(t => /^Stop \d$/.test(t)).length, 5, texts.join(' | '))
    assert.ok(texts.includes('Day starts'), 'the itinerary keeps its own start field')
    assert.ok(!texts.some(t => /Nothing fits/.test(t)))
  }
  // A landing time the deadline is worked out from, and before it (08:00, leave by 17:00): it is the day's start, the stops begin at
  // 08:00 and the itinerary draws no second start field (Istanbul layover).
  {
    const landing = {title: 'Layover', eyebrow: 'DAY', subtitle: 'What fits before the flight',
      inputs: [{id: 'landAt', label: 'Landing time', kind: 'time', measure: 'minutes', min: 0, max: 1439, value: 480}],
      needs: [{type: 'figure', id: 'leaveAt', label: 'Leave for airport', means: 'the time of day by which the stops must be over',
               format: 'time_of_day', formula: 'landAt + 540', example: {given: {landAt: 480}, result: 1020}},
              {type: 'content', what: 'a list of stops to see in the city', from: REQUEST}]}
    const h = new AgentHost()
    h.askPlan = async (system, user, onText) => { const t = JSON.stringify(landing); onText(t); return t }
    h.askJev = async body => JSON.stringify({answers: {'ready.0': says('itinerary'), 'whose.0': says('written'), real_data: says('false'),
      'show.leaveAt': says('stat'), 'written.leaveAt': says('right', 0.9), 'asked.value.leaveAt': says('asked'), 'deadline.leaveAt': says('yes')}})
    h.fillBlocks = async request => defaultBlockFill(request)
    const r = await runAgent(Object.assign(new AgentRequest(), {prompt: REQUEST}), h)
    const texts = screen(r.source)
    assert.ok(!texts.includes('Day starts'), 'one start time: ' + texts.join(' | '))
    assert.ok(texts.some(t => /^08:00 - /.test(t)), 'the first stop at landing')
  }
align.setAlignEnabled(true)
  console.log('deadline-check ok')
})().catch(e => { console.error(e); process.exit(1) })
