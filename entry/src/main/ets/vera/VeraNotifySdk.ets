/**
 * What a program needs to tell the person something while it runs: a notification now (a timer or a round that ended, a reading
 * past its limit), and the system's question that switches notifications on for the app.
 *
 * A reminder at a later time is not here. The reminder agent (reminderAgentManager.publishReminder) answers 1700002 "The number of
 * reminders exceeds the limit" on this phone with no reminder set: the log says "VerifyCloudCapability failed ... reminder_capability"
 * and "notification not allowed", a limit of 0 for an app the store has not granted that capability, system-signed or not
 * (measured 2026-11-03). A reminder at a time of day goes into the phone calendar with an alert instead (VeraCalendarSdk.ets).
 *
 * Each call answers in the shapes of docs/intent-call-contract.md: a value, "ok", "declined code=N" or "error ...".
 */
import { notificationManager } from '@kit.NotificationKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { AbilityContext } from './VeraPermissions'

const NOTIFICATION: string = 'NotificationKit.notificationManager.'

export const notifySdkTargets: string[] = [NOTIFICATION + 'publish', NOTIFICATION + 'requestEnableNotification']

/** The parameters, the answer and an example of each, for find_sdk_function to show the section writer. */
export class NotifySdkContract {
  params: string
  returns: string
  description: string
  example: string
  constructor(params: string, returns: string, description: string, example: string) {
    this.params = params
    this.returns = returns
    this.description = description
    this.example = example
  }
}

export function notifySdkContract(target: string): NotifySdkContract | undefined {
  if (target === NOTIFICATION + 'publish') {
    return new NotifySdkContract('title: short text, text: one or two lines', 'string',
      'Shows a notification now. Answers its id as text, or an error such as "error: notifications are off".',
      'sdk.call("NotificationKit.notificationManager.publish", ["title", "Done", "text", "All rounds finished"], "onNotified")')
  }
  if (target === NOTIFICATION + 'requestEnableNotification') {
    return new NotifySdkContract('', 'string',
      'Asks the person to switch notifications on for this app (a system dialog). Answers ok when they are on.',
      'sdk.call("NotificationKit.notificationManager.requestEnableNotification", [], "onAllowed")')
  }
  return undefined
}

function words(params: Map<string, string>, name: string, fallback: string, max: number): string {
  let t = (params.get(name) ?? '').trim()
  if (t.length === 0) { t = fallback }
  return t.length > max ? t.substring(0, max) : t
}

function failure(e: Object): string {
  let code = (e as BusinessError).code
  let message = (e as Error).message ?? String(e)
  // 1600004: notifications are off for this app (NotificationKit); the person switches them on through requestEnableNotification.
  if (code === 1600004) {
    return 'error 1600004: notifications are off for this app -- call NotificationKit.notificationManager.requestEnableNotification'
  }
  return 'error' + (code !== undefined ? ' ' + code.toString() : '') + ': ' + message
}

async function notificationsOn(): Promise<boolean> {
  try { return await notificationManager.isNotificationEnabled() } catch (_e) { return true }
}

export async function runNotifySdkAdapter(target: string, params: Map<string, string>): Promise<string> {
  try {
    if (target === NOTIFICATION + 'requestEnableNotification') {
      if (await notificationsOn()) { return 'ok' }
      let context = AbilityContext.value
      if (context === null) { return 'error: no window to ask from' }
      await notificationManager.requestEnableNotification(context)
      return (await notificationsOn()) ? 'ok' : 'declined code=0'
    }
    if (!(await notificationsOn())) {
      return 'error: notifications are off for this app -- call NotificationKit.notificationManager.requestEnableNotification'
    }
    if (target === NOTIFICATION + 'publish') {
      let id = Math.floor(Date.now() / 1000) % 2000000000
      let request: notificationManager.NotificationRequest = {
        id: id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: words(params, 'title', 'Reminder', 200), text: words(params, 'text', ' ', 1000) }
        }
      }
      await notificationManager.publish(request)
      return id.toString()
    }
    return 'error: no such target'
  } catch (e) {
    return failure(e as Object)
  }
}
