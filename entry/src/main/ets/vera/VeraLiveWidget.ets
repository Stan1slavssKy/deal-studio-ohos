import { VirtualMachine, deserializeVbc2, encodeRuntimeValue, decodeRuntimeValue, RuntimeValue,
  VeraNumberValue, VeraStringValue } from './VeraInterpreter'
import { UiHostEnvironment, VeraUiNode, decodeVeraUi, formatVeraNumber } from './VeraUi'
import { CATALOG } from './VeraUiCatalog'
import { resolveTheme, pathFill } from './VeraTheme'
import { veraStateStamp, stateDigest } from './VeraStateStamp'
import { SOURCE_TARGET } from './VeraSource'
import { decodeGfx, encodeGfxOps, pointerValue, GfxOp } from './VeraGfx'
import { CardNode, LiveFrame } from '../widget/CardModel'
import { cardTextSize, cardTextWeight, cardTextInk, cardTextFamily, cardLetterSpacing, cardGap, cardPanelPad, cardPanelFill, cardButtonFill, cardButtonInk } from './CardStyle'
export { CardNode, LiveFrame } from '../widget/CardModel'

export const LIVE_MAX_DEPTH: number = 4
export const LIVE_MAX_NODES: number = 40
export const LIVE_MAX_TEXT: number = 256
// A shape's path data (a drum with its jingles is about 300); the whole frame is still held to LIVE_MAX_JSON.
export const LIVE_MAX_COMMANDS: number = 600
/** The Motion presets a card plays: each is one short settle from a hit pose (tumble and flip need 3D, which a card does not have). */
export const CARD_MOTIONS: string[] = ['pop', 'shake', 'bounce', 'fade']
export const LIVE_MAX_MOTIONS: number = 3
/** A picture on a card (ui.Surface drawn once for the frame): up to three, of a few dozen shapes each; the frame's own size budget counts the rest. */
export const LIVE_MAX_SURFACES: number = 3
export const LIVE_MAX_SHAPES: number = 60
/** The room a picture is sized to: a card is about 150 vp square (524 px at 3.5 px per vp) with 12 of padding, and 6 between its rows. */
export const LIVE_INNER_HEIGHT: number = 126
export const LIVE_ROW_GAP: number = 6
export const PICTURE_SIDE_MIN: number = 40
export const PICTURE_SIDE_MAX: number = 80
export const LIVE_MAX_STEPS: number = 100000
// UTF-16 length capped conservatively: even non-ASCII JSON remains small on the wire.
export const LIVE_MAX_JSON: number = 8000

/** The gap a column or row puts between its children (the card's own, 6 or 8, unless the node set one). */
function gapOf(node: CardNode, fallback: number): number { return node.gap !== undefined ? node.gap : fallback }
function padOf(node: CardNode): number { return node.pad !== undefined ? node.pad : 0 }

/** The inner width of a card, in vp: what a text wraps in. */
export const LIVE_INNER_WIDTH: number = 126
const LIVE_ROW_SPACE: number = 8

/**
 * About how tall a node draws, in vp, in `width` vp of room: a text of a few words is a line, a longer one wraps (at most two lines, as the card
 * draws it; about 0.55 em a character), a row shares its width among its children. What is left of the card for a picture is what these leave.
 */
function nodeHeight(node: CardNode, pictureSide: number, width: number = LIVE_INNER_WIDTH): number {
  if (node.kind === 'surface') { return Math.min(pictureSide * 1.1, pictureSide * node.h / node.w) }
  if (node.kind === 'path') { return node.size }
  if (node.kind === 'button') { return 40 }
  if (node.kind === 'divider') { return 1 }
  if (node.kind === 'spacer') { return 4 }
  if (node.kind === 'row') {
    let tallest = 0
    let share = (width - 2 * padOf(node) - LIVE_ROW_SPACE * Math.max(0, node.children.length - 1)) / Math.max(1, node.children.length)
    for (let child of node.children) { tallest = Math.max(tallest, nodeHeight(child, pictureSide, share)) }
    return tallest + 2 * padOf(node)
  }
  if (node.kind === 'column' || node.kind === 'motion') {
    return stackHeight(node.children, pictureSide, gapOf(node, LIVE_ROW_GAP), width - 2 * padOf(node)) + 2 * padOf(node)
  }
  // A figure is one line (it shrinks to fit); a text wraps to at most two.
  let lines = node.kind === 'numbertext' ? 1 : Math.max(1, Math.min(2, Math.ceil(node.text.length * 0.55 * node.size / Math.max(20, width))))
  return lines * node.size * 1.25
}

function stackHeight(nodes: CardNode[], pictureSide: number, gap: number = LIVE_ROW_GAP, width: number = LIVE_INNER_WIDTH): number {
  let total = 0
  for (let node of nodes) { total += nodeHeight(node, pictureSide, width) }
  return total + Math.max(0, nodes.length - 1) * gap
}

/** About how tall the widget draws on the card, in vp (its picture, if it has one, at the side it was given). */
export function widgetHeight(frame: LiveFrame): number {
  let side = 0
  let pictures = allPictures(frame.nodes, [])
  if (pictures.length > 0) { side = pictures[0].size }
  return stackHeight(frame.nodes, side)
}

function allPictures(nodes: CardNode[], out: CardNode[]): CardNode[] {
  for (let node of nodes) {
    if (node.kind === 'surface') { out.push(node) }
    allPictures(node.children, out)
  }
  return out
}

/** The widest a picture may be so the pictures of a row (directly, or in a Motion) share the card's width: its inner width less the gaps. */

function widthLimit(nodes: CardNode[]): number {
  let limit = PICTURE_SIDE_MAX
  for (let node of nodes) {
    if (node.kind === 'row') {
      let count = 0
      for (let child of node.children) {
        if (child.kind === 'surface') { count += 1 }
        if (child.kind === 'motion') { count += allPictures(child.children, []).length }
      }
      if (count > 1) { limit = Math.min(limit, Math.floor((LIVE_INNER_WIDTH - LIVE_ROW_SPACE * (count - 1)) / count)) }
    }
    limit = Math.min(limit, widthLimit(node.children))
  }
  return limit
}

/**
 * The side the pictures are drawn at, in vp: the largest, up to PICTURE_SIDE_MAX and what their rows' width allows, with which everything
 * else still fits the card's height. Below PICTURE_SIDE_MIN there is no room: the widget has too much else on it. 0 when it has no picture.
 */
export function pictureRoom(frame: LiveFrame): number {
  if (allPictures(frame.nodes, []).length === 0) { return 0 }
  for (let side = widthLimit(frame.nodes); side > 0; side--) {
    if (stackHeight(frame.nodes, side) <= LIVE_INNER_HEIGHT) { return side }
  }
  return 1
}

/** A live source call widgetRefresh made, for the card to make: its parameters and the handler its answer goes to. */
export class SourceRequest {
  params: Map<string, string>
  handler: string
  constructor(params: Map<string, string>, handler: string) { this.params = params; this.handler = handler }
}

export class WidgetSession {
  private host: UiHostEnvironment = new UiHostEnvironment()
  private vm: VirtualMachine
  private state: RuntimeValue
  private bytecode: string
  private versionId: string
  private hasWidget: boolean = false
  private hasRefresh: boolean = false

  constructor(vbc2: string, versionId: string, saved: string) {
    this.bytecode = vbc2
    this.versionId = versionId
    let module = deserializeVbc2(vbc2)
    this.hasWidget = module.functions.some((fn): boolean => fn.name === 'widget')
    this.hasRefresh = module.functions.some((fn): boolean => fn.name === 'widgetRefresh')
    this.vm = new VirtualMachine(module, this.host, LIVE_MAX_STEPS)
    this.state = saved.length > 0 ? decodeRuntimeValue(JSON.parse(saved) as Object) : this.vm.execute('init')
  }

  encodedState(): string { return JSON.stringify(encodeRuntimeValue(this.state)) }

  frame(projectId: string, title: string, icon: string): LiveFrame {
    let frame = new LiveFrame()
    frame.projectId = projectId
    frame.title = title
    frame.icon = icon
    frame.versionId = this.versionId
    if (!this.hasWidget) { frame.status = 'Open app'; return frame }
    this.host.effectsAllowed = false
    let roots = decodeVeraUi(this.vm.execute('widget', [this.state]))
    if (roots.length !== 1) { throw new Error('widget must return one root') }
    let root = roots[0]
    let theme = resolveTheme(root.kind === 'apptheme' ? root.style : 'clean',
      root.kind === 'apptheme' ? root.value : '', false)
    frame.background = theme.background
    frame.preset = root.kind === 'apptheme' ? root.style : 'clean'
    frame.primary = root.kind === 'apptheme' ? root.value : ''
    let count = 0
    let motions = 0
    let surfaces = 0
    let project = (node: VeraUiNode, depth: number, key: string, motionSlot: number): CardNode => {
      count += 1
      if (count > LIVE_MAX_NODES) { throw new Error('widget exceeds 40 nodes') }
      if (depth > LIVE_MAX_DEPTH) { throw new Error('widget exceeds depth 4') }
      let spec = CATALOG.find((entry): boolean => entry.nodeKind === node.kind)
      if (spec === undefined || !spec.card) { throw new Error('Not card-safe: ' + node.kind) }
      if (node.kind === 'apptheme' && key !== '0') { throw new Error('AppTheme must be the widget root') }
      let item = new CardNode()
      item.key = key
      item.kind = node.kind
      item.text = node.kind === 'numbertext' ? node.prefix + formatVeraNumber(node.numberValue, node.decimals, node.minimumDigits) + node.suffix : node.text
      if (item.text.length > LIVE_MAX_TEXT) { throw new Error('widget text exceeds 256 characters') }
      if (node.kind === 'path') {
        if (node.commands.length > LIVE_MAX_COMMANDS) { throw new Error('widget shape exceeds ' + LIVE_MAX_COMMANDS.toString() + ' characters') }
        item.commands = node.commands
      }
      if (node.kind === 'motion') {
        motions += 1
        if (motions > LIVE_MAX_MOTIONS) { throw new Error('a widget has at most ' + LIVE_MAX_MOTIONS.toString() + ' ui.Motion') }
        if (CARD_MOTIONS.indexOf(node.style) < 0) {
          throw new Error('ui.Motion style "' + node.style + '" does not play on a card: use ' + CARD_MOTIONS.join(', '))
        }
        if (!Number.isFinite(node.numberValue)) { throw new Error('ui.Motion trigger must be a number') }
        item.style = node.style
        item.trigger = node.numberValue
      }
      item.slot = node.kind === 'motion' ? motions - 1 : motionSlot
      if (node.kind === 'surface') {
        surfaces += 1
        if (surfaces > LIVE_MAX_SURFACES) { throw new Error('a widget has at most ' + LIVE_MAX_SURFACES.toString() + ' ui.Surface') }
        if (node.action.length > 0) {
          throw new Error('a card has no frames: leave the frame handler of ui.Surface empty (""), the picture is drawn once for each state')
        }
        if (node.label.length === 0) { throw new Error('ui.Surface needs the name of its draw function') }
        if (!(node.minimum > 0) || !(node.maximum > 0)) { throw new Error('ui.Surface width and height must be above 0') }
        let ops = decodeGfx(this.vm.execute(node.label, [this.state]))
        let shapes = 0
        for (let o of ops) { shapes += o.count }
        if (shapes > LIVE_MAX_SHAPES) {
          throw new Error('a card picture has at most ' + LIVE_MAX_SHAPES.toString() + ' shapes; this one has ' + shapes.toString())
        }
        item.ops = encodeGfxOps(ops)
        item.w = node.minimum
        item.h = node.maximum
        item.pointer = node.value
        item.pic = surfaces - 1
      }
      item.action = node.action
      item.value = node.eventValue
      item.enabled = node.enabled
      item.color = node.kind === 'path' ? pathFill(theme, node.style) : theme.inkStrong
      item.fill = theme.surface
      if (node.kind === 'path') { item.size = 64 }
      if (node.kind === 'text' || node.kind === 'numbertext') {
        // The theme's roles, with the card's sizes (CardStyle): the app's text styles reach the card instead of being flattened to three sizes.
        item.size = cardTextSize(node.style)
        item.color = cardTextInk(theme, node.style)
        let weight = cardTextWeight(theme, node.style)
        if (weight !== 400) { item.weight = weight }
        let family = cardTextFamily(theme, node.style)
        if (family.length > 0) { item.family = family }
        let spacing = cardLetterSpacing(theme, node.style)
        if (spacing !== 0) { item.spacing = spacing }
      }
      if (node.kind === 'button') {
        item.fill = cardButtonFill(theme, node.style)
        item.color = cardButtonInk(theme, node.style)
        if (theme.radiusControl !== 10) { item.radius = theme.radiusControl }
      }
      if (node.kind === 'divider') { item.color = theme.line }
      if (node.kind === 'column' || node.kind === 'row') {
        let gap = cardGap(node.kind, node.style)
        if (gap !== (node.kind === 'row' ? 8 : 6)) { item.gap = gap }
        // A column is centred on a card unless it says 'end'; a row is spread evenly unless it says 'split', 'end' or 'joined'.
        if (node.style === 'end' || (node.kind === 'row' && (node.style === 'split' || node.style === 'joined'))) { item.align = node.style }
        let panel = cardPanelFill(theme, node.style)
        if (panel.length > 0) {
          item.panel = panel
          item.pad = cardPanelPad(node.style)
          item.radius = theme.radiusControl
        }
      }
      item.children = node.children.map((child: VeraUiNode, index: number): CardNode => project(child, depth + 1, key + '.' + index.toString(), item.slot))
      return item
    }
    // The theme wrapper consumes no layout level but is still validated and counted.
    let tree = project(root, root.kind === 'apptheme' ? 0 : 1, '0', -1)
    frame.nodes = root.kind === 'apptheme' ? tree.children : [tree]
    let side = pictureRoom(frame)
    for (let picture of allPictures(frame.nodes, [])) { picture.size = Math.max(PICTURE_SIDE_MIN, Math.min(PICTURE_SIDE_MAX, side)) }
    // Rejects taps from an older frame or state. A digest, not the state itself: the token is in the card's data, which has
    // a size budget, and in every key of its layout, so it must not grow with the app's data.
    frame.token = this.versionId + ':' + veraStateStamp(this.bytecode) + ':' + stateDigest(this.encodedState())
    frame.live = true
    if (JSON.stringify(frame).length > LIVE_MAX_JSON) { throw new Error('widget binding exceeds size budget') }
    return frame
  }

  /** The program has widgetRefresh: the card's periodic update brings its state up to date with the clock. */
  refreshes(): boolean { return this.hasRefresh }

  /**
   * widgetRefresh, as a tap runs a handler: the state is kept only when it returns. The one call it may make is its live source
   * (Vera.Source.fetch, a GET the program was generated with): returned for the card to make, the answer going to `answer`.
   * Any other phone effect is refused.
   */
  refresh(): SourceRequest[] {
    let requests: SourceRequest[] = []
    if (!this.hasRefresh) { return requests }
    this.host.effectsAllowed = true
    this.host.pendingEffects = []
    try {
      let next = this.vm.execute('widgetRefresh', [this.state])
      requests = this.sourceRequests('widgetRefresh asked for a phone action')
      this.state = next
    } finally {
      this.host.effectsAllowed = false
      this.host.pendingEffects = []
    }
    return requests
  }

  /** A source's answer to its handler, as the app delivers one: handler(state, answer). No phone effects. */
  answer(handler: string, text: string): void {
    this.host.effectsAllowed = true
    this.host.pendingEffects = []
    try {
      let next = this.vm.execute(handler, [this.state, new VeraStringValue(text)])
      if (this.host.pendingEffects.length > 0) { throw new Error(handler + ' asked for a phone action') }
      this.state = next
    } finally {
      this.host.effectsAllowed = false
      this.host.pendingEffects = []
    }
  }

  /** A button's handler; its live source call (Vera.Source.fetch), if it makes one, is returned for the card to make. */
  tap(frame: LiveFrame, token: string, action: string, value: number): SourceRequest[] {
    if (!frame.live || token !== frame.token) { throw new Error('Widget changed; tap again') }
    let allowed = (nodes: CardNode[]): boolean => nodes.some((node: CardNode): boolean =>
      ((node.kind === 'button' || node.kind === 'path') && node.enabled && node.action.length > 0 && node.action === action && node.value === value) || allowed(node.children))
    if (!Number.isFinite(value) || !allowed(frame.nodes)) { throw new Error('Action is not available on this widget') }
    this.host.effectsAllowed = true
    this.host.pendingEffects = []
    try {
      let next = this.vm.execute(action, [this.state, new VeraNumberValue(value)])
      let requests = this.sourceRequests('Open app to continue: phone action required')
      this.state = next
      return requests
    } finally {
      this.host.effectsAllowed = false
      this.host.pendingEffects = []
    }
  }

  /**
   * A tap on the picture: the handler the program named for pointers, told the finger went down and came up at x, y (in the
   * picture's own units), as the app's surface tells it. One state change, made together; a card has no moves.
   */
  tapSurface(frame: LiveFrame, token: string, handler: string, x: number, y: number): SourceRequest[] {
    if (!frame.live || token !== frame.token) { throw new Error('Widget changed; tap again') }
    let found = (nodes: CardNode[]): boolean => nodes.some((node: CardNode): boolean =>
      (node.kind === 'surface' && node.pointer.length > 0 && node.pointer === handler) || found(node.children))
    if (!Number.isFinite(x) || !Number.isFinite(y) || !found(frame.nodes)) { throw new Error('Action is not available on this widget') }
    this.host.effectsAllowed = true
    this.host.pendingEffects = []
    try {
      let down = this.vm.execute(handler, [this.state, pointerValue('down', 0, x, y)])
      let up = this.vm.execute(handler, [down, pointerValue('up', 0, x, y)])
      let requests = this.sourceRequests('Open app to continue: phone action required')
      this.state = up
      return requests
    } finally {
      this.host.effectsAllowed = false
      this.host.pendingEffects = []
    }
  }

  /** The effects collected, when every one is a call to the program's live source; else `refused` is thrown. */
  private sourceRequests(refused: string): SourceRequest[] {
    let requests: SourceRequest[] = []
    for (let effect of this.host.pendingEffects) {
      if (effect.rawTarget !== SOURCE_TARGET || effect.resultHandler.length === 0) { throw new Error(refused) }
      requests.push(new SourceRequest(effect.values, effect.resultHandler))
    }
    return requests
  }
}

/**
 * Whether two programs' widgets draw the same card over the same data: what is on it, its colours and sizes, not the
 * frame's token. A widget that cannot be drawn is not the same as one that can.
 */
export function sameCard(before: string, after: string, seed: string): boolean {
  let draw = (vbc2: string): string => {
    try {
      let frame = new WidgetSession(vbc2, 'compare', seed).frame('', '', '')
      return frame.live ? JSON.stringify(frame.nodes) + frame.background : ''
    } catch (_e) {
      return ''
    }
  }
  let a = draw(before)
  return a.length > 0 && a === draw(after)
}
