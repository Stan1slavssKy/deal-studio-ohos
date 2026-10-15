/**
 * Runs a freshly compiled program once, the way VeraPreview does before it draws anything: init(),
 * then view(state), then decode. It tells the caller whether the program starts and shows something,
 * and gives a short description of what it shows for the coverage judge (VeraCoverageJudge.ets).
 *
 * This is a check, not the real run: it uses a bare UiHostEnvironment, so a program that reaches the
 * phone (sdk.call, intents) in init() or view() may trap here for a reason the real preview would
 * not. Callers treat a failure as blocking only for programs they composed themselves from fragments
 * that never do that, and as a warning for model-written ones.
 */

import { VirtualMachine, deserializeVbc2 } from './VeraInterpreter'
import { UiHostEnvironment, decodeVeraUi, VeraUiNode } from './VeraUi'

export class SmokeResult {
  ok: boolean
  /** Why it failed; empty when ok. */
  error: string
  /** Number of nodes in the first frame. */
  nodes: number
  /** Component kinds and visible text of the first frame, short, for the judge; empty when not ok. */
  summary: string
  constructor(ok: boolean, error: string, nodes: number, summary: string) {
    this.ok = ok
    this.error = error
    this.nodes = nodes
    this.summary = summary
  }
}

const MAX_SUMMARY_CHARS: number = 700
const MAX_TEXT_CHARS: number = 36
const MAX_CHART_POINTS: number = 12

function collect(node: VeraUiNode, kinds: string[], texts: string[]): number {
  let count = 1
  if (kinds.indexOf(node.kind) < 0) { kinds.push(node.kind) }
  let candidates: string[] = [node.text, node.label, node.value]
  for (let c of candidates) {
    let t = c.trim()
    if (t.length === 0) { continue }
    if (t.length > MAX_TEXT_CHARS) { t = t.substring(0, MAX_TEXT_CHARS) }
    if (texts.indexOf(t) < 0) { texts.push(t) }
  }
  // A chart's numbers and category names live in props, not in any text field; without them the judge
  // sees a caption and no data ("Price by fruit" with nothing to say what was plotted).
  if (node.series.length > 0) {
    let plotted: string[] = []
    for (let i = 0; i < node.series.length && i < MAX_CHART_POINTS; i++) {
      let name = i < node.categories.length ? node.categories[i] : (i + 1).toString()
      plotted.push(name + '=' + node.series[i].toString())
    }
    texts.push('chart ' + plotted.join(', '))
  }
  for (let child of node.children) { count += collect(child, kinds, texts) }
  return count
}

export function smokeRun(vbc2: string): SmokeResult {
  try {
    let vm = new VirtualMachine(deserializeVbc2(vbc2), new UiHostEnvironment())
    let state = vm.execute('init')
    let roots = decodeVeraUi(vm.execute('view', [state]))
    if (roots.length === 0) { return new SmokeResult(false, 'view() drew nothing', 0, '') }
    let kinds: string[] = []
    let texts: string[] = []
    let nodes = 0
    for (let root of roots) { nodes += collect(root, kinds, texts) }
    if (nodes < 2) { return new SmokeResult(false, 'view() drew an empty screen', nodes, '') }
    let summary = 'components: ' + kinds.join(', ') + '. visible text: ' + texts.join('; ')
    if (summary.length > MAX_SUMMARY_CHARS) { summary = summary.substring(0, MAX_SUMMARY_CHARS) }
    return new SmokeResult(true, '', nodes, summary)
  } catch (e) {
    return new SmokeResult(false, (e as Error).message, 0, '')
  }
}
