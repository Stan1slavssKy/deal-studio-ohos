/**
 * The last run of the Generate screen, kept across restarts: the Metrics tab reads what the page holds in memory, and that is
 * gone when the app is started again, though the program on the screen is not. One small record in the app's own folder
 * ({filesDir}/vera/last-run.json), written when a run ends and shown on the tab when this session has not run anything yet.
 */

import { settings, readText, writeText } from './SettingsStore'

export class LastRun {
  /** When it ended (Date.now()). */
  at: number = 0
  prompt: string = ''
  /** How the screen was made: agent, template, model, structural, or failed. */
  via: string = ''
  /** The whole run, the time the person spent answering questions included. */
  ms: number = 0
  /** Of which the person's own: waiting for answers to the plan's questions. */
  waitedMs: number = 0
  sketchMs: number = 0
  jevMs: number = 0
  /** -1 when no search was made. */
  searchMs: number = -1
  contentMs: number = 0
  holesMs: number = 0
  checkMs: number = 0
  /** Attempts of the model's own generation, or of the written section. */
  attempts: number = 0
  kinds: string[] = []
  note: string = ''
}

export function lastRunToJson(run: LastRun): string {
  let o: Record<string, Object> = {}
  o['v'] = 1
  o['at'] = run.at
  o['prompt'] = run.prompt
  o['via'] = run.via
  o['ms'] = run.ms
  o['waitedMs'] = run.waitedMs
  o['sketchMs'] = run.sketchMs
  o['jevMs'] = run.jevMs
  o['searchMs'] = run.searchMs
  o['contentMs'] = run.contentMs
  o['holesMs'] = run.holesMs
  o['checkMs'] = run.checkMs
  o['attempts'] = run.attempts
  o['kinds'] = run.kinds
  o['note'] = run.note
  return JSON.stringify(o)
}

function numberOf(o: Record<string, Object>, key: string, fallback: number): number {
  let v = o[key]
  return typeof v === 'number' && isFinite(v as number) ? v as number : fallback
}

function textOf(o: Record<string, Object>, key: string): string {
  let v = o[key]
  return typeof v === 'string' ? v as string : ''
}

/** null when the text is not a record this version wrote. */
export function lastRunFromJson(text: string): LastRun | null {
  if (text.length === 0) { return null }
  try {
    let o = JSON.parse(text) as Record<string, Object>
    if ((o['v'] as number) !== 1) { return null }
    let run = new LastRun()
    run.at = numberOf(o, 'at', 0)
    run.prompt = textOf(o, 'prompt')
    run.via = textOf(o, 'via')
    run.ms = numberOf(o, 'ms', 0)
    run.waitedMs = numberOf(o, 'waitedMs', 0)
    run.sketchMs = numberOf(o, 'sketchMs', 0)
    run.jevMs = numberOf(o, 'jevMs', 0)
    run.searchMs = numberOf(o, 'searchMs', -1)
    run.contentMs = numberOf(o, 'contentMs', 0)
    run.holesMs = numberOf(o, 'holesMs', 0)
    run.checkMs = numberOf(o, 'checkMs', 0)
    run.attempts = numberOf(o, 'attempts', 0)
    let kinds = o['kinds']
    if (kinds !== undefined && kinds !== null) { for (let k of kinds as Object[]) { if (typeof k === 'string') { run.kinds.push(k as string) } } }
    run.note = textOf(o, 'note')
    return run.via.length > 0 ? run : null
  } catch (_e) {
    return null
  }
}

function seconds(ms: number): string {
  return ms < 1000 ? ms.toString() + ' ms' : (ms / 1000).toFixed(1) + ' s'
}

/** The record for the Metrics tab, one line each. */
export function describeLastRun(run: LastRun): string[] {
  let lines: string[] = []
  let when = new Date(run.at).toISOString().substring(0, 16).replace('T', ' ')
  lines.push('Last run, before this session (' + when + ' UTC)')
  lines.push((run.prompt.length > 90 ? run.prompt.substring(0, 90) + '...' : run.prompt))
  let total = run.via + ' in ' + seconds(Math.max(0, run.ms - run.waitedMs))
  if (run.waitedMs > 0) { total += ', and ' + seconds(run.waitedMs) + ' waiting for the person' }
  lines.push(total)
  let stages: string[] = []
  if (run.sketchMs > 0) { stages.push('plan ' + seconds(run.sketchMs)) }
  if (run.jevMs > 0) { stages.push('Jev ' + seconds(run.jevMs)) }
  if (run.searchMs >= 0) { stages.push('search ' + seconds(run.searchMs)) }
  if (run.contentMs > 0) { stages.push('text ' + seconds(run.contentMs)) }
  if (run.holesMs > 0) { stages.push('holes ' + seconds(run.holesMs)) }
  if (run.checkMs > 0) { stages.push('check ' + seconds(run.checkMs)) }
  if (stages.length > 0) { lines.push(stages.join(' · ')) }
  if (run.kinds.length > 0) { lines.push('sections: ' + run.kinds.join(' + ')) }
  if (run.attempts > 0) { lines.push(run.attempts.toString() + ' attempt(s)') }
  if (run.note.length > 0) { lines.push(run.note.length > 160 ? run.note.substring(0, 160) + '...' : run.note) }
  return lines
}

function lastRunPath(): string {
  return settings.dir().length > 0 ? settings.dir() + '/last-run.json' : ''
}

export function saveLastRun(run: LastRun): void {
  let path = lastRunPath()
  if (path.length === 0) { return }
  try { writeText(path, lastRunToJson(run)) } catch (_e) {}
}

export function loadLastRun(): LastRun | null {
  let path = lastRunPath()
  return path.length === 0 ? null : lastRunFromJson(readText(path))
}
