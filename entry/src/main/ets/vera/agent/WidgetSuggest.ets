/**
 * The ready-made requests on the widget screen, made from the app itself: its state's figures and lists, and the actions
 * its own buttons take. A tap sends one; the label is what the person reads, the ask what the model is told. The asks
 * name the field or handler and the card style, so that what the chip promises is what the model can do.
 */

import { widgetFacts, WidgetFacts, WidgetFact } from '../VeraCompiler'

export class WidgetSuggestion {
  label: string
  ask: string

  constructor(label: string, ask: string) {
    this.label = label
    this.ask = ask
  }
}

/** Longest label a chip shows: two chips side by side on a phone. */
const LABEL_MAX: number = 22

/** "waterGlasses" and "water_glasses" read "Water glasses". */
export function humanize(name: string): string {
  // A number that numbers a field (stops7, item_2) is the program's, not a word.
  let words = name.replace(/([A-Za-z_])\d+$/, '$1').replace(/_/g, ' ').replace(/([a-z0-9])([A-Z])/g, '$1 $2').trim().toLowerCase()
  return words.length > 0 ? words.charAt(0).toUpperCase() + words.substring(1) : name
}

function fits(label: string): string {
  return label.length > LABEL_MAX ? label.substring(0, LABEL_MAX - 1).trimEnd() + '…' : label
}

const CHOOSE: WidgetSuggestion = new WidgetSuggestion('Let VERA choose',
  'the one figure or list this app is most about, and one quick action if it has one')

/** When nothing is known of the app: requests that fit any. */
const GENERIC_FIRST: WidgetSuggestion[] = [
  new WidgetSuggestion('The main number', 'the one number this app is most about, as ui.NumberText with style "metric"'),
  new WidgetSuggestion('A quick action', 'the main figure and one button for the action used most'),
  CHOOSE
]

/** What the person reads for a fact: the app's own words for it, else its name made readable. */
function said(fact: WidgetFact): string {
  return fact.label.trim().length > 0 ? fact.label.trim() : humanize(fact.name)
}

/** The request for one figure: a field of the state, or a number the app works out and labels. */
function figureAsk(fact: WidgetFact): string {
  let how = ', large, as ui.NumberText with style "metric", with a label of a word or two'
  if (fact.name.length > 0) { return 'state.' + fact.name + how }
  return 'the figure the app shows as "' + fact.label + '", worked out the way the app works it out' + how
}

/** The first widget: a figure or two, the latest of a list, a button the app has, or VERA's own pick. */
export function firstSuggestions(source: string): WidgetSuggestion[] {
  let facts = widgetFacts(source)
  let out: WidgetSuggestion[] = []
  // Four chips at most besides VERA's own pick: one figure when there is a list and a button as well.
  let figures = facts.lists.length > 0 && facts.handlers.length > 0 ? 1 : 2
  for (let fact of facts.numbers.slice(0, figures)) {
    out.push(new WidgetSuggestion(fits(said(fact)), figureAsk(fact)))
  }
  if (facts.lists.length > 0) {
    let fact = facts.lists[0]
    out.push(new WidgetSuggestion(fits('Latest ' + said(fact).toLowerCase()),
      'the latest two or three items of state.' + fact.name + ', one short line each'))
  }
  if (facts.handlers.length > 0) {
    let fact = facts.handlers[0]
    out.push(new WidgetSuggestion(fits('\u201C' + said(fact) + '\u201D button'),
      'the main figure and one button that calls ' + fact.name + ', with the value the app\'s own button gives it'))
  }
  if (out.length === 0) { return GENERIC_FIRST }
  out.push(CHOOSE)
  return out
}

/** A widget that is there: the changes a card can take, and what of the app it does not show yet. */
export function changeSuggestions(source: string): WidgetSuggestion[] {
  let facts: WidgetFacts = widgetFacts(source)
  let out: WidgetSuggestion[] = [
    new WidgetSuggestion('Bigger number', 'the same, but the main number as ui.NumberText with style "metric" (the largest ' +
      'size a card has), and at most one short line besides it'),
    new WidgetSuggestion('Less text', 'the same, with every label one or two words, no sentences and no more than three lines')
  ]
  let handler = facts.handlers.find((fact: WidgetFact): boolean => facts.used.indexOf(fact.name) < 0)
  if (handler !== undefined) {
    out.push(new WidgetSuggestion(fits('Button \u201C' + said(handler) + '\u201D'),
      'the same, plus one button that calls ' + handler.name + ', with the value the app\'s own button gives it'))
  }
  // Only a field of the state: whether a worked-out figure is on the card already cannot be told from its label.
  let figure = facts.numbers.find((fact: WidgetFact): boolean => fact.name.length > 0 && facts.used.indexOf(fact.name) < 0)
  if (figure !== undefined) {
    out.push(new WidgetSuggestion(fits('Add ' + said(figure).toLowerCase()), 'the same, plus ' + figureAsk(figure)))
  }
  return out
}
