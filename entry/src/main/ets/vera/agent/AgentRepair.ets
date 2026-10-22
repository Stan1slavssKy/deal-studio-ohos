/**
 * An assembled program that does not compile or run is repaired by edits, not rebuilt: the model gets the program, the
 * diagnostics with the lines they point at, and answers with SEARCH/REPLACE blocks (VeraRepair.ets, the same form
 * generation repairs with), which are applied and checked again -- at most twice.
 */

import { CodeAsk } from './AgentCustom'
import { repairPrompt, applyRepair } from '../VeraRepair'
import { compileVeraSource, CompileError } from '../VeraCompiler'
import { smokeRun } from '../VeraSmoke'

const ROUNDS: number = 2
/** Room for the edits: a few blocks of a few lines each. */
const EDIT_TOKENS: number = 2000

export class Repaired {
  /** The program that compiles and runs; '' when none did. */
  source: string = ''
  vbc2: string = ''
  /** Edit rounds asked for. */
  rounds: number = 0
  /** What still fails, '' when the repair worked. */
  failed: string = ''
  ms: number = 0
}

/** The program's diagnostics: '' when it compiles and runs once with every handler tapped. */
export function checkProgram(source: string): string {
  try {
    return smokeRun(compileVeraSource(source))
  } catch (e) {
    return e instanceof CompileError ? (e as CompileError).message : (e as Error).message
  }
}

export async function repairProgram(source: string, errors: string, prompt: string, language: string,
    ask: CodeAsk): Promise<Repaired> {
  let out = new Repaired()
  let started = Date.now()
  let current = source
  let problem = errors
  for (let round = 0; round < ROUNDS && problem.length > 0; round++) {
    out.rounds = round + 1
    let reply = await ask(language, 'The program:\n' + current + '\n\n' + repairPrompt('Request: ' + prompt, problem, true, current),
      EDIT_TOKENS, false)
    if (reply === null) { problem = 'no answer for the repair'; break }
    let applied = applyRepair(current, reply)
    if (applied.source.length === 0) { problem = 'the edits did not apply: ' + applied.error; continue }
    current = applied.source
    problem = checkProgram(current)
  }
  out.ms = Date.now() - started
  if (problem.length > 0) {
    out.failed = problem.split('\n')[0]
    return out
  }
  out.source = current
  out.vbc2 = compileVeraSource(current).vbc2
  return out
}
