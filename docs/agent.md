# The agent: how a new screen is built

A new screen (the Generate screen, or a widget in the chat) is built by the **route** (`agent/VeraBuildRoute.ets`): the **agent**, then
the **whole screen as one hole**. What neither builds is handed to the model to write from scratch on the Generate screen (the chat
reports it as *not built*, with the reason). A change to an existing program goes to the model (refine), as before.

The idea: planning and building each have a fast path, where Jev picks something ready, and a slow path, where the model writes it. A simple
request is built from Jev's picks alone; the more a request asks that nothing ready does, the more of it the model writes, down to the whole
screen. **The composer's parts and the catalogue's sections are chosen together**, by the same Jev call, so there is no second planner: a
separate pick of sections and a layout from the request alone (`VeraTemplatePipeline.ets`, "the blocks") used to follow the agent, and was
removed from the route because it never served -- none of the 121 prompts of the table below, none of 22 more on the merged choice.

## Terms

| term | what it is | where |
|---|---|---|
| **sketch** | the plan, as DeepSeek (no thinking) writes it: a JSON object of inputs, constants, values with formulas, a countdown or stopwatch, a list, events (what the phone does, and when), *ready* needs (things a catalogue section does whole), other items, and at most two questions | `VeraCompose.ets` (`SKETCH_BASE`, `parseSketch`) |
| **Jev's choices** | one Jev call over the sketch: a formula for each value, a widget for each input, an effect and a moment for each event, a catalogue section for each ready need, what is covered or left out | `buildComposeRequest`, `readComposition` |
| **block** | one piece of a program in the one format (`FragmentSpec`): state fields, handlers, a view, and tokens for content, ports and holes. The catalogue's **sections** (checklist, itinerary, timeline, charts, timer, reminders, ...) and the composer's **parts** (inputs, figures, clock, list, effects) are both blocks | `VeraTemplates.ets`, `compositionParts` |
| **ScreenPlan** | the one plan format both paths give: the screen's *state* (named values), its *slots* (each thing it does, with what it reads and writes, and whether it is a phone action) and the *components* that fill them. A slot is *open* until something fills it; a plan with an open slot is not served | `ScreenPlan.ets` |
| **effect** | one of six phone actions the composer wires itself: vibrate, beep, add to calendar, navigate, clear calendar, open calendar | `EFFECTS` in `VeraCompose.ets` |
| **hole** | what the model writes for slots nothing ready fills. A *catalogue hole* is one function body inside a section; a **section hole** is a whole section for the open slots; the **whole-screen hole** is the screen as one section | `VeraHoles.ets`, `agent/AgentHole.ets`, `agent/AgentCustom.ets` |
| ~~blocks~~ (removed) | Jev's pick of a layout and sections straight from the request, without a sketch; `VeraTemplatePipeline.ets` stays in the tree for the harness (`align-lib.js`) and as a reference, the route no longer calls it | |
| **notice** | a warning banner in place of what could not be built: "Not available on this phone" with the writer's own sentence, or "Part of this app could not be built" | `noticeBlock` in `agent/AgentHole.ets` |

## The algorithm

1. **Plan.** DeepSeek writes the sketch. One that is missing or does not parse is asked for again with what was wrong,
   then once with thinking on.
2. **Questions.** Jev keeps only the sketch's questions a default cannot stand in for; the person answers on a card,
   and an answer other than the default has the plan drawn again.
3. **Choices.** One Jev call (asked twice if it does not answer) decides how each item is built. What the plan leaves
   open is settled, not refused:
   - a countdown nothing sets the length of, or a figure the parts read that no formula works out, becomes an input
     the person sets, starting from the plan's own number, and the person is told;
   - an event no effect does as asked, the person's own records, a figure nothing works out, an item of "other",
     a ready need with no section: a slot for the written section;
   - an input nothing uses is left out, with a note.
3-. **Part or section, one question.** Where a part and a section of the catalogue can both do a need, the same Jev call asks once
   with the part among the options (`clock.part`: the part or `timer`; `list.part`: the part, `record_log` or `reminders`;
   `chooseSections` in `VeraCompose.ets`). A confident pick (the bar of any ready pick) takes the part's place -- the part is gone from the
   program, the section has a slot of its own (`section.<kind>`) and is read against the need by the claims check -- unless something
   else on the screen is wired to the part: a countdown the person sets the length of, a value that reads the time left or the entries,
   an event at the countdown's end or on an entry (`canReplaceClock`, `canReplaceList`). Those keep the part. A section is never added
   beside the part that does the same: Align's pool leaves out `timer` beside a countdown or a stopwatch and the entry-keeping sections
   beside a list that is wired to something (`alignKindsFor`), and gives a list up for the section it chose when nothing is wired to it.
   The `timer` section counts down from set times and has no stopwatch, so a stopwatch is always the part. `--ps veraUnified 0` keeps
   the parts always. Host check `merge-check.js`; live on the host (6 short prompts): a fixed countdown is not offered a second timer, a list of
   daily medicine reminders is one `reminders` section and no list part, a plain list of books and an expense log with a total stay parts.
3a. **Align** (on by default, `--ps veraAlign 0` turns it off; `AgentAlign.ets`). What the choices leave for the model to write -- a ready
   need no section was chosen for, an event no effect does, an item of "other" -- is offered to the catalogue once more:
   one Jev question per such need, whose answers are a ready-made section (the plan's ready kinds, `reminders`,
   `calendar_event`) or none. A section at 0.5 or more is added once, whatever number of needs it does, and takes those
   needs out of what is written; what Jev finds none for is still written. The person's own records and the figures
   worked out by a written formula are never offered, and a section the screen already has does not stand in for a need.
   When nothing is left to write, the inputs the composer kept only for the written section are dropped. Measured so far:
   8 prompts live, one changed (`set an alarm for my medication every day` is a `reminders` section instead of a notice)
   and none given a section wrongly; not yet run on the 121 prompts or on a phone.
   The default pool (`--ps veraAlign 1` gives the plain one: ready kinds, `reminders`, `calendar_event`) offers every section that stands alone, not only the plan's ready kinds (timer, note, rating,
   record_log and progress_goal as well), bar `actions`, `metrics`, `intent_panel` and `filter_box`. What is still left is then
   asked once more among the **readers** (`list_summary`, `number_strip`, ...) a section on the screen can feed: every port the
   reader reads must be published, by name and type, by a section chosen already (`readerKinds`). Host-checked (`align-agent-check.js`) and run on
   the phone on five short prompts: no section was chosen wrongly (`reminders@0.97` for a daily water reminder, `none` for a workout timer
   with notes), the readers' question was never reached (a checklist's "how many are done" is dropped before Align sees it).
   The composer's parts publish ports too (`compositionParts`): the inputs a person sets, the list's `entries` and `count`,
   and, only when a section on the screen reads a port, each value as a function `port_<id>(state)`. A section that reads
   a name a part publishes is bound to it by name; naming is the plan's, so this meets rarely until the plan's values
   are matched to a reader's ports by a question of their own (not built).

4. **Fill.** The catalogue sections' content is written (from a web search when it must be real) and their holes
   filled, by the one fill both the agent and the blocks use (`SectionFill.ets`): a trend chart or a live-facts block is
   always grounded in a search whatever the plan said (the chart with the longer results), a live-facts block shows only
   the figures and the source that search contains, and with no search the sections are refused.
4b. **Slots and claims.** What each chosen section offers (a button for each item, a calendar, a style) is read from the
   request by one Jev call (`buildSlotRequest`); without it the catalogue's defaults leave out what the request asks for.
   What the composer left out because a section is said to do it (`comp.claimed`) is then read against the assembled
   screen (`agent/AgentClaims.ets`); a claim the screen does not meet goes back to the plan as a slot to write, and the
   hole that follows writes it or reports it. The plan's own questions to the person are part of every "did the request
   ask for this" question to Jev (inputs, figures, fields and items of "other" alike).
5. **Section hole.** One section is written for the open slots (`writeHole`, `writeSection`):
   - for every need the app's own lookups run first (in parallel; the plan's `phone` flag no longer decides whether to look) (`find_intent_function`, keyword and embedding rankings
     together; `find_sdk_function`), and the section may call only targets they returned -- every `sdk.call` target is
     checked before serving;
   - it is compiled and run once with every handler tapped; failures are quoted back for a repair, at most twice;
   - Jev reads it against each need; a need it reads as not done is asked for again;
   - after the quick tries, one more with thinking on;
   - still failing: the best try that works and does part of it is served with a notice for what it misses; none, a
     notice in its place; `<cannot>` (nothing on this phone does it) is reported as the writer says and not retried;
   - needs are decided one by one: the writer may decline a need with `<cannot need="...">` and write the section for the
     rest (the declined need gets its own notice, in the writer's words); a bare `<cannot>` for a hole of several needs
     is not taken for the answer to each -- every need is then written on its own with only the functions found for it.
6. **Check.** The assembled program is compiled, started, drawn and run with every handler tapped (`VeraSmoke.ets`); one
   that fails, or draws an empty screen, is repaired with SEARCH/REPLACE edits, at most twice (`settleProgram`). Every
   program served goes through it, whoever assembled it: the agent, the blocks, a written section or the whole screen.
   **Record.** A served screen that rebuilds exactly from its plan gets a record (`VeraComposition.ets`, `AgentResult.record`):
   the plan's components in order, the catalogue's blocks with their values and hole bodies, everything else (the composer's
   parts, a written section, a notice) as it is. A request to add a section, take one away, swap or move one is then
   answered without the model (`tryStructuralEdit`); it may point at the catalogue's blocks and the written section or
   notice, never at a part (the parts hold each other's state). No record when the repair edited the program, and none is
   kept that does not rebuild the served one. A chat widget is not edited this way.
7. **Whole screen**, when the agent did not build it: the sketch as one hole, with the same lookups and checks.
8. **Not built**, with what the agent said.

A request's holes share what they learned: a phone need one hole found nothing can do is reported by the next as it
said, and each lookup is made once. A refusal of several needs together is not remembered for any of them.

## What a screen says about itself

- A notice (something could not be built, or is not available on this phone) removes the screen's subtitle: the plan wrote it
  before anything was built, and a subtitle that promises what the notice denies contradicts it (`quietSubtitle`,
  `AgentHole.ets`).
- The plan may say how many digits a plain number is shown with (`decimals`, 0 to 6; list fields and values), because one digit
  rounds a measurement into nonsense; money, percent and counts keep their own.
- The section writer is told that a need worded as something to do inside the app that the app cannot do (it has no such
  component) is not refused when a function found does the nearest useful thing in the app made for it, and to say on the screen
  what it does instead (`phoneRule`, `AgentCustom.ets`).
- The time the person takes to answer a question of the plan is measured apart (`Asked.waitedMs`) and said apart ("Composed in
  5.6 s (and 6.6 s waiting for your answer)"): it is theirs, not the app's.
- The Metrics tab shows the last run of the previous session when this session has run nothing (`LastRun.ets`,
  `{filesDir}/vera/last-run.json`).

## Results

Host runs (`tools/vera-harness/agent-run.js -r`, the 121 prompts of `compose-fresh.tsv`, `compose-prompts.tsv` and
`tools/vera-bench/prompts.tsv`), 2026-10-22. The host has no phone lookups, so a phone action there always ends in
a notice; on the phone the same prompts call the phone.

| how it was built | prompts | median | p90 |
|---|---|---|---|
| agent, composer parts only | 88 | 2.0 s | 2.5 s |
| agent + written section | 17 | 6.7 s | 14.4 s |
| agent + notice (phone actions, live data) | 13 | 5.8 s | 9.5 s |
| agent + catalogue sections | 3 | 5.6 s | 7.1 s |
| blocks, whole screen, not built | 0 | | |

Eight game-like requests (tic-tac-toe, hangman, memory, flashcards, ...): all written by the agent, 5-13 s.

On the phone: Shanghai layover 10-23 s, soft-egg timer 2.5 s, to-do list 14 s, hangman 20 s, contacts 6-9 s,
melody with the flashlight 22.6 s; "set an alarm" and "share my location" 6-7 s with a notice (the phone exposes no
target that does either). Generation from scratch, which these replace, took over 30 s for requests like Shanghai and
the melody.

## The merge, measured (host, 2026-10-26, short prompts)

The six prompts of `docs/prompts/block-composition.md` that the removed blocks stage built without a model, before and after the parts and
the sections were chosen together (same run, same Jev and DeepSeek; the host has no web search):

| prompt | before | after |
|---|---|---|
| shared costs between friends, who owes whom | 8.7 s, one section written by the model | 8.6 s, `record_log` + `number_strip` + `breakdown_table` + `settle_up`, one section written |
| roommates split groceries and rent | 8.6 s, written | 4.9 s, `record_log` + `settle_up`, no model |
| log workout minutes, bar chart | 15.5 s, four sections written | 4.0 s, `record_log` + `series_chart` + `number_strip`, no model |
| budget tracker with category charts | refused (a chart section with invented data) | 10.1 s, `record_log` + `series_chart` + `number_strip` + `progress_goal` |
| hours worked per team member | refused | 7.5 s, `record_log` + `breakdown_table` |
| points per player in a board game | 7.0 s, written | 3.9 s, `data_table` (the entries are the person's: see the known problems) |

Fixed after that table, one by one (host runs of the same prompts, then the phone):
- A section that writes content of its own (a checklist's items, a table's rows) is not given a need about the person's own data -- what they
  entered, what is worked out from it, marks on their own entries (`whose.N` in Align's request, read by the probability of "own", as the
  composer's own `whose` question is; the two cases were `checklist` for "mark a settlement as paid" and `data_table` for the people's scores).
  Readers, the sections that keep entries and the phone ones are not refused.
- A need left to write is read against the screen the chosen sections make (`claimsDone`, `AgentClaims.ets`): a detail the log already
  settles in its own way ("a category picker") is not written again; with no answer from Jev nothing is taken for done.
- A total or the entries' own numbers of minutes or seconds are shown as "150 min", not as 2:30:00 or 0:00 (`showEntryTotalsAsNumbers`,
  `entryAmountText`); a countdown is still a clock.
- The run-to-run differences seen between the host and the phone came from the sketch DeepSeek writes: the same prompt gave the same
  choice 10 times of 10 on the host (`workout` and `budget`, `record_log` at 0.55 to 0.92), and on the phone after the fixes.

Still open: a stopwatch is always the part (the `timer` section only counts down), and what to do with a detail Jev is unsure the log does.

## Switches and tools

- `--ps veraCustom 0` turns written sections off;
  `--ps veraWhole 0` the whole-screen hole; `--ps veraAlign 0` turns off the offer of what would be written to the catalogue first (`1` for the plain pool);
  `--ps veraUnified 0` keeps a countdown and a list the person fills in as parts, without asking whether a section does them.
- `--ps veraNeeds 1` (off by default, branch `cortex/needs-plan`) draws the plan as a list of *needs* (`NeedsPlan.ets`: the model is told nothing of
  the parts or the catalogue), then asks Jev once, per need that a part and a section can both do, which does it (`NeedsChoose.ets`:
  a countdown, entries the person keeps, content written for the request). What a section cannot stand in for is taken out of the
  options from the plan's own facts first (`timerMayTakeCountdown`, `listSectionsFor`). The answers go to the composer under the keys
  it reads (`clock.part`, `list.part`, `ready.N`, `whose.N`, `real_data`) and its own call no longer asks them. Host checks
  `needs-plan-check.js`, `needs-choose-check.js` (`VERA_TYPESCRIPT_PATH` names a `typescript` package; the kit's is under
  `~/agent-kit-sdk/command_line_tools/ohpm/node_modules/typescript`).
- `tools/vera-harness/agent-run.js [-r] [-w]` runs the agent (or the whole route: the agent, then the whole screen) live on the host: DeepSeek
  (`$ARKESTR_API_KEY`), Jev (`$TYPESAFE_API_KEY`), Exa (`$EXA_API_KEY`, optional).
- Every written hole is recorded: a `hole` event in the app's trace, `holes.jsonl` beside each host run.
  `tools/vera-harness/hole-report.py` groups the needs that recur -- the blocks the catalogue lacks.
- Host checks: `tools/vera-harness/{agent,plan,parts,compose,route,pipeline,section-fill,align,align-agent}-check.js`; fixtures in
  `tools/vera-harness/compose/`.

## Known limits

- This phone has no target that creates a Clock alarm, texts a phone number (MeeTime's `SendTextMessage` takes a
  MeeTime contact id) or shares the live location; such requests end with a notice.
- `contacts/AddContact` wants a vCard in `contactInfo`; the intent index does not say so, and the call is declined.
- Jev reads code, not behaviour: a melody section whose beats all fired at once was read as doing its job.
- Each live run of the 121 prompts makes several hundred Jev calls.

## Screen shortcomings found in a 20-prompt phone run, and what was done (2026-10-27)

Twenty short prompts were run on the phone before and after; every one was served, none fell to a generation. Fixed:
the notice for a part that could not be built is one plain sentence (`agent/AgentHole.ets`, no plan wording on screen); `checklist` rows no
longer say "not done" and use a list icon, and it is not offered for a deck of cards; the header has no icon unless there is a clock or a list;
the itinerary row has no coordinates; a number field names its unit when the label does not (`labelWithUnit`); choice options "25 minutes"
whose values are 1500 are seconds, not minutes; a fraction shows four digits; a section the model writes is told what the parts already hold
(`partsContract`, `PartsContract` in `VeraCompose.ets`) and is asked again, at most twice, when it makes its own clock or list
(`repeats` in `agent/AgentCustom.ets`); a need for a progress bar is not given to `progress_goal` when a fraction value is already drawn as one
(`alignCandidates`); Align is told what the screen already shows; `claimsDone` also reads screens made of parts alone.

Not fixed: the dice roller gets a log with a Result field (left as it is); two blocks for laps still appear in some runs (a list of laps and a
"Lap splits" view of the same entries) because the writer sometimes keeps its own; "Average mood 0.0" with no entries; a BMI category;
an empty chart plate when a chart has no data yet.
