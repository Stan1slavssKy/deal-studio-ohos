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
const APP_BUILDING: string = 'building'
const APP_READY: string = 'ready'
const APP_FAILED: string = 'failed'
const APP_HEIGHT: number = 520

class ChatMessage {
  id: number = 0
  role: string = 'user'
  text: string = ''
  appDescription: string = ''
  appState: string = APP_NONE
  vbc2: string = ''
  error: string = ''
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
      this.skillPrompt = skill
        .replace('{{UI_CATALOG}}', describeCatalogForPrompt())
        .replace('{{UI_TOOL_NOTE}}\n', '')
      // The widget builder looks platform calls up mid-generation, as the
      // Generate screen's does; both indexes have to be loaded for that.
      loadRegistry()
      loadSdkIndex(mgr)
    } catch (e) {
      this.status = 'Failed to load resources: ' + (e as Error).message
    }
  }

  private add(msg: ChatMessage): void {
    this.messages = [...this.messages, msg]
    this.scrollDown()
  }

  /** Swaps one message for a changed copy so the list sees it; the key carries the state. */
  private replace(updated: ChatMessage): void {
    this.messages = this.messages.map((m: ChatMessage): ChatMessage => m.id === updated.id ? updated : m)
    this.scrollDown()
  }

  private scrollDown(): void {
    setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom) }, 60)
  }

  private history(): ChatTurn[] {
    let turns: ChatTurn[] = []
    for (let m of this.messages) {
      if (m.text.length === 0) { continue }
      let t = new ChatTurn()
      t.role = m.role
      t.text = m.appDescription.length > 0 && m.role === 'assistant' ?
        m.text + '\n[a widget was shown here: ' + m.appDescription + ']' : m.text
      turns.push(t)
    }
    return turns
  }

  private async send(): Promise<void> {
    let text = this.draft.trim()
    if (text.length === 0 || this.busy) { return }
    this.draft = ''
    this.busy = true
    let mine = new ChatMessage()
    mine.id = this.nextId++
    mine.role = 'user'
    mine.text = text
    this.add(mine)
    this.status = 'Thinking...'
    let parsed: ParsedReply
    try {
      parsed = parseReply(await chatReply(this.history()))
    } catch (e) {
      this.status = (e as Error).message
      this.busy = false
      return
    }
    let reply = new ChatMessage()
    reply.id = this.nextId++
    reply.role = 'assistant'
    reply.text = parsed.text
    reply.appDescription = parsed.appDescription
    reply.appState = parsed.appDescription.length > 0 ? APP_BUILDING : APP_NONE
    this.add(reply)
    this.status = ''
    this.busy = false
    if (reply.appState === APP_BUILDING) {
      this.queueBuild(reply)
    }
  }

  private queueBuild(msg: ChatMessage): void {
    this.buildQueue = this.buildQueue.then(async (): Promise<void> => {
      let app: MiniApp = await buildMiniApp(this.skillPrompt, msg.appDescription, (s: string): void => {
        this.status = s
      })
      let done = new ChatMessage()
      done.id = msg.id
      done.role = msg.role
      done.text = msg.text
      done.appDescription = msg.appDescription
      if (app.error.length === 0 && app.vbc2.length > 0) {
        done.appState = APP_READY
        done.vbc2 = app.vbc2
      } else {
        done.appState = APP_FAILED
        done.error = app.error
      }
      this.status = ''
      this.replace(done)
    })
  }

  build() {
    Navigation() {
      Column() {
        List({ space: 10, scroller: this.scroller }) {
          ForEach(this.messages, (m: ChatMessage) => {
            ListItem() {
              this.bubble(m)
            }
          }, (m: ChatMessage) => m.id.toString() + m.appState)
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

  @Builder
  bubble(m: ChatMessage) {
    Column({ space: 8 }) {
      if (m.text.length > 0) {
        Text(m.text)
          .fontSize(16)
          .fontColor(m.role === 'user' ? '#FFFFFF' : '#1A1A1A')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(m.role === 'user' ? '#2F6BFF' : '#FFFFFF')
          .borderRadius(14)
          .constraintSize({ maxWidth: '85%' })
      }
      if (m.appState === APP_BUILDING) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text('Building a widget...').fontSize(13).fontColor('#666666')
        }
        .padding(12)
        .backgroundColor('#FFFFFF')
        .borderRadius(14)
      } else if (m.appState === APP_READY) {
        VeraPreview({ vbc2: m.vbc2 })
          .width('100%')
          .height(APP_HEIGHT)
          .borderRadius(14)
          .clip(true)
          .backgroundColor('#FFFFFF')
      } else if (m.appState === APP_FAILED) {
        Text('The widget could not be built: ' + m.error.substring(0, 240))
          .fontSize(12)
          .fontColor('#B3261E')
          .padding(10)
          .backgroundColor('#FFECEC')
          .borderRadius(10)
      }
    }
    .width('100%')
    .alignItems(m.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
  }
}
