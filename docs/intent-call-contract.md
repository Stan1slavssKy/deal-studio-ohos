# `intent.call`: signature, encoding, and the answer contract that gets misread

## Signature

```ts
intent.call(target: string, params: string[], mode: string, handler: string): int
```

Declared as an `ExternalFunction` in the compiler:

```ts
fns.push(new ExternalFunction('call',
  [STRING, new VeraArrayType(STRING), STRING, STRING], INT, false))
```
— `VeraCompiler.ets:1246`.

| parameter | shape | meaning |
|---|---|---|
| `target` | `string` | `bundleName/moduleName/abilityName/IntentName` — exactly four parts, split on `/` |
| `params` | `string[]` | flat `[name, value, name, value, ...]`, or `[]`. Never JSON: the language has no way to escape a quote or a line break in a string literal, so the host builds the object |
| `mode` | `string` | `"background"` or `"foreground"` |
| `handler` | `string` | the name of a function `(state: AppState, value: string) => AppState` that receives the answer, later, as its own dispatch |
| returns | `int` | a request id; every generated program so far ignores it |

## How the flat array becomes a payload

`runRawIntent` (`VeraIntents.ets:131`) splits `target` on `/` and rejects
anything that isn't four parts. The `params` pairs go through `writeParam`
(`VeraIntents.ets:75`) one at a time:

```ts
function writeParam(params: Record<string, Object>, platformName: string, value: Object): void {
  let dot = platformName.indexOf('.')
  if (dot < 0) { params[platformName] = value; return }
  let group = platformName.substring(0, dot)
  let leaf = platformName.substring(dot + 1)
  ...
  nested![leaf] = value
}
```

A name containing one dot nests one level (`"dstLocation.latitude"` becomes
`{dstLocation: {latitude: ...}}`); this is the same helper the catalogue rows
use for `buildParams`, so `intent.call` and a checked row build payloads the
same way. There is no second level of nesting available to a program — if a
target needs one, `intent.call` cannot express it and nothing here will tell
you that at compile time.

## The answer: four shapes, and only one test tells them apart

This is the part worth reading closely, because the shape that means success is
not the shape most generated code checks for. From `runRawIntent`
(`VeraIntents.ets:131-163`):

```ts
try {
  let result: insightIntent.ExecuteResult = await insightIntentDriver.execute(param)
  let payload = result.result === undefined || result.result === null
    ? '' : JSON.stringify(result.result)
  if (result.code !== 0) { return 'declined code=' + result.code.toString() }
  return payload.length > 0 ? payload : 'ok'
} catch (e) {
  return 'error ' + err.code.toString() + ': ' + err.message
}
```

| what the target did | string the handler receives |
|---|---|
| accepted the call, sent data back | **the target's own JSON, verbatim** — e.g. `{"intentName":"OpenFlashlight"}` |
| accepted the call, sent nothing back | the literal string `"ok"` |
| refused the call (`code !== 0`) | `"declined code=" + code` |
| the platform itself failed (permission, bad target, ...) | `"error " + code + ": " + message` |

**`"ok"` is the exception, not the rule.** On this phone, every probed
`intent.call` target that answered success at all answered with JSON — `ok`
only fires when `result.result` is empty, which is rarer in practice than a
target that echoes something back. A handler written to treat `"ok"` as *the*
success signal is right by accident whenever the JSON case doesn't come up, and
silently wrong the rest of the time.

**The only correct test is the negative one**: a call succeeded if the answer
does *not* start with `"declined"` and does *not* start with `"error"`.
Everything else — `"ok"` or any JSON object — is a success and the handler
should treat it as one.

```ts
function ok(answer: string): boolean {
  return !strings.startsWith(answer, "declined") && !strings.startsWith(answer, "error");
}
```

## Where the wording invites the mistake

`entry/src/main/resources/rawfile/vera-skill.txt` documents two contracts
back to back, in language similar enough that a model reasonably conflates
them:

- for a **catalogue** row (`vera-skill.txt:227-230`): *"The string is `"ok"`,
  or `"declined code=..."` ..., or `"error ..."` ... it is the only sign the
  call worked."* — stated as an equivalence: ok means success.
- for **`intent.call`** (`vera-skill.txt:250-251`): *"The answer is the
  target's own result as JSON text, or `"ok"`, or an error line, or `"declined
  by the person"`."* — stated as an enumeration, with no worked example of how
  to tell success from failure when the answer is JSON.

Nothing in the prompt tells the model the rule above (declined/error are the
only failure shapes; everything else is success). Left to infer it, a model
reaches for the pattern the paragraph just above trained it on — check for
`"ok"` — because that is the only concrete success test the prompt actually
demonstrates.

## Two confirmed cases (device session, 2026-09-24/25)

Both from `docs/prompts/intent-coverage.md` prompts 1 and 2, generated by
deepseek-flash, run on a system-signed build, verified against `hdc shell
hilog` and the physical device.

**Torch** (prompt 1) never increments its own "times lit / times out" counters:

```ts
function onAnswer(state: AppState, value: string): AppState {
  if (strings.contains(value, "ok")) {          // never true: the real answer
    if (state.pending === 1) { ons = ons + 1; } // is {"intentName":"OpenFlashlight"}
    ...
  }
  return {..., onCount: ons, offCount: offs};
}
```
`hilog` for the same tap: `VERA-INTENT-RAW ... OpenFlashlight code=0
result={"intentName":"OpenFlashlight"}` — the flashlight physically turned on,
the counter stayed at 0.

**One Hand** (prompt 2) shows the mirror-image mistake: it never checks the
answer at all, so a refusal looks identical to success.

```ts
function toggleSingleHand(state: AppState, value: boolean): AppState {
  intent.call(".../TurnOnSingleHandMode", [], "background", "onAnswer");
  return {singleHand: value, ...};              // flips immediately, optimistically
}
function onAnswer(state: AppState, value: string): AppState {
  return {..., lastResult: value};              // stores the answer, reconciles nothing
}
```
`hilog`: `code=10010001 result={"resultDesc":"开关已经是打开的了"}` — the
target *refused* ("the switch is already on"), and the toggle still displayed
On.

Neither program is malformed by the compiler's own rules — `checkIntentArguments`
only validates names and closed value sets, never runtime behaviour — so this
class of bug reaches the phone every time, compiles clean, and only shows up by
comparing the screen against `hilog` by hand.

## What this is not

`docs/prompts/intent-coverage.md` prompt 9 ("Note keeper") failed a different
way in the same session: it compiled successfully and then crashed at render
with `View error: array index out of bounds`. That is a runtime defect in
`view()`, unrelated to the answer contract above — worth keeping distinct
because the fix is different (bounds-check a list access, not reconcile an
async answer) and because it demonstrates that `"Compiled successfully"` only
means the static checks passed, not that the program runs.

## Source map

| what | where |
|---|---|
| `intent.call`'s compiler signature | `VeraCompiler.ets:1246` |
| the two answer contracts as told to the model | `vera-skill.txt:220-234` (catalogue), `vera-skill.txt:236-266` (`intent.call`) |
| flat array → nested payload | `VeraIntents.ets:75` (`writeParam`) |
| the four answer shapes | `VeraIntents.ets:131-165` (`runRawIntent`) |
| dispatch from the VM into the raw path | `VeraUi.ets:697` (`queueRawIntent` call site), `VeraUi.ets:737` |
| the "only from a handler, never from view" rule | `VeraUi.ets:363` (`effectsAllowed`) |
| every call and its real answer, as it happened | `hdc shell "hilog | grep VERA-INTENT"` |
