// The launcher's live card. It draws what the form extension sends (the frame, widget/CardModel.ets) with the layout the app's Widget tab also uses
// (widget/CardView.ets); it loads the theme and the painter, never the VM.
import { CardNode, normalizeNodes } from '../CardModel'
import { CardView } from '../CardView'

let liveStorage = new LocalStorage()

@Entry(liveStorage)
@Component
struct LiveCard {
  @LocalStorageProp('formId') formId: string = ''
  @LocalStorageProp('projectId') projectId: string = ''
  @LocalStorageProp('title') title: string = 'VERA app'
  @LocalStorageProp('icon') icon: string = '📱'
  @LocalStorageProp('token') token: string = ''
  @LocalStorageProp('seq') seq: string = ''
  @LocalStorageProp('status') status: string = ''
  @LocalStorageProp('live') live: boolean = false
  @LocalStorageProp('background') cardBackground: string = '#F8FAFC'
  @LocalStorageProp('preset') preset: string = 'clean'
  @LocalStorageProp('primary') primary: string = ''
  @LocalStorageProp('nodes') nodes: CardNode[] = []

  build() {
    // A live widget has the whole card: no title strip with the app's name. A tap anywhere but on a button opens the app
    // (an unbound card: the page that binds it); a button's own tap is the button's.
    Column({ space: 6 }) {
      if (this.live) {
        CardView({
          nodes: normalizeNodes(this.nodes),
          // A refused tap is answered with the same token and seq: nothing is drawn again, so a touched Motion does not play.
          frameKey: this.token + this.seq,
          preset: this.preset,
          primary: this.primary,
          onTap: (action: string, value: number): void => {
            postCardAction(this, { action: 'message', params: { token: this.token, seq: this.seq, handler: action, value: value } })
          },
          onSwitch: (handler: string, on: boolean): void => {
            postCardAction(this, { action: 'message', params: { token: this.token, seq: this.seq, handler: handler, on: on } })
          },
          onPoint: (handler: string, x: number, y: number): void => {
            postCardAction(this, { action: 'message', params: { token: this.token, seq: this.seq, handler: handler, x: x, y: y } })
          }
        })
      } else {
        Text(this.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#475569')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.icon).fontSize(32)
      }
      if (this.status.length > 0) {
        Text(this.status).fontSize(11).fontColor('#64748B').maxLines(2)
      }
    }
    .width('100%').height('100%').padding(12).backgroundColor(this.cardBackground)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { projectId: this.projectId, veraRun: '1', veraFormId: this.projectId.length === 0 ? this.formId : '' } })
    })
  }
}
