import { store, Project } from '../vera/ProjectStore'
import { formBindings } from '../vera/FormBindings'
import { bindLiveForm } from '../vera/LiveWidgetPublish'
import { projectIconResource } from '../vera/ProjectIcons'
import { app } from '../components/AppStyle'
import { tileTint } from '../components/ProjectRows'
import { AppRouteParams, returnToLibrary } from '../vera/AppNavigation'
import { settingsMenuItem } from '../components/SettingsEntry'
import { widgetStatus, WIDGET_READY, WIDGET_NONE, WIDGET_NEEDS_RUN } from '../vera/WidgetStatus'

/** A project in the list, with what its widget is: the card draws the latest version (LiveFormService). */
class BindRow {
  project: Project
  kind: string
  latestId: string

  constructor(project: Project, kind: string, latestId: string) {
    this.project = project
    this.kind = kind
    this.latestId = latestId
  }
}

/**
 * A live card with no app yet, opened by tapping it: the apps with a widget, one tap to bind one; and the apps without
 * one, one tap to make it -- the widget screen then puts it on this card.
 */
@Component
export struct WidgetBindPage {
  params: AppRouteParams = new AppRouteParams()
  @Consume('navPathStack') pathStack: NavPathStack

  @State ready: BindRow[] = []
  @State others: BindRow[] = []
  @State error: string = ''

  aboutToAppear(): void {
    let context = this.getUIContext().getHostContext()
    if (context === undefined) { throw new Error('Widget binding host context is unavailable') }
    store.init(context.filesDir)
    formBindings.init(context.filesDir)
    let rows = store.listProjects().map((project: Project): BindRow => {
      let latest = store.getLatestVersion(project.id)
      let status = widgetStatus(latest !== null ? latest.source : '', latest !== null ? latest.vbc2 : '', 0)
      return new BindRow(project, status.kind, latest !== null ? latest.id : '')
    })
    // The apps worked on last first, as in the library; the ones that cannot have a widget after those that can.
    let recent = (row: BindRow): number => store.summaryOf(row.project).updatedAt
    rows.sort((a: BindRow, b: BindRow): number => recent(b) - recent(a))
    this.ready = rows.filter((row: BindRow): boolean => row.kind === WIDGET_READY)
    let others = rows.filter((row: BindRow): boolean => row.kind !== WIDGET_READY)
    this.others = others.filter((row: BindRow): boolean => row.kind === WIDGET_NONE)
      .concat(others.filter((row: BindRow): boolean => row.kind !== WIDGET_NONE))
  }

  private async bind(project: Project): Promise<void> {
    try {
      await bindLiveForm(this.params.formId, project.id)
      // Opened from the card, possibly as the only page: the library is what is left under it.
      returnToLibrary(this.pathStack)
    } catch (e) { this.error = (e as Error).message }
  }

  /** No widget yet: make one, for this card. */
  private make(row: BindRow): void {
    if (row.kind !== WIDGET_NONE) { return }
    let p = new AppRouteParams()
    p.projectId = row.project.id
    p.baseVersionId = row.latestId
    p.makeWidget = '1'
    p.formId = this.params.formId
    this.pathStack.pushPath({ name: 'generate', param: p })
  }

  private note(kind: string): string {
    if (kind === WIDGET_NONE) { return 'Make' }
    if (kind === WIDGET_NEEDS_RUN) { return 'Not ready' }
    return 'Not available'
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        if (this.ready.length === 0 && this.others.length === 0) {
          Text('No apps yet. Make an app first, then its widget.')
            .fontSize(15).fontColor(app.inkMuted).width('100%')
        }
        if (this.error.length > 0) { Text(this.error).fontSize(14).fontColor(app.warningInk).width('100%') }
        List({ space: 10 }) {
          if (this.ready.length > 0) {
            ListItem() { this.heading('With a widget') }
            ForEach(this.ready, (row: BindRow) => {
              ListItem() { this.row(row, '') }
            }, (row: BindRow) => 'ready-' + row.project.id)
          }
          if (this.others.length > 0) {
            ListItem() { this.heading('No widget yet — tap to make one') }
            ForEach(this.others, (row: BindRow) => {
              ListItem() { this.row(row, this.note(row.kind)) }
            }, (row: BindRow) => 'other-' + row.project.id)
          }
        }.width('100%').layoutWeight(1)
      }
      .width('100%').height('100%').padding(16)
    }
    .title('Choose an app for this widget')
    .menus([settingsMenuItem(this.pathStack)])
    .backgroundColor(app.background)
  }

  @Builder
  heading(text: string) {
    Text(text).fontSize(13).fontWeight(FontWeight.Medium).fontColor(app.inkMuted).width('100%')
      .padding({ top: 6, left: 4 })
  }

  @Builder
  row(row: BindRow, note: string) {
    Row({ space: 14 }) {
      Image(projectIconResource(row.project.icon)).objectFit(ImageFit.Contain)
        .width(40).height(40).padding(8).borderRadius(12).backgroundColor(tileTint(row.project.id))
      Text(row.project.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(app.inkStrong)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      if (note.length > 0) {
        Text(note).fontSize(13).fontColor(row.kind === WIDGET_NONE ? app.primaryInk : app.inkDisabled)
      }
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
        .fontColor([row.kind === WIDGET_READY || row.kind === WIDGET_NONE ? app.inkMuted : app.inkDisabled])
    }
    .width('100%').padding(12).backgroundColor(app.surface).borderRadius(12)
    .opacity(row.kind === WIDGET_READY || row.kind === WIDGET_NONE ? 1 : 0.6)
    .onClick(() => { if (row.kind === WIDGET_READY) { this.bind(row.project) } else { this.make(row) } })
  }
}
