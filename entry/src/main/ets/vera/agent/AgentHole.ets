/**
 * The slow fill of a plan (ScreenPlan.ets): the slots nothing ready does, written by the model as one section of the
 * program (AgentCustom.ets's writeSection) against the rest of the plan, checked, and put in the plan as the component
 * that fills them. Whichever way the plan was made -- the agent's sketch or the blocks' layout -- it is filled the same way.
 */

import { AgentHost } from './AgentHost'
import { CustomRequest, CustomResult, writeSection } from './AgentCustom'
import { FragmentSpec } from '../VeraTemplates'
import { ScreenPlan, PlanComponent, PlanSlot, assemblePlan, FILL_HOLE, FILL_REPORTED } from '../ScreenPlan'

/** How much of each lookup's answer the writer is shown. */
const LOOKUP_CHARS: number = 4000

/** Text as it goes between the quotes of a VERA string literal: no quotes, backslashes or line breaks. */
function literal(text: string): string {
  return text.split('\\').join('/').split('"').join("'").split('\n').join(' ').trim()
}

/**
 * A warning in place of what could not be built. The plan's needs are its own wording, not the person's, so the title is
 * fixed and `why` -- the writer's own sentence for the person when it said it cannot -- carries the rest.
 */
export function noticeBlock(cannot: boolean, why: string): FragmentSpec {
  let title = cannot ? 'Not available on this phone' : 'Part of this app could not be built'
  let view = '{\n  sections.push(ui.Section("supporting", "", "", [ui.InsetBanner("warning", "' + literal(title) + '", "' +
    literal(why) + '", "", "", "warning")]));\n}'
  let spec = new FragmentSpec('notice', '', '', [], '', '', '', view, [], [])
  spec.indexed = false
  return spec
}

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
export async function writeHole(plan: ScreenPlan, prompt: string, hints: string[], host: AgentHost,
    facts: string[] = []): Promise<CustomResult | null> {
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
  asked.facts = facts
  // A plan with nothing in it yet is the whole screen as one hole.
  asked.whole = plan.components.length === 0
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
  } else if (!asked.whole) {
    // Reported, not dropped: the rest of the screen is served with a notice in place of what could not be built. The
    // whole screen as a hole has no rest to serve.
    let cannot = written.cannot.length > 0
    let why = cannot ? written.cannot : 'Not built: ' + asked.needs.join('; ') + '. ' + written.failed
    plan.components.push(new PlanComponent(FILL_REPORTED, noticeBlock(cannot, why), new Map<string, string>()))
    for (let s of slots) { plan.fillWith(s, FILL_REPORTED, plan.components.length - 1, why) }
  }
  return written
}
