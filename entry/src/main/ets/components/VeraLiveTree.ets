/**
 * The renderer's own copy of the UI tree, and the reconciler that keeps it in
 * step with what the program produced.
 *
 * Why a second tree exists at all. The VM builds a brand new VeraUiNode tree on
 * every frame, and ArkUI does not re-render a component because an object was
 * *replaced* -- only because one was *mutated*. Three approaches were each built
 * and measured on device before this one, and all three left the screen stale
 * while the VM ran correctly underneath: passing the node to a nested @Builder,
 * keying ForEach on node content, and a recursive @Component taking the node as
 * @Prop. So the renderer keeps a persistent tree of @Trace'd nodes and copies
 * each new frame into it field by field. Mutation propagates; replacement does
 * not.
 *
 * Why not simply mark VeraUiNode itself observable: decodeVeraUi is a measured
 * phase of the benchmark (decodeUs, part of coldTotalUs), and putting
 * observation overhead inside it would move a published number. Decode stays a
 * cheap pure function producing plain data; the cost of observation lands here,
 * in the renderer, where buildUs already accounts for it.
 */

import { VeraUiNode } from '../vera/VeraUi'

@ObservedV2
export class LiveNode {
  @Trace kind: string = ''
  @Trace style: string = ''
  @Trace text: string = ''
  @Trace source: string = ''
  @Trace alt: string = ''
  @Trace action: string = ''
  @Trace eventValue: number = 0
  @Trace enabled: boolean = true
  @Trace commands: string = ''
  @Trace spinPeriodMs: number = 0
  @Trace label: string = ''
  @Trace tickerId: string = ''
  @Trace columns: number = 1
  @Trace value: string = ''
  @Trace checked: boolean = false
  @Trace minimum: number = 0
  @Trace maximum: number = 100
  @Trace options: string[] = []
  @Trace children: LiveNode[] = []
}

/** A fresh live subtree, used for the parts a frame actually adds. */
export function toLive(node: VeraUiNode): LiveNode {
  let live = new LiveNode()
  live.kind = node.kind
  live.style = node.style
  live.text = node.text
  live.source = node.source
  live.alt = node.alt
  live.action = node.action
  live.eventValue = node.eventValue
  live.enabled = node.enabled
  live.commands = node.commands
  live.spinPeriodMs = node.spinPeriodMs
  live.label = node.label
  live.tickerId = node.tickerId
  live.columns = node.columns
  live.value = node.value
  live.checked = node.checked
  live.minimum = node.minimum
  live.maximum = node.maximum
  live.options = node.options
  let kids: LiveNode[] = []
  for (let child of node.children) { kids.push(toLive(child)) }
  live.children = kids
  return live
}

/**
 * Copy one frame into the live tree, touching only what differs.
 *
 * Assigning a @Trace field notifies every component that reads it, so the
 * comparisons are not an optimisation -- writing an unchanged value would
 * re-render a node that did not change, which is the very behaviour this
 * replaces.
 *
 * Children are matched by position. When the count changes the list is rebuilt
 * wholesale: that is coarse, but a structural change is exactly the case where
 * positional identity is meaningless, and it is rare next to the common one --
 * a fixed layout whose text and enabled flags move.
 */
export function reconcile(live: LiveNode, next: VeraUiNode): void {
  if (live.kind !== next.kind) { live.kind = next.kind }
  if (live.style !== next.style) { live.style = next.style }
  if (live.text !== next.text) { live.text = next.text }
  if (live.source !== next.source) { live.source = next.source }
  if (live.alt !== next.alt) { live.alt = next.alt }
  if (live.action !== next.action) { live.action = next.action }
  if (live.eventValue !== next.eventValue) { live.eventValue = next.eventValue }
  if (live.enabled !== next.enabled) { live.enabled = next.enabled }
  if (live.commands !== next.commands) { live.commands = next.commands }
  if (live.spinPeriodMs !== next.spinPeriodMs) { live.spinPeriodMs = next.spinPeriodMs }
  if (live.label !== next.label) { live.label = next.label }
  if (live.tickerId !== next.tickerId) { live.tickerId = next.tickerId }
  if (live.columns !== next.columns) { live.columns = next.columns }
  if (live.value !== next.value) { live.value = next.value }
  if (live.checked !== next.checked) { live.checked = next.checked }
  if (live.minimum !== next.minimum) { live.minimum = next.minimum }
  if (live.maximum !== next.maximum) { live.maximum = next.maximum }
  if (live.options.join('\u0000') !== next.options.join('\u0000')) { live.options = next.options }

  if (live.children.length !== next.children.length) {
    let kids: LiveNode[] = []
    for (let child of next.children) { kids.push(toLive(child)) }
    live.children = kids
    return
  }
  for (let i = 0; i < next.children.length; i++) {
    reconcile(live.children[i], next.children[i])
  }
}
