import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import window from '@ohos.window';
import hilog from '@ohos.hilog';

const DOMAIN = 0x0000

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', 'EntryAbility onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', 'EntryAbility onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err): void => {
      if (err?.code) {
        hilog.info(DOMAIN, 'testTag', 'EntryAbility onWindowStageCreate. Cause: ${public}s', err);
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'EntryAbility onWindowStageCreate ok');
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', 'EntryAbility onDestroy');
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', 'EntryAbility onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag  EntryAbility', 'EntryAbility onBackground');
  }
}
