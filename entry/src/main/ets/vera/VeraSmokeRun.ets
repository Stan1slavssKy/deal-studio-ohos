/**
 * Runs a freshly compiled program once, the way VeraPreview does before it draws anything: init(),
 * then view(state), then decode. It tells the caller whether the program starts and shows something.
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
  constructor(ok: boolean, error: string, nodes: number) {
    this.ok = ok
    this.error = error
    this.nodes = nodes
  }
}

function countNodes(node: VeraUiNode): number {
  let count = 1
  for (let child of node.children) { count += countNodes(child) }
  return count
}

export function smokeRun(vbc2: string): SmokeResult {
  try {
    let vm = new VirtualMachine(deserializeVbc2(vbc2), new UiHostEnvironment())
    let state = vm.execute('init')
    let roots = decodeVeraUi(vm.execute('view', [state]))
    if (roots.length === 0) { return new SmokeResult(false, 'view() drew nothing', 0) }
    let nodes = 0
    for (let root of roots) { nodes += countNodes(root) }
    if (nodes < 2) { return new SmokeResult(false, 'view() drew an empty screen', nodes) }
    return new SmokeResult(true, '', nodes)
  } catch (e) {
    return new SmokeResult(false, (e as Error).message, 0)
  }
}
