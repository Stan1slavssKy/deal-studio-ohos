// The live_figure section (VeraTemplates.ets, LiveBlock.ets): the plan's live figures, Jev's yes or no for each, the source
// found while the screen is built (mocked), the call the host writes, and a formula of the plan reading the figure through its
// port. Runs the agent with a mocked plan, Jev and network, and the program in the VM. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {AgentHost} = loadVera('agent/AgentHost')
const {AgentRequest, runAgent} = loadVera('agent/VeraAgent')
const c = loadVera('VeraCompose')
const np = loadVera('NeedsPlan')
const fill = loadVera('SectionFill')
const live = loadVera('LiveBlock')
const {SourceSpec} = loadVera('VeraSource')
const {SourceFound, searchSpec, sourceShownError, sourceHandlerOf} = loadVera('VeraSourceFind')
const sc = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, VeraStringValue, VeraNumberValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const {LIVE_KIND} = loadVera('VeraTemplates')

// A source as the finder would have taken it: CoinGecko's simple price, one path, no time of its own.
function coinSpec() {
  const s = new SourceSpec()
  s.url = 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd'
  s.labels = ['Bitcoin']; s.paths = ['bitcoin.usd']; s.units = ['USD']; s.values = ['75939.82']
  s.asof = ''; s.asofValue = ''
  s.sample = 'ok\n75939.82\n\n\nsource\tapi.coingecko.com\t' + s.url + '\nasof\t12:00:00'
  return s
}
const found = spec => Object.assign(new SourceFound(), {spec, tried: spec ? [] : ['https://x.example: not JSON']})

// Everything a screen shows, as text.
function screenOf(vm, state) {
  const out = []
  const walk = n => { for (const k of Object.keys(n)) if (typeof n[k] === 'string' && n[k] && k !== 'kind' && k !== 'style' && k !== 'action') out.push(n[k]); if (n.kind === 'numberstat' || n.kind === 'numbertext') out.push(String(n.numberValue)); (n.children || []).forEach(walk) }
  decodeVeraUi(vm.execute('view', [state])).forEach(walk)
  return out.join('\n')
}
// The kinds of node a screen draws, for what is drawn rather than what it says.
function kindsOf(vm, state) {
  const out = []
  const walk = n => { out.push(n.kind); (n.children || []).forEach(walk) }
  decodeVeraUi(vm.execute('view', [state])).forEach(walk)
  return out
}
// Taps the info button: where the figures are from, and when, is shown or hidden.
function toggleSource(run) { run.state = run.vm.execute('liveToggleSource', [run.state, new VeraNumberValue(0)]) }
function start(vbc2) {
  const host = new UiHostEnvironment()
  const vm = new VirtualMachine(deserializeVbc2(vbc2), host)
  return {host, vm, state: vm.execute('init')}
}
function answer(run, handler, text) {
  run.host.effectsAllowed = true
  run.state = run.vm.execute(handler, [run.state, new VeraStringValue(text)])
  run.host.effectsAllowed = false
}

const btc = Object.assign(new c.SketchLive(), {id: 'btcPrice', label: 'Bitcoin price', means: 'the price of one bitcoin now', unit: 'USD', measure: 'money', query: 'Bitcoin price USD'})

// ---- The block alone: the host's values, the call it writes, the screen ----
async function blockAlone() {
  const v = live.liveValues(coinSpec(), [btc])
  assert.equal(v.get('__LIVE_TARGET__'), 'Vera.Source.fetch')
  assert.equal(v.get('__LIVE_ARGS__'), '["url", "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd", "paths", "bitcoin.usd"]')
  assert.equal(v.get('__LIVE_EVERY__'), '60')
  const src = sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'Bitcoin'], ['__THEME__', 'clean']]), [v])
  const {vbc2} = compileVeraSource(src)
  assert.equal(sourceHandlerOf(src), 'liveAnswer')
  // Handed an answer of its source's shape with another figure, it shows that figure; the source's domain once the info button is
  // tapped (sourceShownError reads the screen without tapping, so it finds the figure and misses only the hidden source).
  assert.match(sourceShownError(src, vbc2, coinSpec()), /without the source api\.coingecko\.com\./)
  assert.doesNotMatch(sourceShownError(src, vbc2, coinSpec()), /without the figure/)
  const run = start(vbc2)
  // Before the first answer: a placeholder box, no dashes, no tiles.
  assert.ok(kindsOf(run.vm, run.state).includes('skeleton'))
  assert.ok(!kindsOf(run.vm, run.state).includes('tilegrid'))
  // The first tick fetches at once (no call made yet); the next not before a minute has passed.
  const tick = () => { run.host.effectsAllowed = true; run.host.pendingEffects = []; run.state = run.vm.execute('liveTick', [run.state, new VeraNumberValue(1000)]); run.host.effectsAllowed = false; return run.host.pendingEffects }
  const first = tick()
  assert.equal(first.length, 1, 'the first tick fetches')
  assert.match(JSON.stringify(first[0]), /Vera\.Source\.fetch/)
  assert.equal(tick().length, 0, 'the second tick does not')
  // While that request is out, Refresh says so and is off, and a tap makes no second request.
  const refresh = () => { run.host.effectsAllowed = true; run.host.pendingEffects = []; run.state = run.vm.execute('liveRefresh', [run.state, new VeraNumberValue(0)]); run.host.effectsAllowed = false; return run.host.pendingEffects }
  const button = () => { let b = null; const walk = n => { if (n.kind === 'button' && n.action === 'liveRefresh') b = n; (n.children || []).forEach(walk) }; decodeVeraUi(run.vm.execute('view', [run.state])).forEach(walk); return b }
  assert.match(screenOf(run.vm, run.state), /Updating\.\.\./)
  assert.equal(button().enabled, false)
  assert.equal(refresh().length, 0)
  // The answer: the button is back, and the screen says when it checked.
  answer(run, 'liveAnswer', 'ok\n76000\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:05:09')
  assert.equal(button().enabled, true)
  assert.match(screenOf(run.vm, run.state), /\nUpdated \d\d:\d\d\n/)
  // A tap now asks at once (no silent ten-second wait); an answer that moves nothing says so.
  assert.equal(refresh().length, 1)
  answer(run, 'liveAnswer', 'ok\n76000\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:05:09')
  assert.match(screenOf(run.vm, run.state), /\nUpdated \d\d:\d\d · no change\n/)
  assert.equal(refresh().length, 1)
  answer(run, 'liveAnswer', 'ok\n76100\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:06:09')
  assert.match(screenOf(run.vm, run.state), /\nUpdated \d\d:\d\d\n/)
  // A failure turns the button back on too.
  assert.equal(refresh().length, 1)
  answer(run, 'liveAnswer', 'error: HTTP 502')
  assert.equal(button().enabled, true)
}

async function blockScreen() {
  const v = live.liveValues(coinSpec(), [btc])
  const src = sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'Bitcoin'], ['__THEME__', 'clean']]), [v])
  const run = start(compileVeraSource(src).vbc2)
  answer(run, 'liveAnswer', 'ok\n76123.5\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:05:09')
  let screen = screenOf(run.vm, run.state)
  assert.match(screen, /76,123\.5 USD/)
  assert.ok(kindsOf(run.vm, run.state).includes('tilegrid') && !kindsOf(run.vm, run.state).includes('skeleton'))
  // Where it is from is behind the info button.
  assert.doesNotMatch(screen, /api\.coingecko\.com/)
  toggleSource(run)
  assert.match(screenOf(run.vm, run.state), /\napi\.coingecko\.com · 14:05:09\n/)
  toggleSource(run)
  assert.doesNotMatch(screenOf(run.vm, run.state), /api\.coingecko\.com/)
  // How the first figure moved since the last answer, under it.
  answer(run, 'liveAnswer', 'ok\n76500\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:06:09')
  assert.match(screenOf(run.vm, run.state), /\u25b2 \+376\.5 \(0\.49%\) since 14:05:09/)
  answer(run, 'liveAnswer', 'ok\n76000\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:07:09')
  assert.match(screenOf(run.vm, run.state), /\u25bc -500 \(-0\.65%\) since 14:06:09/)
  // A rate moves in its fifth place: the change is told in as many places as the figure has, and a tiny share as "<0.01%".
  {
    const rate = Object.assign(new c.SketchLive(), {label: 'EUR to USD rate', unit: 'USD'})
    const rrun = start(compileVeraSource(sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'R'], ['__THEME__', 'clean']]), [live.liveValues(coinSpec(), [rate])])).vbc2)
    answer(rrun, 'liveAnswer', 'ok\n1.11743\n\n\nsource\tapi.exchangerate.dev\thttps://x.dev\nasof\t12:02')
    answer(rrun, 'liveAnswer', 'ok\n1.11747\n\n\nsource\tapi.exchangerate.dev\thttps://x.dev\nasof\t12:03')
    assert.match(screenOf(rrun.vm, rrun.state), /\u25b2 \+0\.00004 \(<0\.01%\) since 12:02/)
    // A tiny fall is told as one, not as a share above nothing.
    answer(rrun, 'liveAnswer', 'ok\n1.11746\n\n\nsource\tapi.exchangerate.dev\thttps://x.dev\nasof\t12:04')
    assert.match(screenOf(rrun.vm, rrun.state), /\u25bc -0\.00001 \(-<0\.01%\) since 12:03/)
  }
  // A page that writes a decimal comma: "92,35" is 92.35, not 9235; "1.234,56" is 1234.56; "1,234" groups thousands.
  {
    const rub = Object.assign(new c.SketchLive(), {label: 'USD to RUB', unit: 'RUB'})
    const crun = start(compileVeraSource(sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'R'], ['__THEME__', 'clean']]), [live.liveValues(coinSpec(), [rub])])).vbc2)
    const num = text => crun.vm.execute('liveNumber', [new VeraStringValue(text)]).value
    assert.equal(num('92,35 \u20bd'), 92.35)
    assert.equal(num('1.234,56'), 1234.56)
    assert.equal(num('1,234.5'), 1234.5)
    assert.equal(num('$50,000.00'), 50000)
    assert.equal(num('1,234'), 1234)
    assert.equal(num('0,125'), 0.125)
    assert.equal(num('12 345,6'), 12345.6)
    assert.equal(num('1.234.567'), 1234567)
    assert.equal(num('-3.5'), -3.5)
    // Shown as people read it: an API's bare number rounded for its size, grouped, a currency sign before it.
    const shown = (text, unit) => crun.vm.execute('liveShown', [new VeraStringValue(text), new VeraStringValue(unit)]).value
    assert.equal(shown('75883.35636482359', '$'), '$75,883.36')
    assert.equal(shown('4065.6', '$'), '$4,065.60')
    assert.equal(shown('81.7947', 'RUB'), '81.7947 RUB')
    assert.equal(shown('1.1168734', 'USD'), '1.11687 USD')
    assert.equal(shown('182.12345678', ''), '182.123')
    assert.equal(shown('10.7', '\u00b0C'), '10.7 \u00b0C')
    assert.equal(shown('1234567', ''), '1,234,567')
    assert.equal(shown('-12.5', '\u20ac'), '-\u20ac12.50')
    // What a page wrote is kept as it wrote it.
    assert.equal(shown('$76,022.73', '$'), '$76,022.73')
    assert.equal(shown('Overcast', ''), 'Overcast')
    assert.equal(shown('2-1', ''), '2-1')
    // Why an update failed, as a sentence.
    const why = text => crun.vm.execute('liveWhy', [new VeraStringValue(text)]).value
    assert.equal(why('error: the figures were not in the search results'), 'The figures were not in the search results.')
    assert.equal(why('error 502: Bad gateway'), 'Bad gateway.')
    assert.equal(why('HTTP 404'), 'HTTP 404.')
    answer(crun, 'liveAnswer', 'ok\n92,35 \u20bd\n\n\nsource\tcbr.ru\thttps://cbr.ru\nasof\t12:02')
    answer(crun, 'liveAnswer', 'ok\n92,50 \u20bd\n\n\nsource\tcbr.ru\thttps://cbr.ru\nasof\t12:03')
    assert.match(screenOf(crun.vm, crun.state), /\u25b2 \+0\.15 \(0\.16%\) since 12:02/)
  }
  // An answer with no first figure still shows the others: the placeholder is only for before the first answer.
  {
    const three = [btc, Object.assign(new c.SketchLive(), {label: 'B'}), Object.assign(new c.SketchLive(), {label: 'C'})]
    const erun = start(compileVeraSource(sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'E'], ['__THEME__', 'clean']]), [live.liveValues(coinSpec(), three)])).vbc2)
    answer(erun, 'liveAnswer', 'ok\n\n12\u00b0C\nOvercast\nsource\tx.org\thttps://x.org\nasof\t14:05')
    assert.ok(kindsOf(erun.vm, erun.state).includes('tilegrid') && !kindsOf(erun.vm, erun.state).includes('skeleton'))
    assert.match(screenOf(erun.vm, erun.state), /Overcast/)
  }
  // With the source shown, it is the line under the change, in the same tile.
  toggleSource(run)
  assert.match(screenOf(run.vm, run.state), /\u25bc -500 \(-0\.65%\) since 14:06:09\napi\.coingecko\.com · 14:07:09/)
  toggleSource(run)
  answer(run, 'liveAnswer', 'ok\n76123.5\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:08:09')
  // A source that writes the degree sign already does not get it twice ("10° °C").
  {
    const temp = Object.assign(new c.SketchLive(), {id: 't', label: 'Temperature now', unit: '°C'})
    const tsrc = sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'W'], ['__THEME__', 'clean']]), [live.liveValues(searchSpec('Moscow temperature now'), [temp])])
    const trun = start(compileVeraSource(tsrc).vbc2)
    answer(trun, 'liveAnswer', 'ok\n10°\n\n\nsource\twhat-temp.com\thttps://what-temp.com\nasof\t14:26:14')
    const tscreen = screenOf(trun.vm, trun.state)
    assert.match(tscreen, /\n10°\n/)
    assert.doesNotMatch(tscreen, /10° °C/)
    answer(trun, 'liveAnswer', 'ok\n10\n\n\nsource\twhat-temp.com\thttps://what-temp.com\nasof\t14:27:14')
    assert.match(screenOf(trun.vm, trun.state), /10 °C/)
  }
  // Open-Meteo: a WMO weather code is shown in words, and an ISO time as its hours and minutes.
  {
    const om = Object.assign(new SourceSpec(), {url: 'https://api.open-meteo.com/v1/forecast?latitude=51.5&longitude=-0.13&current=temperature_2m,weather_code',
      paths: ['current.temperature_2m', 'current.weather_code'], asof: 'current.time', labels: ['', ''], units: ['', ''], values: ['6.4', '3']})
    const figs = [Object.assign(new c.SketchLive(), {label: 'Temperature now', unit: '°C'}), Object.assign(new c.SketchLive(), {label: 'Conditions now'})]
    const osrc = sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'W'], ['__THEME__', 'clean']]), [live.liveValues(om, figs)])
    const orun = start(compileVeraSource(osrc).vbc2)
    answer(orun, 'liveAnswer', 'ok\n6.4\n3\n\nsource\tapi.open-meteo.com\thttps://api.open-meteo.com/x\nasof\t2026-11-06T12:30')
    const oscreen = screenOf(orun.vm, orun.state)
    assert.match(oscreen, /6\.4 °C/)
    assert.match(oscreen, /\nOvercast\n/)
    toggleSource(orun)
    assert.match(screenOf(orun.vm, orun.state), /\napi\.open-meteo\.com · 12:30\n/)
    assert.doesNotMatch(screenOf(orun.vm, orun.state), /T12:30/)
    // A weather code first is not told as a change: 3 to 61 is not "+58".
    const codeFirst = live.liveValues(Object.assign(new SourceSpec(), om, {paths: ['current.weather_code', 'current.temperature_2m']}), [figs[1], figs[0]])
    assert.match(codeFirst.get('__LIVE_ROWS__'), /liveWeather\(state\.liveFigure1\), liveUnder\(state, false\), ""\)/)
  }
  // A failure keeps the figure and says why.
  answer(run, 'liveAnswer', 'error: HTTP 502')
  screen = screenOf(run.vm, run.state)
  assert.match(screen, /76,123\.5 USD/)
  assert.match(screen, /Could not update/)
  assert.match(screen, /HTTP 502/)
  // The next answer clears the note.
  answer(run, 'liveAnswer', 'ok\n76200\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:06:10')
  assert.doesNotMatch(screenOf(run.vm, run.state), /Could not update/)
}

// ---- No API: a search on each refresh, the plan's labels written out, every five minutes ----
async function searchFallback() {
  const filled = await live.fillLive('Bitcoin price now', [btc], async () => found(null), true)
  assert.equal(filled.failed, '')
  assert.equal(filled.values.get('__LIVE_TARGET__'), 'Vera.Live.fetch')
  assert.equal(filled.values.get('__LIVE_ARGS__'), '["query", "Bitcoin price USD", "labels", "Bitcoin price"]')
  assert.equal(filled.values.get('__LIVE_EVERY__'), '300')
  assert.match(filled.note, /source=search/)
  const src = sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'Bitcoin'], ['__THEME__', 'clean']]), [filled.values])
  const {vbc2} = compileVeraSource(src)
  assert.doesNotMatch(sourceShownError(src, vbc2, searchSpec('Bitcoin price USD')), /without the figure/)
  // Neither an API nor a search: the section cannot be filled, and says so.
  const none = await live.fillLive('Bitcoin price now', [btc], async () => found(null), false)
  assert.match(none.failed, /neither is available/)
  // The finder is asked for the plan's figures in order.
  // The search is made with the first figure's own query, which names the place or the thing; not every query run together.
  assert.equal(live.liveQuery([Object.assign(new c.SketchLive(), {query: 'Moscow temperature now'}), Object.assign(new c.SketchLive(), {query: 'Moscow weather conditions now'})]), 'Moscow temperature now')
  assert.match(live.liveNeed('x', [btc, Object.assign(new c.SketchLive(), {label: 'Ether price', means: 'Ether price', unit: 'USD'})]),
    /The figures to fetch, in this order:\n1\. Bitcoin price \(the price of one bitcoin now\), in USD: Bitcoin price USD\n2\. Ether price, in USD$/)
  // A label cannot break out of the call or the row it goes into.
  const odd = Object.assign(new c.SketchLive(), {id: 'x', label: 'A|B "C"\nD', unit: '$'})
  const ov = live.liveValues(searchSpec('q'), [odd])
  assert.equal(ov.get('__LIVE_ARGS__'), '["query", "q", "labels", "A B C D"]')
  compileVeraSource(sc.composeProgram([LIVE_KIND], new Map([['__TITLE__', 'X'], ['__THEME__', 'clean']]), [ov]))
}

// ---- The plan: a live need is SketchLive, at most three, its id readable by a formula ----
function planParse() {
  const plan = np.parseNeedsPlan(JSON.stringify({title: 'Coins', inputs: [{id: 'coins', label: 'Coins', kind: 'amount', measure: 'number', min: 0, max: 100, value: 0.5}],
    needs: [{type: 'live', id: 'btcPrice', label: 'Bitcoin price', means: 'one bitcoin now', measure: 'money', unit: 'USD', query: 'Bitcoin price USD'},
      {type: 'live', id: 'a', label: 'A'}, {type: 'live', id: 'b', label: 'B'}, {type: 'live', id: 'd', label: 'D'},
      {type: 'figure', id: 'worth', label: 'Worth', means: 'coins at the price now', format: 'money', unit: 'USD', formula: 'coins * btcPrice',
        example: {given: {coins: 2, btcPrice: 100}, result: 200}}]}))
  const sketch = np.sketchFrom(plan)
  assert.deepEqual(sketch.live.map(l => l.id), ['btcPrice', 'a', 'b'])
  assert.equal(sketch.live[0].unit, '$')
  assert.equal(sketch.live[0].query, 'Bitcoin price USD')
  // A fourth is left out quietly (Metrics), not handed to the written section, which can fetch nothing either.
  assert.deepEqual(sketch.liveCut, ['D'])
  assert.ok(!sketch.other.some(o => /D/.test(o)))
  assert.match(np.NEEDS_PROMPT, /"type": "live"/)
  // Its place or thing is fixed in its query, never an input; today's forecast is live too.
  assert.match(np.NEEDS_PROMPT, /never an input the person types or changes/)
  assert.match(np.NEEDS_PROMPT, /Today\\?'s forecast \(the high, the chance of rain\) is live too/)
  assert.match(c.describeSketch(sketch), /shows "Bitcoin price" as it is now, fetched from the internet/)
}

// ---- The whole agent: plan, Jev, the section filled from a mocked source, a formula over the live figure ----
const PLAN = {title: 'My bitcoin', eyebrow: '', subtitle: '',
  inputs: [{id: 'coins', label: 'Coins held', kind: 'amount', measure: 'number', min: 0, max: 1000, value: 2, unit: 'BTC'}],
  needs: [{type: 'live', id: 'btcPrice', label: 'Bitcoin price', means: 'the price of one bitcoin now', measure: 'money', unit: 'USD', query: 'Bitcoin price USD'},
    {type: 'figure', id: 'worth', label: 'Holdings value', means: 'what the coins held are worth at the price now', format: 'money', unit: 'USD',
      formula: 'coins * btcPrice', example: {given: {coins: 2, btcPrice: 100}, result: 200}}]}

// Jev: yes or no for the live figure, as told; for every other question the first option, or the one that says the formula is right.
function jev(liveAnswer) {
  const asked = []
  const ask = async body => {
    const q = JSON.parse(body).questions
    asked.push(Object.keys(q))
    const answers = {}
    for (const k of Object.keys(q)) {
      const keys = Object.keys(q[k].criteria || {})
      if (k.startsWith('live.')) answers[k] = {type: 'choice', choice: liveAnswer, confidence: 0.92}
      else if (keys.includes('right')) answers[k] = {type: 'choice', choice: 'right', confidence: 0.9}
      else if (k.startsWith('expr.') && keys.some(x => /^multiply:(coins:btcPrice|btcPrice:coins)$/.test(x))) answers[k] = {type: 'choice', choice: keys.find(x => /^multiply:(coins:btcPrice|btcPrice:coins)$/.test(x)), confidence: 0.9}
      else if (keys.includes('none')) answers[k] = {type: 'choice', choice: 'none', confidence: 0.9}
      else if (keys.length > 0) answers[k] = {type: 'choice', choice: keys[0], confidence: 0.9}
    }
    return JSON.stringify({answers})
  }
  return {ask, asked}
}

async function agentRun(liveAnswer, source) {
  const h = new AgentHost()
  h.askPlan = async (_s, _u, onText) => { const t = JSON.stringify(PLAN); onText(t); return t }
  const j = jev(liveAnswer)
  h.askJev = j.ask
  let request = null
  h.fillBlocks = async r => {
    request = r
    const calls = new fill.BlockCalls()
    calls.search = async () => 'Web results: ...'
    calls.source = async need => { assert.match(need, /1\. Bitcoin price/); return found(source) }
    calls.content = async () => null
    return fill.fillSections(r, calls)
  }
  const r = await runAgent(Object.assign(new AgentRequest(), {prompt: 'What my bitcoin is worth now'}), h)
  return {r, request, asked: j.asked}
}

async function agentYes() {
  const {r, request, asked} = await agentRun('yes', coinSpec())
  assert.ok(asked[0].includes('live.0'), 'the live figure is asked in the first choice call: ' + JSON.stringify(asked))
  assert.ok(asked.slice(1).every(keys => !keys.includes('live.0')), 'and not again')
  assert.deepEqual(request.kinds, [LIVE_KIND])
  assert.deepEqual(request.live.map(l => l.id), ['btcPrice'])
  assert.ok(r.vbc2.length > 0, 'served: ' + r.note)
  assert.match(r.source, /sdk\.call\("Vera\.Source\.fetch", \["url", "https:\/\/api\.coingecko\.com[^"]*", "paths", "bitcoin\.usd"\], "liveAnswer"\)/)
  assert.match(r.source, /let btcPrice: number = liveNumber\(state\.liveFigure1\);/)
  // The value is worked out from the figure the section fetched: 2 coins at 50,000.
  const run = start(r.vbc2)
  answer(run, 'liveAnswer', 'ok\n$50,000.00\n\n\nsource\tapi.coingecko.com\thttps://api.coingecko.com/x\nasof\t14:05:09')
  const screen = screenOf(run.vm, run.state)
  assert.match(screen, /100000/, 'the holdings value reads the live price: ' + screen)
  assert.match(screen, /\$50,000\.00/)
  // The composition record rebuilds with the host's call in it.
  assert.ok(r.record !== null, 'a composition record is kept')
}

async function agentNo() {
  const {r, request} = await agentRun('no', coinSpec())
  // Not fetched: no live section, and the figure that reads it cannot be worked out by the parts.
  assert.ok(request === null || request.kinds.indexOf(LIVE_KIND) < 0)
  assert.ok(r.composed.composition === null || r.composed.composition.blocks.indexOf(LIVE_KIND) < 0)
  // Neither is the value the parts would have bound to it: it goes to the written section with the figure, or is refused.
  const c = r.composed.composition
  assert.ok(c === null || !c.bindings.has('worth') && ![...c.bindings.values()].some(b => [b.a, b.b, ...b.reads].includes('btcPrice')),
    'no binding reads btcPrice: ' + JSON.stringify(c && [...c.bindings.keys()]))
  assert.ok(c === null || c.custom.some(n => /^the figure "Holdings value"/.test(n)) ||
    c.unbound.some(u => /reads btcPrice, which nothing fetches/.test(u)), JSON.stringify(c && {unbound: c.unbound, custom: c.custom}))
}

// ---- What the review of #51 found: the plan's slots, a widget's cut, an edit that takes the section away ----
function reviewFixes() {
  // The live section comes before a section that took a part's place: each slot points at its own section.
  {
    const comp = new c.Composition(new c.Sketch())
    comp.live = [btc]
    comp.blocks = [LIVE_KIND, 'timer']
    comp.replaced = [new c.Replaced('timer', 'a 10 minute countdown')]
    const plan = c.screenPlan(comp)
    const by = id => { const s = plan.slots.find(x => x.id === id); return s && plan.components[s.by].spec.kind }
    assert.equal(by('live'), LIVE_KIND)
    assert.equal(by('section.timer'), 'timer')
  }
  // A widget cut for room takes a figure that reads a live figure cut with it.
  {
    const plan = np.parseNeedsPlan(JSON.stringify({title: 'W', inputs: [{id: 'coins', label: 'Coins', kind: 'amount', measure: 'number', min: 0, max: 9, value: 1}],
      needs: [{type: 'figure', id: 'f1', label: 'One', formula: 'coins * 2', format: 'plain'},
        {type: 'figure', id: 'f2', label: 'Two', formula: 'coins * 3', format: 'plain'},
        {type: 'live', id: 'btcPrice', label: 'Bitcoin price', measure: 'money'},
        {type: 'figure', id: 'worth', label: 'Worth', formula: 'coins * btcPrice', format: 'money'}]}))
    const cut = np.capForWidget(plan, 2)
    assert.ok(cut.some(w => /^Worth/.test(w)), 'cut: ' + JSON.stringify(cut))
    assert.ok(!plan.needs.some(n => n.raw.id === 'worth'))
  }
  // The answer that stood (the person's, or the default) goes into each live query and onto the screen when they lack it.
  {
    const sk = new c.Sketch()
    sk.title = 'Live Football Score'; sk.eyebrow = 'Live score'
    sk.live = [Object.assign(new c.SketchLive(), {id: 's', label: 'Match score', query: 'live football match score now'})]
    const q = Object.assign(new c.SketchQuestion(), {ask: 'Which team?', options: ['Arsenal', 'Chelsea'], fallback: 0})
    assert.equal(c.answerTo(q), 'Arsenal')
    q.answer = 'Real Madrid'
    assert.equal(c.answerTo(q), 'Real Madrid')
    c.keepAnswers(sk, [c.answerTo(q)])
    assert.equal(sk.live[0].query, 'live football match score now Real Madrid')
    assert.equal(sk.eyebrow, 'Live score \u00b7 Real Madrid')
    // Named already: nothing changes.
    const w = new c.Sketch()
    w.title = 'London Weather'
    w.live = [Object.assign(new c.SketchLive(), {id: 't', label: 'Temperature now', query: 'London temperature now'})]
    assert.equal(c.keepAnswers(w, ['London']), '')
    assert.equal(w.eyebrow, '')
  }
  // A figure that is only a live figure again is not shown beside it.
  {
    const comp = new c.Composition(new c.Sketch())
    comp.live = [btc]
    comp.sketch.constants = [Object.assign(new c.SketchConstant(), {id: 'one', value: 1})]
    const bind = o => Object.assign(new c.Binding(), o)
    assert.equal(c.copiesLive(comp, bind({formula: 'copy', a: 'btcPrice'})), 'btcPrice')
    assert.equal(c.copiesLive(comp, bind({formula: 'multiply', a: 'one', b: 'btcPrice'})), 'btcPrice')
    assert.equal(c.copiesLive(comp, bind({formula: 'written', expr: 'btcPrice * 1'})), 'btcPrice')
    assert.equal(c.copiesLive(comp, bind({formula: 'multiply', a: 'coins', b: 'btcPrice'})), '')
    assert.equal(c.copiesLive(comp, bind({formula: 'written', expr: 'coins * btcPrice'})), '')
  }
  // The live section is not taken away while a part reads its figures; it is when nothing does.
  {
    const cm = loadVera('VeraComposition')
    const reader = new cm.Block('figures', new Map(), new Map())
    reader.literal = {initStatements: '', initEntries: '', functions: '  let btcPrice: number = liveNumber(state.liveFigure1);', viewBlock: ''}
    const comp = new cm.Composition()
    comp.blocks = [reader, new cm.Block(LIVE_KIND, new Map(), new Map())]
    const edit = Object.assign(new cm.CompositionEdit(), {op: cm.OP_REMOVE, target: LIVE_KIND})
    assert.equal(cm.applyEdit(comp, edit), null)
    reader.literal.functions = '  let x: number = 1;'
    assert.notEqual(cm.applyEdit(comp, edit), null)
  }
}

;(async () => {
  reviewFixes()
  await blockAlone()
  await blockScreen()
  await searchFallback()
  planParse()
  await agentYes()
  await agentNo()
  console.log('live-figure-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
