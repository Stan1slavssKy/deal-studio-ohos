/**
 * How the catalogue's styles dress a node on a home-screen card: the theme's roles (colours, weights, families) and the card's own sizes. The app's
 * renderer reads the same theme through textSize/textInk/...; a card is a glance 150 vp wide, so its sizes are its own, kept where a widget already
 * had them (heading 18, metric 30, the rest 14) and extended to the roles the card used to flatten into those three. Pure: the form extension
 * calls it while it builds a frame, so the card draws what it is told and imports no theme logic.
 */

import { ResolvedTheme, textWeight, textInk, buttonFill, buttonInk, containerFill } from './VeraTheme'

/** A card's text size by style, in fp. */
export function cardTextSize(style: string): number {
  if (style === 'display') { return 28 }
  if (style === 'title') { return 22 }
  if (style === 'heading') { return 18 }
  if (style === 'metric') { return 30 }
  if (style === 'caption') { return 12 }
  if (style === 'eyebrow') { return 10 }
  return 14
}

/** The theme's weight for the style (a metric is bold in the app and on the card). */
export function cardTextWeight(t: ResolvedTheme, style: string): number { return textWeight(t, style) }

/** The theme's ink for the style: eyebrow and muted quiet, success/warning/danger toned, the rest the theme's ink. */
export function cardTextInk(t: ResolvedTheme, style: string): string { return textInk(t, style) }

/** The theme's family for the role (headings and metrics may have their own); '' leaves the system font. */
export function cardTextFamily(t: ResolvedTheme, style: string): string {
  if (style === 'display' || style === 'title' || style === 'heading') { return t.headingFontFamily.length > 0 ? t.headingFontFamily : t.fontFamily }
  if (style === 'metric') { return t.metricFontFamily.length > 0 ? t.metricFontFamily : t.fontFamily }
  return t.fontFamily
}

/** Letter spacing: the eyebrow's, as in the app; 0 for the rest. */
export function cardLetterSpacing(t: ResolvedTheme, style: string): number { return style === 'eyebrow' ? t.eyebrowSpacing : 0 }

/** The gap between a column's (row's) children, in vp, for the density names; 'joined' children touch. */
export function cardGap(kind: string, style: string): number {
  if (kind === 'row') { return style === 'compact' ? 4 : style === 'spacious' ? 12 : style === 'joined' ? 0 : 8 }
  return style === 'compact' ? 3 : style === 'spacious' ? 10 : 6
}

/** The padding of a column or row that is a panel (style surface or accent), in vp. */
export function cardPanelPad(style: string): number { return style === 'compact' ? 6 : style === 'spacious' ? 12 : 8 }

/** The fill of a panel: '' for no panel (a transparent container), else the theme's surface or accent fill. */
export function cardPanelFill(t: ResolvedTheme, style: string): string {
  let fill = containerFill(t, style)
  return fill === '#00000000' ? '' : fill
}

/** A button's fill and ink by style (success and danger included), and its corner radius. */
export function cardButtonFill(t: ResolvedTheme, style: string): string { return buttonFill(t, style) }
export function cardButtonInk(t: ResolvedTheme, style: string): string { return buttonInk(t, style) }
