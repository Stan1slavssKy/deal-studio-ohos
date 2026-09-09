import UIAbility from '@ohos.app.ability.UIAbility'
import Want from '@ohos.app.ability.Want'
import AbilityConstant from '@ohos.app.ability.AbilityConstant'
import window from '@ohos.window'
import hilog from '@ohos.hilog'
import router from '@ohos.router'

const DOMAIN = 0x0000

class ProjectNavParams {
  projectId: string = ''
}

export default class EntryAbility extends UIAbility {
  private pendingProjectId: string = ''

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onCreate')
    this.extractProjectId(want)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onNewWant')
    this.extractProjectId(want)
    if (this.pendingProjectId.length > 0) {
      this.navigateToProject()
    }
  }

  private extractProjectId(want: Want): void {
    if (want.parameters !== null && want.parameters !== undefined) {
      let params = want.parameters as Record<string, Object>
      let id = params['projectId']
      if (id !== null && id !== undefined && typeof id === 'string') {
        this.pendingProjectId = id as string
        hilog.info(DOMAIN, 'VERA', 'Launch with projectId: ' + this.pendingProjectId)
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onWindowStageCreate')
    windowStage.loadContent('pages/Index', (err): void => {
      if (err?.code) {
        hilog.error(DOMAIN, 'VERA', 'loadContent failed')
        return
      }
      hilog.info(DOMAIN, 'VERA', 'loadContent ok')
      if (this.pendingProjectId.length > 0) {
        setTimeout(() => { this.navigateToProject() }, 100)
      }
    })
  }

  private navigateToProject(): void {
    if (this.pendingProjectId.length === 0) { return }
    let projectId = this.pendingProjectId
    this.pendingProjectId = ''
    try {
      let p = new ProjectNavParams()
      p.projectId = projectId
      router.pushUrl({ url: 'pages/ProjectPage', params: p })
    } catch (e) {
      hilog.error(DOMAIN, 'VERA', 'Navigate to project failed: ' + (e as Error).message)
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onDestroy')
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onBackground')
  }
}
