/**
 * What the form extension sends and the card draws: plain data, nothing here imports the VM, so the launcher's card, the app's Widget tab and the
 * extension all load the same classes. VeraLiveWidget builds them and re-exports them.
 */

/**
 * What one card carries: the widget is refused beyond these (VeraLiveWidget), and the card keeps one canvas, one timer controller and one
 * Motion slot for each (CardView). The prompts say them from here too.
 */
export const CARD_MAX_MOTIONS: number = 5
/** Slices of the drifts on a card (gfx.drift): each slice is a canvas of its own, the strip twice over of up to eight, two drifts. */
export const CARD_MAX_DRIFT_SLICES: number = 32
/** Pictures: ui.Surface and ui.Sparkline, each drawn once for the frame, of at most CARD_MAX_SHAPES shapes. */
export const CARD_MAX_PICTURES: number = 5
export const CARD_MAX_SHAPES: number = 60
/** ui.Timer, the platform's own TextTimer. */
export const CARD_MAX_TIMERS: number = 3
/** What the card posts for a touch on a moving picture that has no handler: the host answers with a new frame and runs nothing. */
export const TOUCH_ACTION: string = '#touch'

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

/** The padding a card keeps round what is on it, in vp: a cover picture (splitCover) runs under it to the card's edges. */
export const CARD_PADDING: number = 12

/**
 * Over a cover picture the card keeps a strip this tall along its bottom, in place of its bottom padding, that opens the app: the picture
 * takes every other touch that lands on no button, so without it a widget with a pointer handler on its cover has no way into the app.
 */
export const OPEN_STRIP: number = 18
/** The small bar drawn in the middle of that strip, in a grey that shows on a light veil and a dark sky alike. */
export const OPEN_STRIP_MARK: string = '#8C808080'

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
  // A countdown already over still gets a count of 1 ms: TextTimer takes 0 or less for its default of a minute.
  if (countDown) { face.count = Math.max(1, Math.min(span, TEXT_TIMER_MAX_MS)) } else { face.startTime = span }
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
  /** A Motion made for a moving part of a picture (gfx.moving): where it turns and scales, as shares of its box (0..1) from the left and the top. */
  px?: number
  py?: number
  /** A ui.Layers made from one picture split at its moving parts, not written by the program (VeraLiveWidget). */
  parts?: boolean
  /** A drift layer of a cover picture: its slices fill the card as the picture does. */
  cover?: boolean
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
  /** Over a cover picture: the share of the card's height, from its bottom, that the rest takes, under which the veil lies (coverScrim); 0 for none. */
  veil: number = 0
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
  if (node.px !== undefined) { out['px'] = node.px }
  if (node.py !== undefined) { out['py'] = node.py }
  if (node.parts !== undefined) { out['parts'] = node.parts }
  if (node.cover !== undefined) { out['cover'] = node.cover }
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
  out['veil'] = frame.veil
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
    node.px = raw.px
    node.py = raw.py
    node.parts = raw.parts
    node.cover = raw.cover
    if (raw.children !== undefined) { node.children = normalizeNodes(raw.children) }
    out.push(node)
  }
  return out
}

/** A frame's nodes with its cover picture taken out: the picture is drawn as the card's background, the rest over it. */
export class CoverSplit {
  /** The ui.Surface of style "cover" (inside its ui.Motion when one holds only it), or null for a widget without one. */
  cover: CardNode | null = null
  rest: CardNode[] = []
}

/**
 * A picture's style as words: 'cover' (the card's background), 'clear' (no background of its own, over another), or both for a layer of
 * a cover picture split at its moving parts.
 */
export function pictureCovers(style: string): boolean { return style.split(' ').indexOf('cover') >= 0 }
export function pictureBare(style: string): boolean { return style.split(' ').indexOf('clear') >= 0 }

function isCover(node: CardNode): boolean {
  return (node.kind === 'surface' && pictureCovers(node.style)) || (node.kind === 'layers' && node.parts === true && pictureCovers(node.style))
}

/** A Motion around only the cover picture goes with it, so a touch on the background still plays the movement. */
function coverHolder(node: CardNode): boolean {
  return isCover(node) || (node.kind === 'motion' && node.children.length === 1 && isCover(node.children[0]))
}

/**
 * The first cover picture of a frame, out of the tree: a column left with nothing in it goes too. Copies the nodes it changes,
 * so the frame itself is left as it was. The frame builder (VeraLiveWidget) refuses a cover inside a row or a ui.Layers.
 */
export function splitCover(nodes: CardNode[]): CoverSplit {
  let split = new CoverSplit()
  let take = (list: CardNode[]): CardNode[] => {
    let out: CardNode[] = []
    for (let node of list) {
      if (split.cover === null && coverHolder(node)) { split.cover = node; continue }
      if (split.cover === null && node.kind === 'column' && node.children.length > 0) {
        let children = take(node.children)
        if (children.length === node.children.length) { out.push(node); continue }
        if (children.length === 0) { continue }
        let copy = normalizeNodes([node])[0]
        copy.children = children
        out.push(copy)
        continue
      }
      out.push(node)
    }
    return out
  }
  split.rest = take(nodes)
  return split
}

/**
 * The veil under what lies over a cover picture: the card's colour under the text, so it reads over a busy picture, and clear above
 * it. `veil` is the share of the card's height, from the bottom, the text takes (LiveFrame.veil); 0 is no veil. Only that and a soft
 * edge above it: a veil over the bottom half whitened the ground a scene stands on, and the rocket on its pad with it (found on the
 * phone). `background` is the card's #rrggbb.
 */
export function coverScrim(background: string, veil: number): Array<[ResourceColor, number]> {
  let rgb = background.length === 7 && background.charAt(0) === '#' ? background.substring(1) : 'FFFFFF'
  if (!(veil > 0)) { return [['#00' + rgb, 0], ['#00' + rgb, 1]] }
  let under = Math.max(0.1, 1 - Math.min(1, veil))
  let edge = Math.max(0, under - VEIL_EDGE)
  // Fading in over a fifth of the card and still thin where the text begins: a short ramp read as a grey band with a hard top edge.
  return [['#00' + rgb, 0], ['#00' + rgb, edge], ['#99' + rgb, under], ['#CC' + rgb, (under + 1) / 2], ['#D9' + rgb, 1]]
}

/** How far above the text the veil fades in, as a share of the card's height. */
const VEIL_EDGE: number = 0.22
