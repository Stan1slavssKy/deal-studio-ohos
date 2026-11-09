/**
 * What the form extension sends and the card draws: plain data, nothing here imports the VM, so the launcher's card, the app's Widget tab and the
 * extension all load the same classes. VeraLiveWidget builds them and re-exports them.
 */

/**
 * What one card carries: the widget is refused beyond these (VeraLiveWidget), and the card keeps one canvas, one timer controller and one
 * Motion slot for each (CardView). The prompts say them from here too.
 */
export const CARD_MAX_MOTIONS: number = 5
/** Pictures: ui.Surface and ui.Sparkline, each drawn once for the frame, of at most CARD_MAX_SHAPES shapes. */
export const CARD_MAX_PICTURES: number = 5
export const CARD_MAX_SHAPES: number = 60
/** ui.Timer, the platform's own TextTimer. */
export const CARD_MAX_TIMERS: number = 3

/**
 * A card's size and what a widget may put on it. The system numbers them 2 (2x2, about 150 vp square), 3 (2x4: wide, about 324 x 148) and 4 (4x4, about
 * 324 x 340); measured on the phone at 3.5 px per vp. The inner size is the card less its 12 vp padding; pictureMax is the largest side a picture is drawn at.
 */
export class CardSize {
  dimension: number = 2
  label: string = '2x2'
  width: number = 126
  height: number = 126
  maxNodes: number = 40
  maxButtons: number = 2
  maxTexts: number = 8
  pictureMax: number = 80
}

/** The sizes a card can be, in the system's numbering. */
export const CARD_DIMENSIONS: number[] = [2, 3, 4]

/** The size `dimension` stands for; anything that is not one of CARD_DIMENSIONS is 2x2. */
export function cardSize(dimension: number): CardSize {
  let size = new CardSize()
  if (dimension === 3) {
    size.dimension = 3; size.label = '2x4'; size.width = 300; size.height = 124; size.maxNodes = 60; size.maxButtons = 4; size.maxTexts = 12; size.pictureMax = 100
  } else if (dimension === 4) {
    size.dimension = 4; size.label = '4x4'; size.width = 300; size.height = 316; size.maxNodes = 80; size.maxButtons = 6; size.maxTexts = 24; size.pictureMax = 200
  }
  return size
}

/** The longest countdown the platform's TextTimer takes (its `count`); a longer one would start from its default of a minute. */
export const TEXT_TIMER_MAX_MS: number = 86400000
const HOUR_MS: number = 3600000

/**
 * How a ui.Timer is set on the platform's TextTimer, the same in the app (VeraPreview) and on the card (CardView). A countdown starts from the
 * time left (`count`); a timer counting up starts from the time already gone (`startTime`: TextTimer ignores `count` when it counts up and would
 * start from zero) and has no end (`count` -1). Hours are shown once the time is an hour or more.
 */
export class TimerFace {
  countDown: boolean = false
  count: number = -1
  startTime: number = 0
  format: string = 'mm:ss'
}

/** The face of a timer that counts down to, or up from, `moment` (ms since 1970), as of `now`. */
export function timerFace(moment: number, countDown: boolean, now: number): TimerFace {
  let face = new TimerFace()
  let span = Math.max(0, countDown ? moment - now : now - moment)
  face.countDown = countDown
  if (countDown) { face.count = Math.min(span, TEXT_TIMER_MAX_MS) } else { face.startTime = span }
  face.format = span >= HOUR_MS ? 'HH:mm:ss' : 'mm:ss'
  return face
}

/** A plain binding DTO. All appearance is resolved outside the launcher. */
export class CardNode {
  key: string = ''
  kind: string = ''
  text: string = ''
  commands: string = ''
  /** ui.Motion on a card: the preset (CARD_MOTIONS) and the number whose change plays it. */
  style: string = ''
  trigger: number = 0
  /** ui.Surface: its shapes (encodeGfxOps), its own width and height, and the handler a tap on it runs. */
  ops: string = ''
  w: number = 0
  h: number = 0
  pointer: string = ''
  action: string = ''
  value: number = 0
  enabled: boolean = true
  color: string = '#172033'
  fill: string = '#FFFFFF'
  size: number = 14
  /** The Motion this node is, or sits under, among the widget's (0 up to CARD_MAX_MOTIONS - 1); -1 for none. A touch on it plays that Motion. */
  slot: number = -1
  /** Which picture (0 up to CARD_MAX_PICTURES - 1) or which timer (0 up to CARD_MAX_TIMERS - 1) this is among the widget's; -1 for any other node. */
  pic: number = -1
  /**
   * How the theme dresses the node, set only where it differs from the card's default (an unset field is not in the JSON, so a frame stays small):
   * a text's weight, family and letter spacing; a column's or row's alignment ('end', 'split', 'joined'), gap and padding; a panel's fill; a corner radius.
   */
  weight?: number
  family?: string
  spacing?: number
  align?: string
  gap?: number
  pad?: number
  panel?: string
  radius?: number
  /** A bar's or ring's value and what it is out of, a ring's centre text, and the ink of a label beside it (icons carry their path in `commands`). */
  val?: number
  max?: number
  sub?: string
  ink?: string
  /** The Motion slots a touch on this node plays: every Motion of the ui.Layers it is in (a touch moves the whole scene). */
  links?: number[]
  children: CardNode[] = []
}

export class LiveFrame {
  formId: string = ''
  projectId: string = ''
  title: string = 'Choose app'
  icon: string = '📱'
  versionId: string = ''
  token: string = ''
  /** Set by a tap's answer: another frame even when the state came out the same, so the card draws it again (a touch that changes nothing still plays). */
  seq: string = ''
  status: string = ''
  live: boolean = false
  background: string = '#F8FAFC'
  /** The card's size as the system numbers it (FormDimension): 2 is 2x2, 3 is 2x4 (wide), 4 is 4x4. The frame was fitted to it. */
  dimension: number = 2
  /** The theme the widget named, for a picture whose shapes are coloured by role (ink, accent...). */
  preset: string = 'clean'
  primary: string = ''
  nodes: CardNode[] = []
}


/**
 * The frame as it goes into the card's binding: every node keeps only what differs from a new CardNode (an unset field is the default), so a
 * node costs a few dozen characters instead of a few hundred and the 8000-character budget goes much further. The card gives the defaults
 * back with normalizeNodes. Plain objects: createFormBindingData and the card's LocalStorage carry them as they are.
 */
export function compactNode(node: CardNode): Object {
  let out: Record<string, Object> = {}
  out['key'] = node.key
  out['kind'] = node.kind
  if (node.text.length > 0) { out['text'] = node.text }
  if (node.commands.length > 0) { out['commands'] = node.commands }
  if (node.style.length > 0) { out['style'] = node.style }
  if (node.trigger !== 0) { out['trigger'] = node.trigger }
  if (node.ops.length > 0) { out['ops'] = node.ops }
  if (node.w !== 0) { out['w'] = node.w }
  if (node.h !== 0) { out['h'] = node.h }
  if (node.pointer.length > 0) { out['pointer'] = node.pointer }
  if (node.action.length > 0) { out['action'] = node.action }
  if (node.value !== 0) { out['value'] = node.value }
  if (!node.enabled) { out['enabled'] = false }
  if (node.color !== '#172033') { out['color'] = node.color }
  if (node.fill !== '#FFFFFF') { out['fill'] = node.fill }
  if (node.size !== 14) { out['size'] = node.size }
  if (node.slot !== -1) { out['slot'] = node.slot }
  if (node.pic !== -1) { out['pic'] = node.pic }
  if (node.weight !== undefined) { out['weight'] = node.weight }
  if (node.family !== undefined) { out['family'] = node.family }
  if (node.spacing !== undefined) { out['spacing'] = node.spacing }
  if (node.align !== undefined) { out['align'] = node.align }
  if (node.gap !== undefined) { out['gap'] = node.gap }
  if (node.pad !== undefined) { out['pad'] = node.pad }
  if (node.panel !== undefined) { out['panel'] = node.panel }
  if (node.radius !== undefined) { out['radius'] = node.radius }
  if (node.val !== undefined) { out['val'] = node.val }
  if (node.max !== undefined) { out['max'] = node.max }
  if (node.sub !== undefined) { out['sub'] = node.sub }
  if (node.ink !== undefined) { out['ink'] = node.ink }
  if (node.links !== undefined) { out['links'] = node.links }
  if (node.children.length > 0) { out['children'] = node.children.map((child: CardNode): Object => compactNode(child)) }
  return out
}

export function compactFrame(frame: LiveFrame): Object {
  let out: Record<string, Object> = {}
  out['formId'] = frame.formId
  out['projectId'] = frame.projectId
  out['title'] = frame.title
  out['icon'] = frame.icon
  out['versionId'] = frame.versionId
  out['token'] = frame.token
  out['seq'] = frame.seq
  out['status'] = frame.status
  out['live'] = frame.live
  out['background'] = frame.background
  out['dimension'] = frame.dimension
  out['preset'] = frame.preset
  out['primary'] = frame.primary
  out['nodes'] = frame.nodes.map((node: CardNode): Object => compactNode(node))
  return out
}

/** What compactNode left out, put back: each node a whole CardNode again, for a card that reads every field. */
export function normalizeNodes(nodes: CardNode[]): CardNode[] {
  let out: CardNode[] = []
  for (let raw of nodes) {
    let node = new CardNode()
    if (raw.key !== undefined) { node.key = raw.key }
    if (raw.kind !== undefined) { node.kind = raw.kind }
    if (raw.text !== undefined) { node.text = raw.text }
    if (raw.commands !== undefined) { node.commands = raw.commands }
    if (raw.style !== undefined) { node.style = raw.style }
    if (raw.trigger !== undefined) { node.trigger = raw.trigger }
    if (raw.ops !== undefined) { node.ops = raw.ops }
    if (raw.w !== undefined) { node.w = raw.w }
    if (raw.h !== undefined) { node.h = raw.h }
    if (raw.pointer !== undefined) { node.pointer = raw.pointer }
    if (raw.action !== undefined) { node.action = raw.action }
    if (raw.value !== undefined) { node.value = raw.value }
    if (raw.enabled !== undefined) { node.enabled = raw.enabled }
    if (raw.color !== undefined) { node.color = raw.color }
    if (raw.fill !== undefined) { node.fill = raw.fill }
    if (raw.size !== undefined) { node.size = raw.size }
    if (raw.slot !== undefined) { node.slot = raw.slot }
    if (raw.pic !== undefined) { node.pic = raw.pic }
    node.weight = raw.weight
    node.family = raw.family
    node.spacing = raw.spacing
    node.align = raw.align
    node.gap = raw.gap
    node.pad = raw.pad
    node.panel = raw.panel
    node.radius = raw.radius
    node.val = raw.val
    node.max = raw.max
    node.sub = raw.sub
    node.ink = raw.ink
    node.links = raw.links
    if (raw.children !== undefined) { node.children = normalizeNodes(raw.children) }
    out.push(node)
  }
  return out
}
