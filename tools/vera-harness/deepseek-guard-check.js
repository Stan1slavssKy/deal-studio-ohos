// DeepSeekEngine with its network turn stubbed: the web search budget holds per call, not per round, and the
// template-content and UI-needs side calls do not take over the engine while another generation runs. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {deepseek} = loadVera('DeepSeekEngine')
const {settings} = loadVera('SettingsStore')
const {GenerateRequest} = loadVera('LlamaEngine')
const {SEARCH_TOOL_NAME} = loadVera('VeraWebSearch')

settings.getApiKey = () => 'sk-test'
settings.hasExaKey = () => true

async function searchBudget() {
  // Round 1 asks for three searches at once, round 2 for two more; then the model answers.
  const rounds = [3, 2]
  let id = 0
  deepseek.streamOnce = async () => {
    const n = rounds.shift()
    if (n === undefined) return {content: 'fn view() {}', reasoning: '', finishReason: 'stop', toolCalls: [], inputTokens: 0, outputTokens: 0, cacheHitTokens: 0}
    const toolCalls = Array.from({length: n}, () => ({id: 'c' + id++, name: SEARCH_TOOL_NAME, arguments: '{"query":"q"}'}))
    return {content: '', reasoning: '', finishReason: 'tool_calls', toolCalls, inputTokens: 0, outputTokens: 0, cacheHitTokens: 0}
  }
  let ran = 0
  deepseek.runToolCall = async call => { ran++; return {role: 'tool', tool_call_id: call.id, content: 'found'} }
  const request = new GenerateRequest()
  request.userPrompt = 'x'
  await deepseek.generate(request, () => {})
  assert.equal(ran, 2, 'web searches that ran in one generation')
}

async function sideCallKeepsFlags() {
  deepseek.generating = true
  deepseek.cancelled = true
  let streamed = 0
  deepseek.streamOnce = async () => { streamed++; return {content: '{}', toolCalls: []} }
  for (const call of [() => deepseek.extractTemplateContent('s', 'u', 100), () => deepseek.extractUiNeeds('u')]) {
    assert.equal(await call(), null, 'a side call while generating answers null')
  }
  assert.equal(streamed, 0, 'no request is sent while generating')
  assert.equal(deepseek.generating, true, 'generating is kept')
  assert.equal(deepseek.cancelled, true, 'cancelled is kept')
  deepseek.generating = false
  deepseek.cancelled = false
}

;(async () => {
  await searchBudget()
  await sideCallKeepsFlags()
  console.log('deepseek-guard-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
