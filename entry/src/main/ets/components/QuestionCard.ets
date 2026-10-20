/**
 * A blocking question from the agent (agent/AgentQuestions.ets): the question, its answers as buttons, the one the plan
 * was drawn for marked and first in focus. Used by the Generate screen above the preview and by the chat in the bubble
 * of the widget being built.
 */
@Component
export struct QuestionCard {
  @Prop question: string = ''
  @Prop options: string[] = []
  @Prop fallback: number = 0
  onPick: (index: number) => void = (_index: number): void => {}

  build() {
    Column({ space: 10 }) {
      Text(this.question)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1A1A1A')
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.options, (option: string, index: number) => {
          Button(index === this.fallback ? option + ' (suggested)' : option)
            .type(ButtonType.Capsule)
            .fontSize(14)
            .fontColor(index === this.fallback ? '#FFFFFF' : '#2F6BFF')
            .backgroundColor(index === this.fallback ? '#2F6BFF' : '#E8EEFF')
            .margin({ right: 8, bottom: 8 })
            .onClick(() => { this.onPick(index) })
        }, (option: string, index: number) => index.toString() + option)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#F3F6FF')
    .borderRadius(12)
  }
}
