import { KeyboardAvoidMode } from '@ohos.arkui.UIContext'
import { store } from '../vera/ProjectStore'
import { consent } from '../vera/VeraConsentStore'
import { projectIconResource } from '../vera/ProjectIcons'
import { app } from '../components/AppStyle'
import { APP_STARTERS, ChatStarter, STARTERS_EN } from '../components/ChatStarters'
import { ProjectNavParams, ProjectRow, confirmDeleteProject, loadProjectRows, tileTint } from '../components/ProjectRows'

/** Width of one label in the Chat / App switch, in vp. */
const MODE_TAB_WIDTH: number = 112

/** Height of the zone above the box, in vp: the apps in one mode, the ready-made requests in the other, so the centre never moves. */
const ZONE_HEIGHT: number = 150

@Entry
@Component
struct Index {
  @State projects: ProjectRow[] = []
  /** What the box at the bottom is for: talking, or making an app. */
  @State makeApp: boolean = true
  @State draft: string = ''
  /** The box has the keyboard: the greeting and the zone give up their room to it. */
  @State typing: boolean = false

  aboutToAppear(): void {
    let context = this.getUIContext().getHostContext()
    if (context === undefined) { throw new Error('Project library host context is unavailable') }
    store.init(context.filesDir)
    consent.init(context.filesDir)
    // Shrink the page for the keyboard instead of panning it, so the box and its button stay in view.
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.reload()
  }

  onPageShow(): void {
    this.reload()
    // Coming back, the box would take the focus again and open the keyboard over the apps; the person taps it when they want it.
    setTimeout(() => {
      try { this.getUIContext().getFocusController().clearFocus() } catch (e) { console.warn('VERA clearFocus failed: ' + (e as Error).message) }
    }, 250)
  }

  private reload(): void {
    this.projects = loadProjectRows()
  }

  private setMode(makeApp: boolean): void {
    if (this.makeApp === makeApp) { return }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => { this.makeApp = makeApp })
  }

  /** `run` sends what was typed straight away; otherwise it waits in the box of the next page. */
  private openChat(prompt: string, run: boolean): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ChatPage', params: { prompt: prompt, run: run ? '1' : '' } })
      .catch((e: Error): void => { console.error('Navigate to chats failed: ' + e.message) })
  }

  private openHistory(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ChatListPage' })
      .catch((e: Error): void => { console.error('Navigate to chat list failed: ' + e.message) })
  }

  private openApps(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/AppsPage' })
      .catch((e: Error): void => { console.error('Navigate to apps failed: ' + e.message) })
  }

  /**
   * A new app starts on the Generate screen with no project behind it: nothing is asked for
   * and nothing is made until the first Save, which offers a name taken from the program.
   */
  private openCreate(prompt: string, run: boolean): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/GeneratePage', params: { prompt: prompt, run: run ? '1' : '' } })
      .catch((e: Error): void => { console.error('Navigate to generate failed: ' + e.message) })
  }

  /** What the box and a ready-made request do: go to the page of the current mode with the text, and start it if there is any. */
  private submit(text: string): void {
    let request = text.trim()
    this.draft = ''
    if (this.makeApp) { this.openCreate(request, request.length > 0) } else { this.openChat(request, request.length > 0) }
  }

  build() {
    Column() {
      this.topBar()
      this.middle()
      if (!this.typing) {
        this.zone()
      }
      this.promptBox()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(app.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  /** The saved chats, at the right. */
  @Builder
  topBar() {
    Row({ space: 8 }) {
      Blank()
      Button({ type: ButtonType.Circle }) {
        // The button follows the mode: chats' history for Chat, the apps made so far for App.
        SymbolGlyph($r(this.makeApp ? 'sys.symbol.square_grid_2x2' : 'sys.symbol.clock')).fontSize(20).fontColor([app.inkStrong])
      }
      .width(44).height(44)
      .backgroundColor(app.secondaryFill)
      .accessibilityText(this.makeApp ? 'My apps' : 'Chat history')
      .onClick(() => { if (this.makeApp) { this.openApps() } else { this.openHistory() } })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 12 })
  }

  /** The greeting in the middle of the free space, and the switch between the two things to do. */
  @Builder
  middle() {
    Column({ space: 20 }) {
      if (!this.typing) {
        Image($r('app.media.vera_mark')).width(52).height(52).objectFit(ImageFit.Contain)
      }
      Column({ space: 8 }) {
        Text(this.makeApp ? 'What shall we make?' : 'How can I help?')
          .fontSize(30).fontWeight(FontWeight.Medium).fontColor(app.inkStrong).textAlign(TextAlign.Center)
        if (!this.typing) {
          Text(this.makeApp ? 'Describe an idea and VERA builds the screens, logic and data.' :
            'Ask, plan, get a card.')
            .fontSize(15).fontColor(app.inkSoft).textAlign(TextAlign.Center).constraintSize({ maxWidth: 290 })
        }
      }
      // The white pill slides under the label that is on; the state flips inside animateTo so the pill and the ink move together.
      Stack({ alignContent: Alignment.TopStart }) {
        Row()
          .width(MODE_TAB_WIDTH).height(40).borderRadius(20)
          .backgroundColor(app.surface)
          .shadow({ radius: 2, color: '#20000000', offsetY: 1 })
          .translate({ x: this.makeApp ? MODE_TAB_WIDTH + 2 : 0 })
        Row({ space: 2 }) {
          this.modeTab('Chat', 'sys.symbol.ellipsis_message', !this.makeApp, () => { this.setMode(false) })
          this.modeTab('App', 'sys.symbol.plus', this.makeApp, () => { this.setMode(true) })
        }
      }
      .padding(4)
      .borderRadius(24)
      .backgroundColor(app.secondaryFill)
      .margin({ top: 8 })
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  modeTab(label: string, symbol: string, on: boolean, go: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph($r(symbol)).fontSize(18).fontColor([on ? app.inkStrong : app.inkSoft])
      Text(label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(on ? app.inkStrong : app.inkSoft)
    }
    .width(MODE_TAB_WIDTH)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .onClick(go)
  }

  /** The apps made so far in the app mode, else ready-made requests to start from; the same height either way. */
  @Builder
  zone() {
    Column() {
      if (this.makeApp && this.projects.length > 0) {
        this.appsStrip()
      } else {
        this.starterChips(this.makeApp ? APP_STARTERS : STARTERS_EN)
      }
    }
    .width('100%')
    .height(ZONE_HEIGHT)
    .justifyContent(FlexAlign.Start)
  }

  /** A row of icons: a press opens one, a long press offers to delete it, "All" lists them with their pictures. */
  @Builder
  appsStrip() {
    Column({ space: 10 }) {
      Row() {
        Text('My apps').fontSize(15).fontWeight(FontWeight.Medium).fontColor(app.inkStrong).layoutWeight(1)
        Text('All ' + this.projects.length.toString()).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(app.primaryInk)
          .height(44).padding({ left: 12, right: 4 }).align(Alignment.Center)
          .onClick(() => { this.openApps() })
      }
      .width('100%').height(24).padding({ left: 16, right: 12 })
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.projects, (row: ProjectRow) => {
            this.appTile(row)
          }, (row: ProjectRow) => row.project.id + '|' + row.project.name + '|' + row.project.icon)
        }
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Top)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }

  /** What to try: titles of ready-made requests, one tap sends one. */
  @Builder
  starterChips(starters: ChatStarter[]) {
    Column({ space: 10 }) {
      Text(this.makeApp ? 'Try one of these' : 'Or start with').fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(app.inkStrong).width('100%').height(24).padding({ left: 16 })
      Scroll() {
        Row({ space: 8 }) {
          ForEach(starters, (starter: ChatStarter) => {
            Text(starter.title).fontSize(14).fontColor(app.inkStrong).maxLines(1)
              .height(40).padding({ left: 16, right: 16 }).borderRadius(20)
              .backgroundColor(app.surface).borderWidth(1).borderColor(app.line)
              .onClick(() => { this.submit(starter.prompt) })
          }, (starter: ChatStarter) => starter.id)
        }
        .padding({ left: 12, right: 12 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')
    }
  }

  @Builder
  appTile(row: ProjectRow) {
    Column({ space: 8 }) {
      Image(projectIconResource(row.project.icon)).width(40).height(40).objectFit(ImageFit.Contain)
        .width(60).height(60).padding(10).borderRadius(18).backgroundColor(tileTint(row.project.id))
      Text(row.project.name).fontSize(12).fontColor(app.inkStrong).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
        .width('100%').height(32)
    }
    .width(76)
    .onClick(() => {
      let nav = new ProjectNavParams()
      nav.projectId = row.project.id
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ProjectPage', params: nav })
        .catch((e: Error): void => { console.error('Navigate to project failed: ' + e.message) })
    })
    // The press that asks is its own confirmation: nothing is deleted before the dialog is answered.
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      confirmDeleteProject(this.getUIContext(), row.project.id, () => { this.reload() })
    }))
  }

  /** The request: a rounded card that floats above the bottom edge, with the send button at its corner. */
  @Builder
  promptBox() {
    Column({ space: 8 }) {
      TextArea({ placeholder: this.makeApp ? 'Describe the app…' : 'Write a message…', text: this.draft })
        .fontSize(16).fontColor(app.inkStrong).backgroundColor(Color.Transparent)
        .height(64).padding({ left: 6, right: 6 })
        .enterKeyType(EnterKeyType.Send)
        .onChange((value: string) => { this.draft = value })
        .onSubmit(() => { this.submit(this.draft) })
        .onFocus(() => { this.getUIContext().animateTo({ duration: 180 }, () => { this.typing = true }) })
        .onBlur(() => { this.getUIContext().animateTo({ duration: 180 }, () => { this.typing = false }) })
      Row() {
        Blank()
        // Pale while there is nothing to send, as on the Generate screen; a press then just opens the page.
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(20).fontColor([app.onPrimary])
        }
        .width(44).height(44)
        .backgroundColor(app.primary)
        .opacity(this.draft.trim().length > 0 ? 1 : 0.4)
        .accessibilityText(this.makeApp ? 'Create app' : 'Send')
        .onClick(() => { this.submit(this.draft) })
      }
      .width('100%')
    }
    .margin({ left: 12, right: 12, bottom: 24 })
    .padding({ top: 10, left: 10, right: 10, bottom: 10 })
    .borderRadius(26)
    .backgroundColor(app.surface)
    .borderWidth(1)
    .borderColor(app.line)
    .shadow({ radius: 20, color: '#12000000', offsetY: 4 })
  }
}
