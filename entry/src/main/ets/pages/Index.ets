import { Project, ProjectSummary, store } from '../vera/ProjectStore'
import { versionCountText } from '../vera/ProjectText'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { projectOperations, ProjectOperationStatus } from '../vera/ProjectOperations'
import { consent } from '../vera/VeraConsentStore'
import { refreshForms } from '../vera/FormUpdater'
import { projectIconResource } from '../vera/ProjectIcons'
import { common } from '@kit.AbilityKit'
import { app, PrimaryButton, DangerButton } from '../components/AppStyle'
import { VeraPreview } from '../components/VeraPreview'

class ProjectNavParams {
  projectId: string = ''
}

/** A project and what its row shows of it. */
class ProjectRow {
  project: Project = new Project()
  summary: ProjectSummary = new ProjectSummary()
}

/** The rows, handed to a LazyForEach so only the ones on screen build their picture. */
class RowSource implements IDataSource {
  rows: ProjectRow[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number { return this.rows.length }
  getData(index: number): ProjectRow { return this.rows[index] }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener) }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at = this.listeners.indexOf(listener)
    if (at >= 0) { this.listeners.splice(at, 1) }
  }
  replace(rows: ProjectRow[]): void {
    this.rows = rows
    for (const l of this.listeners) { l.onDataReloaded() }
  }
}

/** How tall the picture of a program is on its row, in vp; the program is drawn at twice this, then halved. */
const THUMB_HEIGHT: number = 150

@Entry
@Component
struct Index {
  @State projects: ProjectRow[] = []
  private source: RowSource = new RowSource()
  @State deletionPending: boolean = false

  aboutToAppear(): void {
    let context = this.getUIContext().getHostContext()
    if (context === undefined) { throw new Error('Project library host context is unavailable') }
    store.init(context.filesDir)
    consent.init(context.filesDir)
    this.reload()
  }

  onPageShow(): void {
    this.reload()
  }

  /** Newest work first: by when a project's latest version was saved, or when it was made if it has none. */
  private reload(): void {
    let rows: ProjectRow[] = []
    for (let project of store.listProjects()) {
      let row = new ProjectRow()
      row.project = project
      row.summary = store.summaryOf(project)
      rows.push(row)
    }
    rows.sort((a: ProjectRow, b: ProjectRow): number => b.summary.updatedAt - a.summary.updatedAt)
    this.projects = rows
    this.source.replace(rows)
  }

  private openChat(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ChatPage' })
      .catch((e: Error): void => { console.error('Navigate to chats failed: ' + e.message) })
  }

  /**
   * A new app starts on the Generate screen with no project behind it: nothing is asked for
   * and nothing is made until the first Save, which offers a name taken from the program.
   */
  private openCreate(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/GeneratePage' })
      .catch((e: Error): void => { console.error('Navigate to generate failed: ' + e.message) })
  }

  build() {
    Stack() {
      Navigation() {
        List({ space: 12 }) {
          // The two things to do: talk, or make an app. Everything made so far is listed below.
          ListItem() {
            Row({ space: 12 }) {
              this.entryCard('Chat', 'Ask, plan, get a card', 'sys.symbol.ellipsis_message', false, () => { this.openChat() })
              this.entryCard('Create app', 'Describe it, run it', 'sys.symbol.plus', true, () => { this.openCreate() })
            }
            .width('100%')
          }
          if (this.projects.length > 0) {
            ListItem() {
              Text('My apps').fontSize(15).fontWeight(FontWeight.Medium).fontColor(app.inkSoft)
                .width('100%').padding({ left: 4, top: 8 })
            }
          }
          LazyForEach(this.source, (row: ProjectRow) => {
            ListItem() {
              this.projectRow(row)
            }
            .swipeAction({
              end: {
                builder: () => { this.deleteAction(row.project.id) }
              }
            })
          // Keyed by what a row shows, so a rename, a new picture or a saved version redraws it.
          }, (row: ProjectRow) => row.project.id + '|' + row.project.name + '|' + row.project.icon + '|' +
            row.summary.versions.toString() + '|' + row.summary.updatedAt.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
        .scrollBar(BarState.Off)
      }
      .title(this.homeTitle)
      .titleMode(NavigationTitleMode.Mini)
      // The first screen: there is nowhere to go back to.
      .hideBackButton(true)
      .backgroundColor(app.background)
    }
    .width('100%')
    .height('100%')
  }

  /** One of the two ways in: a tall card, the primary one filled. */
  @Builder
  entryCard(title: string, hint: string, symbol: string, primary: boolean, go: () => void) {
    Column({ space: 6 }) {
      SymbolGlyph($r(symbol)).fontSize(30).fontColor([primary ? app.onPrimary : app.primaryInk])
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(primary ? app.onPrimary : app.inkStrong)
        .margin({ top: 8 })
      Text(hint).fontSize(13).fontColor(primary ? app.onPrimary : app.inkSoft).opacity(primary ? 0.85 : 1)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(16)
    .height(130)
    .justifyContent(FlexAlign.End)
    .borderRadius(16)
    .backgroundColor(primary ? app.primary : app.surface)
    .shadow({ radius: 2, color: '#10000000', offsetY: 1 })
    .onClick(go)
  }

  /**
   * One project: a still picture of its latest program on top, then what it is (the request it
   * began as), how much work is in it, and when it was last worked on. A project with no program
   * that runs has the picture left out.
   */
  @Builder
  projectRow(row: ProjectRow) {
    Column() {
      if (row.summary.vbc2.length > 0) {
        this.thumbnail(row.summary.vbc2)
      }
      Row() {
        Image(projectIconResource(row.project.icon))
          .width(44).height(44).objectFit(ImageFit.Contain).margin({ right: 14 })
        Column({ space: 2 }) {
          Text(row.project.name).fontSize(17).fontWeight(FontWeight.Medium).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (row.summary.request.length > 0) {
            Text(row.summary.request).fontSize(13).fontColor(app.inkSoft).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(versionCountText(row.summary.versions) + ' · ' + new Date(row.summary.updatedAt).toLocaleDateString())
            .fontSize(12).fontColor(app.inkMuted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([app.inkDisabled])
      }
      .width('100%')
      .padding(14)
    }
    .width('100%')
    .backgroundColor(app.surface)
    .borderRadius(12)
    .clip(true)
    .shadow({ radius: 2, color: '#10000000', offsetY: 1 })
    .onClick(() => {
      let nav = new ProjectNavParams()
      nav.projectId = row.project.id
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ProjectPage', params: nav })
        .catch((e: Error): void => { console.error('Navigate to project failed: ' + e.message) })
    })
    // A swipe is not a thing anyone is told about: the press that opens a menu is.
    .bindContextMenu(this.rowMenu(row.project.id), ResponseType.LongPress)
  }

  /**
   * The program as it starts, drawn by the same renderer with taps and timers off (previewOnly), at
   * twice the width and half the size so a whole screen's worth of it fits in a short strip.
   */
  @Builder
  thumbnail(vbc2: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      VeraPreview({ previewOnly: true, embedded: true, vbc2: vbc2 })
        .width('200%')
        .scale({ x: 0.5, y: 0.5, centerX: 0, centerY: 0 })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(THUMB_HEIGHT)
    .clip(true)
    .backgroundColor(app.background)
  }

  @Builder
  rowMenu(id: string) {
    Menu() {
      MenuItem({ content: 'Delete project', symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')) })
        .onClick(() => { this.confirmDelete(id) })
    }
  }

  /** A compact bar, as on the other screens: a small mark and what the screen holds. */
  @Builder
  homeTitle() {
    Row({ space: 8 }) {
      Image($r('app.media.vera_mark')).width(28).height(28).objectFit(ImageFit.Contain)
      Text('VERA').fontSize(20).fontWeight(FontWeight.Bold).fontColor(app.inkStrong)
    }
    .padding({ left: 16 })
  }

  @Builder
  deleteAction(id: string) {
    Row() {
      Button('Delete')
        .attributeModifier(new DangerButton())
        .height('100%')
        .enabled(!this.deletionPending)
        .onClick(() => { this.confirmDelete(id) })
    }.height('100%').padding({ left: 8 })
  }

  private confirmDelete(id: string): void {
    let project = store.getProject(id)
    if (project === null) { return }
    this.getUIContext().showAlertDialog({
      title: 'Delete mini-app?',
      message: 'Delete "' + project.name + '" and all its saved versions and data? This cannot be undone.',
      primaryButton: {
        value: 'Cancel',
        action: () => {}
      },
      secondaryButton: {
        value: 'Delete',
        fontColor: app.danger,
        action: () => { this.doDelete(id) }
      }
    })
  }

  private async doDelete(id: string): Promise<void> {
    if (this.deletionPending) { return }
    this.deletionPending = true
    let context = (): common.UIAbilityContext => this.getUIContext().getHostContext() as common.UIAbilityContext
    const status = await projectOperations.deleteProject(context, id)
    this.deletionPending = false
    this.reload()
    refreshForms()
    if (status !== ProjectOperationStatus.Success) {
      const message = status === ProjectOperationStatus.ProjectDeletedShortcutRemovalFailed ?
        'Mini-application was deleted, but its shortcut cannot be removed.' : 'Error deleting mini-app.'
      try {
        this.getUIContext().getPromptAction().showToast({ message: message })
      } catch (toastError) {
        console.error('Show deletion error failed: ' + (toastError as Error).message)
      }
    }
  }
}
