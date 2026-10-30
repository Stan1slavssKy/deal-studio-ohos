import { app } from './AppStyle'
import { projectIconResource } from '../vera/ProjectIcons'

/** The pictures an app can have; the first is the one a new app starts with. */
export const APP_ICONS: string[] = ['📱', '🎮', '📊', '🧮', '🎯',
  '📝', '🔧', '🎨', '🌍', '⚡']

/** A wrapped row of the app pictures; the chosen one is tinted, a tap hands another back. */
@Component
export struct IconPicker {
  @Prop selected: string = ''
  onPick: (icon: string) => void = (_i: string): void => {}

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(APP_ICONS, (icon: string) => {
        Image(projectIconResource(icon))
          .width(40)
          .height(40)
          .objectFit(ImageFit.Contain)
          .padding(6)
          .backgroundColor(this.selected === icon ? app.primaryFill : '#00000000')
          .borderRadius(8)
          .onClick(() => { this.onPick(icon) })
      }, (icon: string) => icon)
    }
    .width('100%')
  }
}
