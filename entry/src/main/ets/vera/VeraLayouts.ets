/**
 * Screen layouts for the Jev template path: a layout names slots, and each slot says which fragment
 * kinds it accepts, how many it holds and whether it must be filled. Jev picks the layout (or none);
 * the kinds it picked for the sections are then placed into the slots by what each slot accepts, so
 * no per-block "which slot" question is needed -- accepts lists are disjoint on purpose.
 *
 * A placement that breaks a rule (a required slot empty, a slot over its max, a kind no slot takes)
 * is not repaired: arrangeInLayout returns null and the caller keeps the plain top-to-bottom order,
 * which is what the path did before layouts existed.
 */

export class LayoutSlot {
  name: string
  /** Fragment kinds this slot takes; ['*'] takes any kind no earlier slot of the layout accepts by name. */
  accepts: string[]
  max: number
  required: boolean
  constructor(name: string, accepts: string[], max: number, required: boolean) {
    this.name = name
    this.accepts = accepts
    this.max = max
    this.required = required
  }
}

export class LayoutSpec {
  id: string
  /** Shown to Jev as this layout's criteria text. */
  criteria: string
  slots: LayoutSlot[]
  /**
   * [from, to] pairs: a standalone kind Jev may pick on its own that this layout replaces with the
   * kind that is wired into it (search_list has its own names; filter_box narrows the layout's list).
   */
  swaps: string[][]
  constructor(id: string, criteria: string, slots: LayoutSlot[], swaps: string[][] = []) {
    this.id = id
    this.criteria = criteria
    this.slots = slots
    this.swaps = swaps
  }
}

export const LAYOUT_NONE: string = 'none'
export const LAYOUT_STACK: string = 'stack'

export function layouts(): LayoutSpec[] {
  return [
    new LayoutSpec(LAYOUT_STACK, 'Independent parts one under another; nothing on the screen depends on another part',
      [new LayoutSlot('main', ['*'], 4, true)]),
    new LayoutSpec('master_detail', 'A list of items where choosing one shows its details in another part of the screen',
      [
        new LayoutSlot('filter', ['filter_box'], 1, false),
        new LayoutSlot('list', ['master_list'], 1, true),
        new LayoutSlot('detail', ['detail_view'], 1, true),
        new LayoutSlot('extra', ['*'], 2, false)
      ], [['search_list', 'filter_box']]),
    new LayoutSpec('log_report', 'Records the person enters one at a time, each for one of several named people or categories, with figures worked out from them: totals, averages, who is above or below, who should pay whom',
      [
        new LayoutSlot('log', ['record_log'], 1, true),
        new LayoutSlot('figures', ['number_strip'], 1, false),
        new LayoutSlot('breakdown', ['breakdown_table', 'series_chart'], 2, false),
        new LayoutSlot('result', ['settle_up'], 1, false),
        new LayoutSlot('extra', ['*'], 2, false)
      ]),
    new LayoutSpec('itinerary_day', 'An ordered list of places or steps with times, each marked reached one by one, optionally opened in the maps app or added to the phone calendar: a day plan, a tour, a route of stops',
      [
        new LayoutSlot('route', ['itinerary'], 1, true),
        new LayoutSlot('progress', ['progress_line', 'list_summary'], 1, false),
        new LayoutSlot('extra', ['*'], 2, false)
      ]),
    new LayoutSpec('progress_list', 'A checklist with summary numbers about how many of its items are done',
      [
        new LayoutSlot('summary', ['list_summary'], 1, false),
        new LayoutSlot('list', ['checklist'], 1, true),
        new LayoutSlot('extra', ['*'], 2, false)
      ])
  ]
}

export function findLayout(id: string): LayoutSpec | null {
  for (let spec of layouts()) { if (spec.id === id) { return spec } }
  return null
}

/**
 * Places `kinds` (one per section, 'none' for an empty one) into the layout's slots and returns them
 * in slot order, empty sections dropped, or null when the placement breaks a slot rule. The order
 * inside a slot is the order of `kinds`. Kinds are returned as indices into `kinds`, so the caller
 * can reorder whatever it keeps per section (slot values, picks) the same way.
 */
export function arrangeInLayout(layoutId: string, kinds: string[]): number[] | null {
  let layout = findLayout(layoutId)
  if (layout === null) { return null }
  let taken: boolean[] = []
  for (let i = 0; i < kinds.length; i++) { taken.push(kinds[i] === 'none') }
  let order: number[] = []
  // Named slots first, so a wildcard slot only gets what no named slot wants.
  let pass: number[] = []
  for (let s = 0; s < layout.slots.length; s++) { if (layout.slots[s].accepts.indexOf('*') < 0) { pass.push(s) } }
  for (let s = 0; s < layout.slots.length; s++) { if (layout.slots[s].accepts.indexOf('*') >= 0) { pass.push(s) } }
  let bySlot: number[][] = []
  for (let s = 0; s < layout.slots.length; s++) { bySlot.push([]) }
  for (let s of pass) {
    let slot = layout.slots[s]
    let wildcard = slot.accepts.indexOf('*') >= 0
    for (let i = 0; i < kinds.length; i++) {
      if (taken[i]) { continue }
      if (wildcard || slot.accepts.indexOf(kinds[i]) >= 0) {
        if (bySlot[s].length >= slot.max) { return null }
        bySlot[s].push(i)
        taken[i] = true
      }
    }
  }
  for (let i = 0; i < kinds.length; i++) { if (!taken[i]) { return null } }
  for (let s = 0; s < layout.slots.length; s++) {
    if (layout.slots[s].required && bySlot[s].length === 0) { return null }
    for (let i of bySlot[s]) { order.push(i) }
  }
  return order
}

/**
 * Jev answers each section on its own, so after choosing a layout it can still leave a required slot
 * unfilled (it answered master_list twice for "recipe list with details"; the duplicate was dropped).
 * Choosing the layout is the statement that the pair belongs together, so each required slot that
 * accepts exactly one named kind and has none placed gets that kind in the first empty section.
 * Returns the indices filled, as [section index, kind]; leaves `kinds` changed in place. A layout
 * with no free section for it is left as it is and fails arrangeInLayout.
 */
export function completeRequiredSlots(layoutId: string, kinds: string[]): number[] {
  let filled: number[] = []
  let layout = findLayout(layoutId)
  if (layout === null) { return filled }
  for (let slot of layout.slots) {
    if (!slot.required || slot.accepts.length !== 1 || slot.accepts[0] === '*') { continue }
    if (kinds.indexOf(slot.accepts[0]) >= 0) { continue }
    for (let i = 0; i < kinds.length; i++) {
      if (kinds[i] === 'none') { kinds[i] = slot.accepts[0]; filled.push(i); break }
    }
  }
  return filled
}

/**
 * Replaces, in place, each kind this layout swaps for the kind that is wired into it (see
 * LayoutSpec.swaps), unless the target is already on the screen. Returns the indices changed;
 * `kinds` is changed in place.
 */
export function swapForLayout(layoutId: string, kinds: string[]): number[] {
  let changed: number[] = []
  let layout = findLayout(layoutId)
  if (layout === null) { return changed }
  for (let pair of layout.swaps) {
    let from = kinds.indexOf(pair[0])
    if (from >= 0 && kinds.indexOf(pair[1]) < 0) { kinds[from] = pair[1]; changed.push(from) }
  }
  return changed
}

/** Every kind some layout names in a slot (not the '*' wildcard): the parts Jev is asked about one by one once a layout is chosen. */
export function layoutKinds(): string[] {
  let out: string[] = []
  for (let layout of layouts()) {
    for (let slot of layout.slots) {
      for (let kind of slot.accepts) { if (kind !== '*' && out.indexOf(kind) < 0) { out.push(kind) } }
    }
  }
  return out
}

/** The kinds a layout's slots name, in slot order. */
export function kindsOfLayout(layoutId: string): string[] {
  let out: string[] = []
  let layout = findLayout(layoutId)
  if (layout === null) { return out }
  for (let slot of layout.slots) {
    for (let kind of slot.accepts) { if (kind !== '*' && out.indexOf(kind) < 0) { out.push(kind) } }
  }
  return out
}

/** Puts each wanted kind that is not on the screen yet into the first empty section; returns the indices filled. `kinds` is changed in place. */
export function placeKinds(kinds: string[], wanted: string[]): number[] {
  let filled: number[] = []
  for (let kind of wanted) {
    if (kinds.indexOf(kind) >= 0) { continue }
    for (let i = 0; i < kinds.length; i++) {
      if (kinds[i] === 'none') { kinds[i] = kind; filled.push(i); break }
    }
  }
  return filled
}

/**
 * The wanted kinds that still fit the layout's slots, in the order given (best first): a kind whose named slot is already full
 * -- by what is on the screen or by an earlier wanted kind -- is dropped, so two readers competing for a slot of one keep the
 * likelier one and the layout is not rejected for it. A kind no named slot takes (or already on the screen) is passed through
 * or skipped respectively.
 */
export function fitToSlots(layoutId: string, kinds: string[], wanted: string[]): string[] {
  let layout = findLayout(layoutId)
  if (layout === null) { return wanted }
  let counts: number[] = []
  for (let s = 0; s < layout.slots.length; s++) { counts.push(0) }
  for (let kind of kinds) {
    if (kind === 'none') { continue }
    let slot = namedSlotOf(layout, kind)
    if (slot >= 0) { counts[slot] = counts[slot] + 1 }
  }
  let out: string[] = []
  for (let kind of wanted) {
    if (kinds.indexOf(kind) >= 0) { continue }
    let slot = namedSlotOf(layout, kind)
    if (slot < 0) { out.push(kind); continue }
    if (counts[slot] >= layout.slots[slot].max) { continue }
    counts[slot] = counts[slot] + 1
    out.push(kind)
  }
  return out
}

function namedSlotOf(layout: LayoutSpec, kind: string): number {
  for (let s = 0; s < layout.slots.length; s++) {
    if (layout.slots[s].accepts.indexOf(kind) >= 0) { return s }
  }
  return -1
}
