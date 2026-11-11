# Live-widget foundation / counter proof

This is the first slice of `docs/ISSUE-home-screen-widgets.md`, Part 2, **not the complete feature**.

## Try it

1. Open an app, then "..." > **Make widget**, and say what the widget shows; Save.
2. On its project page, "..." > **Add widget**.
3. On this phone `isRequestPublishFormSupported()` returns false. The fallback opens the system widget manager. Add **VERA live app**.
   The manager does not pass the project on, so Add widget leaves it in `form-offer.json` and the next live card added
   within five minutes takes it, once (`FormBindings.offer` / `takeOffer`). A card added later, or from the launcher's own
   picker, is unbound: tap it and choose one of the apps that have a widget in **Choose widget app** (the `widgetBind`
   destination).
4. The card's buttons run the program's handlers in the form extension. A tap anywhere else on the card opens the full
   program. A live card has no title strip: the widget has the whole card. It is offered in 2x2 only, the size the widget,
   its preview and the prompt are made for.

A program without `widget(state)` displays a tile-like fallback and opens the app. An uncompiled project opens its project
page. Make widget is refused for a program whose own code calls `widget` or `widgetRefresh` (`appUsesWidgetError`): a new
widget would change the app too. The `widget-counter.vera` fixture, whose screen is its widget, is a host-check example only.

## Architecture

- `FormBindings.ets`: persistent form-to-project mapping; reloads for every access because app and extension are separate processes.
- `VeraLiveWidget.ets`: platform-independent VM session, rendering projection and event validation.
- `LiveFormService.ets`: load latest version/state, render, validate tap, run handler, render the candidate state, commit only on success.
- `VeraStateStamp.ets`: unchanged state-stamp formula shared with VeraPreview.
- `LiveCard.ets`: launcher-only binding renderer. Fixed depth; no compiler/VM/filesystem imports.
- `FormUpdater.ets`: list/live form routing. A running app's saves redraw only that project's cards, and only when it has
  any, at most every `CARD_REFRESH_MS` (5 s): a ticker saves every second.
- `VeraPreview.ets`: reload saved state when the app comes back, and run the program's `widgetRefresh` when it starts and
  comes back. In the background a ticker's tick is skipped, not stopped: the time it last fired is kept, so the first tick
  back carries the time away, as before.
- State-file writes use a temporary sibling plus rename. Other project/version write semantics are unchanged.

Initial supported kinds are explicitly opted into `ComponentSpec.card`: AppTheme (root only), Column, Row, Text, NumberText, Button, Spacer and Divider. Do not infer that all app components are card-safe.

Limits: 100,000 VM steps per entry call; four layout levels (the theme wrapper does not consume a level); 40 nodes; 256 characters per text; 8,000 UTF-16 code units for the complete frame. This is a conservative application budget, **not a measured platform maximum**. Theme currently resolves light mode only.

Events contain `handler`, numeric `value`, and a token: the version, the program's stamp and a 64-bit digest of the state
(`stateDigest`). It is not the state itself, which would grow with the app's data past the card's budget. The OS overwrites a message field named `action` with the transport action (`message`), so that name must not be used for the program handler. Only an enabled button in the freshly rendered tree can dispatch. SDK effects are collected but never executed; an effectful handler does not commit state. The card asks the person to open the app; it does not try extension `startAbility`.

The root ForEach key includes the frame token. Without this, nested card builders retain the old displayed number even though updateForm succeeds.

## Verification on this machine

```sh
export VERA_TYPESCRIPT_PATH=/home/mbolshov/agentsdk/panda_sdk/package/driver/build_system/node_modules/typescript
node tools/vera-harness/live-widget-check.js
node tools/vera-harness/live-form-check.js
node tools/vera-harness/widget-launch-check.js
node tools/vera-harness/smoke-check.js
node tools/vera-harness/visual-check.js /tmp/vera-live-proof/visual-host.json
node tools/vera-harness/chat-handoff-check.js . /tmp/vera-live-proof/chat-host.json
```

Native build and in-place system-signed update succeeded with zero reported diagnostics; identity and first-install time were preserved. No uninstall or app-data clearing.

Device evidence in `/tmp/vera-live-proof/`:

- `final-home`: persisted count 3 after app update.
- `final-plus`: card + changes 3 → 4.
- `final-minus`: card − changes 4 → 3.
- `final-app`: opening the program shows 3.
- `app-to-widget`: app-side + was reflected on the card (2).
- `roundtrip`: subsequent widget-side + was reflected in the app (3).
- `hilog.txt`: measured form handler + render + state-save duration 11–13 ms for the counter; frame about 1.2 KB. This is not end-to-end tap latency.

Screenshots and accessibility dumps were captured, but full visual QA is **not signed off**. The configured external image analyzer rejected requests (413 on full PNG, 400 on cropped JPEG). No independent QC/subagent tool was available in this session. This proof must not be represented as full Part 2 acceptance.

## Make widget: a widget the person describes

The project page's "..." menu offers **Make widget** for the latest runnable version. It opens Generate on that version with
the box empty -- "What should the widget show?" -- and the **Widget** tab open. What the person types is the request
("The home-screen widget should show: ..."); the instructions for what a widget is go in the system prompt
(`widgetRefinementPrompt`). Generate, refine and Save work as for any change; the action does not publish a card.

- **What a widget is, to the model:** a second view of the same state -- `widget(state)` draws the very state `view(state)`
  draws -- read at a glance: one to three figures or short lines with labels of a word or two, at most two buttons for the
  actions worth doing without opening the app, nothing else (no lists, history, settings, inputs, explanations, no heading
  with the app's name: the card has no title strip). When the request asks for more, keep what matters most. No button that opens the app.
- **Held to it:** Make widget's validation refuses more than 2 buttons or 8 texts on a 2x2 card (`cardSize`'s `maxButtons`,
  `maxTexts`; more on the bigger sizes), with a reason the repair loop passes to the next attempt. The card's own budgets are unchanged.
- **Only the widget is written** (DeepSeek mode, `agent/AgentWidget.ets`): the model is shown the program, the request and
  the card's components only (`languageWith`, the full-screen composition advice left out), and answers with the widget's
  declarations alone (`widgetRefinementPrompt(false)`); a failing answer goes back with its reason, three answers at most,
  the last with thinking on. Host, deepseek-flash, the same five requests on three generated apps (150-211 lines), two
  runs each: whole-program refine 10/10, median 6.3 s, about 2,200 output tokens; widget alone 10/10, median 2.0 s, about
  370. Server and local modes still refine the whole program.
- **The app cannot change:** `spliceWidget` (VeraCompiler) builds the program from the saved one as it is plus the reply's
  `widget`, new helpers and new imports; the reply's rewrite of an existing declaration is not taken. A widget that needs
  state the app does not keep fails to compile, and `widgetRepairNote` tells the next attempt that the state cannot grow.
- **Widget tab:** `WidgetPreview` draws the widget with the card's own session (`WidgetSession`) and layout, 2x2, over the
  state the app preview holds -- Make widget starts both from the project's saved data. Taps there run the handlers but are
  not saved.
- The compiler checks an optional synchronous `widget(init-result): ui.View` signature (`E2115`). `smokeRun` validates widget
  trees and enabled buttons without executing phone effects.
- Save rechecks preservation and the widget against the base version's **latest saved state**, refuses a changed
  latest-version ID, and stages that state with the new bytecode stamp before publishing the new version. A refused Save
  stays on the page. There is no cross-process lock: state remains last-writer-wins.
- Foreground restoration redraws the same runner instance. Background signals stop program timers.

- **Kept current:** the live card is updated about every 30 minutes (`updateDuration` 1), so a figure `widget` works out
  from the clock moves by itself. When the state itself goes out of date with the time (the day's figures, a countdown that
  is over), Make widget may add `function widgetRefresh(state): AppState` (signature checked, `E2113`). On each periodic
  update `LiveFormService.liveFormRefresh` runs it as a tap runs a handler -- phone effects refused, render, THEN commit --
  and the project's other cards are redrawn. `RefreshLedger` (`widget-refresh.json`) lets it run once per project per
  `REFRESH_EVERY_MS` (20 minutes), however many cards show it; a failing one waits for the next period. Validation runs it
  twice and refuses one whose second run changes the state again (timestamps may differ by under a minute). The splice
  treats it as the widget's own: replaced with the widget, dropped when a new widget has none.

Host replay (`deepseek-flash`, thinking off, the refine request DeepSeekEngine sends, up to three attempts with the error fed
back): six requests on four apps (a generated water tracker and packing list, the expense and habit examples), including two
that ask for everything ("every drink logged today ... and buttons for 100, 250, 330 and 500 ml", "the whole list with a
checkbox for each item"), three runs each: 18/18 valid. With `widgetRefresh` in the prompt and a seventh request ("start again from zero every morning"): 21/21 valid; the water tracker's widgets added a `widgetRefresh` that empties the day's drinks on a new day and keeps the goal, while the packing list, budget and habit widgets (no state that dates) added none. Before the splice and the repair note, 6/18 passed in one attempt;
most failures were the model also rewriting an existing declaration. Run on the phone since: Make widget on a roulette app
and on two live-data apps, Save, Add widget, the card's buttons and a tap that opens the app.

Host evidence for this follow-up:

- `widget-refine-check.js`: preservation, optional signature, catalogue-derived instructions, smoke diagnostics, saved-state validation, glance limits, the splice and the repair note pass.
- `live-widget-check.js`: repeated rows with distinct item IDs, middle-row removal, shifted rows and stale/removed-item taps pass using Column/Row (no ListGroup/ListItem required).
- `live-form-check.js`: two widgets sharing state, stale tokens across widgets, binding removal/rebind, missing-project fallback and preserved state in a new version pass.
- `capability-check.js`: **10/10 pass**, including executing extracted renderer lifecycle methods with the real VM, restoring the same runner instance and stopping timers on background. Report `/tmp/vera-widget-capability.json`.
- Widget launch, smoke and visual-tree checks pass (**97/97** visual-tree checks; not screenshot QA).
- Chat regression: **39 pass / 18 fail**. An archived clean HEAD has the exact same failing check names and counts; these are baseline failures, not a clean suite. Reports `/tmp/vera-widget-chat{,-baseline}.json`. The earlier summary's chat-success statement should not be used as evidence for this follow-up.

Native build: `./build-hap.sh --unsigned` passes with zero diagnostics on this branch.

Independent QC and device/visual verification remain blocked: tool discovery exposes no independent task/subagent review tool. No merge-ready or full Part 2 claim is made.

## Animation on the card: a drum that moves when it is hit

A card can play **one short movement per redraw**; it cannot loop. Measured on this phone (API 26, the card is drawn by
`com.ohos.formrenderservice`), with a throwaway block in `LiveCard.ets` that was removed afterwards:

- A property that changes after `updateForm` (`rotate`, `scale`, `opacity`, `translate`) animates with `.animation({duration, curve: Curve.*})`, on a
  plain node and on a `Shape/Path`; `onFinish` arrives after the duration. The platform's card rules (a duration of at most 1 s;
  `iterations`, `delay` and `tempo` not allowed) match the `@form` marks in the SDK's `common.d.ts`: `iterations: -1` played once.
- A node **made again** for the frame (the ForEach key carries the frame token) has nothing to animate from. The way that works:
  create it in the hit pose when the frame carries a new trigger, and set it to rest in `onAppear`; it settles with the
  animation. Three hits out of three: `watch`, `appear` within 5 ms, `finish` about 410 ms later.
- Not available: `spinPeriodMs` (the app's ticker has no counterpart on a card), `LoadingProgress` (turns for about 1 s after a
  redraw), curves from `@ohos.curves` (not `@form`), `playMode: Reverse/AlternateReverse` (settle upright whatever the state says).
  A chain of animations driven from `onFinish` stops about two seconds after the redraw (2.35 s with 600 ms steps, 2.0 s with
  300 ms), a time and not a count; the reason is not known.
- Six taps 330 ms apart (the fastest `uitest` clicks) all reached the handler (8-17 ms each) and the shape was at rest at the end.
  Faster hits, and rhythm, are not measured.

How it is built: `ui.Motion(style, trigger, children)` is a card kind (`CARD_MOTIONS`: pop, shake, bounce, fade; no tumble or flip),
**one per widget** (`LIVE_MAX_MOTIONS`; the compiler already refuses one Motion inside another, E2107). The frame carries the
preset and the trigger (`CardNode.style`, `.trigger`). `LiveCard` and `WidgetPreview` keep `settled`, the trigger last drawn: a
frame with another trigger starts the Motion in its pose (pop 1.25x, shake +-12 degrees alternating with the trigger, bounce 16 up,
fade transparent) and `onAppear` sets `settled`, which animates it back (350-600 ms). The first frame only records the trigger,
so a card never plays on opening or after the launcher restarts it. The program keeps the count in its state and passes it as the
trigger (`examples/widget-drum-motion.vera`); the Make widget prompt says so, and says there is no continuous motion, sound or vibration.

On the phone (a saved project with `examples/widget-drum-motion-app.vera`, a card bound to it): one tap on the drum, and the next
frame shows it 1.18x its size (210 px against 178 at rest, on the way down from 1.25x) with the counter already at "1 hits"; from the
second frame on it is at rest. Six taps about 330 ms apart all counted (1 -> 7 hits); while they ran the drum stayed enlarged (193-211 px,
each hit starting the settle again) and 1.5 s after the last one it was at 178 px. The other three presets were played on the card too
(shake: tilted on the first frame after the tap; bounce: displaced upwards, settling; fade: about half transparent on the first
frame), and the Widget tab (`WidgetPreview`) plays them the same way. A `Path` on a card needs `.stroke(Color.Transparent)`: left
with ArkUI's default stroke the drum came out outlined in thick black (found on the phone, fixed in both `LiveCard` and `WidgetPreview`).

Host checks: `live-widget-check.js` (the frame, the trigger following the count, the presets, a second Motion refused),
`widget-refine-check.js` (the prompt, `tumble` refused). Not covered by a check: the picture on a phone.

## A picture on the card: ui.Surface, drawn once for the state

The card is drawn by the launcher's render service from data the extension sends, so the VM cannot run there (no frame loop, no
timers). But the card **can import the app's pure modules and use a `Canvas`**: `paintGfx` (VeraGfx), `resolveTheme` (VeraTheme) ran in
`formrenderservice` on this phone, and a black-and-white panda drawn by the app's own painter showed in the widget picker. So the app's
drawing path is shared; only the program's execution stays in the extension.

How: `ui.Surface` is a card kind in a static form. `WidgetSession.frame` runs the program's draw function once for the state
(`decodeGfx`), checks it (one Surface per widget, `LIVE_MAX_SHAPES` = 60 shapes, an empty frame handler: "a card has no frames"), and
carries the shapes in the frame as a compact text (`encodeGfxOps`: only what each shape sets; the nine-shape panda is 464
characters, the whole frame 1.8 KB of the 8 KB budget). The frame also carries the widget's theme (`preset`, `primary`). `LiveCard` and
`WidgetPreview` draw it with `paintGfx` on a `Canvas` 80 vp wide (a card is about 150 vp square -- 524 px at 3.5 px per vp -- with 12 of padding; at 100 vp the figure
under the picture was cut off on the phone. The Widget tab used to draw the card at 172 vp, which hid such overflow; it now draws 150). A tap on the picture sends the point (`x`, `y`, in the picture's own units) to
`liveFormTap`, which calls the program's pointer handler with a finger "down" and then "up" there (`WidgetSession.tapSurface`); a
picture without a pointer handler lets the tap fall through to the card, which opens the app. The picture counts as one of the two
buttons in Make widget when it takes a tap, and the tap is checked like a button's (twice, no phone calls). `ui.Motion` around it makes it
jump (`examples/widget-panda.vera`).

Measured on the phone (a saved project with the panda, a card bound to it): a tap on the panda reached the handler at 50.3, 54 (the
middle of 100 by 100 units), the handler and save took 6-13 ms, the picture was painted about 30 ms after the extension finished, the
paint itself 2 ms; the panda jumped (bounce) and the counter rose by one per tap, on the card and in the Widget tab. Cost of loading: the
card now pulls in about 87 KB of source (`VeraGfx` 27, `VeraInterpreter` 26, `VeraTheme` 24, `LiveCard` 11). `VeraGfx` brings the
interpreter with it; a split that leaves the painter and `GfxOp` in a module of their own would drop that. Memory of the render service
was 129 MB PSS in total (all cards, all apps): the share of this card was not isolated and a build without the imports was not measured.

What a real generation showed (Make widget on a copy of the "Little panda that jump" game, request "a little panda that jumps when I touch it",
read from the log: `VERA-WIDGET attempt N answer ...` in `AgentWidget`). The first build drew a one-colour blob and did not move:

- The model drew the panda with `ui.Path`: the catalogue's own text for Path says "use it whenever the user asks to draw something", which
  outweighed the paragraph about `ui.Surface`. A Path is one colour, so ears and eyes were lost. The prompt now says, first and in capitals, that a
  drawing of more than one colour is a Surface and never a Path (`WHAT TO DRAW WITH`), and the catalogue's Path text says the same for a card.
- The program had no counter of touches and a widget may not add state fields (`E2022 unknown field taps`); the next answer used `state.score` as
  the Motion's trigger with a handler that returned the state unchanged, so nothing could ever move. A touch now plays a Motion **by itself**:
  `LiveCard` and `WidgetPreview` count the touches on their pictures and shapes (`touches`, a plain field) and add them to the Motion's trigger, and a
  tap's answer carries `seq` (`LiveFrame.seq`, set in `liveFormTap`) so the card draws another frame even when the state came out the same. The widget
  writes `ui.Motion("bounce", 0, [picture])` and a touch handler that may return the state as it is.
- The picture was 80 vp whatever else was on the card, and "Best 0" fell off the bottom. The frame now sizes it to the room the rest leaves
  (`pictureRoom`, `nodeHeight`: a card is 126 vp inside its padding, rows 6 apart, 40 for a button, 1.25 x the size for text; 40 to 80 vp), and Make
  widget refuses a widget that leaves under 40 ("too much around its picture"), with the reason fed back.

After these, the same request gave a panda of several colours (a green disc, a platform, orange ears, cheeks) on the first attempt, the widget passed
every check, and on the phone a touch on it makes it jump, in the Widget tab and on the card on the home screen, with the score unchanged.

The layout is one component, `widget/CardView.ets`, which `LiveCard` and the Widget tab (`WidgetPreview`) both use, over the plain frame classes in
`widget/CardModel.ets`; the painter and colours moved to `vera/GfxPaint.ets` (no interpreter import; `VeraGfx` re-exports them). A widget may have up to three
pictures and three Motions: a Motion has a `slot`, a node under it carries that slot, and a touch is counted for that slot only. On the phone, two pictures side by
side (`examples/widget-two-pictures.vera`): a touch on the left one moved only it (it rose from y 150 to 100 px and settled), the right square stayed where it was,
and the other way round for the right one.

Not covered: a picture changing under a finger (a card has no moves), pictures of more than 60 shapes, dark theme, 2x4 and 4x4 cards.

## What else a card can draw: spikes on the phone (stage 0 of the full-UI plan)

Throwaway blocks in `LiveCard.ets` (restored afterwards), each rendered on a card on the home screen of this phone (API 26). **The ArkTS compiler itself
refuses what a card may not use** (`11706006 'onAreaChange' can't support form application`), so a build that passes is a first check of `@form`;
the picture on the phone is the second.

Drawn and working:
- `TextTimer` ticks by itself on the card, up and down (a 90 s countdown read 01:19, 01:18, 01:16, and 00:10 seventy seconds later); `TextClock`
  moves on (2:59 to 3:00), but its `format` was not honoured (it showed H:mm). So the card is not frozen for the platform's own components: only our code and animations are.
- `Progress` (linear and ring), `Gauge`, `Rating`, `SymbolGlyph($r('sys.symbol.ohos_wifi'))`, `Stack` (a badge over a square), `linearGradient`, `shadow`,
  `fontWeight`, `fontFamily` (`'Noto Serif'` and `'monospace'`, the ones the themes use).
- A `@Component` imported from its own module (`widget/CardParts.ets`), and two `Canvas` with their own contexts in one card.

Not working or not possible:
- `DataPanel` (circle, three values) drew nothing.
- A local `onClick` that changes `@State` does not run on a card (only `postCardAction`), so a transition cannot be tried by touching the card; it needs a frame from the extension.
- `Image('memory://...')` made the **whole card blank**, text included, in both variants tried (with `formImages` in the binding, and without): not resolved. The documented
  pattern (the image's key carried in the data and read with `@LocalStorageProp`, plus a loaded flag) was not tried. Images stay unverified.

Sizes: `onAddForm` receives the dimension in `ohos.extra.param.key.form_dimension` (2 = 2*2, 3 = 2*4, 4 = 4*4; the widget manager calls it once per
variant it previews). With `supportDimensions` ["2*2", "2*4", "4*4"]: 2*2 is about 150 x 150 vp, **2*4 is wide (about 324 x 148 vp: four columns, two rows)**, 4*4 about 324 x 340 vp
(measured from screenshots at 3.5 px per vp).

## Styles: the theme's roles on the card

The card used to flatten the catalogue's styles into three text sizes and one ink. `vera/CardStyle.ets` (pure; the extension calls it while it builds the
frame) now carries the theme's roles to the card: a text's size by style (display 28, title 22, heading 18, metric 30, caption 12, eyebrow 10, the rest 14: the three
sizes a widget already had are unchanged), its weight, family and letter spacing from the theme (an editorial heading is bold Noto Serif, an eyebrow is spaced and
quiet), tone inks (muted, success, warning, danger), buttons in all four styles with the theme's radius, the divider in the theme's line colour; a column's `end`,
`compact`, `spacious`, a row's `split`, `end`, `joined`, and panels (`surface`, `accent`: the theme's fill, padding and radius). A field that equals the card's default
is not in the frame (the new node fields are optional), so the frame stays small: `examples/widget-styles.vera` is 2.2 KB. On the phone the card drew "TODAY" spaced and
muted, "Plan" in bold serif, a panel with the accent fill and rounded corners, and a split row (a muted word at the left, a red one at the right).

The height estimate (`widgetHeight`) uses the real sizes, wraps a long text at two lines (0.55 em a character) and counts a row's width as shared; Make widget refuses a
widget estimated more than 14 vp over the card's 126 ("what does not fit is cut off"). The estimate was 84 to 126 vp for every example in `tools/vera-harness/examples`.

## Icons, marks and data on the card

`ui.Icon`, `ui.IconButton`, `ui.Badge`, `ui.Progress`, `ui.ProgressRing`, `ui.Stat`, `ui.NumberStat`, `ui.MetricGroup` and `ui.Sparkline` are card kinds (opted in by
name in `VeraUiCatalog`, `CARD_OPT_IN`). VeraLiveWidget turns each into card nodes: an icon into the catalogue's stroked path (`VeraIcons`; the card draws it with the
viewPort and stroke in px, as the app does), a bar and a ring into the platform's own `Progress` (spike: it draws on a card), a Stat or NumberStat into a column of a caption, a
figure that shrinks to fit and a supporting line, a MetricGroup into a row of them, and a Sparkline into a small picture (100 by 36 units: a line and its last point, or one
bar for each value; a card draws it with the same painter, and it counts among the three pictures). An IconButton is one of the two buttons.

On the phone (examples/widget-water.vera, widget-metrics.vera): a ring at 38 % that went to 50 % when the plus button was touched, the buttons in the theme's primary and
secondary fills with their icons; a "On track" badge with a check, a star, two stats side by side and a trend line with its last point. A bug found there: the block that fills
these nodes ran before the default colour and fill were assigned, so a ring came out in the plain ink and the buttons white; the order is now fixed and a test holds it.

## Time that moves: ui.Timer

`ui.Timer(style, millis, down)` is a new catalogue component, in the app and on the card: the platform's own `TextTimer`, which keeps counting without our code (the card is
frozen for our animations, not for platform components: stage-0 spike). `millis` is a moment in ms since 1970; `down` false counts up from it, true counts down to it. The
program keeps the moment in its state as a number (`time.nowMillis()` plus or minus a length), the frame carries it (`CardNode.val`, direction in `max`), and at draw time the
card works out where the timer starts (`timerFace` in `widget/CardModel.ets`, which the app uses too: a countdown starts from the time left, `count`; a timer counting up from the
time already gone, `startTime`, since TextTimer ignores `count` when it counts up), so a card the launcher redraws later still shows the right time. The format is
`mm:ss`, or `HH:mm:ss` once an hour or more is involved. Up to three timers per widget; the theme's size, weight, family and ink apply as for a text.

On the phone (examples/widget-timer.vera, technical theme): a monospace stopwatch read 00:03, 00:07, 00:16 and a countdown 01:29:53, 01:29:49, 01:29:40 over a quarter of a minute with no
update from the app, and Restart (a handler that sets both moments to now) started both over. The Make widget prompt says to prefer it to a figure computed from the clock, which stands
still between redraws. Not done: what a countdown does at zero (it stops at 00:00; the program's `widgetRefresh`, about every 30 minutes, is what can change the state then).

## Card sizes: 2x2, 2x4, 4x4

`form_config.json` offers the live card in all three. The system numbers them 2 (2x2), 3 (2x4) and 4 (4x4) (`FormDimension`); `onAddForm` receives the number in
`ohos.extra.param.key.form_dimension` and `FormBindings` keeps it per form (`form-sizes.json`, beside the bindings; a removed card forgets it). Measured from screenshots at
3.5 px per vp: 2x2 is about 150 x 150, **2x4 is wide, about 324 x 148** (four columns, two rows), 4x4 about 324 x 340; inside the 12 vp padding 126 x 126, 300 x 124 and 300 x 316.
`cardSize(dimension)` holds those and the limits that grow with them (nodes 40, 60, 80; buttons 2, 4, 6; texts 8, 12, 24; the largest picture 80, 100, 200 vp). The frame is
fitted to its card: the picture's side and the height gate use that card's inner size, and the frame says its `dimension`.

A widget may declare `function widget(state, size: number): ui.View` (the compiler accepts the second parameter, E2115 otherwise) and draw differently: `size` is 2, 3 or 4.
One with a single parameter is drawn the same everywhere. Make widget checks a size-aware widget at all three sizes, with each size's limits; `examples/widget-sizes.vera` shows a
plan with one figure on 2x2, a row more on 2x4 and a bar and a button more on 4x4. The Widget tab shows the card at the chosen size (chips under it).

The 8000-character budget bound before the node limit on the bigger cards, so the frame now goes into the binding **compact**: `CardModel.compactFrame` keeps on a node only what
differs from a new `CardNode`, `normalizeNodes` puts the defaults back in the card. Every example frame is under 70 % of its full size (the metrics widget: half).
Not measured on the phone: the cards placed at 2x4 and 4x4 with real content (see the next section for what was checked).

## Switches: ui.Toggle and ui.Checkbox

Both draw on the card (a pill with a knob; a rounded box with the check mark from `VeraIcons`) and are taps like a button: the card posts `{handler, on}`,
`LiveFormService.liveFormTap` runs `WidgetSession.tapSwitch` (token-checked, handler must be a switch on the shown frame) and the answer is the next frame. The handler takes
`(state, value: boolean)` as in the app. Measured on the phone (4x4 card, `examples/widget-switch.vera`): tap Focus then Done -> `VERA-FORM event action=setFocus on=true`,
both drawn on, about 9 ms each. Make widget counts them as buttons, runs each handler on and off and re-checks the view; the prompt has a SWITCHES paragraph.
Not done: multi-step motion presets and button press feedback (unmeasured on the card), and images (stage 7: `Image('memory://')` blanked the card).

## Motion: 25 presets by meaning, played as stages

`ui.Motion` has 25 presets, chosen by what the movement means so a prompt never needs a preset made for it: emphasis (pop, pulse, jelly, press,
flash, breathe), reaction (shake, nod, wobble, swing, recoil), gravity (bounce, hop, jump, fall), turning (spin, turn, tumble, flip), arrival
(fade, rise, zoom, slide), ambient (float, drift). Each is a table in `VeraMotion.motionStages`: a starting pose and stages
`[ms, dx, dy, scaleX, scaleY, rotation, opacity, curve]`. The card plays a preset as a **chain of platform animations**, each stage started from the
`onFinish` of the one before (`CardView.motionAnimation/advance`); the app samples the same table for the new presets (the six it had first keep their formulas).
Every preset lasts under `MOTION_BUDGET_MS` (1500; the chain stops about 2 s after a redraw) and ends where it should rest (`motion-check.js`).
Swing hangs from its top edge and wobble rocks on its base (`motionPivot`); up to 5 Motions play at once, each by its own touch (`LIVE_MAX_MOTIONS`).

Measured on the phone (a gallery widget with five Motions in the Widget tab at 4x4, frames about 290 ms apart): jump rises about 46 vp and lands in
three frames; spin turns the arrow through down, right, left and up; swing hangs and swings from the top. On the **home-screen card** (a project saved
from Make widget, card bound to it): a touch on the panda made it jump clear of the top of the card and settle in under a second.

Make widget with four short requests (a panda that jumps; a casino roulette wheel that spins; a tambourine and a drumstick; live weather in Moscow),
before and after the new presets and prompt paragraph (one attempt each, 2.5-3.6 s):

| request | before | after |
|---|---|---|
| panda | pop (a few pixels) | jump: leaps clear of the card |
| roulette | a dartboard, touch did nothing | a wheel of segments, spin |
| tambourine and stick | static, touch did nothing | two Motions: recoil (drum) and wobble (stick) |
| weather | static picture | float; **still not live**: no source was written for it |

Not solved: a card cannot loop, so rain "falling" or a sun that keeps shining is one movement per touch or refresh; a symmetric drawing (a wheel with
twelve equal segments) hides a spin (give it a mark or a ball); the model does not yet reach for `Vera.Source` for "live" on its own.

## Layers: a scene of parts that move on their own

`ui.Layers(style, width, height, children)` lays its children one over another, each in the middle, the first at the bottom (the app: a `Stack`; the card: a `Stack` in
each of the three builder levels). Each child can be its own `ui.Motion` around its own `ui.Surface`, so a stick swings while the drum recoils and clouds drift over a sky.
A `ui.Surface` above the first takes the style **`clear`** (no background of its own: `paintGfx(..., bare)`; without it the top layer hides the ones under it, found on the
phone). Up to 5 pictures and 5 Motions (`LIVE_MAX_SURFACES`, `LIVE_MAX_MOTIONS`, five canvas contexts). A touch on any part of a Layers plays **every** Motion in it
(`CardNode.links`: the slots a touch plays, set on the Layers too, even with one Motion). A part with no handler lets a touch through (`HitTestMode.None`), so the
topmost layer with a pointer under the finger runs it, and a touch that no part takes lands on the Layers. A touch on a Motion around a picture or a shape with no handler of
its own plays it too: the card posts `#touch` (`TOUCH_ACTION`), the host runs nothing and answers with a new frame, in which the movement plays. A Motion around only a
figure or a text has no touch of its own: it plays when its trigger changes, and a tap on it opens the app as before. Measured: stick over drum, one touch, both moved
(frames ~290 ms apart).

Make widget on the user's Moscow Weather app (live figures already in the program): "weather as a living scene that matches the current condition" gave, on the first
attempt, a sky, sun, clouds and rain/snow as separate layers chosen from the live weather code, each with its own Motion (sky breathes, clouds drift or float, rain falls); a touch
moved them all. With the earlier limit of 3 pictures the model had to drop a layer (found when the clouds vanished), hence 5.
A widget can only be live when the program already has the source (Vera.Source); Make widget does not add one.

## Light and depth: gradients, effects and the cover picture

A run of 15 short toy prompts (a frog that jumps, a drum, a fortune wheel, a night sky...) gave widgets that worked and looked flat: `std/gfx` had
only flat fills, and most pictures were a model-drawn dark square in the middle of the card. What the card can draw was measured first, on the phone,
with a throwaway block in `LiveCard` for one test project: a Canvas linear and radial gradient, `shadowBlur` (a glow), `globalCompositeOperation
'lighter'`, `ctx.filter = 'blur()'`, a dash and a bezier, and on components `radialGradient`, `shadow` and `blur()` all drew on the card. The SDK's
`@form` tags (`ohos_sdk/26/ets/dynamic/component/*.d.ts`) are a fast first check of what a card may use: not a conic gradient, `saveLayer`,
`Particle`, `transition`, `iterations` or `delay`. A card's script stops about 2 s after a redraw (an `onFinish` chain stopped after 3 steps even
with another animation running beside it), but native animations keep going: `Swiper` with `autoPlay` and `loop` turned its pages for over 3
minutes, a symbol's `HierarchicalSymbolEffect` for over a minute; `ImageAnimator` played once.

What a program draws with now (one painter, `GfxPaint.paintGfx`, for the app's Canvas, the card and the host's SVG proofs):

- `gfx.linear(x1, y1, x2, y2, colors)` and `gfx.radial(x, y, radius, colors)` are colours: a short string (`lin:...`, `rad:...`) any shape takes in
  place of a colour, so the frame's format did not change. The painter makes a canvas gradient of it in the units the shape is drawn in, so one inside
  a `gfx.group` moves with it. One that does not read is drawn in its first colour.
- `gfx.glow(blur, color, shapes)`, `gfx.shadow(dx, dy, blur, color, shapes)`, `gfx.blur(radius, shapes)` and `gfx.blend("add" | "screen" |
  "multiply", shapes)` hold shapes like a group (`GfxOp` kind `fx`, packed key `f`). A canvas does not scale a shadow or a filter with its
  transform, so their sizes are turned from surface units by the scale in force: a glow is as wide relative to the picture on a 4x4 card as on a 2x2.
  ArkUI reads a filter's `px` in the canvas's own unit, not in pixels (with the density factor a blur of 3 units spread over 130 px and vanished; found
  on the phone), unlike a path string.
- `ui.Surface("cover", ...)` is the card's background: the picture fills the whole card to its edges, past its padding (`gfxFit(..., cover)`), and
  the rest of the widget lies over its bottom on a veil of the card's colour (`CardModel.splitCover`, `coverScrim`; `LiveCard` and `WidgetPreview`).
  It takes no room from the rest (`nodeHeight`, `pictureRoom`); one per widget, not in a row or a `ui.Layers` (`coverError`). In the app it is
  drawn as `fill`.
- The Make widget prompt (MAKE IT LOOK GOOD) and the game prompt (`vera-surface-skill.txt`) say how: a ball is a circle in a radial colour lit from
  the top left, a sky a linear one, a thing standing has a soft shadow, a lamp a glow, a scene with a background is a cover picture.

Measured on the phone (`examples/widget-rich.vera` as a cover picture in a test project with a card): a sky in a gradient, a glowing moon, two lights
added, a lit ball with its shadow and a glowing ring, edge to edge on the card, "0 taps" over the veil; a touch counted and played `pop`; the same in the
widget screen at 2x2, 2x4 (the cover cut at the top and bottom) and 4x4, and in the app's full-screen run. Host checks: `gfx-check.js` (the functions,
their checks, the SVG of each effect, the scale, the frame round trip, the example within 60 shapes; `proofs/widget-rich.svg`), `live-widget-check.js`
(the cover in the frame, within the 8000-character budget, split from the tree with its Motion, one only, not in a row).

## Moving parts: what moves in life moves, about its own pivot

`ui.Motion` moves a whole picture, so in the toy run the clock case swung with its pendulum, the pointer spun with the wheel and the sky jumped with the
rocket. `gfx.moving(style, trigger, pivotX, pivotY, shapes)` marks the part of a drawing that moves: its shapes play a Motion preset about the part's own
pivot (in surface units: the top of the rod, the centre of the wheel), and the rest of the drawing stays. A touch anywhere on the picture plays every part,
and so does a change of trigger.

- **On a card** the extension cannot move a part of one canvas, so `WidgetSession.frame` splits the picture where its parts are into layers of the same box
  (a `ui.Layers` with `parts`): what is still under the parts, each part in a Motion of its own, what is still over them. Each layer is a picture (five on a
  card), at most three parts; the picture's pointer goes on the bottom layer and the scene's links play every part. The Motion carries the pivot as shares
  of its box (`CardNode.px`, `py`), which `CardView` gives `rotate` and `scale` as their centre. A part must be among the shapes the draw function returns
  (not in a group or an effect); a picture with parts must sit directly in the widget's column, since its layers take two levels. A `ui.Motion` around it is
  dropped, since the parts move by themselves (the model kept adding one).
- **In the app** `paintGfx` takes the parts' poses: each part plays from when its trigger changed or the picture was touched (`SurfaceBox.partStarts`,
  `partPoses` in `VeraPreview`), sampled from the same preset table, turned and scaled about its pivot, its offset turned from points into surface units.
  A surface with no frame loop gets a short repaint timer while a part plays. The host and the SVG proofs draw parts at rest.
- Two presets for things that leave and come back: `launch` (up out of sight, unseen back below, up into place) and `roll` (away to the side, turning, and back).
- Make widget refuses a `ui.Motion` around a scene (a cover picture or one that paints its own background): its background would move too. The reason asks for
  the thing to be a `gfx.moving` part, and for a cover picture in the same answer when it is not one yet, so one retry fixes both.

Measured on the phone: `examples/widget-pendulum.vera` in a test project with a card -- the case stayed and the rod and bob swung about the top, right, left,
right and still, and the count rose by one; the same in the app's full-screen run. Generated (six toy prompts, twice): with the checks, the rocket launched out of a
night sky that stayed, the frog hopped off a lily pad that stayed, the punching bag swung from a hook that stayed. The wheel and the pendulum were still written
without parts (the wheel spun whole, the pendulum did not move): the model reaches for gfx.moving only when a check says so. Host checks: `gfx-check.js` (the part
at rest and posed about its pivot, the preset check), `live-widget-check.js` (the layers, pivot, pointer, links, cover, the limits and the dropped Motion),
`widget-refine-check.js` (the scene check), `motion-check.js` (the two presets).

## A tap finishes what it started; a picture that does nothing is refused

A card has no frames, so a widget whose tap only starts something (a wheel set spinning, a die thrown) never finished it: on the phone the user's
Roulette card read "Spinning..." with its Spin button off for good, and the toy run's wheel the same. Now, after a tap (a button, a switch, a picture),
`WidgetSession` runs the app's own clock (the `ui.Surface` frame functions of `view` and its running `ui.Ticker` handlers at their intervals, asked again
every 5 steps since a tap often starts a ticker) on the state in steps of 33 ms (`SETTLE_STEP_MS`), as the app
would, and keeps the state they reach once 3 steps in a row change nothing (`settle`). What a frame asks of the phone (most generated wheels
vibrate on each tick) is dropped and never answered: the card can do none of it, and refusing it left the wheel spinning. A state that does not come to
rest within 600 steps (20 s; a generated wheel took 3.5 s, a generated rocket's 10 s countdown and launch 14 s) -- a game that plays on, a clock that counts -- is left as the tap left it, so the card never plays
on for the person; so is one whose frame traps, and one waiting for its live source. Measured on the phone: `examples/widget-wheel.vera` on a card -- Spin, and
the next frame read "Won 5" with Spin on again; a generated Fortune Wheel (a vibration on each tick) in the widget screen -- a touch, "Won 5", `VERA-WIDGET
settle rested steps=106 ms=8`. On the host 300 steps of a game that never rests took 5 ms.

A generated "Rocket launch" (a 10 s countdown on a `ui.Ticker`, then the rocket rises in the frames) showed two more gaps: only the frames ran, so the
countdown never ended; and its state never came to rest, since a field counted the animation's time by the same amount every frame (for a flame's flicker).
Now the running tickers run too, and a state whose only changing fields are such clocks for a second is at rest (`StateClocks`). On the phone two new
generations of the prompt: a tap finished the countdown and the launch on the card ("Liftoff complete"), and one written with a `gfx.moving("launch")`
rocket flew off its sky and came back. A button the app turns off once its work is over (a Start that waits for Reset) is no longer refused.

What settling costs: on a scene that never rests (a generated night sky whose stars twinkle on a clock) a tap first took 657 ms on the phone; most of it was
encoding the state, twice a step. Encoded once a step: 365 ms. Taking a state whose only changing fields are clocks at once from 10 s on
(`SETTLE_CLOCK_EARLY_STEPS`) rather than at the end of the 20 s: 186 ms. A wheel that lands takes a few ms.

The 15 toy prompts at the end of the day, on the phone, against the morning's run: 13 of 15 widgets made (bubble wrap still over the 60-shape picture limit;
the fish tank's third answer did not come). The frog hops off a lily pad that fills the card, the cat fills the card and is stroked, the die tumbles and shows
a new face, the rocket launches out of a sky that stays, the punching bag swings from its hook, the wheel lands on its result, the night sky's stars drift; the
pendulum still swings whole and one wheel was drawn as a single slice by the model.

Make widget holds two more things to the card:

- a picture that takes a touch and shows nothing for it: no ui.Motion or gfx.moving around it and the same card after the tap and the settling (`unseenTouch`;
  a generated countdown rocket stood on its pad: its tap started a countdown on a `ui.Ticker`, which the card did not run then);
- a button a tap leaves off for good (what it started does not come to rest in the card's 20 s): the reason asks for a handler of the widget's own that works
  out the result at once (`stuckButton`);
- a picture with no handler and no button, when the app's picture takes a touch: on the card it would only play a movement (8 of 14 toy widgets: a die that
  tumbled and kept its face, a cat that could not be stroked). The reason names the app's handler (`deadPicture`).

The prompt says a tap is finished by the app's frames for up to 20 s, and that a scene on a 2x4 card is drawn wide (with `widget(state, size)`), since a square
picture leaves its sides empty there and a square cover picture loses its top and bottom. Host checks: `live-widget-check.js` (the wheel lands from a button,
from a touch and with a vibration on each tick; a slow one stays as the tap left it; `examples/widget-countdown-rocket.vera`: a ticker's countdown runs out
and the rocket leaves), `widget-refine-check.js` (the two reasons, the prompt).

## Always moving: gfx.drift on the platform's Swiper

A card's script stops a couple of seconds after a redraw, so nothing we animate can loop there; the platform's own animations keep going. Measured with a
throwaway card (three strips of `Swiper` with `autoPlay`, `interval(0)`, `loop`, `curve(Linear)`): a strip of two identical pages slid at a steady
~115 vp/s, about a page a second (the page change's duration cannot be set on a card), with no stop between pages; a strip cut into eight slices with four
on view slid a quarter as fast; a vertical one turned over fell. All three were still moving 10 and 30 minutes later, the render service's CPU the same. The render service spent 1.13 s of CPU in 30 s with the three strips on screen
(about 4 % of one core) and 0.04 s with the card on another page: off screen the strips stop. The screen was not switched off (the phone would lock).

`gfx.drift(direction, speed, shapes)`: the shapes are a tile the size of the picture that slides on and on towards direction (`left`, `right`, `up`,
`down`) at speed (`slow`, `medium`, `fast`: the picture's width or height in 8, 4 or 2 pages of 1.05 s, `DRIFT_PAGE_MS`, `driftSlices`) and comes back in
from the other side; the painter draws the tile and a copy either side, so it joins up.

- **On a card** the picture is split into layers as for moving parts, and a drift is a layer of kind `drift`: a `Swiper` of its slices, all on view, each a
  canvas painting its slice of the picture (`paintGfx` with a shift), one slice a page, looping. Right is the strip laid right to left (`Direction.Rtl`),
  down the upward strip turned over with each slice painted upside down. Its canvases come from a pool of their own (16: two drifts of up to eight slices).
  A picture that starts with a drift gets an empty bottom layer for its touches; a drift layer lets touches through.
- **In the app** `paintGfx` takes a clock and draws the tile moved by the share of its period that has passed; a surface with a drift is repainted on every
  tick while it is on screen.
- The Make widget prompt (ALWAYS MOVING) says what is drawn with it, and keeps it to one or two.
- Measured on the phone (`examples/widget-sky.vera` as a cover picture on a card): the stars slid left and the clouds right while the moon stayed. A Swiper with no
  more items than it shows stood still, so its items are the strip twice over. A `gfx.blur` inside a drift showed a thin seam where slices meet (each slice
  blurs only what it holds), so the prompt keeps blur out of a drift. A touch through the drift layers reached the picture's handler.
- Generated (three prompts): a fish tank used `gfx.drift("up")` for its bubbles and a `gfx.moving` fish, on a cover picture; a field of clouds and a night
  sky did not use a drift (the clouds stood still), so the model reaches for it only some of the time.

Host checks: `gfx-check.js` (the literals, the tile and its copies, the travel with a clock, the frame round trip), `live-widget-check.js`
(`examples/widget-sky.vera`: the layers, the slices, cover, the bottom layer for touches, two at most).

## Wheels of slices: gfx.sector, and the pattern of moving parts in the prompt

Wheels came out as one slice: a wedge built from a stroked `gfx.arc` (round caps) or a hand-made `gfx.polygon` goes wrong. `gfx.sector(x, y, radius,
startDegrees, sweepDegrees, color)` is a filled pie slice, angles as `gfx.arc` (0 at twelve o'clock, clockwise): the painter goes from the centre out
along its start, round its rim and back (`GfxPaint.paintOp`), so the SVG proofs and the card draw it from the same code; it reuses the frame's fields
(x, y, r, start, sweep). The Make widget prompt's MOVING PARTS now carries an eight-line worked example -- a clock case that stays and a rod and bob in
`gfx.moving("swing", 0, 50, 15, ...)`, six sectors in `gfx.moving("spin", 0, 50, 52, ...)` under a pointer that stays -- and says it shows how parts
move, not a drawing to copy. The game prompt says a wheel, a pie or a pizza is sectors.

Measured on the phone (five short prompts, one widget each): the pizza's widget was eight `gfx.sector` wedges in two shades, drawn right on the card;
but none of the five used `gfx.moving`. The pendulum clock swung whole in a `ui.Motion("swing")`, the windmill turned whole in a `ui.Motion("spin")`
(sky and tower with it), the fortune wheel did not move at all (its tap landed it on a prize after the card's settling), and bubble wrap failed three
times (97 shapes, then a handler with a vibration, then a background). The generated wheel apps still drew their slices as polygons in a group. As
before, prose in the prompt moves the model only some of the time; the next steps put the guidance in checks. Host checks: `gfx-check.js` (a sector
is a closed wedge at the right angles, a whole turn a disc, a negative sweep anticlockwise, the frame round trip, six slices that meet),
`widget-refine-check.js` (the example in the prompt compiles in a draw function, and a widget of it passes Make widget's checks).

## Many of the same: gfx.repeat

Bubble wrap could not be drawn on a card: about 145 circles against 60 shapes for each card picture and 8000 characters for the whole frame.
`gfx.repeat(columns, rows, dx, dy, shapes)` draws its shapes `columns x rows` times. Each copy is `dx` further right and `dy` further down than the
one before. It is one `GfxOp` of kind `repeat`: its children are written once, and the painter repeats them (`GfxPaint.paintOp`). That keeps a
12 x 12 sheet short in the frame: `examples/widget-bubbles.vera` is under 2000 characters. Two counts are kept. `count` is the number of shapes
written: a card picture may hold 60 of these, and a repeat counts its children once. `drawn` is the number of shapes painted: every copy counts.
The app's 4000-shape frame limit (`MAX_GFX_SHAPES`) uses `drawn`. A card picture may paint at most 400 shapes (`LIVE_MAX_DRAWN`), and one repeat
may make at most 400 copies (`MAX_GFX_REPEAT`). The painter applies the copy limit as well, so a frame from anywhere else cannot paint more. A touch on the picture goes to the picture's pointer handler, as before.

The card's 60-shape refusal now says what to do: "Many of the same (bubbles, bricks, stars, dots in a grid) is one gfx.repeat(...), which counts
its shapes once; draw only what differs from copy to copy (a popped bubble) over it". The prompt says the same beside the limit.

One limit remains. Copies of a repeat cannot differ from one another, so whatever differs is drawn as shapes of its own. A sheet with more than about
50 popped bubbles, each drawn separately, goes over the 60 shapes again. When that happens, the card refuses to draw it, just as it did before
gfx.repeat existed.

Measured on the phone (seven runs: bubble wrap four times, a brick wall twice, a box of chocolates once). Each time the 60-shape refusal named
gfx.repeat, the model's next answer for bubble wrap used it (the answers are logged at debug level). One sheet of 10 x 10 lit bubbles became a cover
picture on the card, and a tap there popped a bubble ("99 bubbles left"). A second answer with a repeat was refused by the touch check: that check
touched only the middle of the picture, and on this sheet the middle falls between bubbles. It now tries six points (`TOUCH_POINTS`) before it calls a
touch unseen. On the host the same answer is then served. Of the other runs, one bubble wrap app had a small sheet (48 bubbles) and needed no repeat.
One run failed: a depth error, then no answer from the model. The two brick walls (66 and 68 shapes) failed on other checks, without a repeat. The
box of chocolates fitted as it was. Make widget now logs `attempt N failed: no answer` when the model sends nothing back
(`AgentWidget.writeWidget`). Host checks: `gfx-check.js` (copies at their offsets, written once and painted every time, whole columns, the 400-copy
trap, the app's limit counting copies, a forged frame not painted, the bubble wrap example within 60 shapes, `proofs/widget-bubbles.svg`),
`live-widget-check.js` (the sheet in a small frame, a tap pops a bubble, the same sheet as 144 shapes refused with the gfx.repeat reason, a
repeat that paints 807 refused), `widget-refine-check.js` (the prompt, the example's widget passes, a touch between bubbles is not the only one tried).

## Deferred / known limits

- Habit-list fixture, ListGroup/ListItem and remaining card-safe components.
- Actual platform payload maximum, large form sizes, dark mode and full visual/accessibility QA.
- Removal/rebind lifecycle device coverage and foreground resume to an existing runner without a new router push.
- Last-writer-wins state is intentional; binding-map updates currently use read/modify/replace from two processes (the app binds,
  the extension unbinds) with no lock, so truly concurrent bind/remove operations can overwrite each other.
- Timer/game programs are not supported widget fits.
- Independent QC gate remains required before treating the slice as ready to merge.
