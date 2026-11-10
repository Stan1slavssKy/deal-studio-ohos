import { SymbolGlyphModifier } from '@kit.ArkUI'
import { AppRouteParams } from '../vera/AppNavigation'

/** The Settings page, from any screen. Tapped again from a page above it, it goes back to the one already open. */
export function openSettings(pathStack: NavPathStack): void {
  if (pathStack.getAllPathName().indexOf('settings') >= 0) {
    pathStack.popToName('settings')
    return
  }
  pathStack.pushPath({ name: 'settings', param: new AppRouteParams() })
}

/** The gear in a title bar: the same item on every screen that has a title bar. */
export function settingsMenuItem(pathStack: NavPathStack): NavigationMenuItem {
  return {
    value: 'Settings',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape')),
    action: () => { openSettings(pathStack) }
  }
}
