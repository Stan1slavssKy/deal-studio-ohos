// The launcher only consumes binding DTOs. No VM, filesystem, or app imports here.
import { paintGfx, decodeGfxOps, gfxFit, gfxToSurface } from '../../vera/VeraGfx'
import { resolveTheme } from '../../vera/VeraTheme'

/** A picture on a card is as wide as its node says (the frame sizes it to the room left, VeraLiveWidget.pictureRoom); this when it says nothing (vp). */
const PICTURE_WIDTH: number = 80

let liveStorage = new LocalStorage()

class CardNode {
  key: string = ''
  kind: string = ''
  text: string = ''
  commands: string = ''
  style: string = ''
  trigger: number = 0
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
  children: CardNode[] = []
}

@Entry(liveStorage)
@Component
struct LiveCard {
  @LocalStorageProp('formId') formId: string = ''
  @LocalStorageProp('projectId') projectId: string = ''
  @LocalStorageProp('title') title: string = 'VERA app'
  @LocalStorageProp('icon') icon: string = '📱'
  @LocalStorageProp('token') token: string = ''
  @LocalStorageProp('seq') seq: string = ''
  @LocalStorageProp('status') status: string = ''
  @LocalStorageProp('live') live: boolean = false
  @LocalStorageProp('background') cardBackground: string = '#F8FAFC'
  @LocalStorageProp('preset') preset: string = 'clean'
  @LocalStorageProp('primary') primary: string = ''
  @LocalStorageProp('nodes') nodes: CardNode[] = []
  /**
   * ui.Surface: a still picture. The app's own painter (paintGfx) draws, on a Canvas, the shapes the frame carries; a tap on
   * it goes to the program's pointer handler as a finger down and up at that point, in the picture's own units.
   */
  private pictureCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private pictureW(node: CardNode): number { return node.size > 0 ? node.size : PICTURE_WIDTH }
  private pictureH(node: CardNode): number { return Math.min(this.pictureW(node) * 1.1, this.pictureW(node) * node.h / node.w) }
  private paintPicture(node: CardNode): void {
    let start = Date.now()
    paintGfx(this.pictureCtx, decodeGfxOps(node.ops), resolveTheme(this.preset, this.primary, false),
      this.pictureW(node), this.pictureH(node), node.w, node.h, vp2px(1))
    console.info('VERA-CARD picture painted ms=' + (Date.now() - start).toString() + ' at=' + Date.now().toString())
  }
  private pictureAt(node: CardNode, event: ClickEvent): number[] {
    return gfxToSurface(gfxFit(this.pictureW(node), this.pictureH(node), node.w, node.h), event.x, event.y)
  }

  /**
   * ui.Motion: the trigger the card last settled on. The node is made again for every frame (its key carries the token), so
   * there is nothing on it to animate from: a frame that carries another trigger starts it in the hit pose and it settles in
   * onAppear. The first frame only records its trigger, so a card never plays when it opens. A card plays for about two
   * seconds after a redraw, which is all a hit needs; there is no repeat or loop.
   */
  @State settled: number = -1e18

  /**
   * Touches on this card's pictures and shapes, counted here and added to a Motion's trigger: a touch makes the picture react
   * whether or not the program's handler changed anything (a plain field, not state: it must not redraw before the answer comes).
   */
  private touches: number = 0
  private effective(node: CardNode): number { return node.trigger + this.touches }
  private playing(node: CardNode): boolean { return this.settled > -1e17 && this.effective(node) !== this.settled }
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


  build() {
    // A live widget has the whole card: no title strip with the app's name. A tap anywhere but on a button opens the app
    // (an unbound card: the page that binds it); a button's own tap is the button's.
    Column({ space: 6 }) {
      if (this.live) {
        ForEach(this.nodes, (node: CardNode) => { this.level1(node, false) }, (node: CardNode) => node.key + this.token + this.seq)
      } else {
        Text(this.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#475569')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.icon).fontSize(32)
      }
      if (this.status.length > 0) {
        Text(this.status).fontSize(11).fontColor('#64748B').maxLines(2)
      }
    }
    .width('100%').height('100%').padding(12).backgroundColor(this.cardBackground)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { projectId: this.projectId, veraRun: '1', veraFormId: this.projectId.length === 0 ? this.formId : '' } })
    })
  }

  @Builder
  leaf(node: CardNode) {
    if (node.kind === 'button') {
      Button(node.text).type(ButtonType.Normal).borderRadius(10).height(40)
        .backgroundColor(node.fill).fontColor(node.color).fontSize(14)
        .enabled(node.enabled).onClick(() => {
          postCardAction(this, { action: 'message', params: { token: this.token, handler: node.action, value: node.value } })
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
          this.touches += 1
          postCardAction(this, { action: 'message', params: { token: this.token, handler: node.action, value: node.value } })
        }
      })
    } else if (node.kind === 'surface') {
      // A picture without a pointer handler lets a tap fall through to the card, which opens the app.
      if (node.pointer.length > 0) {
        Canvas(this.pictureCtx).width(this.pictureW(node)).height(this.pictureH(node))
          .onReady(() => { this.paintPicture(node) })
          .onClick((event: ClickEvent) => {
            let at = this.pictureAt(node, event)
            this.touches += 1
            postCardAction(this, { action: 'message', params: { token: this.token, handler: node.pointer, x: at[0], y: at[1] } })
          })
      } else {
        Canvas(this.pictureCtx).width(this.pictureW(node)).height(this.pictureH(node))
          .onReady(() => { this.paintPicture(node) })
      }
    } else if (node.kind === 'divider') {
      Divider().color('#CBD5E1')
    } else if (node.kind === 'spacer') {
      Blank().height(4)
    } else if (node.kind === 'numbertext') {
      // A figure is never broken over two lines: beside another, it shrinks to fit its half of the card.
      Text(node.text).maxFontSize(node.size).minFontSize(Math.min(node.size, 12)).fontColor(node.color).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else {
      Text(node.text).fontSize(node.size).fontColor(node.color).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  // This layout (leaf and the level builders) is a copy of components/WidgetPreview.ets's, kept in step by hand: a card cannot import the
  // app's code. A change to how a node is drawn goes into both, or the preview stops showing what the card shows.
  @Builder
  level1(node: CardNode, inRow: boolean) {
    if (node.kind === 'row') {
      Row({ space: 8 }) {
        ForEach(node.children, (child: CardNode) => { this.level2(child, true) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).justifyContent(FlexAlign.SpaceEvenly)
    } else if (node.kind === 'column') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level2(child, false) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0)
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
      .onAppear(() => { this.settled = this.effective(node) })
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level2(node: CardNode, inRow: boolean) {
    if (node.kind === 'row') {
      Row({ space: 8 }) {
        ForEach(node.children, (child: CardNode) => { this.level3(child, true) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).justifyContent(FlexAlign.SpaceEvenly)
    } else if (node.kind === 'column') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level3(child, false) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0)
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
      .onAppear(() => { this.settled = this.effective(node) })
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level3(node: CardNode, inRow: boolean) {
    if (node.kind === 'row') {
      Row({ space: 8 }) {
        ForEach(node.children, (child: CardNode) => { this.level4(child, true) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).justifyContent(FlexAlign.SpaceEvenly)
    } else if (node.kind === 'column') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level4(child, false) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0)
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
      .onAppear(() => { this.settled = this.effective(node) })
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level4(node: CardNode, inRow: boolean) {
    this.leaf(node)
  }
}
