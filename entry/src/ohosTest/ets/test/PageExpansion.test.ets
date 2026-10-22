import { describe, it, expect } from '@ohos/hypium';
import { PageExpansion, ExpansionStep } from '../../../main/ets/service/PageExpansion';
import { ScanData } from '../../../main/ets/service/PageScanner';
import { ScanImage } from '../../../main/ets/service/PictureFactory';

function page(url: string, images: string[], bottom: boolean = true): ExpansionStep {
  return { data: { url: url, title: 'fixture',
    images: images.map((image: string): ScanImage => ({ url: image, description: '' })) }, bottom: bottom };
}

export default function pageExpansionTest() {
  describe('PageExpansion', () => {
    it('merges_new_urls_and_stops_after_stable_bottom', 0, async () => {
      const loader: PageExpansion = new PageExpansion();
      let calls: number = 0;
      let count: number = -1;
      let limited: boolean = true;
      await loader.run('https://example.test/', ['old'], async (): Promise<ExpansionStep> => {
        calls++;
        return page('https://example.test/', ['old', 'new', 'new']);
      }, (): void => {}, (added: number, capped: boolean): void => { count = added; limited = capped; },
      (): void => { throw new Error('unexpected failure'); }, 0);
      expect(calls).assertEqual(4);
      expect(count).assertEqual(1);
      expect(limited).assertFalse();
    });

    it('caps_infinite_pages_at_twelve_steps', 0, async () => {
      const loader: PageExpansion = new PageExpansion();
      let calls: number = 0;
      let capped: boolean = false;
      await loader.run('https://example.test/', [], async (): Promise<ExpansionStep> => {
        calls++;
        return page('https://example.test/', [calls.toString()], false);
      }, (): void => {}, (added: number, limited: boolean): void => {
        expect(added).assertEqual(12); capped = limited;
      }, (): void => {}, 0);
      expect(calls).assertEqual(12);
      expect(capped).assertTrue();
    });

    it('drops_late_results_after_stop', 0, async () => {
      const loader: PageExpansion = new PageExpansion();
      let updates: number = 0;
      let settled: boolean = false;
      await loader.run('https://example.test/', [], async (): Promise<ExpansionStep> => {
        loader.stop();
        return page('https://example.test/', ['late']);
      }, (): void => { updates++; }, (): void => { settled = true; }, (): void => {}, 0);
      expect(updates).assertEqual(0);
      expect(settled).assertFalse();
    });

    it('does_not_merge_a_different_page', 0, async () => {
      const loader: PageExpansion = new PageExpansion();
      let failed: boolean = false;
      let updates: number = 0;
      await loader.run('https://example.test/', [], async (): Promise<ExpansionStep> =>
        page('https://other.test/', ['wrong']),
      (data: ScanData): void => { updates += data.images.length; }, (): void => {},
      (): void => { failed = true; }, 0);
      expect(updates).assertEqual(0);
      expect(failed).assertTrue();
    });

    it('stopping_during_the_delay_does_not_inject_another_script', 0, async () => {
      const loader: PageExpansion = new PageExpansion();
      let calls: number = 0;
      const work: Promise<void> = loader.run('https://example.test/', [], async (): Promise<ExpansionStep> => {
        calls++; return page('https://example.test/', []);
      }, (): void => {}, (): void => {}, (): void => {}, 1000);
      loader.stop();
      await work;
      expect(calls).assertEqual(0);
    });
  });
}
