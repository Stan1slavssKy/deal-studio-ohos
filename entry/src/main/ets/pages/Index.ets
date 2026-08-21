import hidebug from '@ohos.hidebug'
import { systemDateTime } from '@kit.BasicServicesKit'
import { RuntimeResult, VeraVM, parseBytecodeAssembly } from '../vera/VeraInterpreter'
import { VeraUiNode, decodeVeraUi } from '../vera/VeraUi'
import { DASHBOARD_VBC1, TICTACTOE_VBC1 } from '../vera/VeraPrograms'

/**
 * Times the whole VERA path on device: the paired half of webview-probe, which
 * loads the same two prompts as HTML into a WebView on the same phone.
 *
 * Phases are microsecond-scale -- parse + boot measured 435 us on an x86 host --
 * so timing uses nanosecond uptime. Millisecond resolution would floor every
 * phase to zero. The cold pass is reported separately from a warm iterated
 * average because the cold number is what a user actually pays when opening a
 * freshly generated program.
 *
 * uiBuildUs is the ArkUI construction term, from the state write to onAppear.
 * It is the number the host benchmark could only proxy from Blink.
 */

/** Nanoseconds since boot; monotonic, and fine enough for these phases. */
function nowNs(): number {
  return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, true)
}

interface Sample {
  label: string
  bytes: number
  parseUs: number
  bootUs: number
  renderUs: number
  decodeUs: number
  coldTotalUs: number
  warmTotalUs: number
  pssBaselineKb: number
  pssDeltaKb: number
  nodes: number
}

const REPS: number = 100

@Entry
@Component
struct Index {
  @State log: string = 'Ready. Tap a program to measure it cold.'
  @State uiRoot: VeraUiNode | null = null
  @State revision: number = 0
  private uiBuildStart: number = 0
  private uiBuildLogged: boolean = true

  private countNodes(node: VeraUiNode): number {
    let n: number = 1
    for (const child of node.children) {
      n += this.countNodes(child)
    }
    return n
  }

  private benchmark(label: string, vbc1: string): void {
    // bigint -> number outside the timed region; getPss() returns KB.
    const pss0: number = Number(hidebug.getPss())

    const t0: number = nowNs()
    const program = parseBytecodeAssembly(vbc1)
    const t1: number = nowNs()
    const vm = new VeraVM(program)
    vm.run()
    const t2: number = nowNs()
    const runtime: RuntimeResult = vm.invokeFunction('render', [])
    const t3: number = nowNs()
    const ui: VeraUiNode = decodeVeraUi(runtime)
    const t4: number = nowNs()

    // Warm, iterated pass so a per-run figure survives clock granularity.
    const w0: number = nowNs()
    for (let i: number = 0; i < REPS; i++) {
      const p2 = parseBytecodeAssembly(vbc1)
      const v2 = new VeraVM(p2)
      v2.run()
      decodeVeraUi(v2.invokeFunction('render', []))
    }
    const w1: number = nowNs()

    const pss1: number = Number(hidebug.getPss())
    const us: number = 1000.0
    const sample: Sample = {
      label: label,
      bytes: vbc1.length,
      parseUs: (t1 - t0) / us,
      bootUs: (t2 - t1) / us,
      renderUs: (t3 - t2) / us,
      decodeUs: (t4 - t3) / us,
      coldTotalUs: (t4 - t0) / us,
      warmTotalUs: (w1 - w0) / us / REPS,
      pssBaselineKb: pss0,
      pssDeltaKb: pss1 - pss0,
      nodes: this.countNodes(ui)
    }

    this.log =
      `program:      ${sample.label}  (${sample.bytes} B vbc1, ${sample.nodes} nodes)\n` +
      `parse vbc1:   ${sample.parseUs.toFixed(1)} us\n` +
      `vm boot:      ${sample.bootUs.toFixed(1)} us\n` +
      `render():     ${sample.renderUs.toFixed(1)} us\n` +
      `decode+check: ${sample.decodeUs.toFixed(1)} us\n` +
      `cold total:   ${sample.coldTotalUs.toFixed(1)} us\n` +
      `warm total:   ${sample.warmTotalUs.toFixed(1)} us  (mean of ${REPS})\n` +
      `PSS delta:    ${(sample.pssDeltaKb / 1024).toFixed(2)} MB\n` +
      `baseline PSS: ${(sample.pssBaselineKb / 1024).toFixed(1)} MB`
    console.info('VERA_PROBE ' + JSON.stringify(sample))

    this.uiBuildLogged = false
    this.uiRoot = ui
    this.revision += 1
    this.uiBuildStart = nowNs()
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text('VERA probe').fontSize(24).fontWeight(FontWeight.Bold)
        Text('Measures the VERA runtime on device. Restart between runs for a cold measurement.')
          .fontSize(13).opacity(0.7)

        Row({ space: 10 }) {
          Button('Bench tictactoe')
            .onClick(() => { this.benchmark('tictactoe', TICTACTOE_VBC1) })
          Button('Bench dashboard')
            .onClick(() => { this.benchmark('dashboard', DASHBOARD_VBC1) })
        }

        Text(this.log)
          .fontSize(13)
          .fontFamily('monospace')
          .padding(12)
          .width('100%')
          .backgroundColor('#11000000')
          .borderRadius(8)

        if (this.uiRoot != null) {
          Column() {
            this.renderNode(this.uiRoot!, 'root')
          }
          .width('100%')
          .onAppear(() => {
            // Fires once the ArkUI subtree for this program exists, so the
            // delta from the state write is the construction cost itself.
            if (!this.uiBuildLogged) {
              this.uiBuildLogged = true
              const buildUs: number = (nowNs() - this.uiBuildStart) / 1000.0
              console.info('VERA_PROBE_UI {"buildUs":' + buildUs.toFixed(1) + '}')
            }
          })
        }
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  renderChildren(node: VeraUiNode) {
    ForEach(node.children, (child: VeraUiNode) => {
      this.renderNode(child, node.kind)
    }, (child: VeraUiNode) => child.id.toString() + '-' + this.revision.toString())
  }

  /**
   * The same node kinds vera-static-hello renders, so the construction cost is
   * representative rather than a toy.
   */
  @Builder
  renderNode(node: VeraUiNode, parentKind: string) {
    if (node.kind === 'column' || node.kind === 'scroll') {
      Column() {
        this.renderChildren(node)
      }
      .width('100%')
      .alignItems(node.style === 'center' ? HorizontalAlign.Center : HorizontalAlign.Start)
      .padding(node.style === 'compact' ? 6 : 10)
    } else if (node.kind === 'row') {
      Row() {
        this.renderChildren(node)
      }
      .width('100%')
      .justifyContent(node.style === 'split' ? FlexAlign.SpaceBetween : FlexAlign.Start)
      .padding(6)
    } else if (node.kind === 'card') {
      Column() {
        this.renderChildren(node)
      }
      .width(parentKind === 'row' ? undefined : '100%')
      .layoutWeight(parentKind === 'row' ? 1 : 0)
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .backgroundColor('#F3F6FA')
      .border({ width: 1, color: '#D8E1ED' })
      .borderRadius(14)
    } else if (node.kind === 'text') {
      Text(node.text)
        .fontSize(node.style === 'title' ? 22 : node.style === 'caption' ? 12 : 15)
        .fontWeight(node.style === 'title' ? FontWeight.Bold : FontWeight.Normal)
        .width('100%')
    } else if (node.kind === 'button') {
      Button(node.text.length === 0 ? ' ' : node.text)
        .height(42)
        .fontSize(15)
    } else if (node.kind === 'cell') {
      Column() {
        Text(node.text).fontSize(20).fontWeight(FontWeight.Bold)
      }
      .layoutWeight(1)
      .height(64)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#CBD6E4' })
      .borderRadius(10)
    } else if (node.kind === 'spacer') {
      Blank().height(node.style === 'large' ? 32 : node.style === 'small' ? 8 : 18)
    } else {
      Text(node.text).fontSize(14).width('100%')
    }
  }
}
