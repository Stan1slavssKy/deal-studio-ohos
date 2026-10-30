import { pasteboard } from '@kit.BasicServicesKit'

/** Puts text on the system clipboard and says so. */
export function copyText(ui: UIContext, text: string): void {
  let message = 'Copied'
  try {
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
  } catch (e) {
    console.error('Copy failed: ' + (e as Error).message)
    message = 'Cannot copy'
  }
  try {
    ui.getPromptAction().showToast({ message: message })
  } catch (e) {
    console.error('Show copy message failed: ' + (e as Error).message)
  }
}
