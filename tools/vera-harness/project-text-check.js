// ProjectText.ets: a project is listed under the request it began as, and a refinement says what it changed.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {requestHeadline, changeNote, versionCountText} = loadVera('ProjectText')

// The first answer to a request: the request is the headline and there is no change to report.
assert.equal(requestHeadline('Daily water tracker', 'Daily water tracker'), 'Daily water tracker')
assert.equal(changeNote('Daily water tracker', 'Daily water tracker'), '')

// A refinement keeps the history in `prompt` and the last request in `note`.
const history = 'Daily water tracker\n\nRefinement:\nAdd a one-tap button'
assert.equal(requestHeadline(history, 'Add a one-tap button'), 'Daily water tracker', 'named by what the app is')
assert.equal(changeNote(history, 'Add a one-tap button'), 'Add a one-tap button')
const twice = history + '\n\nRefinement:\nMake it blue'
assert.equal(requestHeadline(twice, 'Make it blue'), 'Daily water tracker')
assert.equal(changeNote(twice, 'Make it blue'), 'Make it blue', 'the last change of several')

// A version saved before requests were kept has only its note.
assert.equal(requestHeadline('', 'Old note'), 'Old note')
assert.equal(changeNote('', 'Old note'), '')
// A request of several lines is its first line.
assert.equal(requestHeadline('Line one\nLine two', 'x'), 'Line one')
assert.equal(requestHeadline('', ''), '')

assert.equal(versionCountText(0), 'No versions yet')
assert.equal(versionCountText(1), '1 version')
assert.equal(versionCountText(7), '7 versions')
console.log('project-text-check: ok')
