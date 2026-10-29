import { app } from './AppStyle'

/** One ready-made first message: a short title and the prompt that is sent. */
export class ChatStarter {
  id: string = ''
  title: string = ''
  prompt: string = ''

  constructor(id: string, title: string, prompt: string) {
    this.id = id
    this.title = title
    this.prompt = prompt
  }
}

const LANG_ZH: string = 'zh'
const LANG_EN: string = 'en'

/** The starters an empty chat offers, in Chinese and English. See docs/demo-prompts.md. */
const STARTERS_ZH: ChatStarter[] = [
  new ChatStarter('trip', '旅行计划', '我们一家三口要去西湖玩一天，帮忙计划行程。'),
  new ChatStarter('baby', '宝宝护理', '我宝宝发烧了，37.5度。帮我创建宝宝发热护理卡片与服务。'),
  new ChatStarter('pills', '吃药提醒', '帮我创建一张吃药卡，提醒我每天吃药。'),
]
const STARTERS_EN: ChatStarter[] = [
  new ChatStarter('trip', 'Trip plan', 'We are a family of three going to West Lake for a day. Help us plan the itinerary.'),
  new ChatStarter('baby', 'Baby fever', 'My baby has a fever of 37.5°C. Create a baby fever care card and services for me.'),
  new ChatStarter('pills', 'Pills', 'Create a medicine card that reminds me to take my pills every day.'),
]

/** The language last picked, kept while the app runs so the next new chat opens in it. */
let starterLang: string = LANG_ZH

/** What an empty chat shows: a list of starters; a tap sends one as the first message. */
@Component
export struct ChatStarters {
  @State lang: string = starterLang
  onPick: (prompt: string) => void = (_p: string): void => {}

  private setLang(lang: string): void {
    starterLang = lang
    this.lang = lang
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.lang === LANG_EN ? 'Try one of these' : '试试这些')
          .fontSize(13).fontColor(app.inkMuted).layoutWeight(1)
        this.langChip('EN', LANG_EN)
        this.langChip('中文', LANG_ZH)
      }
      .width('100%')
      .padding({ left: 4 })

      Column() {
        ForEach(this.lang === LANG_EN ? STARTERS_EN : STARTERS_ZH, (s: ChatStarter, i: number) => {
          if (i > 0) {
            Divider().color(app.lineSoft).margin({ left: 14, right: 14 })
          }
          Column({ space: 2 }) {
            Text(s.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(app.inkStrong).maxLines(1)
            Text(s.prompt).fontSize(13).fontColor(app.inkMuted)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .onClick(() => { this.onPick(s.prompt) })
        }, (s: ChatStarter) => this.lang + '-' + s.id)
      }
      .width('100%')
      .backgroundColor(app.surface)
      .borderRadius(12)
      .shadow({ radius: 2, color: '#10000000', offsetY: 1 })
      .clip(true)
    }
    .width('100%')
    .padding({ top: 8 })
  }

  @Builder
  langChip(label: string, lang: string) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.lang === lang ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.lang === lang ? app.primaryInk : app.inkMuted)
      .backgroundColor(this.lang === lang ? app.primaryFill : Color.Transparent)
      .borderRadius(12)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .margin({ left: 4 })
      .onClick(() => { this.setLang(lang) })
  }
}
