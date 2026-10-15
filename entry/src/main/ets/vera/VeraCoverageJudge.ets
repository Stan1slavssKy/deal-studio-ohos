/**
 * Does the screen cover the request? One yes/no question to Jev, after the program is built.
 *
 * Without this a template that is the right kind of screen but cannot do what was asked passes every
 * other check -- a grocery checklist for "calculate the amounts for 10 people" compiles, runs and
 * draws a list. Jev sees the request and a plain description of what the screen shows (component
 * kinds and visible text, from VeraSmokeRun.ets) and answers with a probability.
 *
 * The state sent is the person's request and that description of the generated screen, nothing the
 * program holds at run time. Any failure answers -1 ("no opinion"), and callers never block on it.
 */

import http from '@ohos.net.http'
import hilog from '@ohos.hilog'

const DOMAIN = 0x0000
const ENDPOINT: string = 'https://api.typesafe.ai/v1/systemone'
const MODEL: string = 'jev-latest'

/**
 * Below this probability the screen is taken not to cover the request and goes to the model to be
 * finished. 0 means never: the judge only reports. It was 0.5, then 0.2, and neither held up on the
 * device: good screens scored 0.34-0.52 (packing and grocery lists), a correct bar chart of three
 * given numbers scored 0.05 and then 0.18 (the second time with the chart's values in the description),
 * and the one clearly insufficient screen (a checklist asked to scale quantities to three days) scored
 * 0.03. A bar below 0.2 therefore threw away a correct template as often as it caught a weak one, and
 * nothing separates 0.03 from 0.05. The value is still logged (VERA-JUDGE) and shown as `covers=` in the
 * note. Turning it back on needs a better question or a handful of labelled good and bad screens.
 */
export const COVERS_BELOW: number = 0

export function buildJudgeRequest(request: string, summary: string): string {
  let criteria: Record<string, Object> = {}
  criteria['true'] = 'yes, every part of the request is present on this screen and would work'
  criteria['false'] = 'no, something the request asks for is missing, is only a placeholder, or cannot work on this screen'
  let question: Record<string, Object> = {}
  question['type'] = 'noul'
  question['instructions'] = 'Below is a request for an app and a description of the screen that was built for it. ' +
    'Does the screen cover everything the request asks for -- every calculation, input, list, chart and button it names -- ' +
    'and not merely the same kind of screen? Sample names and numbers are fine; a missing feature is not.'
  question['criteria'] = criteria
  let questions: Record<string, Object> = {}
  questions['covers'] = question
  let body: Record<string, Object> = {}
  body['model'] = MODEL
  body['state'] = 'Request: ' + request + '\nScreen built: ' + summary
  body['questions'] = questions
  return JSON.stringify(body)
}

/** Probability that the screen covers the request, or -1 when Jev could not be asked or the answer was unreadable. */
export function readJudgeAnswer(body: string): number {
  try {
    let parsed = JSON.parse(body) as Record<string, Object>
    let answers = parsed['answers'] as Record<string, Object>
    if (answers === null || answers === undefined) { return -1 }
    let answer = answers['covers'] as Record<string, Object>
    if (answer === null || answer === undefined) { return -1 }
    let value = answer['noul']
    if (typeof value !== 'number') { return -1 }
    let p = value as number
    return p < 0 || p > 1 ? -1 : p
  } catch (_e) {
    return -1
  }
}

export async function judgeCoverage(request: string, summary: string, apiKey: string): Promise<number> {
  if (apiKey.length === 0 || request.trim().length === 0 || summary.length === 0) { return -1 }
  let client = http.createHttp()
  try {
    let headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + apiKey
    let started = Date.now()
    let response = await client.request(ENDPOINT, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: buildJudgeRequest(request, summary),
      connectTimeout: 5000,
      readTimeout: 15000
    })
    if ((response.responseCode as number) !== 200) {
      hilog.warn(DOMAIN, 'VERA', 'VERA-JUDGE http ' + (response.responseCode as number).toString())
      return -1
    }
    let p = readJudgeAnswer(response.result as string)
    hilog.info(DOMAIN, 'VERA', 'VERA-JUDGE ms=' + (Date.now() - started).toString() + ' covers=' + p.toFixed(2))
    return p
  } catch (e) {
    hilog.warn(DOMAIN, 'VERA', 'VERA-JUDGE failed: ' + (e as Error).message)
    return -1
  } finally {
    client.destroy()
  }
}
