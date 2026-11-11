import { WidgetSession, LiveFrame, CardNode, SourceRequest } from '../vera/VeraLiveWidget'
import { app } from './AppStyle'
import { sourceFetch } from '../vera/VeraSource'
import { CardView } from '../widget/CardView'
import { CARD_PADDING, splitCover, coverScrim } from '../widget/CardModel'

/** A 2x2 home-screen card on this phone, in vp: the size the widget is written for (measured: 524 px wide at 3.5 px per vp). */
const CARD_SIDE: number = 150
/** The other sizes the card is offered in (measured the same way): 2x4 is wide, 4x4 is nearly square. */
const CARD_WIDE_WIDTH: number = 324
const CARD_WIDE_HEIGHT: number = 148
const CARD_BIG_HEIGHT: number = 340
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
  /** Which card size to show, as the system numbers it: 2 is 2x2, 3 is 2x4, 4 is 4x4. */
  @State dimension: number = 2
  @State frame: LiveFrame = new LiveFrame()
  @State error: string = ''
  private session: WidgetSession | null = null
  /** Another frame after every tap, even one that left the state as it was, so the card draws it again. */
  @State seq: number = 0

  aboutToAppear(): void {
    this.restart()
  }

  /** A new program or a new state: draw it from the start. A state the program cannot draw falls back to init. */
  restart(): void {
    this.error = ''
    this.session = null
    this.frame = new LiveFrame()
    if (this.vbc2.length === 0) { return }
    let seeds = this.seedState.length > 0 ? [this.seedState, ''] : ['']
    for (let seed of seeds) {
      try {
        let session = new WidgetSession(this.vbc2, 'preview', seed)
        this.frame = session.frame('', this.title, '', this.dimension)
        this.session = session
        return
      } catch (e) {
        this.error = (e as Error).message
      }
    }
  }

  /** A tap is being handled (a Refresh's fetch may take seconds): another tap meanwhile is ignored, not handled twice. */
  private busy: boolean = false

  /**
   * A tap of any kind, run here only and never saved: a button's handler, a switch's, a picture's pointer. Its live source call, if it
   * makes one, is fetched and answered here too, as the card does (LiveFormService): one call, as on the card.
   */
  private async run(handle: (session: WidgetSession) => SourceRequest[]): Promise<void> {
    if (this.session === null || this.busy) { return }
    let session = this.session!
    // What the session held before the tap: put back if the tap or its answer fails, so it matches the frame on show.
    let before = session.encodedState()
    this.busy = true
    try {
      let requests = handle(session)
      if (requests.length > 0) { session.answer(requests[0].handler, await sourceFetch(requests[0].params)) }
      if (session !== this.session) { return }
      this.frame = session.frame('', this.title, '', this.dimension)
      this.seq += 1
      this.error = ''
    } catch (e) {
      if (session === this.session) { this.session = new WidgetSession(this.vbc2, 'preview', before) }
      this.error = (e as Error).message
    } finally {
      this.busy = false
    }
  }

  private tap(action: string, value: number): void {
    this.run((session: WidgetSession): SourceRequest[] => session.tap(this.frame, this.frame.token, action, value))
  }

  private tapSwitch(handler: string, on: boolean): void {
    this.run((session: WidgetSession): SourceRequest[] => session.tapSwitch(this.frame, this.frame.token, handler, on))
  }

  private tapPicture(handler: string, x: number, y: number): void {
    this.run((session: WidgetSession): SourceRequest[] => session.tapSurface(this.frame, this.frame.token, handler, x, y))
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
        // The size the card will be placed at: the widget is fitted to it (a widget that asks for the size draws differently).
        Row({ space: 8 }) {
          ForEach([2, 3, 4], (d: number) => {
            Text(d === 2 ? '2×2' : d === 3 ? '2×4' : '4×4')
              .fontSize(12).padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(14)
              .fontColor(this.dimension === d ? app.onPrimary : app.inkStrong)
              .backgroundColor(this.dimension === d ? app.primary : app.surface)
              .onClick(() => { this.dimension = d; this.restart() })
          }, (d: number) => d.toString())
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(app.background)
    }
  }

  /** As LiveCard: the cover picture under everything, to the card's edges (splitCover), and the rest over it. */
  private coverNodes(): CardNode[] {
    let cover = splitCover(this.frame.nodes).cover
    return this.frame.live && cover !== null ? [cover] : []
  }
  private restNodes(): CardNode[] { return splitCover(this.frame.nodes).rest }
  private overCover(): boolean { return this.coverNodes().length > 0 && this.restNodes().length > 0 }

  @Builder
  card() {
    // As LiveCard: the widget has the whole card, with no title strip.
    Stack() {
      if (this.coverNodes().length > 0) {
        CardView({
          nodes: this.coverNodes(),
          fill: true,
          dimension: this.dimension,
          frameKey: this.frame.token + this.dimension.toString() + this.seq.toString(),
          preset: this.frame.preset,
          primary: this.frame.primary,
          onTap: (action: string, value: number): void => { this.tap(action, value) },
          onPoint: (handler: string, x: number, y: number): void => { this.tapPicture(handler, x, y) }
        })
      }
      Column({ space: 6 }) {
        if (this.frame.live) {
          CardView({
            nodes: this.restNodes(),
            dimension: this.dimension,
            frameKey: this.frame.token + this.dimension.toString() + this.seq.toString(),
            preset: this.frame.preset,
            primary: this.frame.primary,
            onTap: (action: string, value: number): void => { this.tap(action, value) },
            onSwitch: (handler: string, on: boolean): void => { this.tapSwitch(handler, on) },
            onPoint: (handler: string, x: number, y: number): void => { this.tapPicture(handler, x, y) }
          })
        }
      }
      .width('100%').height('100%').padding(CARD_PADDING)
      .justifyContent(this.overCover() ? FlexAlign.End : FlexAlign.Center)
      .linearGradient({ angle: 180, colors: coverScrim(this.frame.background, this.overCover()) })
      .hitTestBehavior(this.coverNodes().length > 0 ? HitTestMode.Transparent : HitTestMode.Default)
    }
    .width(this.dimension === 2 ? CARD_SIDE : CARD_WIDE_WIDTH)
    .height(this.dimension === 2 ? CARD_SIDE : this.dimension === 3 ? CARD_WIDE_HEIGHT : CARD_BIG_HEIGHT)
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
}
