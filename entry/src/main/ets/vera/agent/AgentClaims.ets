/**
 * What the composer leaves out of the plan because "a section of the catalogue does it" is a claim, and the section's own
 * options decide whether it does: a button for each item, a calendar, a style. The finished screen is read against each
 * claim, as a written section is read against its needs (AgentCustom.ets), and what it does not do is put back in the plan
 * to be written, or reported on the screen, rather than lost without a word.
 */

import { CustomRequest, undone, verifyRequest } from './AgentCustom'
import { ScreenPlan } from '../ScreenPlan'

/** The claimed needs the program, as assembled, is not read as doing; [] when it does all, or Jev did not answer. */
export async function claimsUndone(claimed: string[], prompt: string, source: string,
    askJev: (body: string) => Promise<string>): Promise<string[]> {
  if (claimed.length === 0) { return [] }
  let request = new CustomRequest()
  request.needs = claimed
  request.prompt = prompt
  return undone(request, await askJev(verifyRequest(request, source)))
}

/** Puts the needs back in the plan as slots to write; the section hole that follows writes them, or reports them. */
export function putBack(plan: ScreenPlan, needs: string[]): void {
  for (let i = 0; i < needs.length; i++) { plan.addToWrite('claimed.' + i.toString(), needs[i]) }
}
