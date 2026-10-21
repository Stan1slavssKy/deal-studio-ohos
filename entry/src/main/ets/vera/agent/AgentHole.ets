/**
 * The slow fill of a plan (ScreenPlan.ets): the slots nothing ready does, written by the model as one section of the
 * program (AgentCustom.ets's writeSection) against the rest of the plan, checked, and put in the plan as the component
 * that fills them. Whichever way the plan was made -- the agent's sketch or the blocks' layout -- it is filled the same way.
 */

import { AgentHost } from './AgentHost'
import { CustomRequest, CustomResult, writeSection } from './AgentCustom'
import { FragmentSpec } from '../VeraTemplates'
import { ScreenPlan, PlanComponent, PlanSlot, assemblePlan, FILL_HOLE } from '../ScreenPlan'

/** How much of each lookup's answer the writer is shown. */
const LOOKUP_CHARS: number = 4000

/** The plan with `section` after everything else, assembled; null assembles what is filled, the program so far. */
function withSection(plan: ScreenPlan, section: FragmentSpec | null): string {
  if (section === null) { return assemblePlan(plan, true) }
  plan.components.push(new PlanComponent(FILL_HOLE, section, new Map<string, string>()))
  let source = assemblePlan(plan, true)
  plan.components.pop()
  return source
}

/**
 * Writes the section for the plan's slots to be written, and fills them with it. Null when there are none; otherwise
 * what writing did, with `failed` saying why the slots are still open. `hints` are lines the writer is told about the
 * screen (inputs nothing else reads, and where they are in the state).
 */
export async function writeHole(plan: ScreenPlan, prompt: string, hints: string[], host: AgentHost): Promise<CustomResult | null> {
  let slots: PlanSlot[] = plan.toWrite()
  if (slots.length === 0) { return null }
  if (host.askCode === null || host.language.length === 0) {
    let none = new CustomResult()
    none.failed = 'no model to write a custom section'
    return none
  }
  let asked = new CustomRequest()
  asked.needs = slots.map((s: PlanSlot): string => s.need)
  asked.prompt = prompt
  asked.inputs = hints
  asked.compose = (section: FragmentSpec | null): string => withSection(plan, section)
  asked.verify = host.askJev
  // What the phone is to do: its functions found for each such need, the only targets the section may call.
  let found: string[] = []
  for (let s of slots) {
    if (!s.phone) { continue }
    let text = await host.lookup(s.need)
    if (text.length > 0) { found.push('For "' + s.need + '":\n' + text.substring(0, LOOKUP_CHARS)) }
  }
  asked.phone = found.join('\n\n')
  let written = await writeSection(asked, host.language, host.askCode!)
  if (written.section !== null) {
    plan.components.push(new PlanComponent(FILL_HOLE, written.section, new Map<string, string>()))
    for (let s of slots) { plan.fillWith(s, FILL_HOLE, plan.components.length - 1) }
  }
  return written
}
