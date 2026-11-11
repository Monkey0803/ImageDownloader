import { describe, it, expect } from '@ohos/hypium';
import { windowInsets, WindowInsets } from '../../../main/ets/util/WindowAvoidPolicy';

export default function windowAvoidPolicyTest() {
  describe('WindowAvoidPolicy', () => {
    it('uses_largest_live_avoid_area_on_each_edge', 0, () => {
      const insets: WindowInsets = windowInsets(72, 24, 40, 100, 16, 36, 20, 2);
      expect(insets.top).assertEqual(50);
      expect(insets.bottom).assertEqual(20);
      expect(insets.left).assertEqual(18);
      expect(insets.right).assertEqual(10);
    });
    it('ignores_negative_areas_and_bad_density', 0, () => {
      const insets: WindowInsets = windowInsets(-5, 0, -8, 0, 0, 0, 0, 0);
      expect(insets.top).assertEqual(0);
      expect(insets.bottom).assertEqual(0);
    });
  });
}
