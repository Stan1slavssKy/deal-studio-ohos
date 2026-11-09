/**
 * What the form extension sends and the card draws: plain data, nothing here imports the VM, so the launcher's card, the app's Widget tab and the
 * extension all load the same classes. VeraLiveWidget builds them and re-exports them.
 */

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
  /** The Motion this node is, or sits under, among the widget's (0, 1, 2); -1 for none. A touch on it plays that Motion. */
  slot: number = -1
  /** Which picture (ui.Surface) this is among the widget's (0, 1, 2); -1 for a node that is not one. */
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
  /** The theme the widget named, for a picture whose shapes are coloured by role (ink, accent...). */
  preset: string = 'clean'
  primary: string = ''
  nodes: CardNode[] = []
}

