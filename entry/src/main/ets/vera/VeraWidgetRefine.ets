import { CATALOG, describeComponents } from './VeraUiCatalog'
import { widgetRefinementError } from './VeraCompiler'
import { VirtualMachine, deserializeVbc2, decodeRuntimeValue } from './VeraInterpreter'
import { decodeVeraUi, UiHostEnvironment } from './VeraUi'
import { WidgetSession, CardNode, SourceRequest, LIVE_MAX_DEPTH, LIVE_MAX_NODES, LIVE_MAX_TEXT, LIVE_MAX_COMMANDS, CARD_MOTIONS, LIVE_MAX_MOTIONS, LIVE_MAX_SURFACES, LIVE_MAX_SHAPES, PICTURE_SIDE_MIN, pictureRoom, widgetHeight, cardSize, LIVE_MAX_JSON, LIVE_MAX_STEPS } from './VeraLiveWidget'

/** The components a card draws: only these are shown to the widget writer, and only these may a widget use. */
export const CARD_KINDS: string[] = CATALOG.filter((component): boolean => component.card).map((component): string => component.name)

/**
 * Only Make widget receives these instructions. Fullscreen UI is not restricted.
 *
 * The person's request says what the widget shows ("The home-screen widget should show: ..."); this says what a widget is:
 * a second, small view of the same state, read at a glance, with only the few things that matter most.
 */
export function widgetRefinementPrompt(whole: boolean = true): string {
  return (whole ? 'Add a home-screen widget to this existing program. Return the complete program.\n' :
    'Write a home-screen widget for this existing program.\n') +
    'The widget is a second view of the same app: function widget(state) draws the very state view(state) draws, on a small ' +
    'card on the phone\'s home screen. The person\'s request says what it should show; follow it. ' +
    'A widget is read at a glance, in a second: show only the few things that matter most -- one to three figures or short ' +
    'lines, each with a label of a word or two -- and at most two buttons, for the actions worth doing without opening the app. ' +
    'Leave out everything else: lists and history, settings, inputs, explanations, and the app\'s name or any title or ' +
    'heading -- the space is too small for them. When the request asks for more than fits, keep what matters most and drop ' +
    'the rest. If the program already has a widget, replace it with the one asked for.\n' +
    'The card is redrawn about every 30 minutes without the app being opened, so a figure widget works out from the clock ' +
    '(time left until something) stays current by itself. If the state itself goes out of date with the time -- the day\'s ' +
    'figures start again after midnight, a countdown that is over should end, a streak breaks after a missed day -- also add ' +
    'function widgetRefresh(state: the init return type): the init return type. The card runs it before redrawing, and the ' +
    'app when it opens and when it comes back, and both save what it returns: bring the state up to date with the clock ' +
    '(std/time) and return it, changing only ' +
    'what the time has made out of date. Running it twice in a row must give the same state as running it once, so never ' +
    'add to a figure in it. No phone effects, but one: if the program gets live figures with sdk.call("Vera.Source.fetch", ...), ' +
    'widgetRefresh makes that same call, copied exactly with the same handler, and returns the state; the card makes the call ' +
    'and passes the answer to that handler before it redraws, so the card shows the figures as they are now. A button may ' +
    'make the same call (a Refresh), the same way. A program that reads its figures off a search (sdk.call("Vera.Live.fetch", ' +
    '...)) is not refreshed on the card -- a search is too slow for it -- so neither widgetRefresh nor a widget button makes ' +
    'that call: the widget shows the figures the app fetched last, with their time, and no Refresh button. ' +
    'Leave widgetRefresh out when nothing in the state goes out of date.\n' +
    (whole ? 'Preserve every existing class, init, view and handler unchanged, including their signatures and bodies. ' +
    'Add or replace only function widget(state: the init return type): ui.View, widgetRefresh, and new uniquely named ' +
    'helpers/number handlers. ' : WIDGET_ONLY) +
    'Share the existing state; do not add fields or reset data. ' +
    'Keep the existing import lines; add import * as time from "std/time" only if widget or widgetRefresh reads the clock. ' +
    'If an action needs SDK/intent effects, omit it. Do not add a button that opens the app: a tap on the card outside a ' +
    'button already does. ' +
    'widget must be synchronous and side-effect free, with no ticker, scrolling, inputs, images, or networking. ' +
    'Use ONLY the card-safe constructors below in widget and its helpers; the fullscreen view keeps its full catalogue. ' +
    'AppTheme is optional and root-only; light theme only. The whole 2x2 card is the widget\'s; nothing is drawn above it. ' +
    'Prefer one Column with a summary and one Row of buttons; avoid long lists. ' +
    'WHAT TO DRAW WITH. A drawing of the subject the person asks for -- an animal, a face, a character, a scene, a gauge, ' +
    'anything of more than one colour -- is a ui.Surface (below), NEVER a ui.Path: a Path is ONE shape in ONE colour, and a ' +
    'Path of several shapes comes out as one flat blob with its eyes and ears lost. Use ui.Path only for a single-colour icon or ' +
    'symbol (up to ' + LIVE_MAX_COMMANDS.toString() + ' characters of path data, M L C Q A Z in a 100x100 box). ' +
    'ui.Surface(style, width, height, "draw", "", "touch") draws a picture of several shapes of several colours. width and height ' +
    'are the picture\'s own units (100 by 100 is usual); draw is a function you write, (state: the init return type): ' +
    'gfx.Shape[], that returns its shapes back to front (gfx.circle, gfx.rect, gfx.roundRect, gfx.arc, gfx.polygon, gfx.path ...: ' +
    'the faces of an animal are circles; give each part its own colour, "#rrggbb" or a role like "accent"); touch is a function ' +
    '(state: the init return type, p: gfx.Pointer): the init return type that runs when the picture is touched (p.phase is ' +
    '"down", then "up"), or "" for a picture that is only looked at. The third argument must be "": a card has no frames, the picture ' +
    'is drawn once for each state. The card is about 150 vp tall: the picture takes what the rest leaves (it is shrunk to fit), so ' +
    'put at most one figure or one short line beside it, with no buttons. At most ' + LIVE_MAX_SHAPES.toString() + ' shapes and ' + LIVE_MAX_SURFACES.toString() +
    ' ui.Surface. A picture or shape that takes a touch counts as one of the two buttons. A handler the card runs must not make phone calls ' +
    '(no sdk.call): when the app\'s own handler vibrates, plays a sound or the like, write a new handler that only changes the ' +
    'state -- or returns it as it is. ' +
    'MOVEMENT. A thing that is drawn should DO what that thing does, once, when it is touched (or when the state changes): wrap it in ' +
    'ui.Motion(style, 0, [the picture]) and every touch on the picture inside plays the movement by itself, whether or not the handler ' +
    'changed the state. The style is chosen by the movement the thing makes, never by its looks: ' + CARD_MOTIONS.join(', ') + '. By meaning -- ' +
    'emphasis (stays in place): pop swells, pulse beats twice, jelly squashes and wobbles, press dips like a pushed button, flash blinks, breathe ' +
    'swells slowly; reaction: shake sideways, nod up and down, wobble rocks on its base, swing hangs from its top edge like a pendulum, ' +
    'recoil is a sharp kick; gravity: bounce drops in and settles, hop jumps once, jump crouches then leaps and lands, fall drops in from above; ' +
    'turning: spin turns twice and slows (a wheel, a dial, a fan), turn one quick whole turn, tumble spins and hops, flip turns into view; ' +
    'arrival: fade, rise, zoom, slide; ambient: float, drift (slow, gentle). Ask what the thing does when touched and take the movement ' +
    'for that: something hit shakes or recoils, something turned spins, something alive hops or jumps, something hanging swings, ' +
    'something pushed presses. A touch that does nothing visible is a defect: every picture the person can touch moves. Several things ' +
    'move at once when each has its own ui.Motion around its own picture (at most ' + LIVE_MAX_MOTIONS.toString() + ' ui.Motion in all; ' +
    'put the pictures side by side or one above the other, there is no overlap). Do NOT add a counter to the state just for the movement ' +
    '(the state cannot grow). The second argument is 0, or a number the state really changes with, which then also plays it. A movement ' +
    'lasts about a second and plays once: a card cannot loop, spin forever or repeat, there is no sound or vibration, and a drawing is a ' +
    'picture of one moment, so draw the subject at its most recognisable, not a scene that needs motion to be understood. ' +
    'LAYERS. A subject made of parts that move differently -- something that hits and something that is hit, a sky with weather in front ' +
    'of it, a body with a part that swings -- is drawn as ui.Layers(style, width, height, [back, ..., front]): the children lie one over another, ' +
    'the first at the bottom, each in the middle, and each can be its own ui.Motion(style, 0, [ui.Surface(...)]) so the parts move ' +
    'separately. Give every ui.Surface in one ui.Layers the same width and height as the ui.Layers and draw each part where it belongs ' +
    'in that box (its own function, only its part), so they line up; every ui.Surface above the first has the style "clear" (no background of its own: without it it hides the layers under it). A touch on any layer plays that layer\'s own movement. ' +
    'Draw exactly the subject the person asked for; do not reuse a shape from these instructions. '+
    'STYLES. A text style is drawn as the app draws it, with the theme\'s weight, font and colour: display, title, heading, body, caption ' +
    '(small), eyebrow (a small spaced label above something), metric (a big figure), muted (quiet), success, warning, danger (toned). ' +
    'A column\'s style: default or center (centred), end (to the right), compact or spacious (the gap between its children), surface or ' +
    'accent (a panel with a fill, padding and rounded corners -- for the one thing to look at). A row\'s: default or center (spread ' +
    'evenly), split (first at the left, last at the right), end, joined (touching), compact or spacious, surface or accent. Buttons: ' +
    'primary, secondary, success, danger. Use the roles instead of one size for everything: a label, a figure, a caption. ' +
    'ICONS AND DATA. ui.Icon(style, name) and ui.IconButton(style, icon, label, handler, value, enabled) (a button: one of the two) draw ' +
    'the catalogue\'s icons; ui.Badge(style, text, icon) is a small label; ui.Progress(style, label, value, max) is a bar and ' +
    'ui.ProgressRing(style, label, value, max, text) a ring (about 52 vp) for how far along a goal is; ui.Stat(style, label, text, supporting, icon) and ' +
    'ui.NumberStat(...) are a labelled figure, and ui.MetricGroup(style, columns, [stats]) puts a few side by side; ui.Sparkline(series, max, ...) is ' +
    'a small trend (a picture: it counts among the three pictures, about 80 by 29 vp). Prefer these to drawing the same thing by hand, ' +
    'and mind the height: a ring and a row of buttons fit, a ring, a chart and a stat row do not.\n' +
    'TIME THAT MOVES. ui.Timer(style, millis, down) runs by itself on the card, with no refresh: counting up from the moment millis (a stopwatch, ' +
    '"since" something began) or, with down true, down to it ("left until"); millis is milliseconds since 1970 (time.nowMillis() plus or minus a ' +
    'length, kept in the state as a number). Prefer it to a figure computed from the clock, which stands still between redraws.\n' +
    'CARD SIZES. The card is 2x2 by default (about 150 vp square). Declare function widget(state, size: number): ui.View to draw differently on a ' +
    'wider card: size is 2 for 2x2, 3 for 2x4 (wide: about 324 x 148 vp, four columns, two rows) and 4 for 4x4 (about 324 x 340 vp). On a bigger card show ' +
    'more -- a 2x4 has room for up to 4 buttons and 12 texts, a 4x4 for 6 buttons and 24 texts, and bigger pictures -- but only what the person asked for; ' +
    'a widget with one parameter is drawn the same on every size, centred. The limits below are the 2x2 card\'s.\n' +
    'SWITCHES. ui.Toggle(style, label, checked, handler) and ui.Checkbox(style, label, checked, handler) are a tap that says on or off: the handler takes ' +
    '(state, value: boolean). Each counts as a button, and a handler is told only on or off, never which box it was: use one for a single setting, not one per item.\n' +
    'Limits: depth ' + LIVE_MAX_DEPTH.toString() + ' excluding root AppTheme, ' + LIVE_MAX_NODES.toString() +
    ' nodes, ' + LIVE_MAX_TEXT.toString() + ' UTF-16 characters/text, ' + LIVE_MAX_JSON.toString() +
    ' UTF-16 units/frame including state token, ' + LIVE_MAX_STEPS.toString() + ' VM steps/entry.\n' +
    (whole ? describeComponents(CARD_KINDS) : '')
}

/**
 * The answer when only the widget is written (AgentWidget): the program around it is kept as it is, so nothing of it is
 * written again -- most of what made the whole-program reply slow.
 */
const WIDGET_ONLY: string = 'Answer with only what the widget adds, in one fenced block: function widget(state: the init ' +
  'return type): ui.View, widgetRefresh when it is needed, new uniquely named helpers or number handlers, and an import line ' +
  'only when it is new. Do not write anything else of the program again: its classes, init, view and handlers stay exactly ' +
  'as they are and cannot be changed from here. '

/** A widget is read at a glance: what widgetRefinementPrompt asks for, held to. */
export const WIDGET_MAX_BUTTONS: number = 2
export const WIDGET_MAX_TEXTS: number = 8

/** Structural preservation is checked separately from runtime validation so repair gets precise feedback. */
export function validateWidgetRefinement(base: string, source: string, vbc2: string, saved: string = ''): string {
  try {
    let preservation = widgetRefinementError(base, source)
    if (preservation.length > 0) { return preservation }
    let runtime = checkWidget(vbc2, saved)
    if (runtime.length > 0) { return runtime }
    // A widget that asks for the card's size is held to the limits of each size it will be drawn on.
    let sizes: number[] = new WidgetSession(vbc2, 'validation', saved).takesSize() ? [2, 3, 4] : [2]
    for (let dimension of sizes) {
      let problem = glanceError(vbc2, saved, dimension)
      if (problem.length > 0) { return problem }
    }
    return ''
  } catch (e) { return 'Widget validation: ' + (e as Error).message }
}

/**
 * More than a glance: too many buttons or lines for the few things a widget shows. Only Make widget is held to it; the card
 * itself draws any frame within its budget. Said so the model can cut the widget down on the next attempt.
 */
function glanceError(vbc2: string, saved: string, dimension: number = 2): string {
  let frame = new WidgetSession(vbc2, 'validation', saved).frame('project', 'App', '', dimension)
  let buttons = 0
  let texts = 0
  let count = (nodes: CardNode[]): void => {
    for (let node of nodes) {
      if (node.kind === 'button' || node.kind === 'iconbutton' || node.kind === 'toggle' || node.kind === 'checkbox' || (node.kind === 'path' && node.action.length > 0) || (node.kind === 'surface' && node.pointer.length > 0)) { buttons++ } else if (node.kind === 'path' || node.kind === 'surface' || node.kind === 'icon' || node.kind === 'badge' || node.kind === 'progress' || node.kind === 'ring') { /* a drawing or a mark, not a line of text */ } else if (node.text.length > 0) { texts++ }
      count(node.children)
    }
  }
  count(frame.nodes)
  let size = cardSize(frame.dimension)
  if (buttons > size.maxButtons) {
    return 'The widget has ' + buttons.toString() + ' buttons; a ' + size.label + ' widget has at most ' + size.maxButtons.toString() +
      ', for the actions that matter most. Not one per item: drop the rest, they stay in the app.'
  }
  if (texts > size.maxTexts) {
    return 'The widget shows ' + texts.toString() + ' texts; a ' + size.label + ' widget shows at most ' + size.maxTexts.toString() +
      ' (one to three figures with short labels). No lists or history: keep what matters most, the rest stays in the app.'
  }
  // A picture needs room: everything else on the card, counted by its height, must leave it a few dozen vp.
  if (pictureRoom(frame) !== 0 && pictureRoom(frame) < PICTURE_SIDE_MIN) {
    return 'The widget has too much around its picture: the card is about 150 vp tall and the picture needs at least ' +
      PICTURE_SIDE_MIN.toString() + ' of it, but the figures, texts and buttons leave ' + Math.max(0, pictureRoom(frame)).toString() +
      '. Keep one short line of text (one figure with a label of a word) or none, and no buttons beside the picture.'
  }
  // Taller than the card: what does not fit is cut off at the card's edge. The estimate is rough, so only what is clearly too tall is refused.
  if (widgetHeight(frame) > size.height + 14) {
    return 'The widget is about ' + Math.round(widgetHeight(frame)).toString() + ' vp tall and the ' + size.label + ' card is ' + size.height.toString() +
      ' inside its padding: what does not fit is cut off. Drop a line, a button or a figure, or shorten the texts (a text over two lines is cut).'
  }
  return ''
}

function phoneCallMessage(handler: string): string {
  return 'The handler "' + handler + '" makes a phone call (sdk.call: a vibration, a sound, a notification...), and ' +
    'the home-screen card is not allowed to: the tap is refused and nothing changes. Write a NEW handler with its own ' +
    'name (not one the app has) that does only the state change -- for a hit counter, add one to the count and leave ' +
    'out the vibration -- and give the widget that handler.'
}

/** Also used by smokeRun for any program that declares widget. Never executes phone effects. */
export function checkWidget(vbc2: string, saved: string = ''): string {
  try {
    let session = new WidgetSession(vbc2, 'validation', saved)
    let frame = session.frame('project', 'App', '')
    if (!frame.live) { return 'Missing function widget(state): ui.View' }
    if (session.takesSize()) { session.frame('project', 'App', '', 3); session.frame('project', 'App', '', 4) }
    let state = session.encodedState()
    // Each actual visible button, twice: includes distinct repeated-row payloads and redraw validation.
    let buttons: CardNode[] = []
    let collect = (nodes: CardNode[]): void => {
      for (let node of nodes) {
        if ((node.kind === 'button' || node.kind === 'path' || node.kind === 'iconbutton') && node.enabled && node.action.length > 0) { buttons.push(node) }
        collect(node.children)
      }
    }
    collect(frame.nodes)
    // Each picture that takes a tap, twice, in the middle: its pointer handler must run and the state must still draw.
    let pictures: CardNode[] = []
    let collectPictures = (nodes: CardNode[]): void => {
      for (let node of nodes) {
        if (node.kind === 'surface' && node.pointer.length > 0) { pictures.push(node) }
        collectPictures(node.children)
      }
    }
    collectPictures(frame.nodes)
    // Each switch, turned on and off: its handler must run and the state must still draw.
    let switches: CardNode[] = []
    let collectSwitches = (nodes: CardNode[]): void => {
      for (let node of nodes) {
        if ((node.kind === 'toggle' || node.kind === 'checkbox') && node.enabled && node.action.length > 0) { switches.push(node) }
        collectSwitches(node.children)
      }
    }
    collectSwitches(frame.nodes)
    for (let item of switches) {
      let branch = new WidgetSession(vbc2, 'validation', state)
      for (let pass = 0; pass < 2; pass++) {
        let current = branch.frame('project', 'App', '')
        try {
          branch.tapSwitch(current, current.token, item.action, pass === 0)
        } catch (e) {
          if (/phone action required/.test((e as Error).message)) { return phoneCallMessage(item.action) }
          throw (e as Error)
        }
        branch.frame('project', 'App', '')
        let host = new UiHostEnvironment()
        let vm = new VirtualMachine(deserializeVbc2(vbc2), host, LIVE_MAX_STEPS)
        decodeVeraUi(vm.execute('view', [decodeRuntimeValue(JSON.parse(branch.encodedState()) as Object)]))
      }
    }
    let refreshError = checkRefresh(vbc2, state)
    if (refreshError.length > 0) { return refreshError }
    for (let picture of pictures) {
      let branch = new WidgetSession(vbc2, 'validation', state)
      for (let pass = 0; pass < 2; pass++) {
        let current = branch.frame('project', 'App', '')
        try {
          branch.tapSurface(current, current.token, picture.pointer, picture.w / 2, picture.h / 2)
        } catch (e) {
          if (/phone action required/.test((e as Error).message)) { return phoneCallMessage(picture.pointer) }
          throw (e as Error)
        }
        branch.frame('project', 'App', '')
        let host = new UiHostEnvironment()
        let vm = new VirtualMachine(deserializeVbc2(vbc2), host, LIVE_MAX_STEPS)
        decodeVeraUi(vm.execute('view', [decodeRuntimeValue(JSON.parse(branch.encodedState()) as Object)]))
      }
    }
    for (let button of buttons) {
      let branch = new WidgetSession(vbc2, 'validation', state)
      for (let pass = 0; pass < 2; pass++) {
        let current = branch.frame('project', 'App', '')
        let available = (nodes: CardNode[]): boolean => nodes.some((node: CardNode): boolean =>
          ((node.kind === 'button' || node.kind === 'path' || node.kind === 'iconbutton') && node.enabled && node.action === button.action && node.value === button.value) || available(node.children))
        if (!available(current.nodes)) { break }
        // A Refresh button's live source is not fetched here: its handler is given a failure, which it must take and still draw.
        let requests: SourceRequest[] = []
        try {
          requests = branch.tap(current, current.token, button.action, button.value)
        } catch (e) {
          if (/phone action required/.test((e as Error).message)) { return phoneCallMessage(button.action) }
          throw (e as Error)
        }
        for (let request of requests) {
          branch.answer(request.handler, 'error: the source is not reached while checking')
        }
        branch.frame('project', 'App', '')
        let host = new UiHostEnvironment()
        let vm = new VirtualMachine(deserializeVbc2(vbc2), host, LIVE_MAX_STEPS)
        // The same state must still draw in the app, not only on the card.
        decodeVeraUi(vm.execute('view', [decodeRuntimeValue(JSON.parse(branch.encodedState()) as Object)]))
      }
    }
    return ''
  } catch (e) { return 'Widget validation: ' + (e as Error).message }
}

/**
 * A widget that reads or builds state the app does not keep (E2031 no such field, E2022 unknown field). The reply's changes to
 * the app's own declarations are dropped (spliceWidget), so adding the field again cannot work: the next attempt is told so.
 */
export function widgetRepairNote(errors: string): string {
  if (!/\bE20(31|22)\b/.test(errors)) { return errors }
  return 'The widget cannot add fields to the state or change the app\'s existing classes and functions: they are kept ' +
    'exactly as the app has them, and any change to them is dropped. Show and change only what the state already holds; ' +
    'leave out what it does not.\n' + errors
}

/**
 * widgetRefresh, as the card runs it: twice from the saved state. Both times the widget and the app still draw it, and the
 * second run changes nothing the first did not -- the card may run it any number of times. A clock reading the program keeps
 * (a timestamp in ms) may differ between the two runs by up to a minute.
 */
function checkRefresh(vbc2: string, saved: string): string {
  let session = new WidgetSession(vbc2, 'validation', saved)
  if (!session.refreshes()) { return '' }
  let states: string[] = []
  for (let run = 0; run < 2; run++) {
    // A live source is not fetched here: its handler is given a failure, which it must take and still draw.
    for (let request of session.refresh()) { session.answer(request.handler, 'error: the source is not reached while checking') }
    session.frame('project', 'App', '')
    let host = new UiHostEnvironment()
    let vm = new VirtualMachine(deserializeVbc2(vbc2), host, LIVE_MAX_STEPS)
    decodeVeraUi(vm.execute('view', [decodeRuntimeValue(JSON.parse(session.encodedState()) as Object)]))
    states.push(session.encodedState())
  }
  if (!sameState(JSON.parse(states[0]) as Object, JSON.parse(states[1]) as Object)) {
    return 'widgetRefresh changed the state again when run a second time. The card runs it about every 30 minutes, any ' +
      'number of times: bring the state up to date with the clock (a new day starts the day\'s figures again, a countdown ' +
      'that is over ends), so that running it twice gives the same state as running it once. Never add to a figure in it.'
  }
  return ''
}

/** Two encoded states alike, but for timestamps (std/time.nowMillis over 1e12, nowSeconds over 1e9) under a minute apart. */
function sameState(a: Object | null, b: Object | null): boolean {
  if (typeof a === 'number' && typeof b === 'number') {
    let x = a as number
    let y = b as number
    return x === y || (x > 1e12 && y > 1e12 && Math.abs(x - y) < 60000) ||
      (x > 1e9 && y > 1e9 && x < 1e11 && y < 1e11 && Math.abs(x - y) < 60)
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    let left = a as Object[]
    let right = b as Object[]
    return left.length === right.length && left.every((item: Object, i: number): boolean => sameState(item, right[i]))
  }
  if (a !== null && b !== null && typeof a === 'object' && typeof b === 'object') {
    let left = a as Record<string, Object>
    let right = b as Record<string, Object>
    let keys = Object.keys(left)
    return keys.length === Object.keys(right).length && keys.every((key: string): boolean => sameState(left[key], right[key]))
  }
  return a === b
}
