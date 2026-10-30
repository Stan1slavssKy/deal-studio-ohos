/**
 * The name offered for a new app when it is first saved. The program already has one: the
 * model writes the title block (`ui.Header(style, title, eyebrow, supporting, icon)`) as
 * the top of the screen. That title is used when there is one; otherwise the name is cut
 * from the request, and last of all it is "New app". The person can change it either way.
 */

export const DEFAULT_APP_NAME: string = 'New app'
const MAX_NAME_CHARS: number = 40
const MAX_REQUEST_WORDS: number = 4
const LEADING_ASK: RegExp = /^(?:please\s+)?(?:create|make|build|generate|design|write)(?:\s+me)?\s+(?:an?\s+|the\s+|my\s+)?(?:app\s+(?:for|that|to)\s+)?/i
const HEADER_TITLE: RegExp = /ui\.Header\(\s*"(?:[^"\\]|\\.)*"\s*,\s*"((?:[^"\\]|\\.)*)"/

/** A string literal's text as the program means it: \" \\ and \n resolved. */
function unescapeLiteral(text: string): string {
  return text.replace(/\\(["\\n])/g, (_all: string, ch: string): string => ch === 'n' ? ' ' : ch)
}

function tidy(text: string): string {
  let name = text.replace(/\s+/g, ' ').trim()
  if (name.length > MAX_NAME_CHARS) {
    let cut = name.substring(0, MAX_NAME_CHARS)
    let space = cut.lastIndexOf(' ')
    name = (space > 12 ? cut.substring(0, space) : cut).trim()
  }
  return name
}

/** The title of the program's first Header, or '' when it has none or builds it from a value. */
export function headerTitle(source: string): string {
  let m = HEADER_TITLE.exec(source)
  return m === null ? '' : tidy(unescapeLiteral(m[1]))
}

/** The first few words of the request, up to a colon, full stop or comma, first letter capital. */
export function nameFromRequest(request: string): string {
  let head = request.trim().replace(LEADING_ASK, '')
  let stop = head.search(/[:.,;!?\n]/)
  if (stop > 0) { head = head.substring(0, stop) }
  let words = head.split(/\s+/).filter((w: string): boolean => w.length > 0)
  if (words.length > MAX_REQUEST_WORDS) { words = words.slice(0, MAX_REQUEST_WORDS) }
  let name = tidy(words.join(' '))
  return name.length === 0 ? '' : name.charAt(0).toUpperCase() + name.substring(1)
}

export function suggestAppName(source: string, request: string): string {
  let title = headerTitle(source)
  if (title.length > 0) { return title }
  let fromRequest = nameFromRequest(request)
  return fromRequest.length > 0 ? fromRequest : DEFAULT_APP_NAME
}

/**
 * Words that point at a picture; the first group with a hit wins, so the more specific ones come first. A word counts
 * whole, with a plural or an -ing/-er ending, so "play" is not found in "display" nor "log" in "dialog".
 */
const ICON_WORDS: string[][] = [
  ['🎮', 'game', 'quiz', 'puzzle', 'score', 'dice', 'play'],
  ['🌍', 'trip', 'travel', 'layover', 'flight', 'weather', 'world', 'lake', 'city', 'cities', 'itinerary', 'translate', 'translator',
    'translation'],
  ['🧮', 'calculate', 'calculator', 'calculation', 'convert', 'split', 'tip', 'shared cost', 'budget', 'math'],
  ['🎯', 'goal', 'focus', 'study', 'habit', 'streak', 'target'],
  ['📊', 'tracker', 'counter', 'stats', 'expense', 'ledger', 'log', 'water', 'coffee', 'calorie', 'fever', 'chart'],
  ['📝', 'note', 'todo', 'to-do', 'plan', 'planner', 'planning', 'journal', 'remind', 'pill', 'medicine', 'checklist', 'list'],
  ['🎨', 'color', 'colour', 'draw', 'paint', 'wind down', 'relax', 'sleep'],
  ['⚡', 'battery', 'energy', 'power', 'charge', 'quick', 'timer', 'stopwatch'],
  ['🔧', 'tool', 'fix', 'settings', 'manager']
]

/** One test per word: it starts at a word's start and ends at its end, after an optional plural or -ing/-er. */
const ICON_PATTERNS: RegExp[][] = ICON_WORDS.map((group: string[]): RegExp[] =>
  group.slice(1).map((word: string): RegExp => new RegExp('(^|[^a-z])' + word + '(e?s|ed|ing|ers?)?($|[^a-z])')))

/** The picture a new app starts with, picked from its name and request; '' when nothing in them points at one. */
export function suggestAppIcon(name: string, request: string): string {
  let text = (name + ' ' + request).toLowerCase()
  for (let i = 0; i < ICON_WORDS.length; i++) {
    for (let pattern of ICON_PATTERNS[i]) {
      if (pattern.test(text)) { return ICON_WORDS[i][0] }
    }
  }
  return ''
}
