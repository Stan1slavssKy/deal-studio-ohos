/**
 * Whether the Jev template path (VeraTemplatePipeline.ets) runs before a generation.
 *
 * On by default: it runs whenever there is a TypeSafe key (settings.hasSelectorKey()), and a
 * request it cannot serve falls straight through to generation from scratch. `--ps
 * veraTemplateSelect 0` at launch switches it off for that session, for comparing against plain
 * generation; `--ps veraTemplateSelect 1` is accepted and changes nothing. Sticky, unlike
 * VeraUiAb.ets's one-shot flag: once switched off it stays off for every generation in the session.
 */

let enabled = true

export function enableTemplateSelect(): void { enabled = true }

export function disableTemplateSelect(): void { enabled = false }

export function templateSelectEnabled(): boolean { return enabled }
