import { describe, it, expect } from '@ohos/hypium';
import { SuperResolutionGeometry } from '../../../main/ets/service/SuperResolutionGeometry';
import { PreviewSize } from '../../../main/ets/model/ImageEditDocument';

export default function superResolutionTest() {
  describe('SuperResolutionGeometry', () => {
    it('bounds_long_edge_and_keeps_aspect_ratio', 0, () => {
      const small: PreviewSize = SuperResolutionGeometry.decodeSize(960, 1280);
      expect(small.width).assertEqual(960);
      expect(small.height).assertEqual(1280);

      const tall: PreviewSize = SuperResolutionGeometry.decodeSize(2000, 3551);
      expect(tall.height).assertEqual(1600);
      expect(tall.width).assertEqual(901);

      const wide: PreviewSize = SuperResolutionGeometry.decodeSize(3551, 2000);
      expect(wide.width).assertEqual(1600);
      expect(wide.height).assertEqual(901);

      expect(SuperResolutionGeometry.decodeSize(0, 100).width).assertEqual(0);
    });

    it('accepts_real_output_growth_and_rejects_bad_shapes', 0, () => {
      expect(SuperResolutionGeometry.accepts(960, 1280, 3840, 5120)).assertTrue();
      expect(SuperResolutionGeometry.accepts(960, 1280, 1920, 2560)).assertTrue();
      expect(SuperResolutionGeometry.accepts(960, 1280, 960, 1280)).assertFalse();
      expect(SuperResolutionGeometry.accepts(960, 1280, 800, 1000)).assertFalse();
      expect(SuperResolutionGeometry.accepts(960, 1280, 3840, 5000)).assertFalse();
      expect(SuperResolutionGeometry.accepts(0, 1280, 3840, 5120)).assertFalse();
    });
  });
}
