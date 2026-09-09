import router from '@ohos.router'
import { VirtualMachine, deserializeVbc2, RuntimeValue, VeraIntValue } from '../vera/VeraInterpreter'
import { UiHostEnvironment, VeraUiNode, decodeVeraUi } from '../vera/VeraUi'

@Entry
@Component
struct RunnerPage {
  @State uiRoot: VeraUiNode | null = null
  @State revision: number = 0
  @State error: string = ''
  private vm: VirtualMachine | null = null
  private currentState: RuntimeValue | null = null

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, string>
    if (params === null || params === undefined) { this.error = 'No parameters'; return }
    let vbc2 = params['vbc2'] || ''
    if (vbc2.length === 0) { this.error = 'No VBC2 bytecode'; return }
    try {
      let host = new UiHostEnvironment()
      let module = deserializeVbc2(vbc2)
      this.vm = new VirtualMachine(module, host)
      this.currentState = this.vm!.execute('init')
      this.renderView()
    } catch (e) {
      this.error = 'Init error: ' + (e as Error).message
    }
  }

  private renderView(): void {
    if (this.vm === null || this.currentState === null) { return }
    try {
      let viewTree = this.vm!.execute('view', [this.currentState!])
      let nodes = decodeVeraUi(viewTree)
      let root = nodes.length > 0 ? nodes[0] : null
      console.info('VERA-VIEW rev=' + (this.revision + 1).toString() +
        ' root=' + (root !== null ? root!.kind : 'null') +
        ' children=' + (root !== null ? root!.children.length.toString() : '0'))
      this.uiRoot = root
      this.revision += 1
    } catch (e) {
      this.error = 'View error: ' + (e as Error).message
    }
  }

  private handleAction(action: string, value: number): void {
    console.info('VERA-CLICK action=' + action + ' value=' + value.toString() + ' rev=' + this.revision.toString())
    if (this.vm === null || this.currentState === null) { return }
    let t0 = Date.now()
    try {
      this.currentState = this.vm!.execute(action, [this.currentState!, new VeraIntValue(value)])
      console.info('VERA-ACTION ' + action + ' steps=' + this.vm!.stepsExecuted().toString() +
        ' ms=' + (Date.now() - t0).toString())
      this.renderView()
    } catch (e) {
      console.error('VERA-ACTION ' + action + ' TRAP steps=' + this.vm!.stepsExecuted().toString() +
        ' ms=' + (Date.now() - t0).toString() + ' err=' + (e as Error).message)
      this.error = 'Action error: ' + (e as Error).message
    }
  }

  build() {
    Navigation() {
      Column() {
        if (this.error.length > 0) {
          Text(this.error)
            .fontSize(14)
            .fontColor('#CC0000')
            .padding(16)
            .width('100%')
            .backgroundColor('#FFECEC')
        }
        if (this.uiRoot !== null) {
          Scroll() {
            Column() {
              ForEach([this.revision], (_: number) => {
                this.renderNode(this.uiRoot!, 'root')
              }, (r: number) => r.toString())
            }.width('100%')
          }
          .width('100%')
          .layoutWeight(1)
        }
      }.width('100%').height('100%')
    }
    .title('App')
    .titleMode(NavigationTitleMode.Mini)
  }

  @Builder
  renderChildren(node: VeraUiNode) {
    ForEach(node.children, (child: VeraUiNode) => {
      this.renderNode(child, node.kind)
    }, (child: VeraUiNode) => child.id.toString() + '-' + this.revision.toString())
  }

  @Builder
  renderNode(node: VeraUiNode, parentKind: string) {
    if (node.kind === 'column' || node.kind === 'scroll') {
      Column() {
        this.renderChildren(node)
      }
      .width('100%')
      .alignItems(node.style === 'center' ? HorizontalAlign.Center : HorizontalAlign.Start)
      .padding(node.style === 'compact' ? 6 : node.style === 'spacious' ? 16 : 10)
      .backgroundColor(
        node.style === 'surface' ? '#F3F6FA' :
          node.style === 'accent' ? '#EBF0FF' : '#00000000')
    } else if (node.kind === 'row') {
      Row({ space: node.style === 'compact' ? 4 : node.style === 'spacious' ? 12 : 8 }) {
        this.renderChildren(node)
      }
      .width('100%')
      .justifyContent(node.style === 'split' ? FlexAlign.SpaceBetween :
        node.style === 'center' ? FlexAlign.Center : FlexAlign.Start)
      .padding(6)
      .backgroundColor(
        node.style === 'surface' ? '#F3F6FA' :
          node.style === 'accent' ? '#EBF0FF' : '#00000000')
    } else if (node.kind === 'card') {
      Column() {
        this.renderChildren(node)
      }
      .width(parentKind === 'row' ? undefined : '100%')
      .layoutWeight(parentKind === 'row' ? 1 : 0)
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .backgroundColor(
        node.style === 'accent' ? '#EBF0FF' :
          node.style === 'success' ? '#E8F8E8' :
            node.style === 'warning' ? '#FFF8E0' :
              node.style === 'danger' ? '#FFECEC' : '#F3F6FA')
      .border({ width: 1, color: '#D8E1ED' })
      .borderRadius(14)
    } else if (node.kind === 'text') {
      Text(node.text)
        .fontSize(
          node.style === 'title' ? 24 :
            node.style === 'heading' ? 18 :
              node.style === 'metric' ? 32 :
                node.style === 'caption' ? 12 : 15)
        .fontWeight(
          node.style === 'title' ? FontWeight.Bold :
            node.style === 'heading' ? FontWeight.Medium :
              node.style === 'metric' ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(
          node.style === 'muted' ? '#888888' :
            node.style === 'success' ? '#2E7D32' :
              node.style === 'warning' ? '#E65100' :
                node.style === 'danger' ? '#C62828' : '#000000')
        .width('100%')
        .padding({ top: 2, bottom: 2 })
    } else if (node.kind === 'button') {
      Button(node.text.length === 0 ? ' ' : node.text)
        .height(44)
        .fontSize(15)
        .enabled(node.enabled)
        .type(node.style === 'secondary' ? ButtonType.Normal : ButtonType.Capsule)
        .backgroundColor(
          node.style === 'success' ? '#4CAF50' :
            node.style === 'danger' ? '#F44336' :
              node.style === 'secondary' ? '#E0E0E0' : '#007DFF')
        .fontColor(node.style === 'secondary' ? '#333333' : '#FFFFFF')
        .onClick(() => {
          if (node.action.length > 0 && node.enabled) {
            this.handleAction(node.action, node.eventValue)
          }
        })
    } else if (node.kind === 'cell') {
      Column() {
        Text(node.text).fontSize(22).fontWeight(FontWeight.Bold)
          .fontColor(node.enabled ? '#333333' : '#CCCCCC')
      }
      .layoutWeight(1)
      .height(68)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(node.enabled ? '#FFFFFF' : '#F5F5F5')
      .border({
        width: node.style === 'accent' ? 2 : 1,
        color: node.style === 'accent' ? '#007DFF' :
          node.style === 'success' ? '#4CAF50' :
            node.style === 'danger' ? '#F44336' : '#CBD6E4'
      })
      .borderRadius(10)
      .onClick(() => {
        if (node.action.length > 0 && node.enabled) {
          this.handleAction(node.action, node.eventValue)
        }
      })
    } else if (node.kind === 'spacer') {
      if (node.style !== 'none') {
        Blank().height(node.style === 'large' ? 32 : node.style === 'small' ? 8 : 18)
      }
    } else {
      Text(node.text).fontSize(14).width('100%')
    }
  }
}
