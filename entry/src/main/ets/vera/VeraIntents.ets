/**
 * The only place in the project that calls the platform's intent framework.
 *
 * Nothing here knows the name of any intent: the target, the parameter names
 * and the accepted values all arrive as an IntentSpec from VeraIntentCatalog.
 * Adding an intent therefore never touches this file.
 *
 * insightIntentDriver is a system API, gated twice over: the provision profile
 * must carry "app-feature": "hos_system_app" (otherwise every call is 202) and
 * ohos.permission.EXECUTE_INSIGHT_INTENT must be granted through the profile's
 * acls.allowed-acls (otherwise 201). Both are signing, not code, so the
 * failures are reported as they arrive rather than hidden -- the status string
 * is what the generated program shows its user.
 */

import insightIntentDriver from '@ohos.app.ability.insightIntentDriver'
import insightIntent from '@ohos.app.ability.insightIntent'
import hilog from '@ohos.hilog'
import { BusinessError } from '@ohos.base'
import { IntentSpec } from './VeraIntentCatalog'

const DOMAIN = 0x0000

/**
 * Field values as the program wrote them, translated into the payload the
 * platform expects: catalogue names become platform names, catalogue values
 * become platform values, and an empty string means "omit" -- which is how a
 * language with no optional record fields expresses an optional parameter.
 */
function buildParams(spec: IntentSpec, values: Map<string, string>): Record<string, Object> {
  let params: Record<string, Object> = {}
  for (let p of spec.params) {
    let raw = values.get(p.name)
    if (raw === undefined) { continue }
    let text = raw as string
    if (text.length === 0) { continue }
    let mapped = p.valueMap.get(text)
    let out: string = mapped !== undefined ? mapped as string : text
    if (p.kind === 'int') {
      params[p.platformName] = Number.parseInt(out, 10) as Object
    } else {
      params[p.platformName] = out as Object
    }
  }
  return params
}

/**
 * Runs one intent and describes the outcome in a line a person can read.
 *
 * The code in a resolved ExecuteResult is chosen by the target's developer, not
 * by the framework, so a non-zero code is the target talking -- PlayMusicList
 * answers 100060202 for a delisted playlist -- and is reported as such rather
 * than as a failed call.
 */
export async function runIntent(spec: IntentSpec, values: Map<string, string>): Promise<string> {
  let params = buildParams(spec, values)
  let param: insightIntentDriver.ExecuteParam = {
    bundleName: spec.bundle,
    moduleName: spec.moduleName,
    abilityName: spec.ability,
    insightIntentName: spec.intentName,
    insightIntentParam: params,
    // Which mode is on the row, not a fixed choice here: a target that declares
    // only foreground rejects a background call, and one that supports both
    // should not seize the screen for something the user only wanted to hear.
    executeMode: spec.mode === 'background'
      ? insightIntent.ExecuteMode.UI_ABILITY_BACKGROUND
      : insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND
  }
  hilog.info(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' -> ' + spec.bundle + '/' +
    spec.moduleName + '/' + spec.ability + ' mode=' + spec.mode +
    ' params=' + JSON.stringify(params))
  try {
    let result: insightIntent.ExecuteResult = await insightIntentDriver.execute(param)
    if (result.code === 0) {
      hilog.info(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' ok')
      return 'ok'
    }
    hilog.info(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' declined ' + result.code.toString())
    return 'declined code=' + result.code.toString()
  } catch (e) {
    let err = e as BusinessError
    hilog.error(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' failed ' + err.code.toString() +
      ': ' + err.message)
    return 'error ' + err.code.toString() + ': ' + err.message
  }
}
