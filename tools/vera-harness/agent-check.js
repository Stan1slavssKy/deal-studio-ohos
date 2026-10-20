// agent/VeraAgent.ets and agent/VeraBuildRoute.ets without the network: a host that replays recorded sketches and Jev
// answers (tools/vera-harness/compose/) through runAgent -- streamed plan, previews, assembly, compile, first run -- and
// the route's order between the agent and the blocks. The blocks have no network here, so they always answer scratch.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const {AgentHost} = loadVera('agent/AgentHost')
const {AgentRequest, runAgent} = loadVera('agent/VeraAgent')
const route = loadVera('agent/VeraBuildRoute')

const fixture = (label, file) => fs.readFileSync(path.join(__dirname, 'compose', label, file), 'utf8')

// The sketch arrives in pieces, as DeepSeek streams it; Jev answers with the recorded body.
function replayHost(label, {jev = fixture(label, 'jev-answer.json'), cancelled = () => false} = {}) {
  const host = new AgentHost()
  const seen = {status: [], previews: 0, plans: 0, jev: 0}
  host.askPlan = async (system, user, onText) => {
    seen.plans++
    assert.match(system, /JSON sketch/)
    const text = fixture(label, 'sketch.json')
    for (let i = 40; i < text.length; i += 40) onText(text.slice(0, i))
    return text
  }
  host.askJev = async body => { seen.jev++; JSON.parse(body); return jev }
  host.status = s => seen.status.push(s)
  host.preview = vbc2 => { assert.ok(vbc2.length > 0); seen.previews++ }
  host.cancelled = cancelled
  return {host, seen}
}

const request = (prompt, widget = false) => Object.assign(new AgentRequest(), {prompt, widget})

;(async () => {
  // Served: a checked program, previews while the plan streamed, and the plan in words for a generation.
  {
    const {host, seen} = replayHost('tip')
    const r = await runAgent(request('tip calculator'), host)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.equal(r.errors, '')
    assert.ok(r.source.includes('function view('))
    assert.ok(seen.previews > 0 && r.previews === seen.previews && r.firstPreviewMs >= 0)
    assert.equal(seen.plans, 1)
    assert.equal(seen.jev, 1)
    assert.deepEqual(seen.status, ['Composing...'])
    assert.match(r.plan, /^A sketch of this app/)
    assert.match(r.note, /^composed: /)
  }
  // A widget says so in its status and is assembled as one.
  {
    const {host, seen} = replayHost('egg')
    const r = await runAgent(request('egg timer', true), host)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.deepEqual(seen.status, ['Sketching the widget...'])
  }
  // Jev does not answer: nothing served, but the plan is kept for the generation that follows.
  {
    const {host} = replayHost('tip', {jev: ''})
    const r = await runAgent(request('tip calculator'), host)
    assert.equal(r.vbc2, '')
    assert.equal(r.note, 'Jev did not answer')
    assert.match(r.plan, /^A sketch of this app/)
  }

  // A need the plan says a ready-made section handles: Jev's section joins the composition's own parts, its content
  // filled by the host (here the catalogue's defaults), and the program is served. Sections alone make a screen too.
  for (const [label, kind, own] of [['sections-tipping', 'key_facts', true], ['sections-beach', 'checklist', false]]) {
    const {host} = replayHost(label)
    let asked = null
    host.fillBlocks = async request => { asked = request; return loadVera('agent/AgentHost').defaultBlockFill(request) }
    const r = await runAgent(request(label), host)
    assert.ok(r.vbc2.length > 0, label + ': ' + r.note)
    assert.deepEqual(r.blocks, [kind])
    assert.deepEqual(asked.kinds, [kind])
    assert.ok(asked.offset > 0)
    assert.ok(asked.compose(r.blockFill.values).includes('function view('))
    assert.match(r.note, new RegExp('sections ' + kind))
    assert.equal(/composed: 0 inputs/.test(r.note), !own, label)
  }
  // Real data with no search: the host refuses the sections, and nothing is served.
  {
    const {host} = replayHost('sections-tipping')
    host.fillBlocks = async () => Object.assign(new (loadVera('agent/AgentHost').BlockFill)(), {failed: 'sections need real data and no search is available'})
    const r = await runAgent(request('tipping'), host)
    assert.equal(r.vbc2, '')
    assert.match(r.note, /no search is available/)
  }

  // The custom section: what nothing else does, written as one block into the program the rest makes, checked like
  // any block, the failing lines quoted back for a repair; a phone call it makes up, or an answer it cannot give, is
  // never served.
  {
    const {CustomRequest, writeSection, parseSection} = loadVera('agent/AgentCustom')
    const c = loadVera('VeraCompose')
    const comp = c.readComposition(fixture('tip', 'jev-answer.json'), c.parseSketch(fixture('tip', 'sketch.json')))
    const section = (functions, view) => '<classes>\n</classes>\n<fields>\nc_count: number = 0\n</fields>\n<functions>\n' + functions +
      '\n</functions>\n<view>\n' + view + '\n</view>'
    const good = section('function c_bump(state: AppState, value: number): AppState {\n  return {c_count: state.c_count + 1__PASSTHROUGH__};\n}',
      'sections.push(ui.Section("content", "", "", [ui.Button("primary", "Count " + ui.numberToString(state.c_count), "c_bump", 0, true)]));')
    const broken = good.replace('state.c_count + 1', 'state.c_cuont + 1')
    const asks = []
    const run = async replies => {
      const request = Object.assign(new CustomRequest(), {needs: ['a counter'], prompt: 'tip calculator with a counter',
        compose: s => c.assembleProgram(comp, [], s)})
      asks.length = 0
      return writeSection(request, 'LANGUAGE', async (system, user) => { asks.push({system, user}); return replies.shift() })
    }
    assert.equal(parseSection('no tags'), null)
    assert.equal(parseSection(good).stateFields[0].name, 'c_count')
    let r = await run([good])
    assert.ok(r.section !== null && r.attempts === 1, r.failed)
    assert.match(asks[0].system, /^LANGUAGE/)
    assert.match(asks[0].user, /The program so far/)
    assert.match(c.assembleProgram(comp, [], r.section), /return \{c_count: state\.c_count \+ 1, /)
    r = await run([broken, good])
    assert.ok(r.section !== null && r.attempts === 2, r.failed)
    assert.match(asks[1].user, /It failed:[\s\S]*c_cuont/)
    r = await run([good.replace('return {', 'sdk.call("x/y", [], "c_bump");\n  return {'), good])
    assert.equal(r.attempts, 2)
    assert.match(asks[1].user, /sdk\.call/)
    // Compiles and runs, but Jev does not read it as doing the need: refused, not repaired.
    {
      const {verifyRequest, undone} = loadVera('agent/AgentCustom')
      const request = Object.assign(new CustomRequest(), {needs: ['a counter', 'a photo'], prompt: 'p', compose: s => c.assembleProgram(comp, [], s)})
      const body = JSON.parse(verifyRequest(request, good))
      assert.deepEqual(Object.keys(body.questions), ['does.0', 'does.1'])
      assert.match(body.state, /c_bump/)
      const said = (a, b) => JSON.stringify({answers: {'does.0': {probabilities: {yes: a, no: 1 - a}}, 'does.1': {probabilities: {yes: b, no: 1 - b}}}})
      assert.deepEqual(undone(request, said(0.9, 0.2)), ['a photo'])
      assert.deepEqual(undone(request, ''), [])
      request.verify = async () => said(0.9, 0.2)
      const refused = await writeSection(request, 'L', async () => good)
      assert.equal(refused.section, null)
      assert.match(refused.failed, /does not do: a photo/)
      assert.equal(refused.attempts, 1)
    }
    r = await run(['<cannot>it needs the camera</cannot>'])
    assert.equal(r.section, null)
    assert.match(r.failed, /cannot: it needs the camera/)
    r = await run([broken, broken, broken])
    assert.equal(r.section, null)
    assert.equal(r.attempts, 3)
  }

  // Questions: Jev keeps only those a default cannot stand in for; the person's answer, when it differs from the
  // default the plan was drawn for, has the plan drawn again with it; no answer is the default.
  {
    const {blockingRequest, blockingOf, askBlocking} = loadVera('agent/AgentQuestions')
    const c = loadVera('VeraCompose')
    const sketch = c.parseSketch(JSON.stringify({title: 'Converter', inputs: [], values: [], questions: [
      {id: 'units', ask: 'Which units?', options: ['km to miles', 'kg to pounds'], default: 0},
      {id: 'look', ask: 'Which colour?', options: ['blue', 'green'], default: 1},
      {id: 'bad', ask: 'One option only?', options: ['only']}]}))
    assert.equal(sketch.questions.length, 2)
    assert.equal(sketch.questions[1].fallback, 1)
    const body = JSON.parse(blockingRequest('a converter', sketch.questions))
    assert.deepEqual(Object.keys(body.questions), ['blocking.0', 'blocking.1'])
    const jev = (a, b) => async () => JSON.stringify({answers: {'blocking.0': {probabilities: {ask: a, skip: 1 - a}}, 'blocking.1': {probabilities: {ask: b, skip: 1 - b}}}})
    assert.deepEqual(blockingOf(await jev(0.9, 0.1)(), sketch.questions).map(q => q.id), ['units'])
    assert.deepEqual(blockingOf('', sketch.questions), [])
    const shown = []
    let log = []
    let settled = await askBlocking('a converter', sketch.questions, jev(0.9, 0.1), async q => { shown.push(q); return 1 }, log)
    assert.equal(shown.length, 1)
    assert.equal(shown[0].fallback, 0)
    assert.match(settled, /Which units\? kg to pounds/)
    assert.equal(log[0].changed, true)
    log = []
    assert.equal(await askBlocking('a converter', sketch.questions, jev(0.9, 0.1), async () => null, log), '')
    assert.match(log[0].answer, /km to miles \(default\)/)
    // Through the agent: an answer that differs draws the plan again, with the answer in the request.
    const {host} = replayHost('tip')
    const plans = []
    const askPlan = host.askPlan
    host.askPlan = async (system, user, onText) => {
      plans.push(user)
      if (plans.length === 1) return JSON.stringify(Object.assign(JSON.parse(fixture('tip', 'sketch.json')), {questions: [{id: 'q', ask: 'Split it?', options: ['yes', 'no'], default: 0}]}))
      return askPlan(system, user, onText)
    }
    const askJev = host.askJev
    host.askJev = async b => JSON.parse(b).questions['blocking.0'] ? jev(0.9, 0)() : askJev(b)
    host.ask = async () => 1
    const r = await runAgent(request('tip calculator'), host)
    assert.equal(plans.length, 2)
    assert.match(plans[1], /The person was asked, and answered:\n- Split it\? no/)
    assert.equal(r.composed.replanned, true)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.equal(r.asked.length, 1)
  }

  // The route, agent first (the default): a served agent ends it and the blocks never run.
  const routeRequest = (prompt, blocks) => Object.assign(new route.RouteRequest(), {agent: request(prompt), blocksPrompt: blocks ? prompt : ''})
  assert.equal(route.routeOrder(), route.ORDER_AGENT_FIRST)
  {
    const {host} = replayHost('tip')
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_AGENT)
    assert.equal(o.blocks, null)
  }
  // The agent refuses: the blocks run next, and with neither serving it is scratch with the agent's plan.
  {
    const {host} = replayHost('tip', {jev: ''})
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_SCRATCH)
    assert.notEqual(o.blocks, null)
    assert.match(o.plan, /^A sketch of this app/)
  }
  // Blocks first: the blocks run before the agent, and the agent still serves what they do not.
  route.setRouteOrder(route.ORDER_BLOCKS_FIRST)
  {
    const {host, seen} = replayHost('tip')
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_AGENT)
    assert.notEqual(o.blocks, null)
    assert.equal(seen.plans, 1)
  }
  route.setRouteOrder('anything else')
  assert.equal(route.routeOrder(), route.ORDER_AGENT_FIRST)
  // Neither builder asked for: straight to scratch, no model call.
  {
    const {host, seen} = replayHost('tip')
    const o = await route.buildScreen(new route.RouteRequest(), host)
    assert.equal(o.kind, route.OUTCOME_SCRATCH)
    assert.equal(seen.plans, 0)
  }
  // Cancelled before it starts: nothing is asked.
  {
    const {host, seen} = replayHost('tip', {cancelled: () => true})
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_CANCELLED)
    assert.equal(seen.plans, 0)
  }
  console.log('agent-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
