/**
 * The host's side of the live_figure section (VeraTemplates.ets's liveFigureFragment): finding where its figures come from while
 * the screen is built, and writing the call the section makes. A public JSON API found and fetched now (VeraSourceFind.ets) is
 * fetched by the program with Vera.Source.fetch, one GET the home-screen card can make too; with none, the program reads a web
 * search on each refresh (Vera.Live.fetch, VeraLive.ets). The address, the paths, the query and the labels are written out as
 * literals here (the compiler takes them no other way, E2114), and no figure is: the section starts empty and fetches.
 *
 * The figures are the plan's (SketchLive), in its order: their labels and units are the plan's, not the source finder's.
 */

import { SketchLive } from './VeraCompose'
import { SourceFound, searchSpec, sourceArgs } from './VeraSourceFind'
import { SourceSpec, SOURCE_TARGET, SOURCE_MAX_FIGURES, domainOf } from './VeraSource'

export const LIVE_SEARCH_TARGET: string = 'Vera.Live.fetch'
/** The path of a WMO weather code in an answer: Open-Meteo's current.weather_code, daily.weathercode[0]. */
const WEATHER_CODE: RegExp = /weather_?code/i
/** Seconds between fetches: a GET is cheap; a search costs a search and a model call, so it is made every five minutes at most. */
export const LIVE_SOURCE_EVERY: number = 60
export const LIVE_SEARCH_EVERY: number = 300

/** What the source finder is asked for: the request, then each figure in the order the section shows them. */
export function liveNeed(prompt: string, figures: SketchLive[]): string {
  let lines: string[] = []
  for (let i = 0; i < figures.length && i < SOURCE_MAX_FIGURES; i++) {
    let f = figures[i]
    // The query names the place or the thing ("Moscow temperature now"), which the request may not: the person's answer is in it.
    lines.push((i + 1).toString() + '. ' + f.label + (f.means.length > 0 && f.means !== f.label ? ' (' + f.means + ')' : '') +
      (f.unit.length > 0 ? ', in ' + f.unit : '') + (f.query.length > 0 ? ': ' + f.query : ''))
  }
  return prompt + '\nThe figures to fetch, in this order:\n' + lines.join('\n')
}

/**
 * The query a search for the figures is made with, when no API answers them: the plan's own words for the first figure, which
 * name the place or the thing. The others' queries joined on read as a run-on that a search answers worse.
 */
export function liveQuery(figures: SketchLive[]): string {
  for (let f of figures.slice(0, SOURCE_MAX_FIGURES)) { if (f.query.length > 0) { return f.query.substring(0, 120) } }
  return figures.length > 0 ? figures[0].label.substring(0, 120) : ''
}

/** A label as it goes into a call or a string literal: no separator of the call's own, no quote, no line break. */
function plainLabel(s: string): string {
  return s.replace(/[|"\\\n\r\t]/g, ' ').replace(/\s+/g, ' ').trim().substring(0, 30)
}

/** The section's host tokens for this source and these figures. */
export function liveValues(spec: SourceSpec, figures: SketchLive[]): Map<string, string> {
  let q = (s: string): string => JSON.stringify(s)
  let shown = figures.slice(0, SOURCE_MAX_FIGURES)
  let values: Map<string, string> = new Map<string, string>()
  let search = spec.query.length > 0
  values.set('__LIVE_TARGET__', search ? LIVE_SEARCH_TARGET : SOURCE_TARGET)
  values.set('__LIVE_ARGS__', sourceArgs(spec, shown.map((f: SketchLive): string => plainLabel(f.label)).join('|')))
  values.set('__LIVE_EVERY__', (search ? LIVE_SEARCH_EVERY : LIVE_SOURCE_EVERY).toString())
  // The first figure is the screen's own: a tile across the whole width, with how it moved since the last answer under it (not for
  // a weather code, whose number means nothing as a change). The others are tiles in pairs below it; one alone takes the whole row.
  let rows: string[] = []
  for (let i = 0; i < shown.length; i++) {
    let f = shown[i]
    let field = 'state.liveFigure' + (i + 1).toString()
    let code = i < spec.paths.length && WEATHER_CODE.test(spec.paths[i])
    // A WMO weather code (Open-Meteo's weather_code, 3 for overcast) is shown in words; any other figure with its unit.
    let shownAs = code ? 'liveWeather(' + field + ')' : 'liveShown(' + field + ', ' + q(plainLabel(f.unit)) + ')'
    let span = i === 0 || shown.length === 2 ? 2 : 1
    // The first tile is the screen's own (accent), and holds the change and, behind the info button, the source.
    let style = i === 0 ? 'accent' : 'default'
    let under = i === 0 ? 'liveUnder(state, ' + (code ? 'false' : 'true') + ')' : '""'
    rows.push('    liveTiles.push(ui.Tile("' + style + '", ' + span.toString() + ', ' + q(plainLabel(f.label)) + ', ' + shownAs + ', ' + under + ', ""));')
  }
  if (rows.length === 0) { rows.push('    liveTiles.push(ui.Tile("accent", 2, "Value", liveShown(state.liveFigure1, ""), liveUnder(state, true), ""));') }
  values.set('__LIVE_ROWS__', rows.join('\n'))
  return values
}

export class LiveFill {
  values: Map<string, string> = new Map<string, string>()
  /** The source taken: an API's, or a search's (spec.query set). Null when there is none. */
  spec: SourceSpec | null = null
  /** Why no source could be taken; '' when one was. */
  failed: string = ''
  /** One line for the trace: what was taken, or each address tried and why it was not. */
  note: string = ''
  ms: number = 0
}

/**
 * Where the figures come from: an API the finder checked, else a search on each refresh when a search can be made, else none.
 * `find` is the source finder with the app's or the harness's calls; `canSearch` says whether the program's search would work.
 */
export async function fillLive(prompt: string, figures: SketchLive[], find: ((need: string) => Promise<SourceFound>) | null,
    canSearch: boolean): Promise<LiveFill> {
  let out = new LiveFill()
  let started = Date.now()
  if (figures.length === 0) { out.failed = 'no figures to fetch'; return out }
  let found: SourceFound | null = find !== null ? await find(liveNeed(prompt, figures)) : null
  if (found !== null && found.spec !== null) {
    out.spec = found.spec
    out.note = 'source=' + domainOf(found.spec!.url) + ' paths=' + found.spec!.paths.length.toString() + '/' +
      Math.min(figures.length, SOURCE_MAX_FIGURES).toString()
  } else if (canSearch) {
    out.spec = searchSpec(liveQuery(figures))
    out.note = 'source=search query="' + out.spec!.query + '"' + (found !== null && found.tried.length > 0 ? ' tried=' + found.tried.join('; ').substring(0, 300) : '')
  } else {
    out.failed = 'live figures need a public data source or a web search, and neither is available'
    out.note = found !== null ? 'tried=' + found.tried.join('; ').substring(0, 300) : 'no source finder'
  }
  if (out.spec !== null) { out.values = liveValues(out.spec!, figures) }
  out.ms = Date.now() - started
  return out
}
