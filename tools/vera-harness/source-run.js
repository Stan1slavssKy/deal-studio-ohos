// Live run of the live_figure section on the host: the finder (Exa + DeepSeek + the real API) or, with no API, a search on each
// refresh, the section's call written by the host (LiveBlock.ets), then the program run as the phone runs it: its ticker ticked
// until it asks for Vera.Source.fetch or Vera.Live.fetch, the real call made, the answer handed to its handler, and the screen's
// texts printed. Needs ARKESTR_API_KEY (DeepSeek) and EXA_API_KEY. Each argument is a figure, as a plan would name it.
//   node tools/vera-harness/source-run.js ["figure" ...]
const {loadVera} = require('./source-loader')
// The platform http module, on node's fetch (GET and POST), for VeraSource.httpGetText and the Exa search.
globalThis.__veraHttp = () => ({destroy() {}, on() {}, async request(url, o) {
  const r = await fetch(url, {method: o.method || 'GET', headers: o.header, body: o.extraData, signal: AbortSignal.timeout(20000)})
  return {responseCode: r.status, result: await r.text()}
}})
const S = loadVera('VeraSource'), F = loadVera('VeraSourceFind'), L = loadVera('VeraLive')
// Vera.Live.fetch, the fallback, as the phone makes it: Exa and DeepSeek with the keys of this shell.
const {settings} = loadVera('SettingsStore')
Object.assign(settings, {hasExaKey: () => true, getExaKey: () => process.env.EXA_API_KEY, hasApiKey: () => true,
  getApiKey: () => process.env.ARKESTR_API_KEY, getBaseUrl: () => 'https://api.deepseek.com', getModel: () => 'deepseek-flash'})
const {compileVeraSource} = loadVera('VeraCompiler'), {smokeRun} = loadVera('VeraSmoke')
const LB = loadVera('LiveBlock'), C = loadVera('VeraCompose'), {composeProgram} = loadVera('VeraSectionCompose'), {LIVE_KIND} = loadVera('VeraTemplates')
const {VirtualMachine, deserializeVbc2, VeraStringValue, VeraNumberValue, VeraBooleanValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')

async function ds(messages, maxTokens) {
  const r = await fetch('https://api.deepseek.com/chat/completions', {method: 'POST',
    headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + process.env.ARKESTR_API_KEY},
    body: JSON.stringify({model: 'deepseek-flash', temperature: 0, max_tokens: maxTokens, thinking: {type: 'disabled'}, messages})})
  const b = await r.json(); if (!r.ok) throw Error('DeepSeek ' + r.status); return b.choices[0].message.content
}
async function exa(query) {
  const r = await fetch('https://api.exa.ai/search', {method: 'POST', headers: {'Content-Type': 'application/json', 'x-api-key': process.env.EXA_API_KEY},
    body: JSON.stringify({query, numResults: 6, contents: {text: {maxCharacters: 1200}}})})
  const b = await r.json(); return (b.results || []).map((x, i) => `${i + 1}. ${x.title} (${x.url})\n${(x.text || '').slice(0, 1200)}`).join('\n\n')
}

function texts(nodes, out = []) { for (const n of nodes) { if (n.text) out.push(n.text); if (n.kind === 'numbertext') out.push(String(n.numberValue)); texts(n.children || [], out) } return out }
function plain(kind) { return kind === 'string' ? new VeraStringValue('') : kind === 'boolean' ? new VeraBooleanValue(true) : new VeraNumberValue(kind === 'number' ? 1000 : 0) }

async function runApp(compiled) {
  const host = new UiHostEnvironment(), vm = new VirtualMachine(deserializeVbc2(compiled.vbc2), host)
  let state = vm.execute('init')
  // As the phone: the ticker in the view runs first; the other handlers are tried only when there is none.
  const tickers = []; (function find(nodes) { for (const n of nodes) { if (n.kind === 'ticker' && n.action) tickers.push(n.action); find(n.children || []) } })(decodeVeraUi(vm.execute('view', [state])))
  const order = tickers.length ? tickers.map(t => [t, 'number']) : [...compiled.handlers]
  for (const [name, kind] of order) {
    for (let i = 0; i < 400; i++) {   // a ticker: up to 400 ticks of a second
      host.effectsAllowed = true; host.pendingEffects = []
      let next; try { next = vm.execute(name, [state, plain(kind)]) } catch (e) { break }
      const effect = host.pendingEffects.find(e => e.rawTarget === 'Vera.Source.fetch' || e.rawTarget === 'Vera.Live.fetch')
      host.effectsAllowed = false
      state = next
      if (effect) {
        const t = Date.now(), answer = effect.rawTarget === 'Vera.Live.fetch' ? await L.liveFetch(effect.values) : await S.sourceFetch(effect.values)
        state = vm.execute(effect.resultHandler, [state, new VeraStringValue(answer)])
        return {via: (tickers.length ? 'ticker ' : 'NO TICKER, handler ') + name + ' after ' + (i + 1) + ' s', fetchMs: Date.now() - t, answer: answer.split('\n').slice(0, 2).join(' | '),
          screen: texts(decodeVeraUi(vm.execute('view', [state]))).join(' · ').slice(0, 300)}
      }
      if (kind !== 'number') break
    }
  }
  return {via: 'none: no handler asked for the source'}
}

;(async () => {
  const figures = process.argv.slice(2).length ? process.argv.slice(2) : ['Current temperature in Moscow', 'IMOEX index value', 'Bitcoin price in USD']
  for (const label of figures) {
    const t0 = Date.now()
    const calls = new F.SourceCalls()
    calls.search = exa
    calls.askJson = (system, user) => ds([{role: 'system', content: system}, {role: 'user', content: user}], 1200)
    calls.get = url => S.httpGetText(url)
    const figure = Object.assign(new C.SketchLive(), {id: 'figure', label, means: label, query: label})
    const filled = await LB.fillLive('Show ' + label + ' as it is now', [figure], need => F.findSource(need, calls), true)
    console.log('\n== ' + label + '\n   ' + (filled.failed || filled.note) + '  (' + (filled.ms / 1000).toFixed(1) + ' s)')
    if (filled.failed) continue
    const src = composeProgram([LIVE_KIND], new Map([['__TITLE__', label], ['__THEME__', 'clean']]), [filled.values])
    const compiled = compileVeraSource(src)
    const smoke = smokeRun(compiled)
    if (smoke) { console.log('   smoke: ' + smoke.split('\n')[0]); continue }
    const run = await runApp(compiled)
    console.log('   run: via ' + run.via + (run.answer ? '\n   answer: ' + run.answer + ' (' + run.fetchMs + ' ms)\n   screen: ' + run.screen : ''))
    console.log('   total ' + ((Date.now() - t0) / 1000).toFixed(1) + ' s')
  }
})().catch(e => { console.error(e); process.exit(1) })
