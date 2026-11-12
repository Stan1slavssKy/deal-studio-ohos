import { CATALOG, describeComponents } from './VeraUiCatalog'
import { widgetRefinementError } from './VeraCompiler'
import { decodeGfxOps, GfxOp } from './GfxPaint'
import { appMovingPart, coloursOf, pointsOf, IDENTITY, MovingPart } from './VeraMovingPart'
import { pictureCovers, pictureBare, CARD_PADDING } from '../widget/CardModel'
import { VirtualMachine, deserializeVbc2, decodeRuntimeValue } from './VeraInterpreter'
import { decodeVeraUi, UiHostEnvironment, VeraUiNode } from './VeraUi'
import { WidgetSession, CardNode, LiveFrame, SourceRequest, LIVE_MAX_DEPTH, LIVE_MAX_TEXT, LIVE_MAX_COMMANDS, CARD_MOTIONS, CARD_DIMENSIONS, LIVE_MAX_MOTIONS, LIVE_MAX_SURFACES, LIVE_MAX_SHAPES, PICTURE_SIDE_MIN, pictureRoom, widgetHeight, cardSize, LIVE_MAX_JSON, LIVE_MAX_STEPS, SETTLE_MAX_STEPS, SETTLE_STEP_MS } from './VeraLiveWidget'

/** The card a widget is written for first: a widget with one parameter is drawn at this size on every card. */
const SMALL = cardSize(2)
/** How many of something, in words a sentence can take ("two buttons"). */
function counted(n: number): string {
  let words = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten']
  return n >= 0 && n < words.length ? words[n] : n.toString()
}

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
    'lines, each with a label of a word or two -- and at most ' + counted(SMALL.maxButtons) + ' buttons, for the actions worth doing without opening the app. ' +
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
    'AppTheme is optional and root-only; light theme only. The whole ' + SMALL.label + ' card is the widget\'s; nothing is drawn above it. ' +
    'Prefer one Column with a summary and one Row of buttons; avoid long lists. ' +
    'WHAT TO DRAW WITH. A drawing of the subject the person asks for -- an animal, a face, a character, a scene, a gauge, ' +
    'anything of more than one colour -- is a ui.Surface (below), NEVER a ui.Path: a Path is ONE shape in ONE colour, and a ' +
    'Path of several shapes comes out as one flat blob with its eyes and ears lost. Use ui.Path only for a single-colour icon or ' +
    'symbol (up to ' + LIVE_MAX_COMMANDS.toString() + ' characters of path data, M L C Q A Z in a 100x100 box). ' +
    'ui.Surface(style, width, height, "draw", "", "touch") draws a picture of several shapes of several colours. width and height ' +
    'are the picture\'s own units (100 by 100 is usual); draw is a function you write, (state: the init return type): ' +
    'gfx.Shape[], that returns its shapes back to front (gfx.circle, gfx.rect, gfx.roundRect, gfx.arc, gfx.sector, gfx.polygon, gfx.path ...: ' +
    'the faces of an animal are circles; give each part its own colour, "#rrggbb" or a role like "accent"); touch is a function ' +
    '(state: the init return type, p: gfx.Pointer): the init return type that runs when the picture is touched (p.phase is ' +
    '"down", then "up"), or "" for a picture that is only looked at. The third argument must be "": a card has no frames, the picture ' +
    'is drawn once for each state. The card is about 150 vp tall: the picture takes what the rest leaves (it is shrunk to fit), so ' +
    'put at most one figure or one short line beside it, with no buttons. At most ' + LIVE_MAX_SHAPES.toString() + ' shapes and ' + LIVE_MAX_SURFACES.toString() +
    ' pictures (ui.Surface or ui.Sparkline) in all; many of the same (bubbles, bricks, stars in a grid) is one gfx.repeat(columns, rows, dx, dy, [the shapes of one]), ' +
    'which counts its shapes once whatever the copies. A picture or shape that takes a touch counts as one of the ' + counted(SMALL.maxButtons) + ' buttons. A handler the card runs must not make phone calls ' +
    '(no sdk.call): when the app\'s own handler vibrates, plays a sound or the like, write a new handler that only changes the ' +
    'state -- or returns it as it is. ' +
    'MOVING PARTS. Only what moves in life moves: a pendulum\'s bob swings and its clock stays, a wheel spins under a pointer that stays, a ' +
    'punching bag swings from a hook that stays, a frog jumps and its pond stays, a rocket launches and the sky stays. In such a picture ' +
    'wrap just that part\'s shapes in gfx.moving(style, 0, pivotX, pivotY, [shapes]) among the shapes the draw function returns, with the pivot ' +
    'where the part hangs, turns or stands (the pendulum\'s top, the wheel\'s centre, the frog\'s feet), and leave the rest -- the background, ' +
    'the frame, the pointer, the hook -- outside it. A touch anywhere on the picture plays every part; up to three parts in a picture. A picture ' +
    'with gfx.moving is not also wrapped in a ui.Motion. A wheel, a pie or a pizza is slices of gfx.sector, each starting where the last ended. ' +
    'The pattern, in a clock and in a wheel:\n' +
    '  shapes.push(gfx.roundRect(25, 5, 50, 90, 8, "#7c4a2d"));  // the clock case stays\n' +
    '  shapes.push(gfx.moving("swing", 0, 50, 15, [gfx.line(50, 15, 50, 62, 2, "#d4a64a"), gfx.circle(50, 68, 8, "#e0b34a")]));  // rod and bob swing from the top\n' +
    '  let colours: string[] = ["#f87171", "#fbbf24", "#34d399", "#60a5fa", "#a78bfa", "#f472b6"];\n' +
    '  let slices: gfx.Shape[] = [];\n' +
    '  let i: number = 0;\n' +
    '  while (i < 6) { slices.push(gfx.sector(50, 52, 40, i * 60, 60, colours[i])); i = i + 1; }\n' +
    '  shapes.push(gfx.moving("spin", 0, 50, 52, slices));  // the slices turn about the wheel\'s centre\n' +
    '  shapes.push(gfx.polygon([44, 4, 56, 4, 50, 16], "#1f2937"));  // the pointer stays\n' +
    'MOVEMENT. A thing that is drawn should DO what that thing does, once, when it is touched (or when the state changes): in a picture with ' +
    'other things around it, gfx.moving (above); a picture that is only the thing itself, with nothing that should stay, a figure or an icon: ' +
    'ui.Motion(style, 0, [the picture]). Every touch on the picture plays the movement by itself, whether or not the handler ' +
    'changed the state. The style is chosen by the movement the thing makes, never by its looks: ' + CARD_MOTIONS.join(', ') + '. By meaning -- ' +
    'emphasis (stays in place): pop swells, pulse beats twice, jelly squashes and wobbles, press dips like a pushed button, flash blinks, breathe ' +
    'swells slowly; reaction: shake sideways, nod up and down, wobble rocks on its base, swing hangs from its top edge like a pendulum, ' +
    'recoil is a sharp kick; gravity: bounce drops in and settles, hop jumps once, jump crouches then leaps and lands, fall drops in from above; ' +
    'turning: spin turns twice and slows (a wheel, a dial, a fan), turn one quick whole turn, tumble spins and hops, flip turns into view; ' +
    'arrival: fade, rise, zoom, slide; ambient: float, drift (slow, gentle); leaving: launch flies up out of sight and comes back from below ' +
    '(a rocket, a bird taking off), roll rolls away to the side and back (a ball, a wheel on the ground). Ask what the thing does when touched and take the movement ' +
    'for that: something hit shakes or recoils, something turned spins, something alive hops or jumps, something hanging swings, ' +
    'something pushed presses. A touch that does nothing visible is a defect: every picture the person can touch moves. Several things ' +
    'move at once when each has its own ui.Motion around its own picture (at most ' + LIVE_MAX_MOTIONS.toString() + ' ui.Motion in all; ' +
    'put the pictures side by side, one above the other, or one over another in a ui.Layers, below). Do NOT add a counter to the state just for the movement ' +
    '(the state cannot grow). The second argument is 0, or a number the state really changes with, which then also plays it. A movement ' +
    'lasts about a second and plays once: a ui.Motion or a gfx.moving cannot loop, spin forever or repeat (only a gfx.drift goes on, below), there is no sound or vibration, and a drawing is a ' +
    'picture of one moment, so draw the subject at its most recognisable, not a scene that needs motion to be understood. ' +
    'After a tap the card runs the app\'s own frame handlers for up to ' + Math.round(SETTLE_MAX_STEPS * SETTLE_STEP_MS / 1000).toString() + ' s, so what the tap ' +
    'set going comes to rest (a wheel stops on its prize, a die lands) and the card shows the result; what does not come to rest by then ' +
    'stays as the tap left it, so a button that waits for it would stay off -- give such a button a handler of its own that finishes at once. ' +
    'ALWAYS MOVING. What in life never stops -- clouds drifting, fish swimming, rain or snow falling, stars streaming past -- is ' +
    'gfx.drift(direction, speed, [shapes]) among the shapes the draw function returns: its shapes are a tile the size of the picture that slides ' +
    'on and on towards direction ("left", "right", "up", "down") at speed ("slow" for clouds and stars, "medium", "fast" for rain) and comes back ' +
    'in from the other side, so spread them across the whole picture. It is the one thing on a card that moves without a touch, so keep it ' +
    'gentle and to one or two in a widget, behind or in front of what stays (a sky, the moon, a tank, the fish that is touched). No gfx.blur ' +
    'inside a gfx.drift: the card draws a drift in slices, and a blur shows their seams. ' +
    'LAYERS. A subject made of parts that move differently -- something that hits and something that is hit, a sky with weather in front ' +
    'of it, a body with a part that swings -- is drawn as ui.Layers(style, width, height, [back, ..., front]): the children lie one over another, ' +
    'the first at the bottom, each in the middle, and each can be its own ui.Motion(style, 0, [ui.Surface(...)]) so the parts move ' +
    'separately. Give every ui.Surface in one ui.Layers the same width and height as the ui.Layers and draw each part where it belongs ' +
    'in that box (its own function, only its part), so they line up; every ui.Surface above the first has the style "clear" (no background of its own: without it it hides the layers under it). A touch anywhere on the scene plays all its movements. A tap runs the pointer handler of the topmost layer that has one under the finger, and a layer whose pointer is \"\" lets the touch through, so a scene needs one layer with a handler, not one in each. ' +
    'Draw exactly the subject the person asked for: the example above shows how parts move, it is not a drawing to copy for another subject. ' +
    'MAKE IT LOOK GOOD. Give things depth and light, as a painter would: a ball, a face, a fruit, a planet is a circle filled with ' +
    'gfx.radial (a light colour first, centred a little up and left of the middle, the darkest last); a sky, the sea or a wall is gfx.linear; ' +
    'something standing or floating has a soft gfx.shadow under it ("#00000055"); a lamp, a star, a magic spark is in a gfx.glow; ' +
    'lights that overlap are in gfx.blend("add", ...). A scene with its own background (a sky, a room, a sea) is ui.Surface("cover", ...): it ' +
    'fills the whole card edge to edge, under everything else, with the one short line of text over its bottom -- never a dark square ' +
    'in the middle of the card. A single object (a ball, a drum, a pet) is a "default" picture on the card\'s own colour, with no rect behind it. ' +
    'STYLES. A text style is drawn as the app draws it, with the theme\'s weight, font and colour: display, title, heading, body, caption ' +
    '(small), eyebrow (a small spaced label above something), metric (a big figure), muted (quiet), success, warning, danger (toned). ' +
    'A column\'s style: default or center (centred), end (to the right), compact or spacious (the gap between its children), surface or ' +
    'accent (a panel with a fill, padding and rounded corners -- for the one thing to look at). A row\'s: default or center (spread ' +
    'evenly), split (first at the left, last at the right), end, joined (touching), compact or spacious, surface or accent. Buttons: ' +
    'primary, secondary, success, danger. Use the roles instead of one size for everything: a label, a figure, a caption. ' +
    'ICONS AND DATA. ui.Icon(style, name) and ui.IconButton(style, icon, label, handler, value, enabled) (a button: one of the ' + counted(SMALL.maxButtons) + ') draw ' +
    'the catalogue\'s icons; ui.Badge(style, text, icon) is a small label; ui.Progress(style, label, value, max) is a bar and ' +
    'ui.ProgressRing(style, label, value, max, text) a ring (about 52 vp) for how far along a goal is; ui.Stat(style, label, text, supporting, icon) and ' +
    'ui.NumberStat(...) are a labelled figure, and ui.MetricGroup(style, columns, [stats]) puts a few side by side; ui.Sparkline(series, max, ...) is ' +
    'a small trend (a picture: it counts among the ' + counted(LIVE_MAX_SURFACES) + ' pictures, about 80 by 29 vp). Prefer these to drawing the same thing by hand, ' +
    'and mind the height: a ring and a row of buttons fit, a ring, a chart and a stat row do not.\n' +
    'TIME THAT MOVES. ui.Timer(style, millis, down) runs by itself on the card, with no refresh: counting up from the moment millis (a stopwatch, ' +
    '"since" something began) or, with down true, down to it ("left until"); millis is milliseconds since 1970 (time.nowMillis() plus or minus a ' +
    'length, kept in the state as a number). Prefer it to a figure computed from the clock, which stands still between redraws.\n' +
    'CARD SIZES. The card is ' + SMALL.label + ' by default (about 150 vp square). Declare function widget(state, size: number): ui.View to draw differently on a ' +
    'wider card: size is 2 for 2x2, 3 for 2x4 (wide: about 324 x 148 vp, four columns, two rows) and 4 for 4x4 (about 324 x 340 vp). On a bigger card show ' +
    'more -- ' + CARD_DIMENSIONS.filter((d: number): boolean => d !== SMALL.dimension).map((d: number): string => 'a ' + cardSize(d).label +
    ' has room for up to ' + cardSize(d).maxButtons.toString() + ' buttons and ' + cardSize(d).maxTexts.toString() + ' texts').join(', ') +
    ', and bigger pictures -- but only what the person asked for; ' +
    'a widget with one parameter is drawn the same on every size, centred. A scene is the shape of its card: on a 2x4 card a square picture ' +
    'leaves the sides empty, and a square cover picture loses its top and bottom, so a widget with a scene takes size and, for size 3, draws ' +
    'its picture wide (say 220 by 100 units, the subject in the middle and more of its world at the sides). The limits below are the ' + SMALL.label + ' card\'s.\n' +
    'SWITCHES. ui.Toggle(style, label, checked, handler) and ui.Checkbox(style, label, checked, handler) are a tap that says on or off: the handler takes ' +
    '(state, value: boolean). Each counts as a button, and a handler is told only on or off, never which box it was: use one for a single setting, not one per item.\n' +
    'Limits: depth ' + LIVE_MAX_DEPTH.toString() + ' excluding root AppTheme, ' + SMALL.maxNodes.toString() +
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

/** Structural preservation is checked separately from runtime validation so repair gets precise feedback. */
export function validateWidgetRefinement(base: string, source: string, vbc2: string, saved: string = ''): string {
  try {
    let preservation = widgetRefinementError(base, source)
    if (preservation.length > 0) { return preservation }
    return widgetProblem(vbc2, saved, true)
  } catch (e) { return 'Widget validation: ' + (e as Error).message }
}

/**
 * More than a glance: too many buttons or lines for the few things a widget shows. Only Make widget is held to it; the card
 * itself draws any frame within its budget. Said so the model can cut the widget down on the next attempt.
 */
function glanceError(frame: LiveFrame): string {
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
  let room = pictureRoom(frame)
  if (room !== 0 && room < PICTURE_SIDE_MIN) {
    return 'The widget has too much around its picture: the card is about 150 vp tall and the picture needs at least ' +
      PICTURE_SIDE_MIN.toString() + ' of it, but the figures, texts and buttons leave ' + Math.max(0, room).toString() +
      '. Keep one short line of text (one figure with a label of a word) or none, and no buttons beside the picture.'
  }
  // Taller than the card: what does not fit is cut off at the card's edge. The estimate is rough, so only what is clearly too tall is refused.
  let height = widgetHeight(frame)
  if (height > size.height + 14) {
    return 'The widget is about ' + Math.round(height).toString() + ' vp tall and the ' + size.label + ' card is ' + size.height.toString() +
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
    return widgetProblem(vbc2, saved, false)
  } catch (e) { return 'Widget validation: ' + (e as Error).message }
}

/**
 * The widget's first problem over `saved`, '' for none: it runs, its refresh and its taps work on every size it draws, and, with `glance`,
 * each size holds no more than a glance. One session, and one frame for each size, serve all of it.
 */
function widgetProblem(vbc2: string, saved: string, glance: boolean): string {
  let session = new WidgetSession(vbc2, 'validation', saved)
  let memo = new TapMemo()
  // Every size the widget draws differently is a card of its own (2x2 first): what can be tapped on it is tapped there.
  let frames = session.dimensions().map((dimension: number): LiveFrame => session.frame('project', 'App', '', dimension))
  if (!frames[0].live) { return 'Missing function widget(state): ui.View' }
  let state = session.encodedState()
  let refreshError = checkRefresh(vbc2, state)
  if (refreshError.length > 0) { return refreshError }
  for (let frame of frames) {
    let problem = checkTaps(vbc2, state, frame.nodes, frame.dimension, memo)
    if (problem.length > 0) { return problem }
  }
  // A widget that asks for the card's size is held to the limits of each size it will be drawn on.
  for (let frame of glance ? frames : []) {
    let problem = glanceError(frame)
    if (problem.length > 0) { return problem }
  }
  return glance ? (movingSceneError(frames[0].nodes) || movingPartError(vbc2, state, frames[0].nodes) || backgroundError(frames[0].nodes) ||
    coverTextError(frames, session.takesSize()) ||
    deadPicture(vbc2, state, frames[0].nodes) ||
    unseenTouch(vbc2, state, frames[0], memo)) : ''
}

/** The card sizes as their dimension numbers, in the order a reason names them. */
const COVER_CHECK_SIZES: number[] = [2, 3, 4]

/**
 * A text drawn in a cover picture that the card cuts off: a cover picture fills the card, so a square one shows only its middle band on
 * a wide 2x4 card (y 27 to 73 of 100) and its middle on a 4x4. A generated frog drew its score at the bottom of its pond (y 92), and on a
 * 2x4 card the score was gone. Each size the widget is drawn at is looked at: its own frame when it takes the size, else the one frame
 * on every size. Only text is held to it; a scene's edges may well be cut.
 */
function coverTextError(frames: LiveFrame[], sized: boolean): string {
  for (let frame of frames) {
    let sizes = sized ? [frame.dimension] : COVER_CHECK_SIZES
    let covers = collectNodes(frame.nodes, (node: CardNode): boolean => node.kind === 'surface' && pictureCovers(node.style))
    for (let picture of covers) {
      let texts: GfxOp[] = []
      let walk = (ops: GfxOp[]): void => {
        for (let o of ops) {
          if (o.kind === 'text' && o.text.length > 0 && o.size > 0) { texts.push(o) }
          // Children drawn where they are written; a group moves and turns them, a repeat copies them: not followed.
          if (o.kind === 'fx' || o.kind === 'moving') { walk(o.children) }
        }
      }
      walk(decodeGfxOps(picture.ops))
      for (let dimension of sizes) {
        let card = cardSize(dimension)
        let boxW = card.width + 2 * CARD_PADDING
        let boxH = card.height + 2 * CARD_PADDING
        let scale = Math.max(boxW / picture.w, boxH / picture.h)
        let x0 = (picture.w - boxW / scale) / 2
        let y0 = (picture.h - boxH / scale) / 2
        let slack = 0.02 * Math.max(picture.w, picture.h)
        for (let t of texts) {
          let wide = t.text.length * t.size * (t.bold ? 0.6 : 0.55)
          let left = t.align === 'center' ? t.x - wide / 2 : t.align === 'right' ? t.x - wide : t.x
          let cut = left < x0 - slack || left + wide > picture.w - x0 + slack || t.y - t.size / 2 < y0 - slack ||
            t.y + t.size / 2 > picture.h - y0 + slack
          if (cut) {
            let round = (v: number): string => (Math.round(10 * v) / 10).toString()
            return 'The text "' + t.text + '" drawn in the cover picture is cut off on a ' + card.label + ' card: a cover picture fills the ' +
              'card, so of its ' + round(picture.w) + ' x ' + round(picture.h) + ' units only x ' + round(Math.max(0, x0)) + ' to ' +
              round(picture.w - Math.max(0, x0)) + ', y ' + round(Math.max(0, y0)) + ' to ' + round(picture.h - Math.max(0, y0)) +
              ' are seen there. Show it as a ui.Text in the widget\'s column instead (it is drawn over the bottom of the picture, where it ' +
              'reads), or draw it within that part; with widget(state, size) a wide card can have a wide picture of its own.'
          }
        }
      }
    }
  }
  return ''
}

/** The first shape of a picture fills it: the picture paints its own background. */
function paintsBackground(node: CardNode): boolean {
  let ops = decodeGfxOps(node.ops)
  let first = ops.length > 0 ? ops[0] : null
  return first !== null && (first.kind === 'rect' || first.kind === 'roundRect') && first.x <= node.w * 0.05 && first.y <= node.h * 0.05 &&
    first.x + first.w >= node.w * 0.95 && first.y + first.h >= node.h * 0.95
}

/**
 * A ui.Motion around a scene -- a cover picture, or one with its own background -- moves the sky with the rocket and the pond with the
 * frog: the whole card jumps. What moves is the thing in it, as a gfx.moving part (5 of 6 toy widgets wrapped the whole scene even with the
 * prompt saying so), so the reason goes back to the model.
 */
function movingSceneError(nodes: CardNode[]): string {
  // A Motion made for a gfx.moving part (it has a pivot of its own) moves only that part, over a layer that stays.
  for (let node of collectNodes(nodes, (n: CardNode): boolean => n.kind === 'motion' && n.px === undefined)) {
    let scene = node.children.find((c: CardNode): boolean => c.kind === 'surface' && (pictureCovers(c.style) || paintsBackground(c)))
    if (scene !== undefined) {
      return 'The ui.Motion("' + node.style + '") moves the whole scene, its background too: on the card the sky moves with the rocket, the ' +
        'pond with the frog. Take the ui.Motion away and, in the draw function, wrap only the shapes of the thing that moves in ' +
        'gfx.moving("' + node.style + '", 0, pivotX, pivotY, [those shapes]), with the pivot where it hangs, turns or stands; the background stays.' +
        (pictureCovers(scene.style) ? '' : ' Make the picture ui.Surface("cover", ' + scene.w.toString() + ', ' + scene.h.toString() +
          ', ...) too: a scene with a background fills the whole card.')
    }
  }
  return ''
}

/** The ui.Motion presets that turn the picture: around a picture whose app turns only a part of it, they turn what should stay. */
const TURNING: string[] = ['spin', 'turn', 'tumble', 'flip', 'swing', 'wobble', 'roll']

/** A number for the model: at most one decimal. */
function short(n: number): string {
  return (Math.round(n * 10) / 10).toString()
}

/**
 * The app turns a part of its picture (a pendulum swings, a wheel spins) while the rest stays, and the widget draws that picture but moves
 * it whole (a ui.Motion around it: the clock case swings with the pendulum, the pointer spins with the wheel) or not at all. Seen on the
 * phone in every toy run, with the prompt saying otherwise; the app's own frames say which shapes turn and about which point
 * (VeraMovingPart), so the reason names them and gives the pivot. The widget's picture of the part is the one drawn in its colours.
 */
function movingPartError(vbc2: string, state: string, nodes: CardNode[]): string {
  let pictures = collectNodes(nodes, (n: CardNode): boolean => n.kind === 'surface' && n.ops.length > 0)
  if (pictures.length === 0) { return '' }
  // A picture with gfx.moving parts is split into layers: the widget moves a part already.
  if (collectNodes(nodes, (n: CardNode): boolean => n.kind === 'layers' && n.parts === true).length > 0) { return '' }
  let part: MovingPart | null = null
  for (let picture of pictures) {
    let ops = decodeGfxOps(picture.ops)
    let colours = coloursOf(ops)
    if (part === null) {
      part = appMovingPart(vbc2, state)
      if (part === null) { return '' }
    }
    let moving = part.ownColours.length > 0 ? part.ownColours : part.movingColours
    let shown = moving.filter((c: string): boolean => colours.indexOf(c) >= 0).length
    if (moving.length === 0 || shown * 2 < moving.length) { continue }
    let around = collectNodes(nodes, (n: CardNode): boolean => n.kind === 'motion' &&
      collectNodes(n.children, (c: CardNode): boolean => c === picture).length > 0)
    // A movement that does not turn (a sleepy cat that breathes, a drum that shakes) is the model's own choice of what a touch shows.
    if (around.length > 0 && TURNING.indexOf(around[0].style) < 0) { continue }
    let still = part.stillColours
    // A ui.Motion around only the part (one layer of a ui.Layers, the rest in another) is right.
    if (around.length > 0 && still.length > 0 && !still.some((c: string): boolean => colours.indexOf(c) >= 0)) { continue }
    let pivot = widgetPivot(part, picture, ops)
    let own = picture.ops === part.firstOps
    let what = 'In the app\'s picture these shapes ' + (part.style === 'spin' ? 'turn round' : 'swing') + ' about the point ' + pivot +
      ' of the widget\'s picture: ' + part.movingText + '; and these stay where they are: ' + part.stillText + '.'
    let fix = (own ? 'The app\'s draw function "' + part.draw + '" cannot be changed from here: give the widget\'s picture a draw function of ' +
      'its own (a new name) that draws the same shapes, and in it wrap ' : 'In the draw function wrap ') + 'only the shapes that turn in gfx.moving("' +
      part.style + '", 0, ' + pivot + ', [those shapes]) among the shapes it returns, and leave the rest outside it.'
    if (around.length > 0) {
      return what + ' On the card the ui.Motion("' + around[0].style + '") moves the whole picture, what should stay too. Take the ui.Motion away. ' + fix
    }
    return what + ' On the card nothing in the picture moves. ' + fix
  }
  return ''
}

/**
 * Where the part's pivot is in the widget's picture: the same point of the same shape when the part's pivot is a point of one of its shapes
 * and the widget draws that shape (same kind, its colours); else the app's pivot in proportion to the two pictures' sizes.
 */
function widgetPivot(part: MovingPart, picture: CardNode, ops: GfxOp[]): string {
  if (part.anchorPoint >= 0) {
    for (let o of ops) {
      if (o.kind !== part.anchorKind) { continue }
      let colours = coloursOf([o])
      if (!part.anchorColours.some((c: string): boolean => colours.indexOf(c) >= 0)) { continue }
      let points: number[] = []
      pointsOf(o, IDENTITY, points)
      if (part.anchorPoint * 2 + 1 < points.length) {
        return short(points[part.anchorPoint * 2]) + ', ' + short(points[part.anchorPoint * 2 + 1])
      }
    }
  }
  let scaleX = part.width > 0 ? picture.w / part.width : 1
  let scaleY = part.height > 0 ? picture.h / part.height : 1
  return short(part.pivotX * scaleX) + ', ' + short(part.pivotY * scaleY)
}

/**
 * A picture that paints its own background (its first shape a rect over nearly all of it) is a scene: on a card it is a cover picture,
 * edge to edge under the rest. Drawn as a default picture it comes out a dark square in the middle of the card -- what 4 of 14 widgets
 * did in a run of toy prompts even with the prompt saying so, hence a check whose reason goes back to the model. Pictures in a row or a
 * ui.Layers share the card and are left as they are.
 */
function backgroundError(nodes: CardNode[]): string {
  let found = ''
  let walk = (list: CardNode[]): void => {
    for (let node of list) {
      if (found.length > 0 || node.kind === 'row') { continue }
      // A picture split at its moving parts is still one picture: its bottom layer holds its background.
      if (node.kind === 'layers') {
        if (node.parts === true && !pictureCovers(node.style) && node.children.length > 0) {
          let bottom = node.children[0].kind === 'motion' ? node.children[0].children : [node.children[0]]
          walk(bottom)
        }
        continue
      }
      if (node.kind === 'surface' && !pictureCovers(node.style) && !pictureBare(node.style)) {
        if (paintsBackground(node)) {
          found = 'A picture of the widget paints its own background (its first shape fills it), so on the card it would be a ' +
            'square of that colour in the middle. A scene with a background is ui.Surface("cover", ' + node.w.toString() + ', ' + node.h.toString() +
            ', ...): it fills the whole card to its edges, under the rest of the widget. Make it "cover" (keep at most one short line of text ' +
            'beside it), or, for a single object, leave the background rect out.'
        }
      }
      walk(node.children)
    }
  }
  walk(nodes)
  return found
}

/** The nodes, at any depth, that `pick` takes. */
function collectNodes(nodes: CardNode[], pick: (node: CardNode) => boolean, found: CardNode[] = []): CardNode[] {
  for (let node of nodes) {
    if (pick(node)) { found.push(node) }
    collectNodes(node.children, pick, found)
  }
  return found
}

function isButton(node: CardNode): boolean {
  return (node.kind === 'button' || node.kind === 'path' || node.kind === 'iconbutton') && node.enabled && node.action.length > 0
}

/** Where a first tap from the saved state got to: the state after it and its settling, whether it came to rest, and what it asked of its source. */
class TappedFrom {
  state: string
  rested: boolean
  requests: SourceRequest[]
  constructor(state: string, rested: boolean, requests: SourceRequest[]) { this.state = state; this.rested = rested; this.requests = requests }
}

/**
 * First taps from the saved state, done once: every card size taps the same controls from the same state, stuckButton taps each button
 * again, and unseenTouch touches the middle of each picture again. A tap's handler sees only the state, not the card's size, so the
 * answer is the same each time, and settling it (up to 600 steps of the app's clock) is what a tap costs.
 */
class TapMemo {
  private done: Map<string, TappedFrom> = new Map<string, TappedFrom>()

  /** `run` the tap on `branch` (at the saved state), or put `branch` where the same tap got to before. */
  tap(key: string, branch: WidgetSession, run: () => SourceRequest[]): SourceRequest[] {
    let before = this.done.get(key)
    if (before !== undefined) {
      branch.restoreTap(before.state, before.rested)
      return before.requests
    }
    let requests = run()
    this.done.set(key, new TappedFrom(branch.encodedState(), branch.lastTapRested, requests))
    return requests
  }
}

/**
 * Everything on a card of this size a finger can work, each twice from the saved state: a switch turned on and off, a picture touched in
 * the middle, a button pressed. Its handler must run without a phone call, and the state it leaves must still draw on that card and in the app.
 */
function switchKey(handler: string): string { return 'switch ' + handler }
function touchKey(handler: string, x: number, y: number): string { return 'touch ' + handler + ' ' + x.toString() + ' ' + y.toString() }
function buttonKey(action: string, value: number): string { return 'button ' + action + ' ' + value.toString() }

function checkTaps(vbc2: string, state: string, nodes: CardNode[], dimension: number, memo: TapMemo): string {
  let drawsInApp = (branch: WidgetSession): void => {
    branch.frame('project', 'App', '', dimension)
    let vm = new VirtualMachine(deserializeVbc2(vbc2), new UiHostEnvironment(), LIVE_MAX_STEPS)
    decodeVeraUi(vm.execute('view', [decodeRuntimeValue(JSON.parse(branch.encodedState()) as Object)]))
  }
  // A tap the card refuses for a phone call is said as such; any other failure is the handler's own.
  let tapped = (handler: string, run: () => SourceRequest[], branch: WidgetSession): string => {
    let requests: SourceRequest[] = []
    try {
      requests = run()
    } catch (e) {
      if (/phone action required/.test((e as Error).message)) { return phoneCallMessage(handler) }
      throw (e as Error)
    }
    // A Refresh button's live source is not fetched here: its handler is given a failure, which it must take and still draw.
    for (let request of requests) { branch.answer(request.handler, 'error: the source is not reached while checking') }
    drawsInApp(branch)
    return ''
  }
  // Each control twice, from the saved state. The first tap may take it away (a Start that becomes Stop, a box shown only while a
  // task is open): then there is no second.
  // The first tap is the same from every card size (TapMemo): `key` names it.
  let twice = (key: string, handler: string, still: (node: CardNode) => boolean,
      run: (branch: WidgetSession, current: LiveFrame, pass: number) => SourceRequest[]): string => {
    let branch = new WidgetSession(vbc2, 'validation', state)
    for (let pass = 0; pass < 2; pass++) {
      let current = branch.frame('project', 'App', '', dimension)
      if (collectNodes(current.nodes, still).length === 0) { break }
      let problem = tapped(handler, (): SourceRequest[] => pass === 0 ?
        memo.tap(key, branch, (): SourceRequest[] => run(branch, current, pass)) : run(branch, current, pass), branch)
      if (problem.length > 0) { return problem }
    }
    return ''
  }
  let isSwitch = (node: CardNode): boolean => (node.kind === 'toggle' || node.kind === 'checkbox') && node.enabled && node.action.length > 0
  for (let item of collectNodes(nodes, isSwitch)) {
    let problem = twice(switchKey(item.action), item.action, (node: CardNode): boolean => isSwitch(node) && node.action === item.action,
      (branch: WidgetSession, current: LiveFrame, pass: number): SourceRequest[] => branch.tapSwitch(current, current.token, item.action, pass === 0))
    if (problem.length > 0) { return problem }
  }
  for (let picture of collectNodes(nodes, (node: CardNode): boolean => node.kind === 'surface' && node.pointer.length > 0)) {
    let problem = twice(touchKey(picture.pointer, picture.w / 2, picture.h / 2), picture.pointer, (node: CardNode): boolean => node.kind === 'surface' && node.pointer === picture.pointer,
      (branch: WidgetSession, current: LiveFrame, pass: number): SourceRequest[] =>
        branch.tapSurface(current, current.token, picture.pointer, picture.w / 2, picture.h / 2))
    if (problem.length > 0) { return problem }
  }
  for (let button of collectNodes(nodes, isButton)) {
    let problem = twice(buttonKey(button.action, button.value), button.action, (node: CardNode): boolean => isButton(node) && node.action === button.action && node.value === button.value,
      (branch: WidgetSession, current: LiveFrame, pass: number): SourceRequest[] => branch.tap(current, current.token, button.action, button.value))
    if (problem.length > 0) { return problem }
    problem = stuckButton(vbc2, state, button, dimension, memo)
    if (problem.length > 0) { return problem }
  }
  return ''
}

/**
 * A button that a tap leaves off for good: what it started only the app's clock finishes, and it did not come to rest within the seconds the
 * card runs it after a tap (a wheel whose Spin waits for it to stop). On the card it would stay off. A button off after a tap whose work came
 * to rest is the app's own rule (a generated countdown's Start waits for Reset) and passes.
 */
function stuckButton(vbc2: string, state: string, button: CardNode, dimension: number, memo: TapMemo): string {
  let branch = new WidgetSession(vbc2, 'validation', state)
  let current = branch.frame('project', 'App', '', dimension)
  try {
    memo.tap(buttonKey(button.action, button.value), branch, (): SourceRequest[] => branch.tap(current, current.token, button.action, button.value))
  } catch (e) {
    return ''
  }
  // What the tap started came to rest: a button that is off now is the app's own rule (a Start that waits for Reset), not something unfinished.
  if (branch.lastTapRested) { return '' }
  let after = branch.frame('project', 'App', '', dimension)
  let same = collectNodes(after.nodes, (node: CardNode): boolean =>
    (node.kind === 'button' || node.kind === 'iconbutton') && node.action === button.action && node.value === button.value)
  if (same.length > 0 && same.every((node: CardNode): boolean => !node.enabled)) {
    return 'After a tap on "' + (button.text.length > 0 ? button.text : button.action) + '" that button stays off on the card for good: the tap ' +
      'starts something only the app\'s frames finish, and the card runs them for ' + Math.round(SETTLE_MAX_STEPS * SETTLE_STEP_MS / 1000).toString() +
      ' s after a tap, which is not enough for it to come to rest. Give the widget its own handler (a new name) that finishes at once -- ' +
      'works out the result straight away (where the wheel stops, the die\'s face) and returns the state at rest -- and give the button that handler.'
  }
  return ''
}

/** Where a picture is touched to see whether a touch shows, as shares of its width and height: the middle first. */
const TOUCH_POINTS: number[][] = [[0.5, 0.5], [0.3, 0.3], [0.7, 0.3], [0.3, 0.7], [0.7, 0.7], [0.43, 0.57]]

/**
 * What the card's pictures draw, and nothing else: a count beside a picture that changes is not the picture answering the touch. A generated
 * rocket flew up and came back to its pad in the app's frames, so the card, which shows only where they come to rest, drew it on the pad
 * again with its launch count one higher, and the touch passed for one that shows.
 */
function drawnPictures(nodes: CardNode[]): string {
  return collectNodes(nodes, (node: CardNode): boolean => node.kind === 'surface' || node.kind === 'drift')
    .map((node: CardNode): string => node.ops).join('\n')
}

/**
 * A picture that takes a touch and shows nothing for it: no movement around it (a ui.Motion, gfx.moving parts) and, after the tap and what
 * the card runs after it, the same pictures as before (drawnPictures). The rocket of a generated countdown app was such a widget: its tap
 * started a countdown the card could not finish, and nothing on the card moved.
 */
function unseenTouch(vbc2: string, state: string, frame: LiveFrame, memo: TapMemo): string {
  let still = collectNodes(frame.nodes, (node: CardNode): boolean =>
    node.kind === 'surface' && node.pointer.length > 0 && node.slot < 0 && node.links === undefined)
  if (still.length === 0) { return '' }
  // Every touch is made from the saved state, so what the card drew before is the same for all of them. The middle of each picture was
  // touched already by checkTaps (TapMemo).
  let drawnBefore = drawnPictures(new WidgetSession(vbc2, 'validation', state).frame('project', 'App', '', frame.dimension).nodes)
  for (let picture of still) {
    // Not only the middle: in a grid (bubble wrap) the middle may fall between two things a touch acts on.
    let shows = false
    for (let at of TOUCH_POINTS) {
      let branch = new WidgetSession(vbc2, 'validation', state)
      let before = branch.frame('project', 'App', '', frame.dimension)
      let x = picture.w * at[0]
      let y = picture.h * at[1]
      try {
        memo.tap(touchKey(picture.pointer, x, y), branch,
          (): SourceRequest[] => branch.tapSurface(before, before.token, picture.pointer, x, y))
      } catch (e) {
        shows = true
        break
      }
      let after = branch.frame('project', 'App', '', frame.dimension)
      if (drawnPictures(after.nodes) !== drawnBefore) { shows = true; break }
    }
    if (!shows) {
      return 'A touch on the picture changes nothing you can see on the card: nothing in it moves and it is drawn the same after the tap ' +
        '(the card shows only where what the tap starts comes to rest, so a thing that flies off and comes back is drawn where it started; ' +
        'and what the tap starts in the app may need its timers, which the card does not run for long). Make the touched thing move: wrap its ' +
        'shapes in gfx.moving(style, 0, pivotX, pivotY, [shapes]) with the movement it makes (a rocket launches, a frog hops), or the whole ' +
        'picture in ui.Motion when it is only that thing; or give it a handler of its own that changes what is drawn at once.'
    }
  }
  return ''
}

/**
 * A widget whose picture does nothing when touched although the app's does: the toy is dead on the card. In 8 of 14 toy widgets the
 * picture had no handler (a die that tumbled and kept its face, a cat that could not be stroked).
 */
function deadPicture(vbc2: string, state: string, nodes: CardNode[]): string {
  let pictures = collectNodes(nodes, (node: CardNode): boolean => node.kind === 'surface' && node.style.length > 0)
  if (pictures.length === 0) { return '' }
  if (collectNodes(nodes, (node: CardNode): boolean => node.pointer.length > 0 || node.action.length > 0).length > 0) { return '' }
  let appHandler = ''
  try {
    let vm = new VirtualMachine(deserializeVbc2(vbc2), new UiHostEnvironment(), LIVE_MAX_STEPS)
    let walk = (list: VeraUiNode[]): void => {
      for (let node of list) {
        if (appHandler.length === 0 && node.kind === 'surface' && node.value.length > 0) { appHandler = node.value }
        walk(node.children)
      }
    }
    walk(decodeVeraUi(vm.execute('view', [decodeRuntimeValue(JSON.parse(state) as Object)])))
  } catch (e) {
    return ''
  }
  if (appHandler.length === 0) { return '' }
  return 'In the app a touch on the picture does something (its handler "' + appHandler + '"), but on the widget the picture has no handler, ' +
    'so a touch only plays a movement and nothing happens: give the widget\'s ui.Surface a pointer handler as its last argument that does ' +
    'what a tap does in the app -- "' + appHandler + '" itself if it makes no phone call, else a new one that changes the state the same way ' +
    'without it. A card gets a tap (down, then up), not a drag.'
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
