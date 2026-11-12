/**
 * Make widget's checks off the UI thread. A widget is held to its card by running the app: every control is tapped and what
 * the tap starts is played to rest (WidgetSession.settle), up to 600 steps of the app's clock each. For a game that never
 * rests that is most of a second a tap on the phone, several taps in a row, and on the UI thread it froze the app until the
 * system killed it (a generated fish tank: appfreeze THREAD_BLOCK_6S in settle). Here the same checks run in a TaskPool
 * worker; the pure modules they call are the ones the form extension also loads, so they run there unchanged.
 *
 * A tap in the app's widget preview plays what it started to rest the same way (settle), so it runs in a worker too.
 *
 * App only: the host harness calls checkWidgetProgram, validateWidgetRefinement and WidgetSession directly.
 */

import { taskpool } from '@kit.ArkTS'
import { checkWidgetProgram } from './AgentWidget'
import { validateWidgetRefinement } from '../VeraWidgetRefine'
import { PreviewTapRequest, PreviewTapResult, runPreviewTap } from '../VeraLiveWidget'

@Concurrent
function checkProgramTask(base: string, source: string, saved: string): string {
  return checkWidgetProgram(base, source, saved)
}

@Concurrent
function validateTask(base: string, source: string, vbc2: string, saved: string): string {
  return validateWidgetRefinement(base, source, vbc2, saved)
}

/** checkWidgetProgram (compile, one run, the card's checks) in a worker. */
export async function checkWidgetProgramOffMain(base: string, source: string, saved: string): Promise<string> {
  try {
    return await taskpool.execute(checkProgramTask, base, source, saved) as string
  } catch (e) {
    return 'Widget validation: ' + (e as Error).message
  }
}

/** validateWidgetRefinement in a worker. */
export async function validateWidgetOffMain(base: string, source: string, vbc2: string, saved: string = ''): Promise<string> {
  try {
    return await taskpool.execute(validateTask, base, source, vbc2, saved) as string
  } catch (e) {
    return 'Widget validation: ' + (e as Error).message
  }
}

@Concurrent
function previewTapTask(request: PreviewTapRequest): PreviewTapResult {
  return runPreviewTap(request)
}

/** A tap on the widget preview in a worker: the session is made again from the program and the state, as the card makes it (LiveFormService). */
export async function previewTapOffMain(request: PreviewTapRequest): Promise<PreviewTapResult> {
  try {
    return await taskpool.execute(previewTapTask, request) as PreviewTapResult
  } catch (e) {
    let failed = new PreviewTapResult()
    failed.error = 'Widget tap: ' + (e as Error).message
    return failed
  }
}
