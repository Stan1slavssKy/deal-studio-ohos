/**
 * Make widget's checks off the UI thread. A widget is held to its card by running the app: every control is tapped and what
 * the tap starts is played to rest (WidgetSession.settle), up to 600 steps of the app's clock each. For a game that never
 * rests that is most of a second a tap on the phone, several taps in a row, and on the UI thread it froze the app until the
 * system killed it (a generated fish tank: appfreeze THREAD_BLOCK_6S in settle). Here the same checks run in a TaskPool
 * worker; the pure modules they call are the ones the form extension also loads, so they run there unchanged.
 *
 * App only: the host harness calls checkWidgetProgram and validateWidgetRefinement directly.
 */

import { taskpool } from '@kit.ArkTS'
import { checkWidgetProgram } from './AgentWidget'
import { validateWidgetRefinement } from '../VeraWidgetRefine'

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
