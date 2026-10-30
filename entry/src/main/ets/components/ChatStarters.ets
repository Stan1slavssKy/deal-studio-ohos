import { app } from './AppStyle'

/** One ready-made first message: a short title and the prompt that is sent. */
export class ChatStarter {
  id: string = ''
  title: string = ''
  prompt: string = ''
  /** The group it is listed under; empty for a list that is not grouped. */
  category: string = ''

  constructor(id: string, title: string, prompt: string, category: string = '') {
    this.id = id
    this.title = title
    this.prompt = prompt
    this.category = category
  }
}

const LANG_ZH: string = 'zh'
const LANG_EN: string = 'en'

/** The starters an empty chat offers, in Chinese and English. See docs/demo-prompts.md. */
export const STARTERS_ZH: ChatStarter[] = [
  new ChatStarter('trip', '旅行计划', '我们一家三口要去西湖玩一天，帮忙计划行程。'),
  new ChatStarter('baby', '宝宝护理', '我宝宝发烧了，37.5度。帮我创建宝宝发热护理卡片与服务。'),
  new ChatStarter('pills', '吃药提醒', '帮我创建一张吃药卡，提醒我每天吃药。'),
]
export const STARTERS_EN: ChatStarter[] = [
  new ChatStarter('trip', 'Trip plan', 'We are a family of three going to West Lake for a day. Help us plan the itinerary.'),
  new ChatStarter('baby', 'Baby fever', 'My baby has a fever of 37.5°C. Create a baby fever care card and services for me.'),
  new ChatStarter('pills', 'Pills', 'Create a medicine card that reminds me to take my pills every day.'),
]

/** A ready-made request on the home screen: a card with a symbol on a tint, a title and a short hint. */
export class HomeStarter {
  id: string = ''
  title: string = ''
  hint: string = ''
  symbol: string = ''
  /** The card's pale background and the colour of its symbol. */
  tint: string = ''
  ink: string = ''
  prompt: string = ''

  constructor(id: string, title: string, hint: string, symbol: string, tint: string, ink: string, prompt: string) {
    this.id = id
    this.title = title
    this.hint = hint
    this.symbol = symbol
    this.tint = tint
    this.ink = ink
    this.prompt = prompt
  }
}

/** The three demos of docs/demo-prompts.md, the same prompts as STARTERS_EN; the home screen sends one in either mode. */
export const HOME_STARTERS: HomeStarter[] = [
  new HomeStarter('trip', 'Trip plan', 'A day at West Lake for three', 'sys.symbol.airplane', '#E8F1FF', '#0A59F7',
    STARTERS_EN[0].prompt),
  new HomeStarter('baby', 'Baby fever', '37.5°C: a care card', 'sys.symbol.thermometer', '#FFF0E6', '#E0601F',
    STARTERS_EN[1].prompt),
  new HomeStarter('pills', 'Pills', 'A daily reminder card', 'sys.symbol.drug', '#E7F6EE', '#1F9D6B',
    STARTERS_EN[2].prompt),
]

/**
 * The starters an empty Generate screen offers. English only: a prompt typed into the
 * generator is written in English whatever the person's language (CLAUDE.md), so there is
 * nothing to switch. Grouped by `category`. The first eight are the demos of docs/demo-prompts.md and the chat starters; the rest are short one-sentence briefs from the Pocket OS mock-up, picked because they need nothing the phone lacks (no camera, microphone, location or car).
 */
export const APP_STARTERS: ChatStarter[] = [
  new ChatStarter('istanbul', 'Istanbul layover',
    'Istanbul layover: I land at Istanbul Airport at 08:00 with 12 hours before my next flight. Plan the day hour by hour around the sights worth seeing, each stop with its name, how long to spend there and its coordinates, a button that starts navigation to it from the last stop I reached, a button that puts the stop in my phone\'s calendar with a reminder, and the latest time I must leave for the airport. Keep a note of which stops I actually reached, and give me a button that wipes every calendar event this app added and one that opens the phone\'s calendar.', 'Travel'),
  new ChatStarter('pills', 'Pill tracker',
    'Pill tracker: let me add a medicine with a name, the hour and minute to take it and whether it repeats every day; each one goes into the phone\'s calendar with a reminder, and the list below shows what is scheduled and what the calendar answered.', 'Life'),
  new ChatStarter('costs', 'Shared costs',
    'Shared costs between four friends, Anna, Ben, Carol and Dan: any of them sometimes pays for everyone. Let me pick who paid, enter the amount in dollars and cents and add it with a short note, and keep the list of all payments. Everything is split equally among the four. Show the total spent, each person\'s equal share, how much each one has paid so far, and each person\'s balance (positive means the others owe them, negative means they owe). Show who should pay whom to settle everything with the fewest transfers, and a bar chart of what each friend has paid. Give me a button to remove the last payment and one to start over.', 'Life'),
  new ChatStarter('shanghai', 'Shanghai layover',
    'Shanghai layover: I land at Pudong International Airport at 09:00 with 11 hours before my next flight. Plan the day hour by hour around the sights worth seeing, each stop with its name, how long to spend there and its coordinates, a button that starts navigation to it from the last stop I reached, a button that puts the stop in my phone\'s calendar with a reminder, and the latest time I must leave for the airport. Keep a note of which stops I actually reached, and give me a button that wipes every calendar event this app added and one that opens the phone\'s calendar.', 'Travel'),
  new ChatStarter('winddown', 'Wind down',
    'I\'m in bed, don\'t know what to do, create an app for me', 'Life'),
  new ChatStarter('trip-plan', 'Trip plan',
    'We are a family of three going to West Lake for a day. Help us plan the itinerary.', 'Travel'),
  new ChatStarter('baby-fever', 'Baby fever',
    'My baby has a fever of 37.5°C. Create a baby fever care card and services for me.', 'Kids'),
  new ChatStarter('medicine-card', 'Medicine card',
    'Create a medicine card that reminds me to take my pills every day.', 'Life'),
  new ChatStarter('water', 'Water reminder',
    'Make a water tracker that logs a glass with one tap and never sends a notification while I am asleep.', 'Life'),
  new ChatStarter('pantry', 'Pantry expiry',
    'Make a pantry widget that tracks expiry dates and suggests two dinners from what is about to go off.', 'Life'),
  new ChatStarter('feeding', 'Feeding log',
    'Make a feeding tracker for a newborn that logs amount and time, then shows the next expected window.', 'Kids'),
  new ChatStarter('homework', 'Homework timer',
    'Make a homework timer that splits a task into 15-minute focus blocks with real breaks in between.', 'Kids'),
  new ChatStarter('chores', 'Chore stars',
    'Make a chore chart for two kids where stars are earned for tasks and redeemed for rewards we agree on.', 'Kids'),
  new ChatStarter('reading', 'Reading buddy',
    'Make a reading companion that tracks pages and keeps a streak, without turning stories into quizzes.', 'Kids'),
  new ChatStarter('service', 'Service log',
    'Make a vehicle service log that tracks mileage and tells me when the next visit is actually due.', 'Auto'),
  new ChatStarter('fuel', 'Fuel split',
    'Make a fuel cost widget that splits spend between work and private trips and shows cost per kilometre.', 'Auto'),
  new ChatStarter('filters', 'Filter tracker',
    'Make a filter tracker for the three filters in my flat, with a life ring for each and one shared reminder.', 'Auto'),
  new ChatStarter('2048', '2048',
    'Build a 2048 game with three undos per run and a board that stays readable at small sizes.', 'Games'),
  new ChatStarter('minesweeper', 'Minesweeper',
    'Make a calm minesweeper with a dark board, long-press flags and a hint after two mistakes.', 'Games'),
]

/** The language last picked, kept while the app runs so the next new chat opens in it. */
let starterLang: string = LANG_ZH

/**
 * What an empty screen shows: a list of starters; a tap hands one back. With both a Chinese
 * and an English list there is a switch between them; with only one there is none.
 * `flat` drops the card behind the list, for a place that is already a card.
 */
@Component
export struct ChatStarters {
  @State lang: string = starterLang
  @State category: string = ''
  zh: ChatStarter[] = []
  en: ChatStarter[] = []
  flat: boolean = false
  onPick: (prompt: string) => void = (_p: string): void => {}

  private switchable(): boolean {
    return this.zh.length > 0 && this.en.length > 0
  }

  private all(): ChatStarter[] {
    if (!this.switchable()) { return this.en.length > 0 ? this.en : this.zh }
    return this.lang === LANG_EN ? this.en : this.zh
  }

  /** The groups of the list in the order they first appear; none when it is not grouped. */
  private categories(): string[] {
    const out: string[] = []
    for (const s of this.all()) {
      if (s.category.length > 0 && out.indexOf(s.category) < 0) { out.push(s.category) }
    }
    return out
  }

  private shown(): ChatStarter[] {
    const all: ChatStarter[] = this.all()
    if (this.category.length === 0) { return all }
    return all.filter((s: ChatStarter): boolean => s.category === this.category)
  }

  private english(): boolean {
    return !this.switchable() ? this.en.length > 0 : this.lang === LANG_EN
  }

  private setLang(lang: string): void {
    starterLang = lang
    this.lang = lang
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.english() ? 'Try one of these' : '试试这些')
          .fontSize(13).fontColor(app.inkMuted).layoutWeight(1)
        if (this.switchable()) {
          this.langChip('EN', LANG_EN)
          this.langChip('中文', LANG_ZH)
        }
      }
      .width('100%')
      .padding({ left: 4 })

      if (this.categories().length > 1) {
        Scroll() {
          Row() {
            this.categoryChip('All', '')
            ForEach(this.categories(), (c: string) => {
              this.categoryChip(c, c)
            }, (c: string) => c)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }

      Column() {
        ForEach(this.shown(), (s: ChatStarter, i: number) => {
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
      .backgroundColor(this.flat ? Color.Transparent : app.surface)
      .borderRadius(12)
      .shadow(this.flat ? { radius: 0 } : { radius: 2, color: '#10000000', offsetY: 1 })
      .clip(true)
    }
    .width('100%')
    .padding({ top: 8 })
  }

  @Builder
  categoryChip(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.category === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.category === value ? app.primaryInk : app.inkMuted)
      .backgroundColor(this.category === value ? app.primaryFill : app.surface)
      .borderRadius(14)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: 6 })
      .onClick(() => { this.category = value })
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
