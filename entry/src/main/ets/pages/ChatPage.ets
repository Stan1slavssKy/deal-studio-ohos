import { KeyboardAvoidMode } from '@ohos.arkui.UIContext'
import { VeraPreview } from '../components/VeraPreview'
import { loadRawfileText } from '../vera/LlamaEngine'
import { settings } from '../vera/SettingsStore'
import { consent } from '../vera/VeraConsentStore'
import { describeCatalogForPrompt } from '../vera/VeraUiCatalog'
import { loadRegistry } from '../vera/VeraIntentRegistry'
import { loadCatalogFile } from '../vera/VeraCatalogFile'
import { loadSdkIndex } from '../vera/VeraSdkIndex'
import { ChatTurn, ParsedReply, MiniApp, parseReply, chatReply, buildMiniApp } from '../vera/VeraChat'

const APP_NONE: string = 'none'
const APP_DESCRIBING: string = 'describing'
const APP_BUILDING: string = 'building'
const APP_READY: string = 'ready'
const APP_FAILED: string = 'failed'
const APP_HEIGHT: number = 420
const SCROLL_EVERY_MS: number = 150

/**
 * One chat message. Observed, so a reply can grow while it streams and a
 * widget can arrive in it later without the list rebuilding the row: a rebuilt
 * row would throw away the running widget and its state.
 */
@Observed
class ChatMessage {
  id: number = 0
  role: string = 'user'
  /** Text before the widget, or all of it when there is no widget. */
  before: string = ''
  /** Text after the widget. */
  after: string = ''
  appDescription: string = ''
  appState: string = APP_NONE
  vbc2: string = ''
  error: string = ''
}

@Component
struct MessageBubble {
  @ObjectLink msg: ChatMessage

  build() {
    Column({ space: 8 }) {
      if (this.msg.before.length > 0) {
        Text(this.msg.before)
          .fontSize(16)
          .fontColor(this.msg.role === 'user' ? '#FFFFFF' : '#1A1A1A')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.msg.role === 'user' ? '#2F6BFF' : '#FFFFFF')
          .borderRadius(14)
          .constraintSize({ maxWidth: '85%' })
      }
      if (this.msg.appState === APP_DESCRIBING) {
        Text('Planning a widget...')
          .fontSize(13)
          .fontColor('#666666')
          .padding(12)
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
      } else if (this.msg.appState === APP_BUILDING) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text('Building a widget...').fontSize(13).fontColor('#666666')
        }
        .padding(12)
        .backgroundColor('#FFFFFF')
        .borderRadius(14)
      } else if (this.msg.appState === APP_READY) {
        VeraPreview({ vbc2: this.msg.vbc2 })
          .width('100%')
          .height(APP_HEIGHT)
          .borderRadius(14)
          .clip(true)
          .backgroundColor('#FFFFFF')
      } else if (this.msg.appState === APP_FAILED) {
        Text('The widget could not be built: ' + this.msg.error.substring(0, 240))
          .fontSize(12)
          .fontColor('#B3261E')
          .padding(10)
          .backgroundColor('#FFECEC')
          .borderRadius(10)
      }
      if (this.msg.after.length > 0) {
        Text(this.msg.after)
          .fontSize(16)
          .fontColor('#1A1A1A')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
          .constraintSize({ maxWidth: '85%' })
      }
    }
    .width('100%')
    .alignItems(this.msg.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
  }
}

@Entry
@Component
struct ChatPage {
  @State messages: ChatMessage[] = []
  @State draft: string = ''
  @State busy: boolean = false
  @State status: string = ''
  private scroller: Scroller = new Scroller()
  private skillPrompt: string = ''
  private nextId: number = 1
  private lastScrollAt: number = 0
  /** Widget builds run one at a time: the DeepSeek engine has a single generation in flight. */
  private buildQueue: Promise<void> = Promise.resolve()

  aboutToAppear(): void {
    settings.init(getContext(this).filesDir)
    consent.init(getContext(this).filesDir)
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.loadResources()
  }

  onPageShow(): void {
    if (!settings.hasApiKey()) {
      this.status = 'No DeepSeek API key yet (see CLAUDE.md)'
    } else if (this.status.startsWith('No DeepSeek')) {
      this.status = ''
    }
  }

  private async loadResources(): Promise<void> {
    try {
      let mgr = getContext(this).resourceManager
      loadCatalogFile(getContext(this).filesDir)
      let skill = await loadRawfileText(mgr, 'vera-skill.txt')
      // The widget section goes last so it can say which parts of the skill it
      // overrides; it describes a widget in a chat bubble rather than an app.
      let widget = await loadRawfileText(mgr, 'vera-widget.txt')
      this.skillPrompt = skill
        .replace('{{UI_CATALOG}}', describeCatalogForPrompt())
        .replace('{{UI_TOOL_NOTE}}\n', '') + widget
      // The widget builder looks platform calls up mid-generation, as the
      // Generate screen's does; both indexes have to be loaded for that.
      loadRegistry()
      loadSdkIndex(mgr)
    } catch (e) {
      this.status = 'Failed to load resources: ' + (e as Error).message
    }
  }

  private scrollDown(force: boolean = false): void {
    let now = Date.now()
    if (!force && now - this.lastScrollAt < SCROLL_EVERY_MS) { return }
    this.lastScrollAt = now
    setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom) }, 60)
  }

  private history(): ChatTurn[] {
    let turns: ChatTurn[] = []
    for (let m of this.messages) {
      let text = m.before
      if (m.appDescription.length > 0 && m.role === 'assistant') {
        text = text + '\n[a widget was shown here: ' + m.appDescription + ']'
      }
      if (m.after.length > 0) { text = text + '\n' + m.after }
      if (text.trim().length === 0) { continue }
      let t = new ChatTurn()
      t.role = m.role
      t.text = text.trim()
      turns.push(t)
    }
    return turns
  }

  /** Copies what has streamed so far into the message; starts the widget the moment its line is closed. */
  private apply(msg: ChatMessage, parsed: ParsedReply): void {
    msg.before = parsed.before
    msg.after = parsed.after
    if (msg.appState === APP_NONE && parsed.describing) {
      msg.appState = APP_DESCRIBING
    }
    if (parsed.appDescription.length > 0 && msg.appDescription.length === 0) {
      msg.appDescription = parsed.appDescription
      msg.appState = APP_BUILDING
      console.info('VERA-CHAT widget line: ' + msg.appDescription)
      this.queueBuild(msg)
    }
    this.scrollDown()
  }

  private async send(): Promise<void> {
    let text = this.draft.trim()
    if (text.length === 0 || this.busy) { return }
    this.draft = ''
    this.busy = true
    let mine = new ChatMessage()
    mine.id = this.nextId++
    mine.role = 'user'
    mine.before = text
    this.messages = [...this.messages, mine]
    let turns = this.history()
    let reply = new ChatMessage()
    reply.id = this.nextId++
    reply.role = 'assistant'
    this.messages = [...this.messages, reply]
    this.scrollDown(true)
    this.status = 'Thinking...'
    try {
      let raw = await chatReply(turns, (soFar: string): void => {
        if (this.status === 'Thinking...') { this.status = '' }
        this.apply(reply, parseReply(soFar))
      })
      console.info('VERA-CHAT reply: ' + raw)
      this.apply(reply, parseReply(raw))
    } catch (e) {
      this.status = (e as Error).message
      // A reply that never started is not worth an empty row.
      if (reply.before.length === 0 && reply.appState === APP_NONE) {
        this.messages = this.messages.filter((m: ChatMessage): boolean => m.id !== reply.id)
      }
    }
    this.busy = false
    this.scrollDown(true)
  }

  private queueBuild(msg: ChatMessage): void {
    this.buildQueue = this.buildQueue.then(async (): Promise<void> => {
      let app: MiniApp = await buildMiniApp(this.skillPrompt, msg.appDescription, (s: string): void => {
        this.status = s
      })
      if (app.error.length === 0 && app.vbc2.length > 0) {
        msg.vbc2 = app.vbc2
        msg.appState = APP_READY
      } else {
        msg.error = app.error
        msg.appState = APP_FAILED
      }
      this.status = ''
      this.scrollDown(true)
    })
  }

  build() {
    Navigation() {
      Column() {
        List({ space: 10, scroller: this.scroller }) {
          ForEach(this.messages, (m: ChatMessage) => {
            ListItem() {
              MessageBubble({ msg: m })
            }
          }, (m: ChatMessage) => m.id.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .scrollBar(BarState.Off)

        if (this.status.length > 0) {
          Text(this.status).fontSize(12).fontColor('#888888').width('100%').padding({ left: 16, right: 16, bottom: 4 })
        }

        Row({ space: 8 }) {
          TextInput({ placeholder: 'Message', text: this.draft })
            .onChange((value: string) => {
              this.draft = value
              // The key can arrive while this page is open, and onPageShow does not fire for that.
              if (this.status.startsWith('No DeepSeek') && settings.hasApiKey()) { this.status = '' }
            })
            .onSubmit(() => { this.send() })
            .layoutWeight(1)
            .height(44)
          Button('Send')
            .type(ButtonType.Normal)
            .borderRadius(10)
            .enabled(!this.busy && this.draft.trim().length > 0)
            .onClick(() => { this.send() })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 10 })
        .backgroundColor('#FFFFFF')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F3F4F7')
    }
    .title('Chat')
    .titleMode(NavigationTitleMode.Mini)
  }
}
