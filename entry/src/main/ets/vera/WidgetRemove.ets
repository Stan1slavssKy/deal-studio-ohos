import { compileVeraSource, withoutWidget, appUsesWidgetError } from './VeraCompiler'
import { smokeRun } from './VeraSmoke'
import { hasWidgetFunction } from './WidgetStatus'
import { withoutWidgetRequests } from './ProjectText'

/** How the version without a widget is listed. */
export const WIDGET_REMOVED_NOTE: string = 'Removed the home-screen widget'

/** A program without its home-screen widget, ready to be saved as a new version; `error` says why it cannot be. */
export class WidgetRemoval {
  source: string = ''
  vbc2: string = ''
  /** The request history without what the widget was asked to show, so a later Make widget starts from the app alone. */
  prompt: string = ''
  error: string = ''
}

/**
 * Remove widget on the project page: the program without widget, widgetRefresh and what only they use (withoutWidget),
 * compiled and run once. The app itself is unchanged, so its saved state still fits. Cards already on the home screen stay
 * there (only the launcher removes them) and show "Open app".
 */
export function removeWidget(source: string, prompt: string): WidgetRemoval {
  let out = new WidgetRemoval()
  if (!hasWidgetFunction(source)) { out.error = 'This version has no widget.'; return out }
  let usesWidget = appUsesWidgetError(source)
  if (usesWidget.length > 0) { out.error = usesWidget; return out }
  let bare = withoutWidget(source)
  if (hasWidgetFunction(bare)) { out.error = 'The widget could not be taken out of this version.'; return out }
  try {
    let compiled = compileVeraSource(bare)
    let problem = smokeRun(compiled)
    if (problem.length > 0) { out.error = 'Without its widget the app does not run: ' + problem; return out }
    out.vbc2 = compiled.vbc2
  } catch (e) {
    out.error = 'Without its widget the app does not build: ' + (e as Error).message
    return out
  }
  out.source = bare
  out.prompt = withoutWidgetRequests(prompt)
  return out
}
