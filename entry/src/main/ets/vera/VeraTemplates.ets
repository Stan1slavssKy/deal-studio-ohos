/**
 * Experiment only (experiment/jev-template-select branch): two hand-written,
 * self-contained `.vera` programs, each with a few cosmetic placeholder
 * tokens that VeraTemplateSelect.ets fills in from a closed set of values
 * before handing the result to compileVeraSource (see VeraTemplateSelect.ets's
 * header comment for why those are closed-set, Jev-answerable choices).
 *
 * A second kind of token, declared below as ContentFieldSpec, holds the
 * title and item/label text instead. These are NOT answered by Jev -- they
 * are filled, best-effort, by VeraTemplateContent.ets's separate narrow
 * generative call, with a literal fallback (the values below) on any
 * failure. This is the one place in the pipeline that renders text from the
 * user's own request rather than a fixed closed-set identifier.
 *
 * Shape follows docs/examples/shanghai-layover.vera: import, @jsonable state,
 * init(), pure updaters, view(). Only `//` comments are legal in this
 * language -- a /* block *\/ will not parse.
 *
 * Every style token substituted into these two sources is one already
 * registered in VeraUiCatalog.ets's STYLE_SETS (apptheme, header, listgroup,
 * metricgroup, intstat) -- checked there, not invented here.
 */

export class SlotSpec {
  /** Token text in the template source, e.g. "__THEME__". */
  token: string
  /** Allowed values, in the order offered to Jev. First is the safe default. */
  values: string[]
  /** 'choice' or 'noul' -- which Jev question shape asks for this slot. */
  kind: string
  /** Question text sent to Jev for this slot. */
  instructions: string
  /** criteria text per value, only used for 'choice' slots (key = value). */
  criteria: Map<string, string>
  constructor(token: string, values: string[], kind: string, instructions: string, criteria: Map<string, string>) {
    this.token = token
    this.values = values
    this.kind = kind
    this.instructions = instructions
    this.criteria = criteria
  }
}

/**
 * A shared yes/no gate asked once per request, independent of which template
 * matches -- unlike SlotSpec there is no token to substitute and no `values`
 * list, just a probability that can kill the whole pick. See readPick's veto
 * loop in VeraTemplateSelect.ets.
 */
export class VetoSpec {
  /** Stable key in the request/response, prefixed "veto." there. */
  key: string
  instructions: string
  /** criteria text for 'true'/'false', same shape as a SlotSpec noul's. */
  criteria: Map<string, string>
  /**
   * Above this probability, this question alone kills the pick. Each veto
   * gets its own bar rather than one shared constant: the gold-set sweep in
   * tools/template-select-eval.py found that a single shared threshold
   * cannot separate every question's true-accept distribution from its
   * true-reject distribution at once -- e.g. a music player's "needs a phone
   * API" answer (~0.45, must stay rejected) sits well below a grocery list's
   * "needs search" answer (~0.59, must stay accepted), so no single cutoff
   * works for both dimensions simultaneously; each question's own bar does.
   */
  above: number
  constructor(key: string, instructions: string, criteria: Map<string, string>, above: number) {
    this.key = key
    this.instructions = instructions
    this.criteria = criteria
    this.above = above
  }
}

/**
 * One free-text display field inside an already-picked template: a title or
 * an item/stat label. Unlike SlotSpec/VetoSpec this is never asked of Jev --
 * it is filled by VeraTemplateContent.ets's separate narrow generative call,
 * with `fallback` used verbatim whenever that call fails for this field.
 */
export class ContentFieldSpec {
  /** Token text in the template source, e.g. "__TITLE__". */
  token: string
  /** JSON key asked of the content-fill model, e.g. "title". */
  key: string
  /** Literal fallback -- exactly today's hardcoded copy. */
  fallback: string
  /** One-line instruction fragment used to build the content-fill prompt. */
  hint: string
  /** Hard cap on visible characters, enforced before substitution. */
  maxLength: number
  /** True for a bare int literal spliced unquoted into an array (e.g. a chart value), not a quoted string. */
  numeric: boolean
  constructor(token: string, key: string, fallback: string, hint: string, maxLength: number, numeric: boolean = false) {
    this.token = token
    this.key = key
    this.fallback = fallback
    this.hint = hint
    this.maxLength = maxLength
    this.numeric = numeric
  }
}

export function contentFieldsFor(templateId: string): ContentFieldSpec[] {
  if (templateId === 'list_detail') {
    return [
      new ContentFieldSpec('__TITLE__', 'title', 'Checklist', 'Short title for the whole list (2-4 words)', 24),
      new ContentFieldSpec('__ITEM1__', 'item1', 'First item', 'Name of the first checklist item', 28),
      new ContentFieldSpec('__ITEM2__', 'item2', 'Second item', 'Name of the second checklist item', 28),
      new ContentFieldSpec('__ITEM3__', 'item3', 'Third item', 'Name of the third checklist item', 28)
    ]
  }
  if (templateId === 'dashboard') {
    return [
      new ContentFieldSpec('__TITLE__', 'title', 'Demo Dashboard', 'Short title for the dashboard screen (2-4 words)', 24),
      new ContentFieldSpec('__STAT1_LABEL__', 'stat1_label', 'Count', 'Label for the first number shown (1-2 words)', 16),
      new ContentFieldSpec('__STAT2_LABEL__', 'stat2_label', 'Total', 'Label for the second number shown (1-2 words)', 16),
      new ContentFieldSpec('__STAT3_LABEL__', 'stat3_label', 'Remaining', 'Label for the third number shown (1-2 words)', 16)
    ]
  }
  return []
}

export class TemplateSpec {
  id: string
  /** What this template is, shown to Jev as the criteria text for the top-level pick. */
  criteria: string
  source: string
  slots: SlotSpec[]
  constructor(id: string, criteria: string, source: string, slots: SlotSpec[]) {
    this.id = id
    this.criteria = criteria
    this.source = source
    this.slots = slots
  }
}

const BANNER_SHOWN: string = `,
    ui.Section("supporting", "", "", [
      ui.InsetBanner("default", "Demo banner", "This screen comes from a canned template; nothing here is personalized.", "", "", "info")
    ])`

const LIST_DETAIL_SOURCE: string = `import * as ui from "std/ui"

@jsonable
class Item {
  label: string;
  done: boolean;
}

@jsonable
class AppState {
  items: Item[];
  lastToggled: int;
}

function init(): AppState {
  let items: Item[] = [
    {label: "__ITEM1__", done: false},
    {label: "__ITEM2__", done: false},
    {label: "__ITEM3__", done: false}
  ];
  return {items: items, lastToggled: -1};
}

function toggle(state: AppState, index: int): AppState {
  let out: Item[] = [];
  let i: int = 0;
  while (i < state.items.length()) {
    let it: Item = state.items[i];
    if (i === index) {
      out.push({label: it.label, done: !it.done});
    } else {
      out.push(it);
    }
    i = i + 1;
  }
  return {items: out, lastToggled: index};
}

function view(state: AppState): ui.View {
  let count: int = state.items.length();
  let doneCount: int = 0;
  let i: int = 0;
  while (i < count) {
    if (state.items[i].done) { doneCount = doneCount + 1; }
    i = i + 1;
  }
  let rows: ui.View[] = [];
  let j: int = 0;
  while (j < count) {
    let it: Item = state.items[j];
    let icon: string = "pin";
    let subtitle: string = "not done";
    if (it.done) { icon = "check"; subtitle = "done"; }
    rows.push(ui.ListItem("default", it.label, subtitle, "", "toggle", j, true, icon));
    j = j + 1;
  }
  return ui.AppTheme("__THEME__", "", [
    ui.Header("__HEADER_STYLE__", "__TITLE__", "", ui.intToString(doneCount) + " of " + ui.intToString(count) + " done", "check"),
    ui.Section("content", "", "", [
      ui.When(count === 0, ui.EmptyState("default", "Nothing here", "Add an item to get started.", "", "", "pin")),
      ui.When(count > 0, ui.ListGroup("__LIST_STYLE__", "", rows))
    ])__BANNER_SECTION__
  ]);
}
`

const DASHBOARD_SOURCE: string = `import * as ui from "std/ui"

@jsonable
class AppState {
  count: int;
  total: int;
}

function init(): AppState {
  return {count: 0, total: 100};
}

function increment(state: AppState, ignored: int): AppState {
  return {count: state.count + 1, total: state.total};
}

function reset(state: AppState, ignored: int): AppState {
  return {count: 0, total: state.total};
}

function view(state: AppState): ui.View {
  let remaining: int = state.total - state.count;
  return ui.AppTheme("__THEME__", "", [
    ui.Header("default", "__TITLE__", "", "A canned template screen with generic numbers", "clock"),
    ui.Section("summary", "", "", [
      ui.MetricGroup("__METRIC_STYLE__", 3, [
        ui.IntStat("default", "__STAT1_LABEL__", state.count, "", "", 1, "", "pin"),
        ui.IntStat("__ACCENT_STAT__", "__STAT2_LABEL__", state.total, "", "", 1, "", "check"),
        ui.IntStat("default", "__STAT3_LABEL__", remaining, "", "", 1, "", "clock")
      ])
    ]),
    ui.Section("content", "", "", [
      ui.ActionBar("spread", [
        ui.Button("primary", "Add one", "increment", 0, true),
        ui.Button("secondary", "Reset", "reset", 0, true)
      ])
    ])__BANNER_SECTION__
  ]);
}
`

function bannerSlot(): SlotSpec {
  let criteria: Map<string, string> = new Map<string, string>()
  criteria.set('true', 'yes, show one')
  criteria.set('false', 'no')
  return new SlotSpec('__BANNER_SECTION__', ['hide', 'show'], 'noul',
    'Does this app need a standing info note visible at all times?', criteria)
}

function listDetailSlots(): SlotSpec[] {
  let theme: Map<string, string> = new Map<string, string>()
  theme.set('clean', 'restrained and neutral')
  theme.set('soft', 'calm and friendly')
  theme.set('expressive', 'bold and atmospheric')
  let header: Map<string, string> = new Map<string, string>()
  header.set('default', 'left-aligned')
  header.set('center', 'centered')
  let density: Map<string, string> = new Map<string, string>()
  density.set('default', 'normal spacing')
  density.set('compact', 'tighter spacing')
  density.set('comfortable', 'looser spacing')
  return [
    new SlotSpec('__THEME__', ['clean', 'soft', 'expressive'], 'choice',
      'Which look fits best: clean (restrained), soft (calm, friendly) or expressive (bold)?', theme),
    new SlotSpec('__HEADER_STYLE__', ['default', 'center'], 'choice',
      'Should the title block be left-aligned (default) or centered?', header),
    new SlotSpec('__LIST_STYLE__', ['default', 'compact', 'comfortable'], 'choice',
      'How dense should the list rows be?', density),
    bannerSlot()
  ]
}

function dashboardSlots(): SlotSpec[] {
  let theme: Map<string, string> = new Map<string, string>()
  theme.set('clean', 'restrained and neutral')
  theme.set('technical', 'dense, precise numbers')
  theme.set('playful', 'energetic')
  let density: Map<string, string> = new Map<string, string>()
  density.set('default', 'normal spacing')
  density.set('compact', 'tighter spacing')
  density.set('spacious', 'looser spacing')
  let accent: Map<string, string> = new Map<string, string>()
  accent.set('default', 'no, same tone as the rest')
  accent.set('accent', 'yes, highlighted')
  return [
    new SlotSpec('__THEME__', ['clean', 'technical', 'playful'], 'choice',
      'Which look fits best: clean (restrained), technical (dense, precise) or playful (energetic)?', theme),
    new SlotSpec('__METRIC_STYLE__', ['default', 'compact', 'spacious'], 'choice',
      'How dense should the summary numbers be?', density),
    new SlotSpec('__ACCENT_STAT__', ['default', 'accent'], 'choice',
      'Should the middle number stand out with an accent tone?', accent),
    bannerSlot()
  ]
}

export function templates(): TemplateSpec[] {
  return [
    new TemplateSpec('list_detail',
      'A browsable list of items the person can check off or mark one at a time',
      LIST_DETAIL_SOURCE, listDetailSlots()),
    new TemplateSpec('dashboard',
      'A small dashboard of a few summary numbers with a couple of actions',
      DASHBOARD_SOURCE, dashboardSlots())
  ]
}

export function bannerLiteral(): string { return BANNER_SHOWN }

/**
 * Bare view expression for the same banner, for VeraSectionCompose.ets's composer -- which
 * builds `view()` as a sequence of `sections.push(...)` calls rather than one array literal, so
 * it needs the banner as a standalone `ui.Section(...)` expression, not BANNER_SHOWN's
 * leading-comma array-splice text.
 */
export function bannerSectionView(): string {
  return `ui.Section("supporting", "", "", [
      ui.InsetBanner("default", "Demo banner", "This screen comes from a canned template; nothing here is personalized.", "", "", "info")
    ])`
}

/**
 * One field in a FragmentSpec's merged AppState contribution. `name` contains the literal
 * substring "IDX", substituted by the composer with the fragment's 1-based slot instance number
 * so two instances of the same kind never collide (e.g. "itemsIDX" -> "items1"/"items2").
 */
export class StateFieldSpec {
  name: string
  type: string
  constructor(name: string, type: string) {
    this.name = name
    this.type = type
  }
}

/**
 * A list-valued parameter of a fragment: a run of rows whose count the model chooses, between
 * `minRows` and `maxRows`, where a ContentFieldSpec is always exactly one string. The expanded rows
 * are spliced into the fragment text at `token` the same way a content field's value is, so the
 * composer needs no special case -- see VeraTemplateContent.ets's expandListRows for the checks
 * every row goes through (shape, count, length, escaping) and the fallback when the answer is not
 * usable.
 */
export class ListFieldSpec {
  /** Token in the fragment text, containing "IDX", e.g. "__ITEMS_IDX__". */
  token: string
  /** JSON key asked of the content-fill model, e.g. "items". */
  key: string
  /** What the rows are, one line, for the model. */
  hint: string
  /** One entry per column: what the column holds, for the model. A one-column list is an array of strings. */
  columnHints: string[]
  /** Character cap per column, enforced before substitution. */
  columnMax: number[]
  /** Text of one row; "{0}", "{1}", ... stand for the (already escaped) column values. */
  rowTemplate: string
  /** Text placed between rows. */
  separator: string
  minRows: number
  maxRows: number
  /** The rows used when the answer is missing or unusable; one string[] per row, one string per column. */
  fallbackRows: string[][]
  /** Indices of columns that are whole numbers, spliced unquoted (as a bare int literal) instead of as escaped text. */
  numericColumns: number[]
  constructor(token: string, key: string, hint: string, columnHints: string[], columnMax: number[], rowTemplate: string,
      separator: string, minRows: number, maxRows: number, fallbackRows: string[][], numericColumns: number[] = []) {
    this.token = token
    this.key = key
    this.hint = hint
    this.columnHints = columnHints
    this.columnMax = columnMax
    this.rowTemplate = rowTemplate
    this.separator = separator
    this.minRows = minRows
    this.maxRows = maxRows
    this.fallbackRows = fallbackRows
    this.numericColumns = numericColumns
  }
}

/**
 * A pre-authored, parameterized building block for VeraSectionCompose.ets's composer -- the
 * dynamic-composition counterpart to TemplateSpec, picked per section slot instead of picking one
 * whole-screen TemplateSpec. See VeraSectionCompose.ets's header comment for the full composition
 * design (instance indexing, the __PASSTHROUGH__ token, why local view() variables need no
 * indexing but AppState fields and function names do).
 */
export class FragmentSpec {
  /** Stable id, e.g. "checklist", "metrics". */
  kind: string
  /** Shown to Jev as this kind's criteria text for a section slot's `choice` question. */
  criteria: string
  /** A @jsonable support class this kind needs (e.g. "Item"), or '' if none. Deduped by the composer when the same kind is chosen more than once. */
  supportClass: string
  /** This kind's contribution to the merged AppState, names containing "IDX". */
  stateFields: StateFieldSpec[]
  /** Statements run inside init() before the return, containing "IDX"; '' if none needed. */
  initStatements: string
  /** This kind's piece of init()'s returned object literal (no surrounding braces), containing "IDX". */
  initEntries: string
  /** This kind's handler function(s), full text, containing "IDX" and exactly one "__PASSTHROUGH__". */
  functions: string
  /** A `{ ... sections.push(...) ... }` block appended inside view(), containing "IDX" and this kind's own slot/content tokens (which also contain "IDX"). */
  viewBlock: string
  /** Per-instance cosmetic slots; tokens contain "IDX". */
  slots: SlotSpec[]
  /** Per-instance content fields; tokens contain "IDX". */
  contentFields: ContentFieldSpec[]
  /**
   * Full `import * as x from "std/y"` lines this kind needs beyond the always-present
   * `import * as ui from "std/ui"` (e.g. `std/sdk`, `std/strings` for a capability-bound kind).
   * Deduped by the composer when more than one chosen kind needs the same module.
   */
  imports: string[]
  /** List-valued parameters, filled the same way as contentFields but with a model-chosen number of rows. */
  listFields: ListFieldSpec[]
  constructor(kind: string, criteria: string, supportClass: string, stateFields: StateFieldSpec[],
      initStatements: string, initEntries: string, functions: string, viewBlock: string,
      slots: SlotSpec[], contentFields: ContentFieldSpec[], imports: string[] = [], listFields: ListFieldSpec[] = []) {
    this.kind = kind
    this.criteria = criteria
    this.supportClass = supportClass
    this.stateFields = stateFields
    this.initStatements = initStatements
    this.initEntries = initEntries
    this.functions = functions
    this.viewBlock = viewBlock
    this.slots = slots
    this.contentFields = contentFields
    this.imports = imports
    this.listFields = listFields
  }
}

function checklistFragment(): FragmentSpec {
  let listStyle: Map<string, string> = new Map<string, string>()
  listStyle.set('default', 'normal spacing')
  listStyle.set('compact', 'tighter spacing')
  listStyle.set('comfortable', 'looser spacing')
  return new FragmentSpec(
    'checklist',
    'A browsable list of items the person can check off or mark one at a time',
    `@jsonable
class Item {
  label: string;
  detail: string;
  done: boolean;
}`,
    [new StateFieldSpec('itemsIDX', 'Item[]'), new StateFieldSpec('lastToggledIDX', 'int')],
    `  let itemsIDX: Item[] = [
    __ITEMS_IDX__
  ];`,
    `itemsIDX: itemsIDX, lastToggledIDX: -1`,
    `function toggleIDX(state: AppState, index: int): AppState {
  let out: Item[] = [];
  let i: int = 0;
  while (i < state.itemsIDX.length()) {
    let it: Item = state.itemsIDX[i];
    if (i === index) {
      out.push({label: it.label, detail: it.detail, done: !it.done});
    } else {
      out.push(it);
    }
    i = i + 1;
  }
  return {itemsIDX: out, lastToggledIDX: index__PASSTHROUGH__};
}`,
    `{
    let count: int = state.itemsIDX.length();
    let rows: ui.View[] = [];
    let j: int = 0;
    while (j < count) {
      let it: Item = state.itemsIDX[j];
      let icon: string = "pin";
      let subtitle: string = "not done";
      if (it.done) { icon = "check"; subtitle = "done"; }
      if (it.detail.length() > 0) { subtitle = it.detail + " - " + subtitle; }
      rows.push(ui.ListItem("default", it.label, subtitle, "", "toggleIDX", j, true, icon));
      j = j + 1;
    }
    sections.push(ui.Section("content", "", "", [
      ui.When(count === 0, ui.EmptyState("default", "Nothing here", "Add an item to get started.", "", "", "pin")),
      ui.When(count > 0, ui.ListGroup("__LIST_STYLE_IDX__", "", rows))
    ]));
  }`,
    [new SlotSpec('__LIST_STYLE_IDX__', ['default', 'compact', 'comfortable'], 'choice',
      'How dense should the list rows be?', listStyle)],
    [],
    [],
    [new ListFieldSpec('__ITEMS_IDX__', 'items',
      'The things on the list, as many as the request needs (3 to 8); each with an optional short detail such as a quantity',
      ['name of the item', 'short detail such as a quantity or a note, or an empty string'], [28, 20],
      '{label: "{0}", detail: "{1}", done: false}', ',\n    ', 3, 8,
      [['First item', ''], ['Second item', ''], ['Third item', '']])]
  )
}

function metricsFragment(): FragmentSpec {
  let metricStyle: Map<string, string> = new Map<string, string>()
  metricStyle.set('default', 'normal spacing')
  metricStyle.set('compact', 'tighter spacing')
  metricStyle.set('spacious', 'looser spacing')
  let accent: Map<string, string> = new Map<string, string>()
  accent.set('default', 'no, same tone as the rest')
  accent.set('accent', 'yes, highlighted')
  return new FragmentSpec(
    'metrics',
    'A small dashboard of a few summary numbers with a couple of actions',
    '',
    [new StateFieldSpec('countIDX', 'int'), new StateFieldSpec('totalIDX', 'int')],
    '',
    `countIDX: 0, totalIDX: 100`,
    `function incrementIDX(state: AppState, ignored: int): AppState {
  return {countIDX: state.countIDX + 1, totalIDX: state.totalIDX__PASSTHROUGH__};
}

function resetIDX(state: AppState, ignored: int): AppState {
  return {countIDX: 0, totalIDX: state.totalIDX__PASSTHROUGH__};
}`,
    `{
    let remaining: int = state.totalIDX - state.countIDX;
    sections.push(ui.Section("summary", "", "", [
      ui.MetricGroup("__METRIC_STYLE_IDX__", 3, [
        ui.IntStat("default", "__STAT1_LABEL_IDX__", state.countIDX, "", "", 1, "", "pin"),
        ui.IntStat("__ACCENT_STAT_IDX__", "__STAT2_LABEL_IDX__", state.totalIDX, "", "", 1, "", "check"),
        ui.IntStat("default", "__STAT3_LABEL_IDX__", remaining, "", "", 1, "", "clock")
      ])
    ]));
    sections.push(ui.Section("content", "", "", [
      ui.ActionBar("spread", [
        ui.Button("primary", "Add one", "incrementIDX", 0, true),
        ui.Button("secondary", "Reset", "resetIDX", 0, true)
      ])
    ]));
  }`,
    [
      new SlotSpec('__METRIC_STYLE_IDX__', ['default', 'compact', 'spacious'], 'choice',
        'How dense should the summary numbers be?', metricStyle),
      new SlotSpec('__ACCENT_STAT_IDX__', ['default', 'accent'], 'choice',
        'Should the middle number stand out with an accent tone?', accent)
    ],
    [
      new ContentFieldSpec('__STAT1_LABEL_IDX__', 'stat1_label', 'Count', 'Label for the first number shown (1-2 words)', 16),
      new ContentFieldSpec('__STAT2_LABEL_IDX__', 'stat2_label', 'Total', 'Label for the second number shown (1-2 words)', 16),
      new ContentFieldSpec('__STAT3_LABEL_IDX__', 'stat3_label', 'Remaining', 'Label for the third number shown (1-2 words)', 16)
    ]
  )
}

/**
 * No device capability at all -- ui.Ticker/onTick is a pure in-app clock (VeraPreview.ets drives
 * it with a real setInterval), the same safety class as checklist/metrics. Target duration is a
 * fixed 25 minutes rather than a content-filled or slot-chosen value, kept deliberately simple for
 * this first version (see the plan's non-goals).
 */
function timerFragment(): FragmentSpec {
  return new FragmentSpec(
    'timer',
    'A countdown or stopwatch that ticks by itself, with a start/pause toggle and a reset',
    '',
    [new StateFieldSpec('elapsedMsIDX', 'int'), new StateFieldSpec('runningIDX', 'boolean')],
    '',
    `elapsedMsIDX: 0, runningIDX: true`,
    `function onTickIDX(state: AppState, elapsedMs: int): AppState {
  return {elapsedMsIDX: state.elapsedMsIDX + elapsedMs, runningIDX: state.runningIDX__PASSTHROUGH__};
}

function toggleRunningIDX(state: AppState, value: boolean): AppState {
  return {elapsedMsIDX: state.elapsedMsIDX, runningIDX: value__PASSTHROUGH__};
}

function resetTimerIDX(state: AppState, ignored: int): AppState {
  return {elapsedMsIDX: 0, runningIDX: state.runningIDX__PASSTHROUGH__};
}`,
    `{
    let remainingMs: int = 1500000 - state.elapsedMsIDX;
    if (remainingMs < 0) { remainingMs = 0; }
    let remainingSec: int = remainingMs / 1000;
    sections.push(ui.Section("content", "", "", [
      ui.Ticker("default", "timerIDX", 1000, state.runningIDX, "onTickIDX"),
      ui.IntText("display", remainingSec, "", "s left", 1),
      ui.Toggle("default", "__TIMER_LABEL_IDX__", state.runningIDX, "toggleRunningIDX"),
      ui.ActionBar("spread", [
        ui.Button("secondary", "Reset", "resetTimerIDX", 0, true)
      ])
    ]));
  }`,
    [],
    [new ContentFieldSpec('__TIMER_LABEL_IDX__', 'timer_label', 'Running', 'Short label for what is being timed (1-3 words)', 24)]
  )
}

/**
 * Real device capability, hardcoded to one compile-time-verified sdk.call target
 * ("CalendarKit.Calendar.addEvent" -- checked against VeraSdkIndex's static 16,511-entry index,
 * same guarantee a wrong/outdated target would fail to compile rather than fail silently on the
 * phone). Calendar permission is already requested at startup (VeraCalendar
 * .requestCalendarPermissions); nothing new is needed there. hour is a closed-set slot, not
 * content-fill, because VeraCalendarSdk.ets's localStart requires a valid 0-23 integer and an
 * unvalidated model string is exactly the kind of value that should not reach a real write.
 * onAnswer follows docs/intent-call-contract.md's documented rule exactly (declined/error are the
 * only failure shapes; anything else, including "ok" and a target's own JSON, is success) --
 * written once here instead of risking the same mistake two confirmed DeepSeek-generated programs
 * made on this exact device.
 */
function calendarEventFragment(): FragmentSpec {
  let hour: Map<string, string> = new Map<string, string>()
  hour.set('9', 'in the morning, around 9 AM')
  hour.set('12', 'around midday')
  hour.set('15', 'in the afternoon, around 3 PM')
  hour.set('18', 'in the evening, around 6 PM')
  return new FragmentSpec(
    'calendar_event',
    'A single real calendar event the person can add with one button, with a live result',
    '',
    [new StateFieldSpec('lastResultIDX', 'string')],
    '',
    `lastResultIDX: ""`,
    `function addToCalendarIDX(state: AppState, ignored: int): AppState {
  sdk.call("CalendarKit.Calendar.addEvent",
    ["title", "__EVENT_TITLE_IDX__", "hour", "__EVENT_HOUR_IDX__", "minute", "0",
     "durationMinutes", "60", "repeat", "once"], "onAnswerIDX");
  return {lastResultIDX: "pending"__PASSTHROUGH__};
}

function onAnswerIDX(state: AppState, value: string): AppState {
  return {lastResultIDX: value__PASSTHROUGH__};
}`,
    `{
    let failed: boolean = strings.startsWith(state.lastResultIDX, "declined") || strings.startsWith(state.lastResultIDX, "error");
    let statusText: string = "Not added yet";
    let bannerStyle: string = "default";
    if (state.lastResultIDX !== "" && failed) { statusText = state.lastResultIDX; bannerStyle = "warning"; }
    if (state.lastResultIDX !== "" && !failed) { statusText = "Added to calendar"; }
    sections.push(ui.Section("content", "", "", [
      ui.ActionBar("spread", [
        ui.Button("primary", "Add to calendar", "addToCalendarIDX", 0, true)
      ]),
      ui.InsetBanner(bannerStyle, "Calendar", statusText, "", "", "info")
    ]));
  }`,
    [new SlotSpec('__EVENT_HOUR_IDX__', ['9', '12', '15', '18'], 'choice',
      'What time of day does this event happen?', hour)],
    [new ContentFieldSpec('__EVENT_TITLE_IDX__', 'event_title', 'Reminder', 'Short calendar event title (2-5 words)', 40)],
    ['import * as sdk from "std/sdk"', 'import * as strings from "std/strings"']
  )
}

/** A quick-actions row: 3 generic buttons, each records itself as "last tapped" -- no counters, just a record of which action was last chosen. */
function actionsFragment(): FragmentSpec {
  return new FragmentSpec(
    'actions',
    'A row of a few quick action buttons, with a note of which one was last tapped',
    '',
    [new StateFieldSpec('lastActionIDX', 'string')],
    '',
    `lastActionIDX: ""`,
    `function tapAction1IDX(state: AppState, ignored: int): AppState {
  return {lastActionIDX: "__ACTION1_IDX__"__PASSTHROUGH__};
}

function tapAction2IDX(state: AppState, ignored: int): AppState {
  return {lastActionIDX: "__ACTION2_IDX__"__PASSTHROUGH__};
}

function tapAction3IDX(state: AppState, ignored: int): AppState {
  return {lastActionIDX: "__ACTION3_IDX__"__PASSTHROUGH__};
}`,
    `{
    let resultText: string = "Nothing tapped yet";
    if (state.lastActionIDX !== "") { resultText = "Last: " + state.lastActionIDX; }
    sections.push(ui.Section("content", "", "", [
      ui.ActionBar("spread", [
        ui.Button("primary", "__ACTION1_IDX__", "tapAction1IDX", 0, true),
        ui.Button("secondary", "__ACTION2_IDX__", "tapAction2IDX", 0, true),
        ui.Button("secondary", "__ACTION3_IDX__", "tapAction3IDX", 0, true)
      ]),
      ui.Badge("default", resultText, "")
    ]));
  }`,
    [],
    [
      new ContentFieldSpec('__ACTION1_IDX__', 'action1', 'Mark done', 'Label for the first quick action button', 20),
      new ContentFieldSpec('__ACTION2_IDX__', 'action2', 'Snooze', 'Label for the second quick action button', 20),
      new ContentFieldSpec('__ACTION3_IDX__', 'action3', 'Skip', 'Label for the third quick action button', 20)
    ]
  )
}

/** Same shape as metrics (a single adjustable count against a target) but as a visual bar -- ui.Progress has no action prop of its own, so add/reset live in their own ActionBar below it. */
function progressGoalFragment(): FragmentSpec {
  let progressStyle: Map<string, string> = new Map<string, string>()
  progressStyle.set('default', 'no, same tone as the rest')
  progressStyle.set('accent', 'yes, highlighted')
  return new FragmentSpec(
    'progress_goal',
    'A single visual progress bar toward a goal, with a button to add progress and one to reset',
    '',
    [new StateFieldSpec('progressIDX', 'int'), new StateFieldSpec('goalIDX', 'int')],
    '',
    `progressIDX: 0, goalIDX: 10`,
    `function addProgressIDX(state: AppState, ignored: int): AppState {
  return {progressIDX: state.progressIDX + 1, goalIDX: state.goalIDX__PASSTHROUGH__};
}

function resetProgressIDX(state: AppState, ignored: int): AppState {
  return {progressIDX: 0, goalIDX: state.goalIDX__PASSTHROUGH__};
}`,
    `{
    sections.push(ui.Section("summary", "", "", [
      ui.Progress("__PROGRESS_STYLE_IDX__", "__PROGRESS_LABEL_IDX__", state.progressIDX, state.goalIDX)
    ]));
    sections.push(ui.Section("content", "", "", [
      ui.ActionBar("spread", [
        ui.Button("primary", "Add one", "addProgressIDX", 0, true),
        ui.Button("secondary", "Reset", "resetProgressIDX", 0, true)
      ])
    ]));
  }`,
    [new SlotSpec('__PROGRESS_STYLE_IDX__', ['default', 'accent'], 'choice',
      'Should the progress bar stand out with an accent tone?', progressStyle)],
    [new ContentFieldSpec('__PROGRESS_LABEL_IDX__', 'progress_label', 'Progress', 'Short label for what is being tracked (1-3 words)', 20)]
  )
}

/**
 * Small read-only labelled facts, no interactivity at all -- the simplest possible fragment: no
 * state fields, no init entries, no functions. Proves the composer tolerates a fragment that
 * contributes nothing but content-filled display text (see VeraSectionCompose.ets's
 * composeProgram, which now skips an empty initEntries contribution rather than joining a blank
 * string into the return object literal).
 */
function keyFactsFragment(): FragmentSpec {
  return new FragmentSpec(
    'key_facts',
    'A small block of a couple of read-only labelled facts, with no taps or inputs',
    '',
    [],
    '',
    '',
    '',
    `{
    sections.push(ui.Section("content", "", "", [
      ui.KeyValueGroup("default", 2, [
        ui.KeyValueItem("default", "__FACT1_LABEL_IDX__", "__FACT1_VALUE_IDX__", ""),
        ui.KeyValueItem("default", "__FACT2_LABEL_IDX__", "__FACT2_VALUE_IDX__", "")
      ])
    ]));
  }`,
    [],
    [
      new ContentFieldSpec('__FACT1_LABEL_IDX__', 'fact1_label', 'Status', 'Label for the first fact (1-2 words)', 16),
      new ContentFieldSpec('__FACT1_VALUE_IDX__', 'fact1_value', 'Unknown', 'Short value for the first fact (1-4 words)', 24),
      new ContentFieldSpec('__FACT2_LABEL_IDX__', 'fact2_label', 'Detail', 'Label for the second fact (1-2 words)', 16),
      new ContentFieldSpec('__FACT2_VALUE_IDX__', 'fact2_value', 'Unknown', 'Short value for the second fact (1-4 words)', 24)
    ]
  )
}

/**
 * A single-series line chart of a handful of real data points, display-only. Min/max are computed
 * from the actual plotted values at render time (a plain while loop over the array), not asked of
 * the content-fill model as a separate field -- VeraPreview.ets's Sparkline renderer never
 * auto-scales from the data, so a wrong hand-written bound would clip or flatten the chart, while
 * a value the renderer never sees can't be wrong. Same no-state, content-baked-at-compose-time
 * shape as key_facts/spotlight.
 */
function trendChartFragment(): FragmentSpec {
  let chartStyle: Map<string, string> = new Map<string, string>()
  chartStyle.set('default', 'no, same tone as the rest')
  chartStyle.set('accent', 'yes, highlighted')
  return new FragmentSpec(
    'trend_chart',
    'A simple line chart of a handful of data points trending over a sequence (a measurement by ' +
    'year, a reading over months) -- not interactive, no taps, no editable inputs',
    '',
    [],
    '',
    '',
    '',
    `{
    let series: int[] = [__V1_IDX__, __V2_IDX__, __V3_IDX__, __V4_IDX__];
    let categories: string[] = ["__Y1_IDX__", "__Y2_IDX__", "__Y3_IDX__", "__Y4_IDX__"];
    let maxV: int = series[0];
    let minV: int = series[0];
    let i: int = 1;
    while (i < series.length()) {
      if (series[i] > maxV) { maxV = series[i]; }
      if (series[i] < minV) { minV = series[i]; }
      i = i + 1;
    }
    sections.push(ui.Section("content", "", "", [
      ui.Sparkline("__CHART_STYLE_IDX__", series, maxV, "__CHART_LABEL_IDX__", false, [], "default", "", "", categories, minV)
    ]));
  }`,
    [new SlotSpec('__CHART_STYLE_IDX__', ['default', 'accent'], 'choice', 'Should the chart line stand out?', chartStyle)],
    [
      new ContentFieldSpec('__CHART_LABEL_IDX__', 'chart_label', 'Value', 'Short label for what the chart plots (2-4 words, e.g. "Average height (cm)")', 24),
      new ContentFieldSpec('__Y1_IDX__', 'point1_label', 'Point 1', 'Short label for data point 1 (e.g. a year, "1950")', 12),
      new ContentFieldSpec('__V1_IDX__', 'point1_value', '0', 'Numeric value for data point 1, digits only, no units or commas', 6, true),
      new ContentFieldSpec('__Y2_IDX__', 'point2_label', 'Point 2', 'Short label for data point 2', 12),
      new ContentFieldSpec('__V2_IDX__', 'point2_value', '0', 'Numeric value for data point 2, digits only, no units or commas', 6, true),
      new ContentFieldSpec('__Y3_IDX__', 'point3_label', 'Point 3', 'Short label for data point 3', 12),
      new ContentFieldSpec('__V3_IDX__', 'point3_value', '0', 'Numeric value for data point 3, digits only, no units or commas', 6, true),
      new ContentFieldSpec('__Y4_IDX__', 'point4_label', 'Point 4', 'Short label for data point 4', 12),
      new ContentFieldSpec('__V4_IDX__', 'point4_value', '0', 'Numeric value for data point 4, digits only, no units or commas', 6, true)
    ]
  )
}

/** A single editable text field, stored in state. One field is not the "multi-field form" needs_search_or_form vetoes against. */
function noteFragment(): FragmentSpec {
  return new FragmentSpec(
    'note',
    'A single note the person can type and edit, with no other fields',
    '',
    [new StateFieldSpec('noteIDX', 'string')],
    '',
    `noteIDX: ""`,
    `function updateNoteIDX(state: AppState, value: string): AppState {
  return {noteIDX: value__PASSTHROUGH__};
}`,
    `{
    sections.push(ui.Section("content", "", "", [
      ui.TextField("default", "__NOTE_LABEL_IDX__", state.noteIDX, "updateNoteIDX")
    ]));
  }`,
    [],
    [new ContentFieldSpec('__NOTE_LABEL_IDX__', 'note_label', 'Note', 'Short label for what this note is for (1-3 words)', 20)]
  )
}

/** A 1-10 slider with a live readout. */
function ratingFragment(): FragmentSpec {
  let ratingStyle: Map<string, string> = new Map<string, string>()
  ratingStyle.set('default', 'no, same tone as the rest')
  ratingStyle.set('accent', 'yes, highlighted')
  return new FragmentSpec(
    'rating',
    'A single slider from 1 to 10 the person can set, with a live readout',
    '',
    [new StateFieldSpec('ratingIDX', 'int')],
    '',
    `ratingIDX: 5`,
    `function setRatingIDX(state: AppState, value: int): AppState {
  return {ratingIDX: value__PASSTHROUGH__};
}`,
    `{
    sections.push(ui.Section("content", "", "", [
      ui.Slider("__RATING_STYLE_IDX__", "__RATING_LABEL_IDX__", state.ratingIDX, 1, 10, "setRatingIDX")
    ]));
  }`,
    [new SlotSpec('__RATING_STYLE_IDX__', ['default', 'accent'], 'choice',
      'Should the slider stand out with an accent tone?', ratingStyle)],
    [new ContentFieldSpec('__RATING_LABEL_IDX__', 'rating_label', 'Rating', 'Short label for what is being rated (1-3 words)', 20)]
  )
}

/** A static featured highlight, no interactivity at all -- same empty-fields shape as key_facts, already proven live on-device (including composed with itself). */
function spotlightFragment(): FragmentSpec {
  let spotlightStyle: Map<string, string> = new Map<string, string>()
  spotlightStyle.set('plain', 'restrained and neutral')
  spotlightStyle.set('accent', 'bold and highlighted')
  return new FragmentSpec(
    'spotlight',
    'A single featured highlight or callout, display-only, with no taps or inputs',
    '',
    [],
    '',
    '',
    '',
    `{
    sections.push(ui.Section("hero", "", "", [
      ui.Hero("__SPOTLIGHT_STYLE_IDX__", "__SPOTLIGHT_EYEBROW_IDX__", "__SPOTLIGHT_TITLE_IDX__", "__SPOTLIGHT_BODY_IDX__", [])
    ]));
  }`,
    [new SlotSpec('__SPOTLIGHT_STYLE_IDX__', ['plain', 'accent'], 'choice',
      'Should the highlight be plain or bold/accented?', spotlightStyle)],
    [
      new ContentFieldSpec('__SPOTLIGHT_EYEBROW_IDX__', 'spotlight_eyebrow', 'Highlight', 'Short eyebrow label above the title (1-2 words)', 16),
      new ContentFieldSpec('__SPOTLIGHT_TITLE_IDX__', 'spotlight_title', 'Featured', 'Short title for the highlight (2-4 words)', 24),
      new ContentFieldSpec('__SPOTLIGHT_BODY_IDX__', 'spotlight_body', 'Something worth noticing.', 'One short supporting sentence', 60)
    ]
  )
}

/**
 * A short list the person narrows by typing part of a name. Matching is strings.contains on the
 * typed text as it is -- std/strings has no case folding, so the sample names are asked for in
 * lower case and a query typed with a capital first letter will not match them. The rows are fixed
 * sample text baked in at compose time; the model replaces them when the request needs real data.
 */
function searchListFragment(): FragmentSpec {
  return new FragmentSpec(
    'search_list',
    'A short list of named items with a box where the person types part of a name to narrow the list',
    '',
    [new StateFieldSpec('queryIDX', 'string')],
    '',
    `queryIDX: ""`,
    `function setQueryIDX(state: AppState, value: string): AppState {
  return {queryIDX: value__PASSTHROUGH__};
}`,
    `{
    let q: string = state.queryIDX;
    let names: string[] = [__NAMES_IDX__];
    let rows: ui.View[] = [];
    let j: int = 0;
    while (j < names.length()) {
      let name: string = names[j];
      if (q.length() === 0 || strings.contains(name, q)) {
        rows.push(ui.ListItem("default", name, "", "", "", j, false, "list"));
      }
      j = j + 1;
    }
    sections.push(ui.Section("content", "", "", [
      ui.TextField("default", "__SEARCH_LABEL_IDX__", q, "setQueryIDX"),
      ui.When(rows.length() === 0, ui.EmptyState("default", "No matches", "Try a different word.", "", "", "list")),
      ui.When(rows.length() > 0, ui.ListGroup("default", "", rows))
    ]));
  }`,
    [],
    [
      new ContentFieldSpec('__SEARCH_LABEL_IDX__', 'search_label', 'Search', 'Short label for the search box (1-2 words)', 16)
    ],
    ['import * as strings from "std/strings"'],
    [new ListFieldSpec('__NAMES_IDX__', 'names',
      'The entries the person can search, as many as the request needs (3 to 8), each name all lower case',
      ['name of the entry, all lower case'], [24], '"{0}"', ', ', 3, 8,
      [['first item'], ['second item'], ['third item'], ['fourth item']])]
  )
}

/** Three columns, three rows of sample records, display-only. Same no-state shape as key_facts. */
function dataTableFragment(): FragmentSpec {
  return new FragmentSpec(
    'data_table',
    'A small table of records with three labelled columns that are read down and across, such as items with a quantity and a price',
    '',
    [],
    '',
    '',
    '',
    `{
    sections.push(ui.Section("content", "", "", [
      ui.Table("default", ["__H1_IDX__", "__H2_IDX__", "__H3_IDX__"], 3, [
        __ROWS_IDX__
      ])
    ]));
  }`,
    [],
    [
      new ContentFieldSpec('__H1_IDX__', 'h1', 'Name', 'Header of the first column (1-2 words)', 14),
      new ContentFieldSpec('__H2_IDX__', 'h2', 'Detail', 'Header of the second column (1-2 words)', 14),
      new ContentFieldSpec('__H3_IDX__', 'h3', 'Value', 'Header of the third column (1-2 words)', 14)
    ],
    [],
    [new ListFieldSpec('__ROWS_IDX__', 'rows',
      'The records of the table, as many as the request needs (3 to 8), one value per column',
      ['first column value', 'second column value', 'third column value'], [14, 14, 14],
      'ui.TableRow("default", ["{0}", "{1}", "{2}"])', ',\n        ', 3, 8,
      [['Item 1', '-', '-'], ['Item 2', '-', '-'], ['Item 3', '-', '-']])]
  )
}

/** Four steps in time order with a time on the right edge, display-only. */
function timelineFragment(): FragmentSpec {
  let timelineStyle: Map<string, string> = new Map<string, string>()
  timelineStyle.set('default', 'normal spacing')
  timelineStyle.set('compact', 'tighter spacing')
  timelineStyle.set('comfortable', 'looser spacing')
  return new FragmentSpec(
    'timeline',
    'Steps or events in time order, such as an itinerary, a daily schedule or a history, each with a time',
    '',
    [],
    '',
    '',
    '',
    `{
    sections.push(ui.Section("content", "", "", [
      ui.Timeline("__TIMELINE_STYLE_IDX__", "__TL_TITLE_IDX__", [
        __STEPS_IDX__
      ])
    ]));
  }`,
    [new SlotSpec('__TIMELINE_STYLE_IDX__', ['default', 'compact', 'comfortable'], 'choice',
      'How much room should the timeline steps have?', timelineStyle)],
    [new ContentFieldSpec('__TL_TITLE_IDX__', 'tl_title', 'Schedule', 'Short title for the timeline (1-3 words)', 20)],
    [],
    [new ListFieldSpec('__STEPS_IDX__', 'steps',
      'The steps in time order, as many as the request needs (3 to 8), each with the time it happens',
      ['what happens (2-5 words)', 'when it happens (a time, or a short day label)'], [28, 10],
      'ui.TimelineItem("default", "{0}", "", "{1}", "", 0, false, "clock")', ',\n        ', 3, 8,
      [['First step', '09:00'], ['Second step', '12:00'], ['Third step', '15:00']])]
  )
}

/**
 * Display-only bar chart of a few named categories, each with one whole number. The rows are pushed
 * into two arrays by the row template (names, values), the scale is the largest value, and the chart
 * is a ui.Sparkline with bars -- the same component the model reaches for when it writes a bar chart
 * itself. Numbers are the model's answer for the request; they are sample figures unless the request
 * gave real ones.
 */
function barChartFragment(): FragmentSpec {
  let barStyle: Map<string, string> = new Map<string, string>()
  barStyle.set('default', 'no, same tone as the rest')
  barStyle.set('accent', 'yes, highlighted')
  return new FragmentSpec(
    'bar_chart',
    'A bar chart comparing a handful of named categories by one number each, display-only, such as spending per category or votes per option',
    '',
    [],
    '',
    '',
    '',
    `{
    let names: string[] = [];
    let vals: int[] = [];
    let none: int[] = [];
    __BARS_IDX__
    let top: int = 1;
    for (let v: int of vals) {
      if (v > top) { top = v; }
    }
    sections.push(ui.Section("content", "", "", [
      ui.Sparkline("__BAR_STYLE_IDX__", vals, top, "__BAR_LABEL_IDX__", true, none, "accent", "", "", names, 0)
    ]));
  }`,
    [new SlotSpec('__BAR_STYLE_IDX__', ['default', 'accent'], 'choice',
      'Should the bars stand out with an accent tone?', barStyle)],
    [new ContentFieldSpec('__BAR_LABEL_IDX__', 'bar_label', 'Comparison', 'Short caption for the chart (2-5 words)', 32)],
    [],
    [new ListFieldSpec('__BARS_IDX__', 'bars',
      'The categories to compare, as many as the request needs (3 to 8), each with one whole number',
      ['name of the category (1-2 words)', 'its value as a whole number, no units'], [14, 6],
      'names.push("{0}"); vals.push({1});', '\n    ', 3, 8,
      [['A', '3'], ['B', '5'], ['C', '2']], [1])]
  )
}

/**
 * A form that adds entries one at a time -- a short note and a whole-number amount -- and lists them
 * newest first under a running total. The one fragment with a growing list the person fills in, so
 * it covers expense logs, habit and score logs, anything shaped "add a line, see the total".
 * Amounts are whole units on purpose: money with cents is a request for the model to write the
 * program (needs_logic), not something a fixed fragment can promise.
 */
function logEntriesFragment(): FragmentSpec {
  return new FragmentSpec(
    'log_entries',
    'A form where the person adds entries one at a time, each with a short note and a whole-number amount, listed newest first with a running total and a button to remove the last one',
    `@jsonable
class LogEntry {
  note: string;
  amount: int;
}`,
    [new StateFieldSpec('logIDX', 'LogEntry[]'), new StateFieldSpec('draftNoteIDX', 'string'), new StateFieldSpec('draftAmountIDX', 'int')],
    `  let logIDX: LogEntry[] = [];`,
    `logIDX: logIDX, draftNoteIDX: "", draftAmountIDX: 0`,
    `function setNoteIDX(state: AppState, value: string): AppState {
  return {logIDX: state.logIDX, draftNoteIDX: value, draftAmountIDX: state.draftAmountIDX__PASSTHROUGH__};
}

function setAmountIDX(state: AppState, value: int): AppState {
  return {logIDX: state.logIDX, draftNoteIDX: state.draftNoteIDX, draftAmountIDX: value__PASSTHROUGH__};
}

function addEntryIDX(state: AppState, ignored: int): AppState {
  let out: LogEntry[] = [];
  let i: int = 0;
  while (i < state.logIDX.length()) {
    out.push(state.logIDX[i]);
    i = i + 1;
  }
  let label: string = state.draftNoteIDX;
  if (label.length() === 0) { label = "Entry"; }
  out.push({note: label, amount: state.draftAmountIDX});
  return {logIDX: out, draftNoteIDX: "", draftAmountIDX: 0__PASSTHROUGH__};
}

function removeLastIDX(state: AppState, ignored: int): AppState {
  let out: LogEntry[] = [];
  let i: int = 0;
  while (i < state.logIDX.length() - 1) {
    out.push(state.logIDX[i]);
    i = i + 1;
  }
  return {logIDX: out, draftNoteIDX: state.draftNoteIDX, draftAmountIDX: state.draftAmountIDX__PASSTHROUGH__};
}`,
    `{
    let n: int = state.logIDX.length();
    let total: int = 0;
    let rows: ui.View[] = [];
    let k: int = n - 1;
    while (k >= 0) {
      let e: LogEntry = state.logIDX[k];
      total = total + e.amount;
      rows.push(ui.ListItem("default", e.note, "", ui.intToString(e.amount), "", k, false, "list"));
      k = k - 1;
    }
    sections.push(ui.Section("summary", "", "", [
      ui.MetricGroup("default", 2, [
        ui.Stat("accent", "Total", ui.intToString(total), "all entries", "chart"),
        ui.Stat("default", "Entries", ui.intToString(n), "logged", "list")
      ])
    ]));
    sections.push(ui.Section("content", "__FORM_TITLE_IDX__", "", [
      ui.TextField("default", "Note", state.draftNoteIDX, "setNoteIDX"),
      ui.IntField("default", "__AMOUNT_LABEL_IDX__", state.draftAmountIDX, 0, 100000, "setAmountIDX"),
      ui.ActionBar("end", [
        ui.Button("secondary", "Remove last", "removeLastIDX", 0, n > 0),
        ui.Button("primary", "Add", "addEntryIDX", 0, state.draftAmountIDX > 0)
      ])
    ]));
    sections.push(ui.Section("content", "", "", [
      ui.When(n === 0, ui.EmptyState("default", "Nothing yet", "Add the first entry above.", "", "", "list")),
      ui.When(n > 0, ui.ListGroup("default", "", rows))
    ]));
  }`,
    [],
    [
      new ContentFieldSpec('__FORM_TITLE_IDX__', 'form_title', 'Add an entry', 'Heading of the form (2-4 words)', 24),
      new ContentFieldSpec('__AMOUNT_LABEL_IDX__', 'amount_label', 'Amount', 'Label of the amount field (1-2 words)', 16)
    ]
  )
}

/**
 * The palette VeraSectionCompose.ets picks from, one per section slot. `checklist`/`metrics`
 * reproduce today's two flat templates exactly (as single-fragment compositions); `timer` and
 * `calendar_event` are the first capability-bound kinds, see the plan's rationale for why these
 * two specifically are safe to hardcode and navigation is not. `actions`/`progress_goal`/
 * `key_facts`/`note`/`rating`/`spotlight` round out the generic, SDK-free side of the palette.
 */
export function fragments(): FragmentSpec[] {
  return [
    checklistFragment(), metricsFragment(), timerFragment(), calendarEventFragment(),
    actionsFragment(), progressGoalFragment(), keyFactsFragment(), trendChartFragment(),
    noteFragment(), ratingFragment(), spotlightFragment(),
    searchListFragment(), dataTableFragment(), timelineFragment(),
    barChartFragment(), logEntriesFragment()
  ]
}

/**
 * Both templates are generic, SDK-free placeholders: they cannot call a
 * phone API, cannot show real/named data, and cannot do anything beyond a
 * short fixed list or a couple of numbers. Jev's top-level `template` choice
 * is a shape match against a one-line description, which does not by itself
 * check for any of that -- a request can look "list-shaped" or "number-
 * shaped" while also demanding capability neither template has (confirmed
 * live: a detailed itinerary brief asking for real navigation/calendar SDK
 * calls still matched `list_detail` at 0.95 confidence). These questions are
 * asked once, regardless of which template matched, and clearing its own
 * `above` bar on any one of them vetoes the pick outright -- see readPick in
 * VeraTemplateSelect.ets.
 */
export function vetoes(): VetoSpec[] {
  let yn = (yes: string, no: string): Map<string, string> => {
    let m: Map<string, string> = new Map<string, string>()
    m.set('true', yes)
    m.set('false', no)
    return m
  }
  return [
    new VetoSpec('needs_integration',
      'Does fulfilling this request need calling any phone API, SDK function, or app intent, or ' +
      'integrating with another app (navigation, messaging, camera, contacts, etc.) to read or act ' +
      'on real device/world state -- rather than only showing or manually updating numbers or ' +
      'items the app keeps for itself (even if a complete, faithful version of this app would ' +
      'eventually read one of these from a sensor or a real API)? Answer no if the only such need ' +
      'is adding one real event to the phone calendar with a button, which this app can already do ' +
      '-- that specific capability does not count here. Any other phone API, SDK, or app ' +
      'integration (navigation, messaging, camera, contacts, reading or searching the calendar, ' +
      'anything beyond adding a single new event) still counts as yes.',
      yn('yes', 'no, everything stays inside the app, or is only adding one calendar event'), 0.3),
    new VetoSpec('needs_real_data',
      'Does this request need particular real, named, or externally-sourced information (real ' +
      'places, real contacts, real recipes, real prices, etc.) rather than generic interchangeable ' +
      'placeholder content?',
      yn('yes', 'no, generic placeholder content is fine'), 0.35),
    new VetoSpec('needs_search_or_form',
      'Does this request need the person to search, filter, or sort a list, or fill in a multi-' +
      'field form (several distinct labeled fields in one entry), rather than just tapping a plain ' +
      'row or a plain number? A plain list of items or a few plain numbers do not count on their ' +
      'own just because a complete, faithful version of the app would eventually let someone add, ' +
      'remove or log an arbitrary number of them.',
      yn('yes', 'no, tapping a plain row or a plain number is enough'), 0.6),
    new VetoSpec('needs_live_ticking',
      'Does this request need a display that visibly ticks, counts down, or updates continuously ' +
      'on screen in real time by itself, like a running stopwatch or a live clock face -- rather ' +
      'than a number that only changes when the person taps something? A number that in real life ' +
      'would be measured or accumulated automatically over time (step count, water intake, ' +
      'calories, distance) still counts as a plain tap-to-change number here if it is simply shown ' +
      'as a static daily or periodic total, not a continuously ticking display. Answer no if all ' +
      'that is needed is a single simple countdown or stopwatch with a start/pause control and a ' +
      'reset, since this app already has exactly that. Still answer yes for anything beyond one ' +
      'plain timer -- several independent timers at once, a timer tied to a real alarm/notification, ' +
      'or a countdown driven by a real scheduled event rather than the person starting it.',
      yn('yes', 'no continuously updating display is needed, or only a single simple timer is'), 0.3),
    new VetoSpec('needs_multiple_counters',
      'Does this request need two or more separate NUMERIC counters or running totals that each ' +
      'independently go up or down, one per distinct person or thing -- for example one score per ' +
      'player in a multiplayer game -- rather than a single adjustable number shown alongside other ' +
      'read-only derived numbers like a total or a remaining amount? A list of items that are each ' +
      'just marked done/not done, present/absent, or on/off is one list, not multiple counters, and ' +
      'does not count -- only answer yes for genuinely separate running numeric tallies.',
      yn('yes', 'no, one adjustable number (plus derived read-only numbers) is enough'), 0.65),
    new VetoSpec('needs_logic',
      'Does this request ask the app to calculate, convert, scale, split, total, compare or decide ' +
      'something from values -- for example amounts for a number of people, a tip split, a unit ' +
      'conversion, a score from rules, or anything that depends on an input the person gives -- ' +
      'rather than only listing, showing, or tapping fixed items and plain numbers?',
      yn('yes', 'no, showing or tapping fixed items and numbers is enough'), 0.8)
  ]
}
