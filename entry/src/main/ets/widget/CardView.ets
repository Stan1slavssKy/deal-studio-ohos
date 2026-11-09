/**
 * The layout of a home-screen card: the nodes of a frame (VeraLiveWidget) drawn the one way, by both the launcher's card (pages/LiveCard.ets) and
 * the app's Widget tab (components/WidgetPreview.ets), so the preview cannot drift from what the card shows. It loads only the theme and
 * the painter, never the VM. What happens on a touch is the host's: this reports it through onTap and onPoint.
 */

import { CardNode } from './CardModel'
import { paintGfx, decodeGfxOps, gfxFit, gfxToSurface } from '../vera/GfxPaint'
import { resolveTheme } from '../vera/VeraTheme'

/** A picture on a card is as wide as its node says (the frame sizes it to the room left, VeraLiveWidget.pictureRoom); this when it says nothing (vp). */
const PICTURE_WIDTH: number = 80
/** Pictures and Motions a card carries, each with a place of its own below. */
const SLOTS: number = 3

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
  /** A picture was tapped: its pointer handler's name and where, in the picture's own units. */
  onPoint: (handler: string, x: number, y: number) => void = (handler: string, x: number, y: number): void => {}

  /**
   * ui.Surface: a still picture. The app's own painter (paintGfx) draws, on a Canvas, the shapes the frame carries; each picture has
   * its own context, by its number in the frame.
   */
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
  @State settled0: number = -1e18
  @State settled1: number = -1e18
  @State settled2: number = -1e18
  private settledOf(node: CardNode): number { return node.slot === 1 ? this.settled1 : node.slot === 2 ? this.settled2 : this.settled0 }
  private settle(node: CardNode): void {
    let now = this.effective(node)
    if (node.slot === 1) { this.settled1 = now } else if (node.slot === 2) { this.settled2 = now } else { this.settled0 = now }
  }

  /**
   * Touches on the pictures and shapes under each Motion, counted here and added to its trigger: a touch makes the picture react
   * whether or not the program's handler changed anything (a plain field, not state: it must not redraw before the answer comes).
   */
  private touches: number[] = [0, 0, 0]
  private touched(node: CardNode): void {
    if (node.slot >= 0 && node.slot < SLOTS) { this.touches[node.slot] = this.touches[node.slot] + 1 }
  }
  private effective(node: CardNode): number { return node.trigger + (node.slot >= 0 && node.slot < SLOTS ? this.touches[node.slot] : 0) }
  private playing(node: CardNode): boolean { return this.settledOf(node) > -1e17 && this.effective(node) !== this.settledOf(node) }
  private motionScale(node: CardNode): number { return this.playing(node) && node.style === 'pop' ? 1.25 : 1 }
  private motionAngle(node: CardNode): number {
    if (!this.playing(node) || node.style !== 'shake') { return 0 }
    return Math.floor(node.trigger) % 2 === 0 ? 12 : -12
  }
  private motionDrop(node: CardNode): number { return this.playing(node) && node.style === 'bounce' ? -16 : 0 }
  private motionOpacity(node: CardNode): number { return this.playing(node) && node.style === 'fade' ? 0 : 1 }
  private motionMs(node: CardNode): number {
    return node.style === 'bounce' ? 600 : node.style === 'shake' ? 450 : node.style === 'pop' ? 350 : 400
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
      .scale({ x: this.motionScale(node), y: this.motionScale(node) })
      .rotate({ angle: this.motionAngle(node) })
      .translate({ y: this.motionDrop(node) })
      .opacity(this.motionOpacity(node))
      .animation({ duration: this.motionMs(node), curve: Curve.EaseOut })
      .onAppear(() => { this.settle(node) })
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
      .scale({ x: this.motionScale(node), y: this.motionScale(node) })
      .rotate({ angle: this.motionAngle(node) })
      .translate({ y: this.motionDrop(node) })
      .opacity(this.motionOpacity(node))
      .animation({ duration: this.motionMs(node), curve: Curve.EaseOut })
      .onAppear(() => { this.settle(node) })
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
      .scale({ x: this.motionScale(node), y: this.motionScale(node) })
      .rotate({ angle: this.motionAngle(node) })
      .translate({ y: this.motionDrop(node) })
      .opacity(this.motionOpacity(node))
      .animation({ duration: this.motionMs(node), curve: Curve.EaseOut })
      .onAppear(() => { this.settle(node) })
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level4(node: CardNode, inRow: boolean) {
    this.leaf(node)
  }
}
