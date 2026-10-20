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
