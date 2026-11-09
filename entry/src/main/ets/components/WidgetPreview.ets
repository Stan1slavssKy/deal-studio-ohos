import { WidgetSession, LiveFrame, CardNode } from '../vera/VeraLiveWidget'
import { app } from './AppStyle'
import { sourceFetch } from '../vera/VeraSource'
import { CardView } from '../widget/CardView'

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

  private async tap(action: string, value: number): Promise<void> {
    if (this.session === null || this.busy) { return }
    let session = this.session!
    // What the session held before the tap: put back if the tap or its answer fails, so it matches the frame on show.
    let before = session.encodedState()
    this.busy = true
    try {
      // A Refresh button fetches its live source here too, as the card does: one call, as on the card.
      let requests = session.tap(this.frame, this.frame.token, action, value)
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

  /** A tap on a toggle or a checkbox: its handler runs here only, as a button's does; nothing is saved. */
  private tapSwitch(handler: string, on: boolean): void {
    if (this.session === null || this.busy) { return }
    let session = this.session!
    let before = session.encodedState()
    this.busy = true
    try {
      session.tapSwitch(this.frame, this.frame.token, handler, on)
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

  /** A tap on the picture: the pointer handler runs here only, as a button's does; nothing is saved. */
  private tapPicture(handler: string, x: number, y: number): void {
    if (this.session === null || this.busy) { return }
    let session = this.session!
    let before = session.encodedState()
    this.busy = true
    try {
      session.tapSurface(this.frame, this.frame.token, handler, x, y)
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

  @Builder
  card() {
    // As LiveCard: the widget has the whole card, with no title strip.
    Column({ space: 6 }) {
      if (this.frame.live) {
        CardView({
          nodes: this.frame.nodes,
          frameKey: this.frame.token + this.seq.toString(),
          preset: this.frame.preset,
          primary: this.frame.primary,
          onTap: (action: string, value: number): void => { this.tap(action, value) },
          onSwitch: (handler: string, on: boolean): void => { this.tapSwitch(handler, on) },
          onPoint: (handler: string, x: number, y: number): void => { this.tapPicture(handler, x, y) }
        })
      }
    }
    .width(this.dimension === 2 ? CARD_SIDE : CARD_WIDE_WIDTH)
    .height(this.dimension === 2 ? CARD_SIDE : this.dimension === 3 ? CARD_WIDE_HEIGHT : CARD_BIG_HEIGHT)
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
}
