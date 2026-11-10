import { appUsesWidgetError } from './VeraCompiler'

/** Whether a program declares the home-screen widget, widget(state). */
export function hasWidgetFunction(source: string): boolean {
  return /\bfunction\s+widget\s*\(/.test(source)
}

export const WIDGET_NEEDS_RUN: string = 'needsRun'
export const WIDGET_UNAVAILABLE: string = 'unavailable'
export const WIDGET_NONE: string = 'none'
export const WIDGET_READY: string = 'ready'
export const WIDGET_PLACED: string = 'placed'
/** Cards are on the home screen, but the latest version, which they draw, has no widget: they show "Open app". */
export const WIDGET_BROKEN: string = 'broken'

export class WidgetStatus {
  kind: string = WIDGET_NONE
  /** Why a widget cannot be made, for unavailable. */
  reason: string = ''
  placed: number = 0
}

/**
 * What a project's widget is, from its latest version (the one a card draws, LiveFormService) and how many cards
 * show the project.
 */
export function widgetStatus(source: string, vbc2: string, placed: number): WidgetStatus {
  let status = new WidgetStatus()
  status.placed = placed
  let has = source.length > 0 && hasWidgetFunction(source)
  // A card over a version that does not compile shows "Open project": as good as no widget.
  if (placed > 0 && (!has || vbc2.length === 0)) { status.kind = WIDGET_BROKEN; return status }
  if (source.length === 0 || vbc2.length === 0) { status.kind = WIDGET_NEEDS_RUN; return status }
  let refused = appUsesWidgetError(source)
  if (refused.length > 0) { status.kind = WIDGET_UNAVAILABLE; status.reason = refused; return status }
  if (!has) { status.kind = WIDGET_NONE; return status }
  status.kind = placed > 0 ? WIDGET_PLACED : WIDGET_READY
  return status
}
