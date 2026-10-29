// What a chat widget is built from (VeraChat.ets): the marker's plain request, else the description, else the message; a revision is
// no replacement to build.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const chat = loadVera('VeraChat')
const {WidgetBuildContext} = loadVera('VeraWidgetContext')
const {settings} = loadVera('SettingsStore')
const compose = loadVera('VeraCompose')

settings.hasSelectorKey = () => true
const context = fields => Object.assign(new WidgetBuildContext(), fields)
const agent = c => chat.chatAgentRequest(c) && chat.chatAgentRequest(c).prompt

// The marker's plain request first, then the description, then the message.
assert.equal(agent(context({request: ' tip calculator ', brief: 'a long description', currentRequest: 'the message'})), 'tip calculator')
assert.equal(agent(context({request: '', brief: 'a long description', currentRequest: 'the message'})), 'a long description')
assert.equal(agent(context({request: '  ', brief: ' ', currentRequest: ' the message '})), 'the message')
// A revision of an existing widget is no replacement to build.
assert.equal(chat.chatAgentRequest(context({request: 'tip calculator', source: 'import ...'})), null)
// A widget built on search results is not the agent's.
assert.equal(chat.chatAgentRequest(context({request: 'weather', verifiedSearchResults: ['x']})), null)
assert.equal(chat.chatAgentRequest(context({request: 'tip calculator'})).widget, true)
// The reply just before the person's message searched: a widget asked for now is built on those results; an older reply's are
// another subject's.
const {earlierSearchResults, SearchedTurn} = loadVera('VeraWidgetContext')
const turn = (role, searchResults = []) => Object.assign(new SearchedTurn(), {role, searchResults})
const weather = 'Web results for "Moscow weather today"...'
assert.deepEqual(earlierSearchResults([turn('user'), turn('assistant', [weather]), turn('user')]), [weather])
assert.deepEqual(earlierSearchResults([turn('user'), turn('assistant', [weather]), turn('user'), turn('assistant'), turn('user')]), [])
assert.deepEqual(earlierSearchResults([turn('user')]), [])
const after = context({request: 'weather card', verifiedSearchResults: earlierSearchResults([turn('assistant', [weather]), turn('user')])})
assert.equal(chat.chatAgentRequest(after), null)
// The chat searches for a current figure rather than refusing it.
assert.match(chat.chatSystemPrompt(true), /search before you answer: do not say you cannot get it/)
assert.doesNotMatch(chat.chatSystemPrompt(false), /web_search/)
console.log('chat-prompt-check: ok')
