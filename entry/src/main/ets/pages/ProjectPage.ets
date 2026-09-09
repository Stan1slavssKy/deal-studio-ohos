import router from '@ohos.router'
import { Project, Version, store } from '../vera/ProjectStore'

class RunVersionParams {
  projectId: string = ''
  versionId: string = ''
  vbc2: string = ''
}

class GenerateNavParams {
  projectId: string = ''
  baseVersionId: string = ''
}

@Entry
@Component
struct ProjectPage {
  @State project: Project | null = null
  @State versions: Version[] = []
  @State projectId: string = ''

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, string>
    if (params !== null && params !== undefined) {
      this.projectId = params['projectId'] || ''
    }
    this.reload()
  }

  onPageShow(): void {
    this.reload()
  }

  private reload(): void {
    if (this.projectId.length === 0) { return }
    this.project = store.getProject(this.projectId)
    this.versions = store.listVersions(this.projectId)
  }

  build() {
    Navigation() {
      Column() {
        if (this.project !== null) {
          Row() {
            Text(this.project!.icon).fontSize(48).margin({ right: 16 })
            Column() {
              Text(this.project!.name).fontSize(22).fontWeight(FontWeight.Bold)
              Text(this.versions.length.toString() + ' version' + (this.versions.length !== 1 ? 's' : ''))
                .fontSize(14).fontColor('#999999').margin({ top: 4 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }
          .width('100%')
          .padding(16)

          Row({ space: 10 }) {
            Button('Generate')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .onClick(() => { this.openGenerate('') })
            Button('Run')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .enabled(this.versions.length > 0 && this.versions[0].vbc2.length > 0)
              .onClick(() => { this.runLatest() })
            Button('Pin')
              .type(ButtonType.Normal)
              .fontSize(14)
              .onClick(() => { this.pinToHome() })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 12 })

          Divider().color('#EEEEEE')

          List({ space: 1 }) {
            ForEach(this.versions, (v: Version, index: number) => {
              ListItem() {
                Row() {
                  Column() {
                    Row() {
                      Text('v' + (this.versions.length - index).toString())
                        .fontSize(15).fontWeight(FontWeight.Medium)
                      if (v.vbc2.length === 0) {
                        Text('needs compile')
                          .fontSize(11)
                          .fontColor('#FF9500')
                          .backgroundColor('#FFF3E0')
                          .borderRadius(4)
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .margin({ left: 8 })
                      }
                    }
                    if (v.note.length > 0) {
                      Text(v.note).fontSize(13).fontColor('#666666').margin({ top: 2 })
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    Text(new Date(v.createdAt).toLocaleString())
                      .fontSize(12).fontColor('#AAAAAA').margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column({ space: 8 }) {
                    if (v.vbc2.length > 0) {
                      Button('Run')
                        .type(ButtonType.Normal)
                        .height(32)
                        .fontSize(13)
                        .onClick(() => { this.runVersion(v) })
                    }
                    Button('Refine')
                      .type(ButtonType.Normal)
                      .height(32)
                      .fontSize(13)
                      .backgroundColor('#E0E0E0')
                      .fontColor('#333333')
                      .onClick(() => { this.openGenerate(v.id) })
                  }
                }
                .width('100%')
                .padding(14)
                .backgroundColor('#FFFFFF')
              }
              .swipeAction({
                end: {
                  builder: () => { this.deleteVersionAction(v) }
                }
              })
            }, (v: Version) => v.id)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }.width('100%').height('100%')
    }
    .title(this.project !== null ? this.project!.name : 'Project')
    .titleMode(NavigationTitleMode.Mini)
  }

  @Builder
  deleteVersionAction(v: Version) {
    Row() {
      Button('Delete')
        .backgroundColor('#FF3B30')
        .fontColor('#FFFFFF')
        .height('100%')
        .onClick(() => {
          store.deleteVersion(v.projectId, v.id)
          this.reload()
        })
    }.height('100%').padding({ left: 8 })
  }

  private runLatest(): void {
    if (this.versions.length === 0) { return }
    this.runVersion(this.versions[0])
  }

  private runVersion(v: Version): void {
    if (v.vbc2.length === 0) { return }
    let p = new RunVersionParams()
    p.projectId = v.projectId
    p.versionId = v.id
    p.vbc2 = v.vbc2
    router.pushUrl({ url: 'pages/RunnerPage', params: p })
  }

  private openGenerate(baseVersionId: string): void {
    let p = new GenerateNavParams()
    p.projectId = this.projectId
    p.baseVersionId = baseVersionId
    router.pushUrl({ url: 'pages/GeneratePage', params: p })
  }

  private pinToHome(): void {
    console.info('Shortcut pinning requires system API — not available for non-system apps')
  }
}
