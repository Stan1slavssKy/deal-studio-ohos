// The project page's widget block: what widgetStatus says for each kind of latest version and card count.
const assert = require('node:assert/strict')
const fs = require('node:fs'), path = require('node:path')
const {loadVera} = require('./source-loader')
const {compileVeraSource} = loadVera('VeraCompiler')
const {widgetStatus, hasWidgetFunction} = loadVera('WidgetStatus')
// widget-counter's view draws with widget(state): the app itself would change with a new widget.
const own = fs.readFileSync(path.join(__dirname, 'examples/widget-counter.vera'), 'utf8')
const base = own.replace('function widget(', 'function compact(').replace('return widget(state);', 'return compact(state);')
const withWidget = base + '\nfunction widget(state: AppState): ui.View { return compact(state); }'
const vbc2 = (source) => compileVeraSource(source).vbc2

assert.equal(hasWidgetFunction(base), false)
assert.equal(hasWidgetFunction(withWidget), true)
assert.equal(widgetStatus(base, vbc2(base), 0).kind, 'none')
assert.equal(widgetStatus(withWidget, vbc2(withWidget), 0).kind, 'ready')
const placed = widgetStatus(withWidget, vbc2(withWidget), 2)
assert.equal(placed.kind, 'placed'); assert.equal(placed.placed, 2)
// Cards over a version with no widget, or one that does not compile, show "Open app" / "Open project".
assert.equal(widgetStatus(base, vbc2(base), 1).kind, 'broken')
assert.equal(widgetStatus(withWidget, '', 1).kind, 'broken')
assert.equal(widgetStatus(base, '', 0).kind, 'needsRun')
assert.equal(widgetStatus('', '', 0).kind, 'needsRun')
const refused = widgetStatus(own, vbc2(own), 0)
assert.equal(refused.kind, 'unavailable'); assert.match(refused.reason, /calls widget\(\)/)
// The version list names a widget change by the words Make widget sends.
const {WIDGET_ASK_TEXT, changeNote} = loadVera('ProjectText')
assert.equal(WIDGET_ASK_TEXT, loadVera('agent/AgentWidget').WIDGET_ASK)
assert.equal(changeNote('x\n\nRefinement:\ny', WIDGET_ASK_TEXT + 'the main number'), 'Widget: the main number')
assert.equal(changeNote('x\n\nRefinement:\ny', 'Add a button'), 'Add a button')
console.log('widget-status-check: ok')

// The widget screen's chips come from the app: its figures, lists and the actions its buttons take.
{
  const {widgetFacts} = loadVera('VeraCompiler')
  const {firstSuggestions, changeSuggestions, humanize} = loadVera('agent/WidgetSuggest')
  const app = [
    'import * as ui from "std/ui"',
    '@jsonable class Entry { ml: number; }',
    '@jsonable class AppState { waterGlasses: number; goal: number; entries: Entry[]; draft: number; }',
    'function init(): AppState { return { waterGlasses: 0, goal: 8, entries: [], draft: 0 }; }',
    'function addGlass(state: AppState, value: number): AppState { return { waterGlasses: state.waterGlasses + value, goal: state.goal, entries: state.entries, draft: state.draft }; }',
    'function setDraft(state: AppState, value: number): AppState { return { waterGlasses: state.waterGlasses, goal: state.goal, entries: state.entries, draft: value }; }',
    'function view(state: AppState): ui.View { return ui.AppTheme("clean", "", [ui.Column("default", [',
    '  ui.NumberText("metric", state.waterGlasses, "", "", 1), ui.NumberField("default", "Draft", state.draft, 0, 10, "setDraft"),',
    '  ui.Button("primary", "+1", "addGlass", 1, true)])]); }',
  ].join('\n')
  compileVeraSource(app)
  const facts = widgetFacts(app)
  // goal is never shown and draft only sits in a field: neither is a figure for the card. entries is never laid out.
  assert.deepEqual(facts.numbers.map(f => f.name), ['waterGlasses'])
  assert.deepEqual(facts.lists, [])
  // setDraft is fed by a field, not a button: a card button is not offered for it.
  assert.deepEqual(facts.handlers.map(f => [f.name, f.label]), [['addGlass', '+1']])
  assert.equal(humanize('stops7'), 'Stops'); assert.equal(humanize('item_2'), 'Item');
  assert.equal(humanize('waterGlasses'), 'Water glasses'); assert.equal(humanize('best_score'), 'Best score')
  assert.deepEqual(firstSuggestions(app).map(s => s.label), ['Water glasses', '\u201C+1\u201D button', 'Let VERA choose'])
  assert.match(firstSuggestions(app)[0].ask, /state\.waterGlasses, .*"metric"/)
  const withWidget = app + '\nfunction widget(state: AppState): ui.View { return ui.NumberText("metric", state.waterGlasses, "", "", 1); }'
  assert.deepEqual(changeSuggestions(withWidget).map(s => s.label), ['Bigger number', 'Less text', 'Button \u201C+1\u201D'])
  // A game: the figures it labels (Score, Lives), its primary button; not the paddle's x or the bricks it paints.
  const game = [
    'import * as ui from "std/ui"',
    '@jsonable class Brick { col: number; alive: boolean; }',
    '@jsonable class AppState { paddleX: number; bricks: Brick[]; score: number; lives: number; }',
    'function init(): AppState { return { paddleX: 50, bricks: [], score: 0, lives: 3 }; }',
    'function start(state: AppState, ignored: number): AppState { return state; }',
    'function nudgeLeft(state: AppState, ignored: number): AppState { return state; }',
    'function view(state: AppState): ui.View {',
    '  let paths: ui.View[] = [];',
    '  for (let b: Brick of state.bricks) { paths.push(ui.Path("accent", "M0 0 L1 1 Z", 0)); }',
    '  paths.push(ui.Path("accent", "M" + ui.numberToString(1) + " 0 Z", 0));',
    '  return ui.AppTheme("clean", "", [ui.Column("default", [',
    '    ui.NumberStat("accent", "Score", state.score, "", "", 1, "", "star"),',
    '    ui.Text("body", "Lives " + ui.numberToString(state.lives)),',
    '    ui.Button("secondary", "< Left", "nudgeLeft", 0, true), ui.Button("primary", "Start", "start", 0, true)])]); }',
  ].join('\n')
  const gameFacts = widgetFacts(game)
  assert.deepEqual(gameFacts.numbers.map(f => [f.name, f.label]), [['score', 'Score'], ['lives', '']])
  assert.deepEqual(gameFacts.lists, [])
  assert.deepEqual(gameFacts.handlers.map(f => f.name), ['start', 'nudgeLeft'])
  assert.deepEqual(firstSuggestions(game).map(s => s.label), ['Score', 'Lives', '\u201CStart\u201D button', 'Let VERA choose'])
  // A list laid out as rows is offered.
  const log = app.replace('ui.NumberText("metric", state.waterGlasses, "", "", 1),',
    'ui.NumberText("metric", state.waterGlasses, "", "", 1), ui.List("default", rows(state)),') +
    '\nfunction rows(state: AppState): ui.View[] { let out: ui.View[] = []; for (let e: Entry of state.entries) { out.push(ui.ListItem("default", "Glass", "", ui.numberToString(e.ml), "", "")); } return out; }'
  assert.deepEqual(widgetFacts(log).lists.map(f => f.name), ['entries'])
  // Nothing known of the app: requests that fit any.
  assert.deepEqual(firstSuggestions('not a program').map(s => s.label), ['The main number', 'A quick action', 'Let VERA choose'])
  // A program the model wrote: its figures are worked out (glassesToday = entries.length()), not fields; read from their labels.
  const water = fs.readFileSync(path.join(__dirname, 'examples/water-tracker.vera'), 'utf8')
  const waterFirst = firstSuggestions(water)
  assert.deepEqual(waterFirst.map(s => s.label).slice(0, 2), ['Glasses today', 'Latest entries'])
  assert.match(waterFirst[0].ask, /shows as "Glasses today", worked out the way the app works it out/)
  assert.ok(waterFirst.some(s => s.label === '\u201CAdd\u201D button'))
  // Remove passes a row's index to its handler: not a card's button.
  assert.ok(!widgetFacts(water).handlers.some(f => f.name === 'removeEntry'))
  // A figure drawn as a Hero or a Stat with a label counts too (a program the model wrote).
  const push = fs.readFileSync(path.join(__dirname, 'examples/pushups-counter.vera'), 'utf8')
  assert.equal(firstSuggestions(push)[0].label, 'Total pushups')
  console.log('widget-status-check: chips from the app ok')
}

// Start over: the program without its widget, its refresh and what only they use; what the app uses as well stays.
{
  const {withoutWidget, spliceWidget} = loadVera('VeraCompiler')
  const app = [
    'import * as ui from "std/ui"',
    '@jsonable class AppState { count: number; }',
    'function init(): AppState { return { count: 0 }; }',
    'function left(state: AppState): number { return 10 - state.count; }',
    'function bump(state: AppState, value: number): AppState { return { count: state.count + value }; }',
    'function view(state: AppState): ui.View { return ui.Column("default", [ui.NumberText("metric", left(state), "", "", 1), ui.Button("primary", "+1", "bump", 1, true)]); }',
  ].join('\n') + '\n'
  const card = '\nfunction cardLine(state: AppState): string { return ui.numberToString(left(state)) + " left"; }\n' +
    'function widget(state: AppState): ui.View { return ui.Text("body", cardLine(state)); }\n' +
    'function widgetRefresh(state: AppState): AppState { return state; }\n'
  const withCard = app + card
  compileVeraSource(withCard)
  const bare = withoutWidget(withCard)
  compileVeraSource(bare)
  assert.equal(hasWidgetFunction(bare), false)
  assert.ok(!/widgetRefresh|cardLine/.test(bare), 'the widget and what only it used are gone')
  assert.ok(/function left\(/.test(bare) && /function view\(/.test(bare), 'what the app uses stays')
  assert.equal(withoutWidget(app), app, 'a program without a widget is left as it is')
  assert.equal(withoutWidget('not a program'), 'not a program')
  // A new widget with a helper of the old one's name: on the bare program its own helper is taken, not the old one.
  const fresh = 'function cardLine(state: AppState): string { return "now " + ui.numberToString(state.count); }\n' +
    'function widget(state: AppState): ui.View { return ui.Text("body", cardLine(state)); }'
  const made = spliceWidget(bare, fresh)
  compileVeraSource(made)
  assert.ok(made.includes('"now "') && !made.includes('" left"'))
  // On the program with the old widget, the old helper would have won: why Start over cuts it.
  assert.ok(spliceWidget(withCard, fresh).includes('" left"'))
  // Start over offers the first widget's requests again.
  const {firstSuggestions} = loadVera('agent/WidgetSuggest')
  assert.ok(firstSuggestions(bare).some(s => s.label === 'Let VERA choose'))
  console.log('widget-status-check: start over ok')
}

// Redo: the history the model is told the app was made for leaves out what the old widget was asked to show.
{
  const {withoutWidgetRequests, WIDGET_ASK_TEXT} = loadVera('ProjectText')
  const mark = '\n\nRefinement:\n'
  const history = 'Tambourine' + mark + WIDGET_ASK_TEXT + 'a stick that hits it' + mark + 'Make it louder' + mark +
    WIDGET_ASK_TEXT + 'bigger stick'
  assert.equal(withoutWidgetRequests(history), 'Tambourine' + mark + 'Make it louder')
  assert.equal(withoutWidgetRequests('Tambourine'), 'Tambourine')
  console.log('widget-status-check: redo history ok')
}

// Remove widget: a new version without the widget, its refresh and what only they use; the app and its requests stay.
{
  const {removeWidget, WIDGET_REMOVED_NOTE} = loadVera('WidgetRemove')
  const {WIDGET_ASK_TEXT} = loadVera('ProjectText')
  const mark = '\n\nRefinement:\n'
  const app = [
    'import * as ui from "std/ui"',
    '@jsonable class AppState { count: number; }',
    'function init(): AppState { return { count: 0 }; }',
    'function bump(state: AppState, value: number): AppState { return { count: state.count + value }; }',
    'function view(state: AppState): ui.View { return ui.Column("default", [ui.NumberText("metric", state.count, "", "", 0), ui.Button("primary", "+1", "bump", 1, true)]); }',
  ].join('\n') + '\n'
  const withCard = app + '\nfunction cardLine(state: AppState): string { return ui.numberToString(state.count); }\n' +
    'function widget(state: AppState): ui.View { return ui.Text("body", cardLine(state)); }\n'
  const removed = removeWidget(withCard, 'Counter' + mark + WIDGET_ASK_TEXT + 'the count' + mark + 'Make it blue')
  assert.equal(removed.error, '')
  assert.equal(hasWidgetFunction(removed.source), false)
  assert.ok(!/cardLine/.test(removed.source) && /function view\(/.test(removed.source))
  assert.equal(removed.vbc2, compileVeraSource(removed.source).vbc2)
  assert.equal(removed.prompt, 'Counter' + mark + 'Make it blue')
  assert.equal(widgetStatus(removed.source, removed.vbc2, 1).kind, 'broken', 'a card left on the home screen shows "Open app"')
  assert.equal(widgetStatus(removed.source, removed.vbc2, 0).kind, 'none')
  assert.notEqual(removeWidget(app, 'Counter').error, '', 'nothing to remove')
  assert.ok(WIDGET_REMOVED_NOTE.length > 0)
  console.log('widget-status-check: remove widget ok')
}
