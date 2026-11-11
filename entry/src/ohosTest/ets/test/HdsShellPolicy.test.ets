import { describe, it, expect } from '@ohos/hypium';
import { hdsShellPlan, HdsShellPlan } from '../../../main/ets/util/HdsShellPolicy';
import { TAB_DISCOVER, TAB_LIBRARY } from '../../../main/ets/model/Navigation';

export default function hdsShellPolicyTest() {
  describe('HdsShellPolicy', () => {
    it('keeps_web_tab_opaque_and_hides_tabs_on_results', 0, () => {
      const browser: HdsShellPlan = hdsShellPlan(TAB_DISCOVER, true, true, 'adaptive', true, 35);
      expect(browser.showTabs).assertTrue();
      expect(browser.tabMaterial).assertFalse();
      expect(browser.titleMaterial).assertTrue();
      expect(browser.bottomMargin).assertEqual(35);
      const results: HdsShellPlan = hdsShellPlan(TAB_DISCOVER, false, true, 'adaptive', true, 0);
      expect(results.showTabs).assertFalse();
      expect(results.bottomMargin).assertEqual(0);
    });

    it('enables_both_hds_slots_and_respects_disabled_or_unsupported_material', 0, () => {
      expect(hdsShellPlan(TAB_LIBRARY, true, true, 'immersive', true, 12).tabMaterial).assertTrue();
      expect(hdsShellPlan(TAB_LIBRARY, true, false, 'immersive', true, 12).titleMaterial).assertFalse();
      expect(hdsShellPlan(TAB_LIBRARY, true, true, 'none', true, 12).tabMaterial).assertFalse();
      expect(hdsShellPlan(TAB_LIBRARY, true, true, 'adaptive', false, 12).tabMaterial).assertFalse();
    });
  });
}
