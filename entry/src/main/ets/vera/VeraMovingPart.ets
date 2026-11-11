/**
 * What moves in the app's own animation, and about which point: a pendulum's rod and bob swing about the top of the rod, a wheel's
 * slices turn about its centre, and the clock case and the pointer stay.
 *
 * Make widget asks the model for that part as a gfx.moving with its pivot, and the model often wraps the whole picture in a ui.Motion
 * (the case swings with the pendulum, the pointer spins with the wheel) or moves nothing. The app already knows the answer: its frame
 * handler animates the picture. So the app's frames are run from the saved state (as they are, else after a touch on the picture or a
 * press of one of its buttons), its draw function is decoded at a few of them, and the shapes compared: those whose points move are the
 * part, the rest stays, and the point the moving points turn about (a least-squares fit of the centre of their circles) is the pivot.
 * Only turning is found (a swing or a spin); a part that slides or rises is left alone.
 *
 * Pure: runs the program's own functions in a VM of its own, with phone effects dropped, and returns plain data.
 */

import { VirtualMachine, deserializeVbc2, decodeRuntimeValue, RuntimeValue, VeraNumberValue } from './VeraInterpreter'
import { decodeVeraUi, UiHostEnvironment, VeraUiNode } from './VeraUi'
import { decodeGfx, pointerValue, GfxOp, encodeGfxOps } from './VeraGfx'

/** Frames run after the start, and how often the picture is looked at: 3 s of the app's clock, a look every 100 ms. */
const PART_STEPS: number = 90
const PART_EVERY: number = 3
const PART_STEP_MS: number = 33
const PART_MAX_VM_STEPS: number = 100000
/** Buttons tried, after the touch, to set the picture going. */
const PART_MAX_BUTTONS: number = 3
/** The least turn, in degrees, that counts as the part moving. */
const PART_MIN_TURN: number = 8

/** The app's moving part, in the units of its picture. */
export class MovingPart {
  /** The app's draw function and its picture's units. */
  draw: string = ''
  width: number = 0
  height: number = 0
  pivotX: number = 0
  pivotY: number = 0
  /** 'swing' (turns back and forth) or 'spin' (goes round). */
  style: string = 'swing'
  /** How far it turned while it was watched, in degrees. */
  turn: number = 0
  /** Which of the shapes the draw function returns move, and which stay (their places in the list). */
  moving: number[] = []
  still: number[] = []
  /** The shapes, said for the model ("the gfx.line in #d4a64a and the gfx.circle in #e0b34a"). */
  movingText: string = ''
  stillText: string = ''
  /** The colours each set is drawn in, to recognise it in the widget's own drawing. */
  movingColours: string[] = []
  stillColours: string[] = []
  /** The moving part's colours that no shape that stays is drawn in (a pin in the rod's brass is not the rod): what tells its picture. */
  ownColours: string[] = []
  /**
   * The pivot as a point of one of the moving shapes that stays where it is (the end of a pendulum's rod at the top, a wheel's group's
   * origin), when there is one: its kind, its colours and which of its points (pointsOf), so the same point is found in the widget's own
   * drawing of the part, which may be laid out in other units. -1 when the pivot is only the fitted centre.
   */
  anchorKind: string = ''
  anchorColours: string[] = []
  anchorPoint: number = -1
  /** The app's picture as it was first looked at, encoded as a card carries it: a widget that draws with the app's own function shows the same. */
  firstOps: string = ''
}

/** A 2D transform [a, b, c, d, e, f] as a canvas keeps it. */
function times(m: number[], n: number[]): number[] {
  return [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]]
}

function place(m: number[], x: number, y: number, out: number[]): void {
  out.push(m[0] * x + m[2] * y + m[4])
  out.push(m[1] * x + m[3] * y + m[5])
}

const RAD: number = Math.PI / 180

/** The points that say where a shape is (exported for the widget's side: the same point of the same shape), in the picture's units: what moves when it moves (a centre, the ends of a line, a polygon's corners). */
export function pointsOf(o: GfxOp, m: number[], out: number[]): void {
  if (o.kind === 'group') {
    // Its origin first: what a group turns about.
    place(m, o.x, o.y, out)
    let a = o.start * RAD
    let s = o.r
    let inner = times(m, [Math.cos(a) * s, Math.sin(a) * s, -Math.sin(a) * s, Math.cos(a) * s, o.x, o.y])
    for (let c of o.children) { pointsOf(c, inner, out) }
    return
  }
  if (o.kind === 'fx' || o.kind === 'moving' || o.kind === 'drift' || o.kind === 'repeat') {
    for (let c of o.children) { pointsOf(c, m, out) }
    return
  }
  if (o.kind === 'rect' || o.kind === 'roundRect') {
    place(m, o.x, o.y, out)
    place(m, o.x + o.w, o.y + o.h, out)
  } else if (o.kind === 'circle' || o.kind === 'text') {
    place(m, o.x, o.y, out)
  } else if (o.kind === 'arc' || o.kind === 'sector') {
    // The centre, and the middle of the rim, so one that turns about its own centre moves too.
    let mid = (o.start + o.sweep / 2) * RAD
    place(m, o.x, o.y, out)
    place(m, o.x + o.r * Math.sin(mid), o.y - o.r * Math.cos(mid), out)
  } else if (o.kind === 'line') {
    place(m, o.x, o.y, out)
    place(m, o.w, o.h, out)
  } else if (o.kind === 'polygon' || o.kind === 'polyline') {
    for (let i = 0; i + 1 < o.points.length; i += 2) { place(m, o.points[i], o.points[i + 1], out) }
  }
}

export const IDENTITY: number[] = [1, 0, 0, 1, 0, 0]

/** One look at the picture: for each shape the draw function returned, its kind and its points. */
class Look {
  kinds: string[] = []
  points: number[][] = []
}

function look(ops: GfxOp[]): Look {
  let l = new Look()
  for (let o of ops) {
    let out: number[] = []
    pointsOf(o, IDENTITY, out)
    l.kinds.push(o.kind)
    l.points.push(out)
  }
  return l
}

/** What a shape is drawn in, as a colour the model wrote: a gradient by its first colour. */
function colourOf(o: GfxOp): string {
  if (o.color.startsWith('lin:') || o.color.startsWith('rad:')) {
    let parts = o.color.split(':')
    return parts.length > 2 ? parts[2].split('|')[0] : ''
  }
  return o.color
}

/** Every colour a shape and what it holds are drawn in. */
export function coloursOf(ops: GfxOp[], out: string[] = []): string[] {
  for (let o of ops) {
    let c = colourOf(o)
    if (c.length > 0 && out.indexOf(c) < 0) { out.push(c) }
    coloursOf(o.children, out)
  }
  return out
}

/** The shapes at these places, said in a few words: "2 gfx.polygon (#f87171, #fbbf24) and the gfx.circle in white". */
function said(ops: GfxOp[], at: number[]): string {
  let kinds: string[] = []
  let colours: string[][] = []
  for (let i of at) {
    let o = ops[i]
    let name = o.kind === 'fx' ? 'gfx.' + (o.fx === 'add' || o.fx === 'screen' || o.fx === 'multiply' ? 'blend' : o.fx) : 'gfx.' + o.kind
    let k = kinds.indexOf(name)
    if (k < 0) { kinds.push(name); colours.push([]); k = kinds.length - 1 }
    let c = o.children.length > 0 && o.color.length === 0 ? coloursOf(o.children).slice(0, 3).join(', ') : colourOf(o)
    colours[k].push(c)
  }
  let pieces: string[] = []
  for (let k = 0; k < kinds.length; k++) {
    let list = colours[k].filter((c: string, i: number): boolean => c.length > 0 && colours[k].indexOf(c) === i)
    let shown = list.slice(0, 4).join(', ') + (list.length > 4 ? ', ...' : '')
    pieces.push(colours[k].length === 1 ? 'the ' + kinds[k] + (shown.length > 0 ? ' in ' + shown : '') :
      colours[k].length.toString() + ' ' + kinds[k] + (shown.length > 0 ? ' (' + shown + ')' : ''))
  }
  if (pieces.length <= 1) { return pieces.join('') }
  return pieces.slice(0, pieces.length - 1).join(', ') + ' and ' + pieces[pieces.length - 1]
}

/** A trajectory: one point of one shape, at each look. */
class Track {
  shape: number = 0
  xs: number[] = []
  ys: number[] = []
}

class Centre {
  x: number = 0
  y: number = 0
  ok: boolean = false
}

/** The point the tracks turn about: |P_t|^2 - |P_0|^2 = 2 c . (P_t - P_0) for every track and look, solved for c by least squares. */
function fitCentre(tracks: Track[]): Centre {
  let sxx = 0
  let sxy = 0
  let syy = 0
  let bx = 0
  let by = 0
  for (let t of tracks) {
    for (let i = 1; i < t.xs.length; i++) {
      let dx = 2 * (t.xs[i] - t.xs[0])
      let dy = 2 * (t.ys[i] - t.ys[0])
      let rhs = t.xs[i] * t.xs[i] + t.ys[i] * t.ys[i] - t.xs[0] * t.xs[0] - t.ys[0] * t.ys[0]
      sxx += dx * dx; sxy += dx * dy; syy += dy * dy
      bx += dx * rhs; by += dy * rhs
    }
  }
  let c = new Centre()
  let det = sxx * syy - sxy * sxy
  if (!(Math.abs(det) > 1e-9 * Math.max(1, sxx * syy))) { return c }
  c.x = (bx * syy - by * sxy) / det
  c.y = (sxx * by - sxy * bx) / det
  c.ok = isFinite(c.x) && isFinite(c.y)
  return c
}

/** How far a track strays from a circle about c, and its radius. */
function strays(t: Track, c: Centre): number[] {
  let radii: number[] = []
  for (let i = 0; i < t.xs.length; i++) { radii.push(Math.hypot(t.xs[i] - c.x, t.ys[i] - c.y)) }
  let mean = radii.reduce((a: number, b: number): number => a + b, 0) / radii.length
  let worst = 0
  for (let r of radii) { worst = Math.max(worst, Math.abs(r - mean)) }
  return [worst, mean]
}

/** How far a track turns about c, in degrees: [the span of its angle, the sum of every step's turn]. */
function turned(t: Track, c: Centre): number[] {
  let angle = 0
  let least = 0
  let most = 0
  let travel = 0
  let last = Math.atan2(t.ys[0] - c.y, t.xs[0] - c.x)
  for (let i = 1; i < t.xs.length; i++) {
    let now = Math.atan2(t.ys[i] - c.y, t.xs[i] - c.x)
    let step = now - last
    while (step > Math.PI) { step -= 2 * Math.PI }
    while (step < -Math.PI) { step += 2 * Math.PI }
    angle += step
    travel += Math.abs(step)
    least = Math.min(least, angle)
    most = Math.max(most, angle)
    last = now
  }
  return [(most - least) / RAD, travel / RAD]
}

/**
 * The moving part in a series of looks at one picture of w x h units, or null: the shapes whose points move, all turning about one centre
 * inside (or near) the picture, while at least one shape stays.
 */
export function partFromLooks(looks: GfxOp[][], w: number, h: number): MovingPart | null {
  if (looks.length < 3) { return null }
  let first = look(looks[0])
  // Only looks with the same shapes as the first (the same kinds, each with as many points) are compared.
  let same: Look[] = [first]
  for (let i = 1; i < looks.length; i++) {
    let l = look(looks[i])
    if (l.kinds.join(',') !== first.kinds.join(',')) { continue }
    if (l.points.some((p: number[], k: number): boolean => p.length !== first.points[k].length)) { continue }
    same.push(l)
  }
  if (same.length < 3) { return null }
  let size = Math.max(w, h)
  let eps = 0.002 * size
  let tracks: Track[] = []
  let moved: boolean[] = first.kinds.map((): boolean => false)
  // Points of shapes that do not move: [shape, point], a pivot's candidates once their shape is known to move.
  let fixed: number[][] = []
  for (let k = 0; k < first.points.length; k++) {
    for (let p = 0; p + 1 < first.points[k].length; p += 2) {
      let t = new Track()
      t.shape = k
      let far = 0
      for (let l of same) {
        t.xs.push(l.points[k][p]); t.ys.push(l.points[k][p + 1])
        far = Math.max(far, Math.hypot(l.points[k][p] - first.points[k][p], l.points[k][p + 1] - first.points[k][p + 1]))
      }
      if (far > eps) { tracks.push(t); moved[k] = true } else { fixed.push([k, p / 2]) }
    }
  }
  if (tracks.length === 0) { return null }
  // Two things may turn about different points (a clock's second hand and its pendulum): each track's own circle is a candidate centre, the
  // one most tracks lie on wins, and the centre is fitted again on those (a twinkle, a bar that grows, the other part are left out).
  // On the circle about c, and, when the track's own circle can be told, turning about a point near c: a second hand that moved a little lies
  // near enough a circle about the pendulum's pivot too, but its own centre is the dial's.
  let own: Centre[] = tracks.map((t: Track): Centre => fitCentre([t]))
  let onCircle = (t: Track, c: Centre): boolean => {
    let s = strays(t, c)
    if (!(s[1] > eps && s[0] <= 0.01 * size + 0.04 * s[1])) { return false }
    let mine = own[tracks.indexOf(t)]
    return !mine.ok || Math.hypot(mine.x - c.x, mine.y - c.y) <= 0.05 * size
  }
  let kept: Track[] = []
  let reach = -1
  for (let i = 0; i < tracks.length; i++) {
    let candidate = own[i]
    if (!candidate.ok) { continue }
    let inliers = tracks.filter((u: Track): boolean => onCircle(u, candidate))
    let far = 0
    for (let u of inliers) { far += strays(u, candidate)[1] }
    if (inliers.length > kept.length || (inliers.length === kept.length && far > reach)) { kept = inliers; reach = far }
  }
  if (kept.length === 0) { return null }
  let centre = new Centre()
  for (let round = 0; round < 3; round++) {
    centre = fitCentre(kept)
    if (!centre.ok) { return null }
    let c = centre
    let fits = tracks.filter((t: Track): boolean => onCircle(t, c))
    if (fits.length === 0) { return null }
    let same = fits.length === kept.length && fits.every((t: Track): boolean => kept.indexOf(t) >= 0)
    kept = fits
    if (same) { break }
  }
  // A pivot far outside the picture is a slide or a rise seen as a turn about a point at a distance: not a turn.
  if (centre.x < -0.25 * w || centre.x > 1.25 * w || centre.y < -0.25 * h || centre.y > 1.25 * h) { return null }
  // A part turns whole: its points keep their distances (a pendulum, a wheel). Seaweed that bends, a ring that grows, sparks that fly apart
  // turn about nothing and are no part.
  for (let i = 1; i < kept.length; i++) {
    for (let pair of [[i - 1, i], [0, i]]) {
      let a = kept[pair[0]]
      let b = kept[pair[1]]
      let first = Math.hypot(a.xs[0] - b.xs[0], a.ys[0] - b.ys[0])
      for (let k = 1; k < a.xs.length; k++) {
        if (Math.abs(Math.hypot(a.xs[k] - b.xs[k], a.ys[k] - b.ys[k]) - first) > 0.01 * size + 0.03 * first) { return null }
      }
    }
  }
  // How far it turned: the most any of its points turned about the centre.
  let widestRadius = 0
  let turn = [0, 0]
  for (let t of kept) {
    widestRadius = Math.max(widestRadius, strays(t, centre)[1])
    let mine = turned(t, centre)
    if (mine[0] > turn[0]) { turn = mine }
  }
  if (widestRadius > 1.5 * size) { return null }
  if (turn[0] < PART_MIN_TURN) { return null }
  // A shape is in the part when every one of its points that moves turns about the centre.
  let part = new MovingPart()
  part.width = w
  part.height = h
  part.pivotX = Math.round(centre.x * 10) / 10
  part.pivotY = Math.round(centre.y * 10) / 10
  part.turn = Math.round(turn[0])
  part.style = turn[0] >= 200 || turn[1] >= 300 ? 'spin' : 'swing'
  for (let k = 0; k < first.kinds.length; k++) {
    if (!moved[k]) { part.still.push(k); continue }
    let mine = tracks.filter((t: Track): boolean => t.shape === k)
    if (mine.length > 0 && mine.every((t: Track): boolean => kept.indexOf(t) >= 0)) { part.moving.push(k) }
  }
  if (part.moving.length === 0 || part.still.length === 0) { return null }
  let ops = looks[0]
  // A point of a moving shape that stays, near the fitted centre, is the pivot exactly: the top of the rod, not where a shine on the bob
  // (which moves with the bob without turning) pulls the fit.
  let nearest = 0.05 * size
  for (let candidate of fixed) {
    let k = candidate[0]
    if (part.moving.indexOf(k) < 0) { continue }
    let x = first.points[k][candidate[1] * 2]
    let y = first.points[k][candidate[1] * 2 + 1]
    let d = Math.hypot(x - centre.x, y - centre.y)
    if (d < nearest || (d === 0 && part.anchorPoint < 0)) {
      nearest = d
      part.pivotX = Math.round(x * 10) / 10
      part.pivotY = Math.round(y * 10) / 10
      part.anchorKind = ops[k].kind
      part.anchorColours = coloursOf([ops[k]])
      part.anchorPoint = candidate[1]
    }
  }
  part.firstOps = encodeGfxOps(ops)
  part.movingText = said(ops, part.moving)
  part.stillText = said(ops, part.still)
  part.movingColours = coloursOf(part.moving.map((i: number): GfxOp => ops[i]))
  let stillAll = coloursOf(part.still.map((i: number): GfxOp => ops[i]))
  part.stillColours = stillAll.filter((c: string): boolean => part.movingColours.indexOf(c) < 0)
  part.ownColours = part.movingColours.filter((c: string): boolean => stillAll.indexOf(c) < 0)
  return part
}

/** The app's pictures that its clock animates: ui.Surface with a draw and a frame function. */
function animated(nodes: VeraUiNode[], out: VeraUiNode[]): VeraUiNode[] {
  for (let node of nodes) {
    if (node.kind === 'surface' && node.label.length > 0 && node.action.length > 0 && node.minimum > 0 && node.maximum > 0) { out.push(node) }
    animated(node.children, out)
  }
  return out
}

function buttons(nodes: VeraUiNode[], out: VeraUiNode[]): VeraUiNode[] {
  for (let node of nodes) {
    if ((node.kind === 'button' || node.kind === 'iconbutton') && node.enabled && node.action.length > 0) { out.push(node) }
    buttons(node.children, out)
  }
  return out
}

/**
 * The part of the app's animated picture that turns, from `saved` (the encoded state; '' for init's), or null. The app's frames are run
 * as they are first; when nothing turns, again after a touch in the middle of the picture, then after a press of each of its first
 * buttons -- what sets a wheel spinning. Never throws: a program that traps or asks for too much simply has no part found.
 */
export function appMovingPart(vbc2: string, saved: string): MovingPart | null {
  let host = new UiHostEnvironment()
  host.effectsAllowed = true
  try {
    let vm = new VirtualMachine(deserializeVbc2(vbc2), host, PART_MAX_VM_STEPS)
    let start: RuntimeValue = saved.length > 0 ? decodeRuntimeValue(JSON.parse(saved) as Object) : vm.execute('init')
    let tree = decodeVeraUi(vm.execute('view', [start]))
    let pictures = animated(tree, [])
    if (pictures.length === 0) { return null }
    let presses = buttons(tree, []).slice(0, PART_MAX_BUTTONS)
    for (let picture of pictures) {
      // How the picture is set going: as it is, by a touch on it, by a button.
      for (let way = 0; way < 2 + presses.length; way++) {
        let state = start
        try {
          host.pendingEffects = []
          if (way === 1) {
            if (picture.value.length === 0) { continue }
            let x = picture.minimum / 2
            let y = picture.maximum / 2
            state = vm.execute(picture.value, [vm.execute(picture.value, [state, pointerValue('down', 0, x, y)]), pointerValue('up', 0, x, y)])
          } else if (way > 1) {
            let press = presses[way - 2]
            state = vm.execute(press.action, [state, new VeraNumberValue(press.eventValue)])
          }
          let looks: GfxOp[][] = [decodeGfx(vm.execute(picture.label, [state]))]
          for (let step = 1; step <= PART_STEPS; step++) {
            host.pendingEffects = []
            state = vm.execute(picture.action, [state, new VeraNumberValue(PART_STEP_MS)])
            if (step % PART_EVERY === 0) { looks.push(decodeGfx(vm.execute(picture.label, [state]))) }
          }
          let part = partFromLooks(looks, picture.minimum, picture.maximum)
          if (part !== null) {
            part.draw = picture.label
            return part
          }
        } catch (e) {
          // This way of setting it going traps: try the next.
        }
      }
    }
  } catch (e) {
    return null
  } finally {
    host.effectsAllowed = false
    host.pendingEffects = []
  }
  return null
}
