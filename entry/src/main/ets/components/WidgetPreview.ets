import { WidgetSession, LiveFrame, CardNode } from '../vera/VeraLiveWidget'
import { app } from './AppStyle'
import { sourceFetch } from '../vera/VeraSource'
import { paintGfx, decodeGfxOps, gfxFit, gfxToSurface } from '../vera/VeraGfx'
import { resolveTheme } from '../vera/VeraTheme'

/** A picture on a card is as wide as its node says (the frame sizes it to the room left, VeraLiveWidget.pictureRoom); this when it says nothing (vp). */
const PICTURE_WIDTH: number = 80

/** A 2x2 home-screen card on this phone, in vp: the size the widget is written for (measured: 524 px wide at 3.5 px per vp). */
const CARD_SIDE: number = 150
/** The thumbnail's side, in vp. */
const THUMB_SIDE: number = 72

/**
 * The program's widget(state) as the home-screen card will draw it: the same session (VeraLiveWidget) and the same
 * layout as LiveCard, over the state the app preview holds. Taps run the handlers here only; nothing is saved.
 */
@Component
export struct WidgetPreview {
  @Prop @Watch('restart') vbc2: string = ''
  @Prop @Watch('restart') seedState: string = ''
  /** Passed to the session, as the card's frame carries it; a live card does not show it. */
  @Prop title: string = 'App'
  /** A small, still picture of the card (the project page): no note under it and no taps. */
  @Prop thumbnail: boolean = false
  @State frame: LiveFrame = new LiveFrame()
  @State error: string = ''
  private session: WidgetSession | null = null
  /**
   * ui.Surface: a still picture. The app's own painter (paintGfx) draws, on a Canvas, the shapes the frame carries; a tap on
   * it goes to the program's pointer handler as a finger down and up at that point, in the picture's own units.
   */
  private pictureCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private pictureW(node: CardNode): number { return node.size > 0 ? node.size : PICTURE_WIDTH }
  private pictureH(node: CardNode): number { return Math.min(this.pictureW(node) * 1.1, this.pictureW(node) * node.h / node.w) }
  private paintPicture(node: CardNode): void {
    paintGfx(this.pictureCtx, decodeGfxOps(node.ops), resolveTheme(this.frame.preset, this.frame.primary, false),
      this.pictureW(node), this.pictureH(node), node.w, node.h, vp2px(1))
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
  /** Another frame after every tap, even one that left the state as it was, so the card draws it again. */
  @State seq: number = 0

  /** Touches on pictures and shapes, added to a Motion's trigger (as on the card): a touch plays whatever the handler did. */
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


  aboutToAppear(): void {
    this.restart()
  }

  /** A new program or a new state: draw it from the start. A state the program cannot draw falls back to init. */
  restart(): void {
    this.error = ''
    this.session = null
    this.settled = -1e18
    this.frame = new LiveFrame()
    if (this.vbc2.length === 0) { return }
    let seeds = this.seedState.length > 0 ? [this.seedState, ''] : ['']
    for (let seed of seeds) {
      try {
        let session = new WidgetSession(this.vbc2, 'preview', seed)
        this.frame = session.frame('', this.title, '')
        this.session = session
        return
      } catch (e) {
        this.error = (e as Error).message
      }
    }
  }

  /** A tap is being handled (a Refresh's fetch may take seconds): another tap meanwhile is ignored, not handled twice. */
  private busy: boolean = false

  private async tap(node: CardNode): Promise<void> {
    if (this.session === null || this.busy) { return }
    let session = this.session!
    // What the session held before the tap: put back if the tap or its answer fails, so it matches the frame on show.
    let before = session.encodedState()
    this.busy = true
    try {
      // A Refresh button fetches its live source here too, as the card does: one call, as on the card.
      let requests = session.tap(this.frame, this.frame.token, node.action, node.value)
      if (requests.length > 0) { session.answer(requests[0].handler, await sourceFetch(requests[0].params)) }
      if (session !== this.session) { return }
      this.frame = session.frame('', this.title, '')
      this.seq += 1
      this.error = ''
    } catch (e) {
      if (session === this.session) { this.session = new WidgetSession(this.vbc2, 'preview', before) }
      this.error = (e as Error).message
    } finally {
      this.busy = false
    }
  }

  /** A tap on the picture: the pointer handler runs here only, as a button's does; nothing is saved. */
  private tapPicture(node: CardNode, x: number, y: number): void {
    if (this.session === null || this.busy) { return }
    let session = this.session!
    let before = session.encodedState()
    this.busy = true
    try {
      session.tapSurface(this.frame, this.frame.token, node.pointer, x, y)
      this.frame = session.frame('', this.title, '')
      this.seq += 1
      this.error = ''
    } catch (e) {
      if (session === this.session) { this.session = new WidgetSession(this.vbc2, 'preview', before) }
      this.error = (e as Error).message
    } finally {
      this.busy = false
    }
  }

  build() {
    if (this.thumbnail) {
      // The card at its own size, scaled down to THUMB_SIDE: what is on it lays out as on the home screen.
      Stack() {
        this.card()
      }
      .width(THUMB_SIDE)
      .height(THUMB_SIDE)
      .clip(true)
      .hitTestBehavior(HitTestMode.Transparent)
    } else {
      Column({ space: 12 }) {
        this.card()
        Text(this.note())
          .fontSize(12).fontColor(this.error.length > 0 ? app.warningInk : app.inkMuted)
          .textAlign(TextAlign.Center).constraintSize({ maxWidth: 300 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(app.background)
    }
  }

  @Builder
  card() {
    // As LiveCard: the widget has the whole card, with no title strip.
    Column({ space: 6 }) {
      if (this.frame.live) {
        ForEach(this.frame.nodes, (node: CardNode) => { this.level1(node, false) }, (node: CardNode) => node.key + this.frame.token + this.seq.toString())
      }
    }
    .width(CARD_SIDE)
    .height(CARD_SIDE)
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.frame.background)
    .borderRadius(20)
    .clip(true)
    .shadow(this.thumbnail ? { radius: 0 } : { radius: 8, color: '#26000000', offsetY: 2 })
    .scale(this.thumbnail ? { x: THUMB_SIDE / CARD_SIDE, y: THUMB_SIDE / CARD_SIDE } : { x: 1, y: 1 })
    .hitTestBehavior(this.thumbnail ? HitTestMode.None : HitTestMode.Default)
  }

  private note(): string {
    if (this.error.length > 0) { return this.error }
    if (!this.frame.live) { return 'No widget yet. Say below what it should show.' }
    return 'Shows your saved data. The app itself doesn\'t change. Taps here aren\'t saved.'
  }

  @Builder
  leaf(node: CardNode) {
    if (node.kind === 'button') {
      Button(node.text).type(ButtonType.Normal).borderRadius(10).height(40)
        .backgroundColor(node.fill).fontColor(node.color).fontSize(14)
        .enabled(node.enabled).onClick(() => { this.tap(node) })
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
        if (node.action.length > 0 && node.enabled) { this.touches += 1; this.tap(node) }
      })
    } else if (node.kind === 'surface') {
      // A picture without a pointer handler lets a tap fall through to the card, which opens the app.
      if (node.pointer.length > 0) {
        Canvas(this.pictureCtx).width(this.pictureW(node)).height(this.pictureH(node))
          .onReady(() => { this.paintPicture(node) })
          .onClick((event: ClickEvent) => {
            let at = this.pictureAt(node, event)
            this.touches += 1
            this.tapPicture(node, at[0], at[1])
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

  // This layout (leaf and the level builders) is a copy of widget/pages/LiveCard.ets's, kept in step by hand: a card cannot import the
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
        ForEach(node.children, (child: CardNode) => { this.leaf(child) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0).justifyContent(FlexAlign.SpaceEvenly)
    } else if (node.kind === 'column') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.leaf(child) }, (child: CardNode) => child.key)
      }.width('100%').layoutWeight(inRow ? 1 : 0)
    } else if (node.kind === 'motion') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.leaf(child) }, (child: CardNode) => child.key)
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
}
