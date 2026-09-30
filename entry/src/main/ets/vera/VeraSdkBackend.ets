/**
 * A small, curated set of real adapters for sdk.call's sdk-style targets --
 * the same relationship VeraIntentCatalog has to the raw intent registry.
 * This is deliberately not "the rest of interface_sdk-js": it is the
 * handful of rows someone has actually read the real signature of, written a
 * binding for, and probed on a phone. Everything else sdk.call can address
 * (the full closed set VeraSdkIndex.isValidSdkTarget checks a target
 * against) still compiles -- it answers with the same "not implemented yet"
 * stub it always has, until a row is added here too.
 *
 * Why a curated table rather than generic reflection dispatch: ArkTS gives
 * no safe way to resolve a module and call a named export by a runtime
 * string the way dynamic JavaScript could, and even if it did, that would
 * only solve half the problem. sdk.call's own parameters are plain name/
 * value strings (the language has no other way to write a call argument),
 * while an arbitrary interface_sdk-js function takes enums, numbers,
 * booleans and nested objects -- there is no generic rule for turning
 * ["mode", "0"] into the right typed argument for a function nobody has
 * looked at. Only a person who has read that one function's actual
 * signature can bridge that gap, which is exactly the process
 * docs/intents-design.md section 7 already describes for adding a row to
 * VeraIntentCatalog -- this is the same idea, for the sdk surface.
 *
 * Adding a row: read the real signature in interface_sdk-js, write a
 * function that turns `params` into the right typed call and its answer
 * back into one string, and add it below keyed by the exact
 * "Kit.module.name" target VeraSdkIndex uses. Probe it on a phone before
 * trusting it -- the same rule every other row in this codebase follows.
 */

import storageStatistics from '@ohos.file.storageStatistics'

/** One row's real implementation: sdk.call's parameters in, its answer string out. */
export type SdkAdapter = (params: Map<string, string>) => Promise<string>

const ADAPTERS: Map<string, SdkAdapter> = new Map<string, SdkAdapter>([
  // Both zero-argument and synchronous in the real API -- about as simple as
  // this surface gets, which is why they're first. Needs
  // ohos.permission.STORAGE_MANAGER (module.json5), system_basic APL
  // (signing/UnsgnedReleasedProfileTemplate.json) -- both already true of
  // this app for std/intent's own sake.
  ['CoreFileKit.storageStatistics.getFreeSizeSync', async (_params: Map<string, string>): Promise<string> => {
    return storageStatistics.getFreeSizeSync().toString()
  }],
  ['CoreFileKit.storageStatistics.getTotalSizeSync', async (_params: Map<string, string>): Promise<string> => {
    return storageStatistics.getTotalSizeSync().toString()
  }],
])

/**
 * Runs the real adapter for `target`, or answers with the same stub text
 * sdk.call has always used if this target doesn't have one yet -- callers
 * don't need to check first, and a target with no adapter is never the
 * reason a call hangs.
 */
export async function runSdkAdapter(target: string, params: Map<string, string>): Promise<string> {
  let adapter = ADAPTERS.get(target)
  if (adapter === undefined) {
    return 'error: sdk.call is not implemented yet'
  }
  try {
    return await adapter(params)
  } catch (e) {
    return 'error: ' + (e as Error).message
  }
}
