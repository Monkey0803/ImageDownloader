import { describe, it, expect } from '@ohos/hypium';
import { GalleryAspect } from '../../../main/ets/util/GalleryAspect';
import { LibraryFlowRow, LibraryFlowRows } from '../../../main/ets/viewmodel/LibraryFlowRows';

export default function galleryFlowTest() {
  describe('GalleryAspect', () => {
    it('uses_original_ratio_with_bounds_and_square_fallback', 0, () => {
      expect(GalleryAspect.heightRatio(100, 150)).assertEqual(1.5);
      expect(GalleryAspect.heightRatio(100, 400)).assertEqual(1.8);
      expect(GalleryAspect.heightRatio(400, 100)).assertEqual(0.7);
      expect(GalleryAspect.heightRatio(0, 100)).assertEqual(1);
      expect(GalleryAspect.heightRatio(100, Number.NaN)).assertEqual(1);
    });
  });

  describe('LibraryFlowRows', () => {
    it('keeps_stable_identity_and_updates_changed_rows', 0, () => {
      const source: LibraryFlowRows = new LibraryFlowRows();
      let reloads: number = 0;
      const changes: number[] = [];
      const listener: DataChangeListener = {
        onDataReloaded: (): void => { reloads++; },
        onDataAdd: (index: number): void => {},
        onDataMove: (from: number, to: number): void => {},
        onDataDelete: (index: number): void => {},
        onDataChange: (index: number): void => { changes.push(index); },
        onDataAdded: (index: number): void => {},
        onDataMoved: (from: number, to: number): void => {},
        onDataDeleted: (index: number): void => {},
        onDataChanged: (index: number): void => {},
        onDatasetChange: (operations: DataOperation[]): void => {}
      };
      source.registerDataChangeListener(listener);
      const header: LibraryFlowRow = new LibraryFlowRow(); header.key = 'controls';
      const image: LibraryFlowRow = new LibraryFlowRow(); image.key = 'image|1'; image.state = 'off';
      source.replace([header, image]);
      expect(reloads).assertEqual(1);
      const changed: LibraryFlowRow = new LibraryFlowRow(); changed.key = 'image|1'; changed.state = 'on';
      source.replace([header, changed]);
      expect(reloads).assertEqual(1);
      expect(changes.includes(1)).assertTrue();
      expect(source.totalCount()).assertEqual(2);
      source.unregisterDataChangeListener(listener);
    });
  });
}
