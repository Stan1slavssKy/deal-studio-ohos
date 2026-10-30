import { store } from '../vera/ProjectStore'
import { versionCountText } from '../vera/ProjectText'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { projectIconResource } from '../vera/ProjectIcons'
import { app, DangerButton } from '../components/AppStyle'
import { VeraPreview } from '../components/VeraPreview'
import { ProjectNavParams, ProjectRow, RowSource, loadProjectRows, confirmDeleteProject } from '../components/ProjectRows'

/** How tall the picture of a program is on its row, in vp; the program is drawn at twice this, then halved. */
const THUMB_HEIGHT: number = 150

/** Every app made so far, each with a still picture of its latest program. Swipe or long press to delete. */
@Entry
@Component
struct AppsPage {
  @State projects: ProjectRow[] = []
  private source: RowSource = new RowSource()

  aboutToAppear(): void {
    let context = this.getUIContext().getHostContext()
    if (context === undefined) { throw new Error('Project library host context is unavailable') }
    store.init(context.filesDir)
    this.reload()
  }

  onPageShow(): void {
    this.reload()
  }

  private reload(): void {
    this.projects = loadProjectRows()
    this.source.replace(this.projects)
  }

  build() {
    Navigation() {
      List({ space: 12 }) {
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
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      .scrollBar(BarState.Off)
    }
    .title('My apps (' + this.projects.length.toString() + ')')
    .titleMode(NavigationTitleMode.Mini)
    .backgroundColor(app.background)
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
      // The strip cuts the program off wherever it falls: a fade to the card says it goes on, instead of a sliced row.
      Column()
        .width('100%')
        .height(56)
        .position({ x: 0, y: THUMB_HEIGHT - 56 })
        .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00F8FAFC', 0], [app.background, 1]] })
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
        .onClick(() => { confirmDeleteProject(this.getUIContext(), id, () => { this.reload() }) })
    }
  }

  @Builder
  deleteAction(id: string) {
    Row() {
      Button('Delete')
        .attributeModifier(new DangerButton())
        .height('100%')
        .onClick(() => { confirmDeleteProject(this.getUIContext(), id, () => { this.reload() }) })
    }.height('100%').padding({ left: 8 })
  }
}
