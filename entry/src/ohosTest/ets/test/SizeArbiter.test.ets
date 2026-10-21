import { describe, it, expect } from '@ohos/hypium';
import { SizeArbiter } from '../../../main/ets/service/SizeArbiter';

export default function sizeArbiterTest() {
  describe('SizeArbiter.selectMeasured', () => {
    const cap: number = 32 * 1024 * 1024;

    it('keeps_a_page_declared_large_original_instead_of_its_thumbnail', 0, () => {
      expect(SizeArbiter.selectMeasured(['original', 'thumbnail'], [36000054, 789], cap, 'original'))
        .assertEqual('original');
    });

    it('rejects_an_over_limit_inferred_replacement', 0, () => {
      expect(SizeArbiter.selectMeasured(['inferred', 'displayed'], [100000000, 789], cap, 'displayed'))
        .assertEqual('displayed');
    });

    it('leaves_unmeasured_and_unapproved_candidates_for_the_caller_to_handle', 0, () => {
      expect(SizeArbiter.selectMeasured(['missing', 'inferred'], [0, 100000000], cap, 'missing'))
        .assertEqual('');
    });
  });
}
