import { VirtualMachine, deserializeVbc2, encodeRuntimeValue, decodeRuntimeValue, RuntimeValue,
  VeraNumberValue, VeraStringValue, VeraBooleanValue } from './VeraInterpreter'
import { UiHostEnvironment, VeraUiNode, decodeVeraUi, formatVeraNumber } from './VeraUi'
import { CATALOG } from './VeraUiCatalog'
import { resolveTheme, pathFill, toneInk, toneEdge, toneFill, buttonFill, buttonInk, textWeight, textInk } from './VeraTheme'
import { iconPath } from './VeraIcons'
import { MOTION_PRESETS } from './VeraMotion'
import { veraStateStamp, stateDigest } from './VeraStateStamp'
import { SOURCE_TARGET } from './VeraSource'
import { decodeGfx, encodeGfxOps, pointerValue, GfxOp } from './VeraGfx'
import { driftSlices } from './GfxPaint'
import { CardNode, LiveFrame, compactFrame, CardSize, cardSize, CARD_DIMENSIONS, CARD_MAX_MOTIONS, CARD_MAX_PICTURES, CARD_MAX_SHAPES,
  CARD_MAX_TIMERS, TOUCH_ACTION, pictureCovers } from '../widget/CardModel'
import { cardTextSize, cardTextFamily, cardLetterSpacing, cardGap, CARD_PANEL_PAD, cardPanelFill } from './CardStyle'
export { CardNode, LiveFrame, compactFrame, compactNode, normalizeNodes, CardSize, cardSize, CARD_DIMENSIONS, TOUCH_ACTION } from '../widget/CardModel'

export const LIVE_MAX_DEPTH: number = 4
export const LIVE_MAX_TEXT: number = 256
// A shape's path data (a drum with its jingles is about 300); the whole frame is still held to LIVE_MAX_JSON.
export const LIVE_MAX_COMMANDS: number = 600
/** The Motion presets a card plays: every one, as stages (VeraMotion.motionStages). */
export const CARD_MOTIONS: string[] = MOTION_PRESETS
export const LIVE_MAX_MOTIONS: number = CARD_MAX_MOTIONS
/** Pictures on a card (ui.Surface or ui.Sparkline, drawn once for the frame), of a few dozen shapes each; the frame's own size budget counts the rest. */
export const LIVE_MAX_SURFACES: number = CARD_MAX_PICTURES
/** Moving parts (gfx.moving) in one card picture: each is a layer of its own, and a card has five pictures in all. */
export const LIVE_MAX_PARTS: number = 3
/** Drifts (gfx.drift) on a card: each is a Swiper of up to eight slices of its own (CardView). */
export const LIVE_MAX_DRIFTS: number = 2
/** After a tap the app's frame handlers run in steps of this many ms (a card has no frames of its own)... */
export const SETTLE_STEP_MS: number = 33
/** ...for at most this many steps (10 s: a wheel takes 4 or 5), and the state they reach is kept only once this many steps in a row change nothing. */
export const SETTLE_MAX_STEPS: number = 300
export const SETTLE_CALM_STEPS: number = 3
export const LIVE_MAX_SHAPES: number = CARD_MAX_SHAPES
/** Timers a card runs (ui.Timer, the platform's own TextTimer). */
export const LIVE_MAX_TIMERS: number = CARD_MAX_TIMERS

export const LIVE_ROW_GAP: number = 6
export const PICTURE_SIDE_MIN: number = 40
export const LIVE_MAX_STEPS: number = 100000
// UTF-16 length capped conservatively: even non-ASCII JSON remains small on the wire.
export const LIVE_MAX_JSON: number = 8000

/** The gap a column or row puts between its children (the card's own, 6 or 8, unless the node set one). */
function gapOf(node: CardNode, fallback: number): number { return node.gap !== undefined ? node.gap : fallback }
function padOf(node: CardNode): number { return node.pad !== undefined ? node.pad : 0 }

/** The inner width of a 2x2 card, in vp: what a text wraps in when nothing says the card is wider. */
const LIVE_INNER_WIDTH: number = cardSize(2).width
const LIVE_ROW_SPACE: number = 8

/**
 * About how tall a node draws, in vp, in `width` vp of room: a text of a few words is a line, a longer one wraps (at most two lines, as the card
 * draws it; about 0.55 em a character), a row shares its width among its children. What is left of the card for a picture is what these leave.
 */
function nodeHeight(node: CardNode, pictureSide: number, width: number = LIVE_INNER_WIDTH): number {
  // A cover picture is the card's background (CardModel.splitCover): it takes no room from the rest.
  if (coverPicture(node)) { return 0 }
  if (node.kind === 'motion' && node.children.length === 1 && coverPicture(node.children[0])) { return 0 }
  if (node.kind === 'surface' || node.kind === 'drift') { return Math.min(pictureSide * 1.1, pictureSide * node.h / node.w) }
  if (node.kind === 'path' || node.kind === 'icon') { return node.size }
  if (node.kind === 'iconbutton') { return node.size }
  if (node.kind === 'badge') { return 22 }
  if (node.kind === 'toggle' || node.kind === 'checkbox') { return 24 }
  if (node.kind === 'progress') { return 30 }
  if (node.kind === 'ring') { return node.size + (node.text.length > 0 ? 16 : 0) }
  if (node.kind === 'button') { return 40 }
  if (node.kind === 'divider') { return 1 }
  if (node.kind === 'spacer') { return 4 }
  if (node.kind === 'row') {
    let tallest = 0
    let share = (width - 2 * padOf(node) - LIVE_ROW_SPACE * Math.max(0, node.children.length - 1)) / Math.max(1, node.children.length)
    for (let child of node.children) { tallest = Math.max(tallest, nodeHeight(child, pictureSide, share)) }
    return tallest + 2 * padOf(node)
  }
  if (node.kind === 'layers') {
    let tallest = 0
    for (let child of node.children) { tallest = Math.max(tallest, nodeHeight(child, pictureSide, width)) }
    return tallest
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

/**
 * '' when the widget's cover pictures (ui.Surface style "cover") can be drawn as the card's background: at most one, and not in a row or a
 * ui.Layers, where it would have to share the card. Else why not, said for the model.
 */
export function coverError(nodes: CardNode[]): string {
  let covers = 0
  let misplaced = false
  let walk = (list: CardNode[], shared: boolean): void => {
    for (let node of list) {
      if (coverPicture(node)) {
        covers++
        if (shared) { misplaced = true }
        // The layers of one cover picture split at its moving parts are that one picture.
        if (node.kind === 'layers') { continue }
      }
      walk(node.children, shared || node.kind === 'row' || node.kind === 'layers')
    }
  }
  walk(nodes, false)
  if (covers > 1) { return 'a widget has at most one ui.Surface of style "cover": it is the whole card\'s background' }
  if (misplaced) {
    return 'a ui.Surface of style "cover" is the whole card\'s background: put it in the widget\'s column (or alone in a ui.Motion), not in a row or a ui.Layers'
  }
  return ''
}

/** About how tall the widget draws on the card, in vp (its picture, if it has one, at the side it was given). */
export function widgetHeight(frame: LiveFrame): number {
  let side = 0
  let pictures = allPictures(frame.nodes, [])
  if (pictures.length > 0) { side = pictures[0].size }
  return stackHeight(frame.nodes, side, LIVE_ROW_GAP, cardSize(frame.dimension).width)
}

/** A cover picture, or the layers it was split into at its moving parts: the card's background. */
function coverPicture(node: CardNode): boolean {
  return (node.kind === 'surface' || (node.kind === 'layers' && node.parts === true)) && pictureCovers(node.style)
}

/** The pictures that share the card's room with the rest: a cover picture lies under it all instead. */
function allPictures(nodes: CardNode[], out: CardNode[]): CardNode[] {
  for (let node of nodes) {
    if ((node.kind === 'surface' && !pictureCovers(node.style)) || (node.kind === 'drift' && node.cover !== true)) { out.push(node) }
    allPictures(node.children, out)
  }
  return out
}

/**
 * How many pictures a node puts side by side: a row adds its children's, a Layers (one over another) or a column, Motion, Stat or
 * Sparkline (one under another) takes the most of any child.
 */
function picturesAcross(node: CardNode): number {
  if (node.kind === 'surface') { return pictureCovers(node.style) ? 0 : 1 }
  if (node.kind === 'drift') { return node.cover === true ? 0 : 1 }
  let most = 0
  let sum = 0
  for (let child of node.children) {
    let across = picturesAcross(child)
    most = Math.max(most, across)
    sum += across
  }
  return node.kind === 'row' ? sum : most
}

/** The widest a picture may be so the pictures of a row, at any depth under it, share the card's width: its inner width less the gaps. */
function widthLimit(nodes: CardNode[], size: CardSize): number {
  let limit = size.pictureMax
  for (let node of nodes) {
    if (node.kind === 'row') {
      let count = picturesAcross(node)
      if (count > 1) { limit = Math.min(limit, Math.floor((size.width - LIVE_ROW_SPACE * (count - 1)) / count)) }
    }
    limit = Math.min(limit, widthLimit(node.children, size))
  }
  return limit
}

/**
 * The side the pictures are drawn at, in vp: the largest, up to the size's pictureMax and what their rows' width allows, with which everything
 * else still fits the card's height. Below PICTURE_SIDE_MIN there is no room: the widget has too much else on it. 0 when it has no picture.
 */
export function pictureRoom(frame: LiveFrame): number {
  if (allPictures(frame.nodes, []).length === 0) { return 0 }
  let size = cardSize(frame.dimension)
  for (let side = widthLimit(frame.nodes, size); side > 0; side--) {
    if (stackHeight(frame.nodes, side, LIVE_ROW_GAP, size.width) <= size.height) { return side }
  }
  return 1
}

/** A live source call widgetRefresh made, for the card to make: its parameters and the handler its answer goes to. */
export class SourceRequest {
  params: Map<string, string>
  handler: string
  constructor(params: Map<string, string>, handler: string) { this.params = params; this.handler = handler }
}

/** The shapes of a ui.Sparkline on a card: 100 by 36 units, a line through the series (or a bar for each value), a second series in a quieter colour. */
function sparkOps(series: number[], series2: number[], maximum: number, bars: boolean): GfxOp[] {
  const width = 100
  const height = 36
  const pad = 3
  let top = maximum > 0 ? maximum : 0
  if (top <= 0) {
    for (let v of series) { top = Math.max(top, v) }
    for (let v of series2) { top = Math.max(top, v) }
  }
  if (!(top > 0)) { top = 1 }
  let ops: GfxOp[] = []
  let line = (values: number[], colour: string, widthPx: number): void => {
    if (values.length === 0) { return }
    let points: number[] = []
    for (let i = 0; i < values.length; i++) {
      points.push(values.length > 1 ? pad + i * (width - 2 * pad) / (values.length - 1) : width / 2)
      points.push(height - pad - Math.max(0, Math.min(1, values[i] / top)) * (height - 2 * pad))
    }
    let o = new GfxOp()
    o.kind = 'polyline'; o.points = points; o.lineWidth = widthPx; o.color = colour
    ops.push(o)
  }
  if (bars) {
    let slot = width / Math.max(1, series.length)
    for (let i = 0; i < series.length; i++) {
      let h = Math.max(1, Math.max(0, Math.min(1, series[i] / top)) * (height - 2 * pad))
      let o = new GfxOp()
      o.kind = 'rect'; o.x = i * slot + slot * 0.19; o.y = height - pad - h; o.w = slot * 0.62; o.h = h; o.color = 'accent'
      ops.push(o)
    }
    return ops
  }
  line(series2, 'muted', 2)
  line(series, 'accent', 2.6)
  if (series.length > 0) {
    let end = new GfxOp()
    end.kind = 'circle'
    end.x = series.length > 1 ? width - pad : width / 2
    end.y = height - pad - Math.max(0, Math.min(1, series[series.length - 1] / top)) * (height - 2 * pad)
    end.r = 3; end.color = 'accent'
    ops.push(end)
  }
  return ops
}

export class WidgetSession {
  private host: UiHostEnvironment = new UiHostEnvironment()
  private vm: VirtualMachine
  private state: RuntimeValue
  private bytecode: string
  private versionId: string
  private hasWidget: boolean = false
  private hasRefresh: boolean = false
  /** widget(state, size: number): the program asked for the card's size too. */
  private hasSize: boolean = false

  constructor(vbc2: string, versionId: string, saved: string) {
    this.bytecode = vbc2
    this.versionId = versionId
    let module = deserializeVbc2(vbc2)
    this.hasWidget = module.functions.some((fn): boolean => fn.name === 'widget')
    this.hasRefresh = module.functions.some((fn): boolean => fn.name === 'widgetRefresh')
    this.hasSize = module.functions.some((fn): boolean => fn.name === 'widget' && fn.parameterCount === 2)
    this.vm = new VirtualMachine(module, this.host, LIVE_MAX_STEPS)
    this.state = saved.length > 0 ? decodeRuntimeValue(JSON.parse(saved) as Object) : this.vm.execute('init')
  }

  encodedState(): string { return JSON.stringify(encodeRuntimeValue(this.state)) }

  /** The frame handlers of the app's own view: the ui.Surface frame functions the app runs about 60 times a second. */
  private frameHandlers(): string[] {
    let names: string[] = []
    try {
      let walk = (nodes: VeraUiNode[]): void => {
        for (let node of nodes) {
          if (node.kind === 'surface' && node.action.length > 0 && names.indexOf(node.action) < 0) { names.push(node.action) }
          walk(node.children)
        }
      }
      walk(decodeVeraUi(this.vm.execute('view', [this.state])))
    } catch (e) {
      return []
    }
    return names
  }

  /**
   * What a tap started, finished: a card has no frames, so a wheel set spinning by a tap would spin for ever and its Spin button stay off
   * (found on the phone). The app's frame handlers run on the state in SETTLE_STEP_MS steps, as the app would run them, and the state they
   * reach is kept once it stops changing. What a frame asks of the phone (a tick's vibration, a sound) is dropped, as the card can do none of
   * it, and never answered. A state that does not come to rest within SETTLE_MAX_STEPS -- a game that plays on, a clock that counts -- is left
   * as the tap left it, so the card never plays a game on for the person; so is one whose frame traps.
   */
  private settle(): void {
    let handlers = this.frameHandlers()
    if (handlers.length === 0) { return }
    let started = Date.now()
    let current = this.state
    let last = JSON.stringify(encodeRuntimeValue(current))
    let calm = 0
    let step = 0
    let rested = false
    this.host.effectsAllowed = true
    try {
      for (; step < SETTLE_MAX_STEPS && !rested; step++) {
        for (let handler of handlers) {
          this.host.pendingEffects = []
          current = this.vm.execute(handler, [current, new VeraNumberValue(SETTLE_STEP_MS)])
        }
        let encoded = JSON.stringify(encodeRuntimeValue(current))
        calm = encoded === last ? calm + 1 : 0
        last = encoded
        rested = calm >= SETTLE_CALM_STEPS
      }
      if (rested) { this.state = current }
    } catch (e) {
      // A frame that traps does not count: the state stays as the tap left it.
    } finally {
      this.host.effectsAllowed = false
      this.host.pendingEffects = []
    }
    console.info('VERA-WIDGET settle ' + (rested ? 'rested' : 'left as tapped') + ' steps=' + step.toString() + ' ms=' + (Date.now() - started).toString())
  }

  frame(projectId: string, title: string, icon: string, dimension: number = 2): LiveFrame {
    let size = cardSize(dimension)
    let frame = new LiveFrame()
    frame.projectId = projectId
    frame.title = title
    frame.icon = icon
    frame.versionId = this.versionId
    frame.dimension = size.dimension
    if (!this.hasWidget) { frame.status = 'Open app'; return frame }
    this.host.effectsAllowed = false
    let roots = decodeVeraUi(this.vm.execute('widget', this.hasSize ? [this.state, new VeraNumberValue(size.dimension)] : [this.state]))
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
    let drifts = 0
    let timers = 0
    // The nodes a component is expanded into (a Stat, a Sparkline) are made, counted and depth-checked like the ones the program wrote.
    let make = (kind: string, key: string, depth: number, slot: number): CardNode => {
      count += 1
      if (count > size.maxNodes) { throw new Error('widget exceeds ' + size.maxNodes.toString() + ' nodes') }
      if (depth > LIVE_MAX_DEPTH) { throw new Error('widget exceeds depth 4') }
      let made = new CardNode()
      made.kind = kind
      made.key = key
      made.slot = slot
      return made
    }
    let iconOf = (name: string): string => {
      let commands = iconPath(name)
      if (commands.length === 0) { throw new Error('unknown icon "' + name + '"') }
      return commands
    }
    let statOf = (item: CardNode, node: VeraUiNode, depth: number, key: string, slot: number, figure: string): void => {
      item.kind = 'column'
      item.gap = 2
      let kids: CardNode[] = []
      if (node.icon.length > 0) {
        // With an icon the caption sits beside it in a row (one level deeper); without, it is a text of the column's own.
        let head = make('row', key + '.h', depth + 1, slot)
        head.gap = 4
        head.align = 'joined'
        let glyph = make('icon', key + '.hi', depth + 2, slot)
        glyph.commands = iconOf(node.icon)
        glyph.size = 12
        glyph.color = toneInk(theme, node.style, theme.inkMuted)
        head.children.push(glyph)
        if (node.label.length > 0) {
          let label = make('text', key + '.hl', depth + 2, slot)
          label.text = node.label
          label.size = cardTextSize('caption')
          label.color = theme.inkMuted
          head.children.push(label)
        }
        kids.push(head)
      } else if (node.label.length > 0) {
        let label = make('text', key + '.hl', depth + 1, slot)
        label.text = node.label
        label.size = cardTextSize('caption')
        label.color = theme.inkMuted
        kids.push(label)
      }
      let big = make('numbertext', key + '.f', depth + 1, slot)
      big.text = figure
      // A Stat's figure is smaller than a lone metric (24, not 30): two of them side by side have to leave room between them.
      big.size = 24
      big.color = toneInk(theme, node.style, theme.ink)
      let weight = textWeight(theme, 'metric')
      if (weight !== 400) { big.weight = weight }
      let family = cardTextFamily(theme, 'metric')
      if (family.length > 0) { big.family = family }
      kids.push(big)
      if (node.value.length > 0) {
        let line = make('text', key + '.s', depth + 1, slot)
        line.text = node.value
        line.size = cardTextSize('caption')
        line.color = theme.inkSoft
        kids.push(line)
      }
      item.children = kids
    }
    // A touch on any part of a scene plays all its movements: the slots of its Motions, on it and on everything in it (CardView).
    let linkScene = (item: CardNode): void => {
      let slots: number[] = []
      let gather = (nodes: CardNode[]): void => {
        for (let child of nodes) {
          if (child.kind === 'motion' && child.slot >= 0) { slots.push(child.slot) }
          gather(child.children)
        }
      }
      gather(item.children)
      let link = (nodes: CardNode[]): void => {
        for (let child of nodes) {
          child.links = slots
          link(child.children)
        }
      }
      if (slots.length > 0) { item.links = slots; link(item.children) }
    }
    /**
     * A picture with moving parts (gfx.moving) as a scene: the card cannot move a part of one canvas, so the picture is split where its
     * parts are into layers of the same box, one over another -- what is still under them, each part in a Motion of its own that turns
     * about the part's pivot, and what is still over them -- and the card plays each layer by itself. The layers are pictures, counted
     * against the card's five; the picture's pointer goes on the bottom one, and a touch anywhere plays every part.
     */
    let splitParts = (item: CardNode, ops: GfxOp[], depth: number, key: string): void => {
      let parts = ops.filter((o: GfxOp): boolean => o.kind === 'moving')
      let strips = ops.filter((o: GfxOp): boolean => o.kind === 'drift')
      if (drifts + strips.length > LIVE_MAX_DRIFTS) {
        throw new Error('a widget has at most ' + LIVE_MAX_DRIFTS.toString() + ' gfx.drift')
      }
      if (parts.length > LIVE_MAX_PARTS) {
        throw new Error('a card picture has at most ' + LIVE_MAX_PARTS.toString() + ' gfx.moving parts; this one has ' + parts.length.toString())
      }
      if (item.slot >= 0) {
        throw new Error('a picture with gfx.moving parts moves them itself: do not put it in a ui.Motion (its parts would move twice)')
      }
      if (depth + 2 > LIVE_MAX_DEPTH) {
        throw new Error('a picture with gfx.moving parts is drawn as layers, two levels deeper than the picture: put it directly in the ' +
          'widget\'s column, not in a row or column inside it')
      }
      let cover = pictureCovers(item.style)
      let w = item.w
      let h = item.h
      let pointer = item.pointer
      surfaces -= 1
      item.kind = 'layers'
      item.parts = true
      item.ops = ''
      item.pointer = ''
      item.pic = -1
      let layers: CardNode[] = []
      let picture = (shapes: GfxOp[], layerKey: string, layerDepth: number, slot: number): CardNode => {
        surfaces += 1
        if (surfaces > LIVE_MAX_SURFACES) {
          throw new Error('a widget has at most ' + LIVE_MAX_SURFACES.toString() + ' pictures, and a picture with moving parts is one for what is ' +
            'still under them, one for each part and one for what is over them: use fewer parts or pictures')
        }
        let layer = make('surface', layerKey, layerDepth, slot)
        layer.ops = encodeGfxOps(shapes)
        layer.w = w
        layer.h = h
        layer.pic = surfaces - 1
        layer.style = layers.length === 0 ? (cover ? 'cover' : 'default') : (cover ? 'cover clear' : 'clear')
        if (layers.length === 0) { layer.pointer = pointer }
        return layer
      }
      let still: GfxOp[] = []
      let flush = (): void => {
        if (still.length === 0) { return }
        layers.push(picture(still, key + '.l' + layers.length.toString(), depth + 1, -1))
        still = []
      }
      // A picture that starts with a drift still has a bottom layer, its background, to take its touches.
      if (ops.length > 0 && ops[0].kind === 'drift') { layers.push(picture([], key + '.l0', depth + 1, -1)) }
      for (let o of ops) {
        if (o.kind === 'drift') {
          flush()
          drifts += 1
          let strip = make('drift', key + '.d' + layers.length.toString(), depth + 1, -1)
          strip.style = o.fx
          strip.value = driftSlices(o.text)
          strip.ops = encodeGfxOps([o])
          strip.w = w
          strip.h = h
          strip.pic = drifts - 1
          if (cover) { strip.cover = true }
          layers.push(strip)
          continue
        }
        if (o.kind !== 'moving') { still.push(o); continue }
        flush()
        if (CARD_MOTIONS.indexOf(o.fx) < 0) { throw new Error('gfx.moving style "' + o.fx + '" does not play on a card: use ' + CARD_MOTIONS.join(', ')) }
        motions += 1
        if (motions > LIVE_MAX_MOTIONS) { throw new Error('a widget has at most ' + LIVE_MAX_MOTIONS.toString() + ' movements (ui.Motion and gfx.moving)') }
        let motion = make('motion', key + '.m' + layers.length.toString(), depth + 1, motions - 1)
        motion.style = o.fx
        motion.trigger = o.sweep
        motion.px = Math.round(1000 * o.x / w) / 1000
        motion.py = Math.round(1000 * o.y / h) / 1000
        // The first layer is the bottom one: it takes the picture's pointer whether it is still or moving.
        let first = layers.length === 0
        motion.children = [picture(o.children, key + '.p' + layers.length.toString(), depth + 2, motions - 1)]
        if (first) { motion.children[0].pointer = pointer }
        layers.push(motion)
      }
      flush()
      item.children = layers
      linkScene(item)
    }
    // Whether a ui.Surface's drawing has moving parts: then a ui.Motion around it is dropped (project), since the parts move by themselves
    // and the two levels it takes are the ones the parts' layers need.
    let drawsParts = (node: VeraUiNode): boolean => {
      if (node.kind !== 'surface' || node.label.length === 0) { return false }
      try {
        return decodeGfx(this.vm.execute(node.label, [this.state])).some((o: GfxOp): boolean => o.kind === 'moving' || o.kind === 'drift')
      } catch (e) {
        return false
      }
    }
    let project = (node: VeraUiNode, depth: number, key: string, motionSlot: number): CardNode => {
      if (node.kind === 'motion' && node.children.length === 1 && drawsParts(node.children[0])) {
        return project(node.children[0], depth, key, motionSlot)
      }
      count += 1
      if (count > size.maxNodes) { throw new Error('widget exceeds ' + size.maxNodes.toString() + ' nodes') }
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
        let nested = (list: GfxOp[], top: boolean): boolean =>
          list.some((o: GfxOp): boolean => (!top && (o.kind === 'moving' || o.kind === 'drift')) || nested(o.children, false))
        if (nested(ops, true)) {
          throw new Error('gfx.moving and gfx.drift must be among the shapes the draw function returns, not inside a gfx.group, an effect or each other')
        }
        item.ops = encodeGfxOps(ops)
        item.w = node.minimum
        item.h = node.maximum
        item.pointer = node.value
        item.pic = surfaces - 1
        item.style = node.style
        if (ops.some((o: GfxOp): boolean => o.kind === 'moving' || o.kind === 'drift')) { splitParts(item, ops, depth, key) }
      }
      item.action = node.action
      item.value = node.eventValue
      item.enabled = node.enabled
      item.color = node.kind === 'path' ? pathFill(theme, node.style) : theme.inkStrong
      item.fill = theme.surface
      if (node.kind === 'path') { item.size = 64 }
      if (node.kind === 'timer') {
        timers += 1
        if (timers > LIVE_MAX_TIMERS) { throw new Error('a widget has at most ' + LIVE_MAX_TIMERS.toString() + ' ui.Timer') }
        if (!Number.isFinite(node.numberValue)) { throw new Error('ui.Timer millis must be a number') }
        item.val = node.numberValue
        item.max = node.checked ? 1 : 0
        item.pic = timers - 1
      }
      if (node.kind === 'text' || node.kind === 'numbertext' || node.kind === 'timer') {
        // The theme's roles, with the card's sizes (CardStyle): the app's text styles reach the card instead of being flattened to three sizes.
        item.size = cardTextSize(node.style)
        item.color = textInk(theme, node.style)
        let weight = textWeight(theme, node.style)
        if (weight !== 400) { item.weight = weight }
        let family = cardTextFamily(theme, node.style)
        if (family.length > 0) { item.family = family }
        let spacing = cardLetterSpacing(theme, node.style)
        if (spacing !== 0) { item.spacing = spacing }
      }
      if (node.kind === 'button') {
        item.fill = buttonFill(theme, node.style)
        item.color = buttonInk(theme, node.style)
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
          item.pad = CARD_PANEL_PAD
          item.radius = theme.radiusControl
        }
      }
      if (node.kind === 'progressring') { item.kind = 'ring' }
      if (node.kind === 'metricgroup') { item.kind = node.columns > 1 ? 'row' : 'column' }
      if (node.kind === 'icon') {
        item.commands = iconOf(node.icon)
        item.size = cardTextSize('heading')
        item.color = toneInk(theme, node.style, theme.inkStrong)
      }
      if (node.kind === 'iconbutton') {
        item.commands = iconOf(node.icon)
        item.size = 36
        item.fill = node.style === 'quiet' ? '#00000000' : node.style === 'secondary' ? theme.secondaryFill : buttonFill(theme, node.style)
        item.color = node.style === 'quiet' || node.style === 'secondary' ? theme.secondaryInk : theme.onPrimary
      }
      if (node.kind === 'badge') {
        item.commands = node.icon.length > 0 ? iconOf(node.icon) : ''
        item.color = toneInk(theme, node.style, theme.inkSoft)
        item.fill = toneFill(theme, node.style, theme.surface)
        item.radius = theme.radiusSmall
      }
      if (node.kind === 'toggle' || node.kind === 'checkbox') {
        // A switch: its label, on or off (val 1 or 0), the colour it is on in and the colour it is off in, and the check mark's path for a box.
        item.text = node.label
        item.val = node.checked ? 1 : 0
        item.color = theme.primary
        item.fill = theme.lineStrong
        item.ink = theme.ink
        if (node.kind === 'checkbox') { item.commands = iconOf('check') }
      }
      if (node.kind === 'progress' || node.kind === 'progressring') {
        item.text = node.label
        item.val = node.eventValue
        item.max = node.maximum > 0 ? node.maximum : 100
        item.color = toneEdge(theme, node.style, theme.primary)
        item.fill = theme.lineSoft
        item.ink = theme.inkStrong
        if (node.kind === 'progressring') {
          item.sub = node.text.length > 0 ? node.text : Math.round(100 * node.eventValue / item.max).toString() + '%'
          item.size = 52
        }
      }
      if (node.kind === 'stat') { statOf(item, node, depth, key, motionSlot, node.text) }
      if (node.kind === 'numberstat') {
        statOf(item, node, depth, key, motionSlot, node.prefix + formatVeraNumber(node.numberValue, node.decimals, node.minimumDigits) + node.suffix)
      }
      if (node.kind === 'sparkline') {
        item.kind = 'column'
        item.gap = 2
        let kids: CardNode[] = []
        if (node.label.length > 0) {
          let label = make('text', key + '.l', depth + 1, motionSlot)
          label.text = node.label
          label.size = cardTextSize('caption')
          label.color = theme.inkSoft
          kids.push(label)
        }
        surfaces += 1
        if (surfaces > LIVE_MAX_SURFACES) { throw new Error('a widget has at most ' + LIVE_MAX_SURFACES.toString() + ' pictures (ui.Surface or ui.Sparkline)') }
        if (node.series.length > 30 && node.bars) { throw new Error('a card sparkline with bars has at most 30 values') }
        let chart = make('surface', key + '.c', depth + 1, motionSlot)
        chart.ops = encodeGfxOps(sparkOps(node.series, node.series2, node.maximum, node.bars))
        chart.w = 100
        chart.h = 36
        chart.pic = surfaces - 1
        kids.push(chart)
        item.children = kids
      }
      if (node.kind !== 'stat' && node.kind !== 'numberstat' && node.kind !== 'sparkline' && !(item.parts === true)) {
        item.children = node.children.map((child: VeraUiNode, index: number): CardNode => project(child, depth + 1, key + '.' + index.toString(), item.slot))
      }
      // A touch on any part of the scene plays all its movements: the stick swings and the drum answers.
      if (node.kind === 'layers') { linkScene(item) }
      return item
    }
    // The theme wrapper consumes no layout level but is still validated and counted.
    let tree = project(root, root.kind === 'apptheme' ? 0 : 1, '0', -1)
    frame.nodes = root.kind === 'apptheme' ? tree.children : [tree]
    let coverProblem = coverError(frame.nodes)
    if (coverProblem.length > 0) { throw new Error(coverProblem) }
    let side = pictureRoom(frame)
    for (let picture of allPictures(frame.nodes, [])) { picture.size = Math.max(PICTURE_SIDE_MIN, Math.min(size.pictureMax, side)) }
    // Rejects taps from an older frame or state. A digest, not the state itself: the token is in the card's data, which has
    // a size budget, and in every key of its layout, so it must not grow with the app's data.
    frame.token = this.versionId + ':' + veraStateStamp(this.bytecode) + ':' + stateDigest(this.encodedState())
    frame.live = true
    // The budget is the size of what goes into the binding: the compact frame (CardModel.compactFrame), not every default field.
    if (JSON.stringify(compactFrame(frame)).length > LIVE_MAX_JSON) { throw new Error('widget binding exceeds size budget') }
    return frame
  }

  /** widget(state, size: number): the program draws differently for the card's size. */
  takesSize(): boolean { return this.hasSize }

  /** The sizes the widget is drawn at differently: every card size when it takes the size, else only 2x2 (the others draw the same, centred). */
  dimensions(): number[] { return this.hasSize ? CARD_DIMENSIONS.slice() : [2] }

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
    // A touch on a ui.Motion that has nothing of its own to run: no handler, only a new frame, in which the movement plays.
    if (action === TOUCH_ACTION) { return [] }
    let allowed = (nodes: CardNode[]): boolean => nodes.some((node: CardNode): boolean =>
      ((node.kind === 'button' || node.kind === 'path' || node.kind === 'iconbutton') && node.enabled && node.action.length > 0 && node.action === action && node.value === value) || allowed(node.children))
    if (!Number.isFinite(value) || !allowed(frame.nodes)) { throw new Error('Action is not available on this widget') }
    this.host.effectsAllowed = true
    this.host.pendingEffects = []
    try {
      let next = this.vm.execute(action, [this.state, new VeraNumberValue(value)])
      let requests = this.sourceRequests('Open app to continue: phone action required')
      this.state = next
      this.settleAfter(requests)
      return requests
    } finally {
      this.host.effectsAllowed = false
      this.host.pendingEffects = []
    }
  }

  /**
   * A tap on a toggle or a checkbox: the program's handler, told whether it is now on (as the app's switch tells it). Like a button, one
   * state change; the answer is the next frame.
   */
  tapSwitch(frame: LiveFrame, token: string, handler: string, on: boolean): SourceRequest[] {
    if (!frame.live || token !== frame.token) { throw new Error('Widget changed; tap again') }
    let found = (nodes: CardNode[]): boolean => nodes.some((node: CardNode): boolean =>
      ((node.kind === 'toggle' || node.kind === 'checkbox') && node.enabled && node.action.length > 0 && node.action === handler) || found(node.children))
    if (!found(frame.nodes)) { throw new Error('Action is not available on this widget') }
    this.host.effectsAllowed = true
    this.host.pendingEffects = []
    try {
      let next = this.vm.execute(handler, [this.state, new VeraBooleanValue(on)])
      let requests = this.sourceRequests('Open app to continue: phone action required')
      this.state = next
      this.settleAfter(requests)
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
      this.settleAfter(requests)
      return requests
    } finally {
      this.host.effectsAllowed = false
      this.host.pendingEffects = []
    }
  }

  /** settle, unless the tap is waiting for its live source: its answer, not the frames, finishes it. */
  private settleAfter(requests: SourceRequest[]): void {
    if (requests.length === 0) { this.settle() }
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
