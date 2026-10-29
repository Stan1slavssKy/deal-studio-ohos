import { resolveTheme, ResolvedTheme } from '../vera/VeraTheme'

/**
 * The look of the app around the screens it makes.
 *
 * The screens the app builds are drawn from a theme (VeraTheme): colours, radii, ink, shadow. The project list, the Generate
 * screen and the chat were drawn from colours typed in place -- a #007DFF button, a #E0E0E0 one, a #0A59F7 one -- so a button
 * of the app and a button in a screen it made were not made of the same thing. `app` is the 'clean' preset's tokens, and the
 * three button looks below are the only ones the pages use: one filled (the thing to do on this screen), one tinted (the next
 * thing), one quiet (the rest). All are capsules, as in the screens.
 */
export const app: ResolvedTheme = resolveTheme('clean', '', false)

/** The one thing to do on the screen. */
export class PrimaryButton implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.type(ButtonType.Capsule).backgroundColor(app.primary).fontColor(app.onPrimary)
  }
}

/** The next thing: a tint of the primary colour, in its ink. */
export class TonalButton implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.type(ButtonType.Capsule).backgroundColor(app.primaryFill).fontColor(app.primaryInk)
  }
}

/** Everything else: grey on grey, nothing to compete with the two above. */
export class QuietButton implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.type(ButtonType.Capsule).backgroundColor(app.secondaryFill).fontColor(app.secondaryInk)
  }
}

/** Taking something away. */
export class DangerButton implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.type(ButtonType.Capsule).backgroundColor(app.danger).fontColor(app.onPrimary)
  }
}
