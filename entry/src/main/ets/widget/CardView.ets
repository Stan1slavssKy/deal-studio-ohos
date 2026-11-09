/**
 * The layout of a home-screen card: the nodes of a frame (VeraLiveWidget) drawn the one way, by both the launcher's card (pages/LiveCard.ets) and
 * the app's Widget tab (components/WidgetPreview.ets), so the preview cannot drift from what the card shows. It loads only the theme and
 * the painter, never the VM. What happens on a touch is the host's: this reports it through onTap and onPoint.
 */

import { CardNode } from './CardModel'
import { paintGfx, decodeGfxOps, gfxFit, gfxToSurface } from '../vera/GfxPaint'
import { resolveTheme } from '../vera/VeraTheme'
import { motionStages, motionPivot } from '../vera/VeraMotion'

/** A picture on a card is as wide as its node says (the frame sizes it to the room left, VeraLiveWidget.pictureRoom); this when it says nothing (vp). */
const PICTURE_WIDTH: number = 80
/** Pictures and Motions a card carries, each with a place of its own below. */
const SLOTS: number = 5

@Component
export struct CardView {
  /** The frame's nodes, and what makes them new: the nodes are made again whenever frameKey changes (a tap's answer, a new state). */
  @Prop nodes: CardNode[] = []
  @Prop frameKey: string = ''
  /** The widget's theme: a picture's colours by role follow it. */
  @Prop preset: string = 'clean'
  @Prop primary: string = ''
  /** A button, or a shape with an action, was tapped: the handler's name and its number. */
  onTap: (action: string, value: number) => void = (action: string, value: number): void => {}
  /** A toggle or a checkbox was tapped: its handler's name and whether it is now on. */
  onSwitch: (handler: string, on: boolean) => void = (handler: string, on: boolean): void => {}
  /** A picture was tapped: its pointer handler's name and where, in the picture's own units. */
  onPoint: (handler: string, x: number, y: number) => void = (handler: string, x: number, y: number): void => {}

  /**
   * ui.Surface: a still picture. The app's own painter (paintGfx) draws, on a Canvas, the shapes the frame carries; each picture has
   * its own context, by its number in the frame.
   */
  private timer0: TextTimerController = new TextTimerController()
  private timer1: TextTimerController = new TextTimerController()
  private timer2: TextTimerController = new TextTimerController()
  private timerOf(node: CardNode): TextTimerController { return node.pic === 1 ? this.timer1 : node.pic === 2 ? this.timer2 : this.timer0 }
  /** Where a timer starts, in ms: the time since its moment (counting up) or the time left until it (counting down), as of when the card draws it. */
  private timerCount(node: CardNode): number {
    let moment = node.val !== undefined ? node.val : 0
    return Math.max(0, node.max === 1 ? moment - Date.now() : Date.now() - moment)
  }
  private ctx0: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private ctx1: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private ctx2: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private contextOf(node: CardNode): CanvasRenderingContext2D {
    return node.pic === 1 ? this.ctx1 : node.pic === 2 ? this.ctx2 : this.ctx0
  }
  private pictureW(node: CardNode): number { return node.size > 0 ? node.size : PICTURE_WIDTH }
  private pictureH(node: CardNode): number { return Math.min(this.pictureW(node) * 1.1, this.pictureW(node) * node.h / node.w) }
  private paintPicture(node: CardNode): void {
    let start = Date.now()
    paintGfx(this.contextOf(node), decodeGfxOps(node.ops), resolveTheme(this.preset, this.primary, false),
      this.pictureW(node), this.pictureH(node), node.w, node.h, vp2px(1))
    console.info('VERA-CARD picture painted ms=' + (Date.now() - start).toString() + ' at=' + Date.now().toString())
  }
  private pictureAt(node: CardNode, event: ClickEvent): number[] {
    return gfxToSurface(gfxFit(this.pictureW(node), this.pictureH(node), node.w, node.h), event.x, event.y)
  }

  /**
   * ui.Motion: the trigger each Motion last settled on (by its slot). The node is made again for every frame (its key carries frameKey), so
   * there is nothing on it to animate from: a frame that carries another trigger starts it in the hit pose and it settles in
   * onAppear. The first frame only records its trigger, so a card never plays when it opens. A card plays for about two
   * seconds after a redraw, which is all a hit needs; there is no repeat or loop.
   */
  @State settled: number[] = [-1e18, -1e18, -1e18, -1e18, -1e18]
  /** How far each Motion's chain of stages has got: 0 is its starting pose, k the pose after stage k. */
  @State phase: number[] = [0, 0, 0, 0, 0]
  private settledOf(node: CardNode): number { return node.slot >= 0 && node.slot < SLOTS ? this.settled[node.slot] : -1e18 }
  private settle(node: CardNode): void {
    if (node.slot < 0 || node.slot >= SLOTS) { return }
    let next = this.settled.slice()
    next[node.slot] = this.effective(node)
    this.settled = next
  }
  private setPhase(slot: number, value: number): void {
    if (slot < 0 || slot >= SLOTS) { return }
    let next = this.phase.slice()
    next[slot] = value
    this.phase = next
  }

  /**
   * Touches on the pictures and shapes under each Motion, counted here and added to its trigger: a touch makes the picture react
   * whether or not the program's handler changed anything (a plain field, not state: it must not redraw before the answer comes).
   */
  private touches: number[] = [0, 0, 0, 0, 0]
  private touched(node: CardNode): void {
    if (node.slot >= 0 && node.slot < SLOTS) {
      this.touches[node.slot] = this.touches[node.slot] + 1
      // A touch while the last movement is still playing starts the next one from its first pose.
      this.setPhase(node.slot, 0)
    }
  }
  private effective(node: CardNode): number { return node.trigger + (node.slot >= 0 && node.slot < SLOTS ? this.touches[node.slot] : 0) }
  private playing(node: CardNode): boolean { return this.settledOf(node) > -1e17 && this.effective(node) !== this.settledOf(node) }

  /** The stages of the node's preset (MOTION_STAGES in VeraMotion): row 0 is where it starts, each later row a stage. */
  private stagesOf(node: CardNode): number[][] { return motionStages(node.style) }
  /**
   * One number of the pose the Motion is in: its starting pose when a movement is about to play, the pose of the stage it has
   * reached while it plays, its resting pose (the last row) otherwise. 1 dx, 2 dy, 3 scale x, 4 scale y, 5 rotation, 6 opacity.
   */
  private poseOf(node: CardNode, index: number): number {
    let stages = this.stagesOf(node)
    if (stages.length === 0) { return index >= 3 && index !== 5 ? 1 : 0 }
    let at = this.playing(node) ? Math.min(this.phase[node.slot], stages.length - 1) : stages.length - 1
    return stages[at][index]
  }
  private pivotOf(node: CardNode): string { return Math.round(100 * motionPivot(node.style)).toString() + '%' }
  /** The platform animation to the stage the Motion is at: its time and curve, and what to do when it ends (go on to the next stage). */
  private motionAnimation(node: CardNode): AnimateParam {
    let stages = this.stagesOf(node)
    let at = node.slot >= 0 && node.slot < SLOTS ? this.phase[node.slot] : 0
    let seen = at
    let slot = node.slot
    let curve = at >= 1 && at < stages.length ? stages[at][7] : 1
    return {
      duration: at >= 1 && at < stages.length ? stages[at][0] : 0,
      curve: curve === 0 ? Curve.Linear : curve === 2 ? Curve.EaseIn : curve === 3 ? Curve.EaseInOut : Curve.EaseOut,
      onFinish: () => { this.advance(node, slot, seen) }
    }
  }
  /** The card shows a movement when the frame is new: the first frame only records its trigger, a later one starts the chain. */
  private begin(node: CardNode): void {
    if (this.settledOf(node) < -1e17) { this.settle(node); return }
    if (this.playing(node)) { this.setPhase(node.slot, 1) }
  }
  /** A stage ended: start the next, or, after the last, record the trigger so a redraw does not play it again. */
  private advance(node: CardNode, slot: number, seen: number): void {
    if (slot < 0 || slot >= SLOTS || this.phase[slot] !== seen || seen < 1) { return }
    if (seen + 1 < this.stagesOf(node).length) {
      this.setPhase(slot, seen + 1)
    } else {
      this.settle(node)
      this.setPhase(slot, 0)
    }
  }

  /** How the theme dressed a node (CardStyle, set by the extension): an unset field is the card's default. */
  private weightOf(node: CardNode): number { return node.weight !== undefined ? node.weight : 400 }
  private familyOf(node: CardNode): string { return node.family !== undefined ? node.family : '' }
  private spacingOf(node: CardNode): number { return node.spacing !== undefined ? node.spacing : 0 }
  private gapOf(node: CardNode, fallback: number): number { return node.gap !== undefined ? node.gap : fallback }
  private padOf(node: CardNode): number { return node.pad !== undefined ? node.pad : 0 }
  private panelOf(node: CardNode): string { return node.panel !== undefined ? node.panel : '#00000000' }
  private radiusOf(node: CardNode, fallback: number): number { return node.radius !== undefined ? node.radius : fallback }
  private colAlign(node: CardNode): HorizontalAlign { return node.align === 'end' ? HorizontalAlign.End : HorizontalAlign.Center }
  private valueNow(node: CardNode): number { return node.val !== undefined ? node.val : 0 }
  private maxOf(node: CardNode): number { return node.max !== undefined && node.max > 0 ? node.max : 100 }
  private inkOf(node: CardNode): string { return node.ink !== undefined ? node.ink : '#333333' }
  private percent(node: CardNode): string { return Math.round(100 * this.valueNow(node) / this.maxOf(node)).toString() + '%' }
  private rowJustify(node: CardNode): FlexAlign {
    return node.align === 'split' ? FlexAlign.SpaceBetween : node.align === 'end' ? FlexAlign.End :
      node.align === 'joined' ? FlexAlign.Center : FlexAlign.SpaceEvenly
  }

  build() {
    Column({ space: 6 }) {
      ForEach(this.nodes, (node: CardNode) => { this.level1(node, false) }, (node: CardNode) => node.key + this.frameKey)
    }.width('100%')
  }

  @Builder
  leaf(node: CardNode) {
    if (node.kind === 'button') {
      Button(node.text).type(ButtonType.Normal).borderRadius(this.radiusOf(node, 10)).height(40)
        .backgroundColor(node.fill).fontColor(node.color).fontSize(14)
        .enabled(node.enabled).onClick(() => {
          this.onTap(node.action, node.value)
        })
    } else if (node.kind === 'path') {
      // A shape is drawn in a 100-unit box; the viewPort has to say 'px' or the path comes out a quarter of its size
      // (VeraIcons.ets), and a Path left with the default stroke is outlined in thick black. One with an action is a
      // button: the same message a button posts.
      Shape() {
        Path({ commands: node.commands }).fill(node.color).stroke(Color.Transparent)
      }
      .viewPort({ x: '0px', y: '0px', width: '100px', height: '100px' })
      .width(node.size).height(node.size)
      .onClick(() => {
        if (node.action.length > 0 && node.enabled) {
          this.touched(node)
          this.onTap(node.action, node.value)
        }
      })
    } else if (node.kind === 'surface') {
      // A picture without a pointer handler lets a tap fall through to the card, which opens the app.
      if (node.pointer.length > 0) {
        Canvas(this.contextOf(node)).width(this.pictureW(node)).height(this.pictureH(node))
          .onReady(() => { this.paintPicture(node) })
          .onClick((event: ClickEvent) => {
            let at = this.pictureAt(node, event)
            this.touched(node)
            this.onPoint(node.pointer, at[0], at[1])
          })
      } else {
        Canvas(this.contextOf(node)).width(this.pictureW(node)).height(this.pictureH(node))
          .onReady(() => { this.paintPicture(node) })
      }
    } else if (node.kind === 'timer') {
      // The platform's own timer: it ticks by itself (a card is not frozen for it, unlike for our animations), from where the frame says.
      if (this.familyOf(node).length > 0) {
        TextTimer({ isCountDown: node.max === 1, count: this.timerCount(node), controller: this.timerOf(node) })
          .format(this.timerCount(node) >= 3000000 ? 'HH:mm:ss' : 'mm:ss')
          .fontSize(node.size).fontColor(node.color).fontWeight(this.weightOf(node)).fontFamily(this.familyOf(node))
          .onAppear(() => { this.timerOf(node).start() })
      } else {
        TextTimer({ isCountDown: node.max === 1, count: this.timerCount(node), controller: this.timerOf(node) })
          .format(this.timerCount(node) >= 3000000 ? 'HH:mm:ss' : 'mm:ss')
          .fontSize(node.size).fontColor(node.color).fontWeight(this.weightOf(node))
          .onAppear(() => { this.timerOf(node).start() })
      }
    } else if (node.kind === 'checkbox') {
      Row({ space: 8 }) {
        Column() {
          if (this.valueNow(node) === 1) { this.glyph(node.commands, 14, '#FFFFFF') }
        }
        .width(20).height(20).alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center).borderRadius(6)
        .backgroundColor(this.valueNow(node) === 1 ? node.color : '#00000000')
        .border({ width: 2, color: this.valueNow(node) === 1 ? node.color : node.fill })
        Text(node.text).fontSize(14).fontColor(this.inkOf(node)).maxLines(1).layoutWeight(1)
      }
      .width('100%').opacity(node.enabled ? 1 : 0.4)
      .onClick(() => { if (node.enabled) { this.onSwitch(node.action, this.valueNow(node) !== 1) } })
    } else if (node.kind === 'toggle') {
      Row({ space: 8 }) {
        Stack({ alignContent: this.valueNow(node) === 1 ? Alignment.End : Alignment.Start }) {
          Column().width(36).height(20).borderRadius(10).backgroundColor(this.valueNow(node) === 1 ? node.color : node.fill)
          Circle().width(14).height(14).fill('#FFFFFF').margin(3)
        }.width(36).height(20)
        Text(node.text).fontSize(14).fontColor(this.inkOf(node)).maxLines(1).layoutWeight(1)
      }
      .width('100%').opacity(node.enabled ? 1 : 0.4)
      .onClick(() => { if (node.enabled) { this.onSwitch(node.action, this.valueNow(node) !== 1) } })
    } else if (node.kind === 'icon') {
      this.glyph(node.commands, node.size, node.color)
    } else if (node.kind === 'iconbutton') {
      Column() {
        this.glyph(node.commands, Math.round(node.size * 0.5), node.color)
      }
      .width(node.size).height(node.size)
      .alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
      .backgroundColor(node.fill).borderRadius(node.size / 2)
      .opacity(node.enabled ? 1 : 0.4)
      .onClick(() => {
        if (node.enabled && node.action.length > 0) { this.onTap(node.action, node.value) }
      })
    } else if (node.kind === 'badge') {
      Row({ space: 4 }) {
        if (node.commands.length > 0) {
          this.glyph(node.commands, 12, node.color)
        }
        Text(node.text).fontSize(12).fontWeight(500).fontColor(node.color).maxLines(1)
      }
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(node.fill).borderRadius(this.radiusOf(node, 8))
    } else if (node.kind === 'progress') {
      // The platform's own bar, with the label on the left and how far along on the right, as the app draws it.
      Column({ space: 4 }) {
        Row() {
          Text(node.text).fontSize(12).fontColor(this.inkOf(node)).maxLines(1).layoutWeight(1)
          Text(this.percent(node)).fontSize(12).fontColor(node.color)
        }.width('100%')
        Progress({ value: this.valueNow(node), total: this.maxOf(node), type: ProgressType.Linear })
          .width('100%').style({ strokeWidth: 8, strokeRadius: 4 }).color(node.color).backgroundColor(node.fill)
      }.width('100%')
    } else if (node.kind === 'ring') {
      Column({ space: 2 }) {
        Stack({ alignContent: Alignment.Center }) {
          Progress({ value: this.valueNow(node), total: this.maxOf(node), type: ProgressType.Ring })
            .width(node.size).height(node.size).style({ strokeWidth: 7 }).color(node.color).backgroundColor(node.fill)
          Text(node.sub !== undefined ? node.sub : '').fontSize(12).fontWeight(700).fontColor(this.inkOf(node))
            .maxLines(1).textAlign(TextAlign.Center).width(node.size - 14)
        }
        if (node.text.length > 0) {
          Text(node.text).fontSize(12).fontColor(this.inkOf(node)).maxLines(1)
        }
      }
    } else if (node.kind === 'divider') {
      Divider().color(node.color)
    } else if (node.kind === 'spacer') {
      Blank().height(4)
    } else if (node.kind === 'numbertext') {
      // A figure is never broken over two lines: beside another, it shrinks to fit its half of the card.
      if (this.familyOf(node).length > 0) {
        Text(node.text).maxFontSize(node.size).minFontSize(Math.min(node.size, 12)).fontColor(node.color).maxLines(1)
          .fontWeight(this.weightOf(node)).fontFamily(this.familyOf(node)).letterSpacing(this.spacingOf(node))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Text(node.text).maxFontSize(node.size).minFontSize(Math.min(node.size, 12)).fontColor(node.color).maxLines(1)
          .fontWeight(this.weightOf(node)).letterSpacing(this.spacingOf(node))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    } else {
      if (this.familyOf(node).length > 0) {
        Text(node.text).fontSize(node.size).fontColor(node.color).maxLines(2)
          .fontWeight(this.weightOf(node)).fontFamily(this.familyOf(node)).letterSpacing(this.spacingOf(node))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Text(node.text).fontSize(node.size).fontColor(node.color).maxLines(2)
          .fontWeight(this.weightOf(node)).letterSpacing(this.spacingOf(node))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
  }

  /** A catalogue icon: strokes in a 100-unit box, the box's unit the pixel (see VeraPreview.drawIcon for why the viewPort and the stroke say 'px'). */
  @Builder
  glyph(commands: string, size: number, color: string) {
    Shape() {
      Path({ commands: commands }).fill(Color.Transparent).stroke(color).strokeWidth('8px')
        .strokeLineCap(LineCapStyle.Round).strokeLineJoin(LineJoinStyle.Round)
    }
    .viewPort({ x: '0px', y: '0px', width: '100px', height: '100px' })
    .width(size).height(size)
  }

  // ArkTS has no recursive builders: four levels, the depth a card is held to (the theme wrapper consumes none of them).
  @Builder
  level1(node: CardNode, inRow: boolean) {
    if (node.kind === 'row') {
      Row({ space: this.gapOf(node, 8) }) {
        ForEach(node.children, (child: CardNode) => { this.level2(child, true) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).justifyContent(this.rowJustify(node))
      .padding(this.padOf(node)).backgroundColor(this.panelOf(node)).borderRadius(this.radiusOf(node, 0))
    } else if (node.kind === 'column') {
      Column({ space: this.gapOf(node, 6) }) {
        ForEach(node.children, (child: CardNode) => { this.level2(child, false) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).alignItems(this.colAlign(node))
      .padding(this.padOf(node)).backgroundColor(this.panelOf(node)).borderRadius(this.radiusOf(node, 0))
    } else if (node.kind === 'motion') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level2(child, false) }, (child: CardNode) => child.key)
      }
      .layoutWeight(inRow ? 1 : 0)
      .scale({ x: this.poseOf(node, 3), y: this.poseOf(node, 4) })
      .rotate({ angle: this.poseOf(node, 5), centerX: '50%', centerY: this.pivotOf(node) })
      .translate({ x: this.poseOf(node, 1), y: this.poseOf(node, 2) })
      .opacity(this.poseOf(node, 6))
      .animation(this.motionAnimation(node))
      .onAppear(() => { this.begin(node) })
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level2(node: CardNode, inRow: boolean) {
    if (node.kind === 'row') {
      Row({ space: this.gapOf(node, 8) }) {
        ForEach(node.children, (child: CardNode) => { this.level3(child, true) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).justifyContent(this.rowJustify(node))
      .padding(this.padOf(node)).backgroundColor(this.panelOf(node)).borderRadius(this.radiusOf(node, 0))
    } else if (node.kind === 'column') {
      Column({ space: this.gapOf(node, 6) }) {
        ForEach(node.children, (child: CardNode) => { this.level3(child, false) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).alignItems(this.colAlign(node))
      .padding(this.padOf(node)).backgroundColor(this.panelOf(node)).borderRadius(this.radiusOf(node, 0))
    } else if (node.kind === 'motion') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level3(child, false) }, (child: CardNode) => child.key)
      }
      .layoutWeight(inRow ? 1 : 0)
      .scale({ x: this.poseOf(node, 3), y: this.poseOf(node, 4) })
      .rotate({ angle: this.poseOf(node, 5), centerX: '50%', centerY: this.pivotOf(node) })
      .translate({ x: this.poseOf(node, 1), y: this.poseOf(node, 2) })
      .opacity(this.poseOf(node, 6))
      .animation(this.motionAnimation(node))
      .onAppear(() => { this.begin(node) })
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level3(node: CardNode, inRow: boolean) {
    if (node.kind === 'row') {
      Row({ space: this.gapOf(node, 8) }) {
        ForEach(node.children, (child: CardNode) => { this.level4(child, true) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).justifyContent(this.rowJustify(node))
      .padding(this.padOf(node)).backgroundColor(this.panelOf(node)).borderRadius(this.radiusOf(node, 0))
    } else if (node.kind === 'column') {
      Column({ space: this.gapOf(node, 6) }) {
        ForEach(node.children, (child: CardNode) => { this.level4(child, false) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).alignItems(this.colAlign(node))
      .padding(this.padOf(node)).backgroundColor(this.panelOf(node)).borderRadius(this.radiusOf(node, 0))
    } else if (node.kind === 'motion') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level4(child, false) }, (child: CardNode) => child.key)
      }
      .layoutWeight(inRow ? 1 : 0)
      .scale({ x: this.poseOf(node, 3), y: this.poseOf(node, 4) })
      .rotate({ angle: this.poseOf(node, 5), centerX: '50%', centerY: this.pivotOf(node) })
      .translate({ x: this.poseOf(node, 1), y: this.poseOf(node, 2) })
      .opacity(this.poseOf(node, 6))
      .animation(this.motionAnimation(node))
      .onAppear(() => { this.begin(node) })
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level4(node: CardNode, inRow: boolean) {
    this.leaf(node)
  }
}
