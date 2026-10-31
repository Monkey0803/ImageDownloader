import { describe, it, expect } from '@ohos/hypium';
import { CollectionRecord, DownloadItem, PictureItem, SavedState, ZipItem } from '../../../main/ets/model/Models';
import { CollectionNames } from '../../../main/ets/service/CollectionNames';
import { CollectionGroups, CollectionSummary } from '../../../main/ets/service/CollectionGroups';
import { StoreState } from '../../../main/ets/service/StoreState';
import { copyIntoDirectory, ActionOutcome } from '../../../main/ets/service/FileActions';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { LivePhoto } from '../../../main/ets/service/LivePhoto';

export default function collectionGroupsTest() {
  describe('CollectionGroups', () => {
    it('names_selected_images_without_losing_original_extensions', 0, () => {
      const picture: PictureItem = new PictureItem();
      picture.url = 'https://example.com/photo.webp?sig=1'; picture.name = 'photo.webp';
      expect(CollectionNames.filename(picture, '素材页', 3, 'original')).assertEqual('photo.webp');
      expect(CollectionNames.filename(picture, '素材页', 3, 'numbered')).assertEqual('素材页_003.webp');
      expect(CollectionNames.folder('素材页', 'page:https://a').length > 0).assertTrue();
      expect(CollectionNames.folder('素材页', 'page:https://a') ===
        CollectionNames.folder('素材页', 'page:https://b')).assertFalse();
    });

    it('keeps_collection_metadata_through_restart_and_counts_zip_members_once', 0, () => {
      const state: SavedState = new SavedState();
      const record: CollectionRecord = new CollectionRecord();
      record.id = 'page:https://a'; record.name = '素材页'; record.added = 4; record.skipped = 2;
      state.collections = [record];
      const item: DownloadItem = new DownloadItem();
      item.id = '1'; item.collectionId = record.id; item.collectionName = record.name;
      item.collectionFolder = '素材页-12345678'; item.status = 'completed';
      state.downloads = [item];
      const zip: ZipItem = new ZipItem();
      zip.id = '2'; zip.collectionId = record.id; zip.collectionName = record.name;
      zip.collectionFolder = item.collectionFolder; zip.imageCount = 2; zip.failedCount = 1;
      state.zips = [zip];
      const restored: SavedState = StoreState.normalized(StoreState.parse(StoreState.serialize(state)) as SavedState);
      expect(restored.downloads[0].collectionFolder).assertEqual(item.collectionFolder);
      expect(restored.zips[0].collectionId).assertEqual(record.id);
      const groups: CollectionSummary[] = CollectionGroups.summaries(restored.downloads, restored.zips,
        restored.batches, restored.collections);
      expect(groups.length).assertEqual(1);
      expect(groups[0].added).assertEqual(4);
      expect(groups[0].skipped).assertEqual(2);
      expect(groups[0].completed).assertEqual(3);
      expect(groups[0].failed).assertEqual(1);
    });

    it('old_records_stay_ungrouped', 0, () => {
      const old: DownloadItem = new DownloadItem(); old.status = 'completed';
      const groups: CollectionSummary[] = CollectionGroups.summaries([old], [], [], []);
      expect(groups.length).assertEqual(1);
      expect(groups[0].name).assertEqual('未分组');
      expect(groups[0].completed).assertEqual(1);
    });

    it('keeps_an_edited_copy_visible_in_its_source_group', 0, () => {
      const edited: DownloadItem = new DownloadItem();
      edited.origin = 'edited'; edited.status = 'completed';
      edited.collectionId = 'page:https://example.com'; edited.collectionName = '网页素材';
      const groups: CollectionSummary[] = CollectionGroups.summaries([edited], [], [], []);
      expect(groups.length).assertEqual(1);
      expect(groups[0].name).assertEqual('网页素材');
    });

    it('creates_a_source_folder_and_copies_without_overwriting', 0, async () => {
      const root: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir
        + '/collection-copy-' + Date.now().toString();
      fs.mkdirSync(root, true);
      const source: string = root + '/source.png';
      try {
        const file: fs.File = fs.openSync(source, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        try { fs.writeSync(file.fd, 'image-bytes'); } finally { fs.closeSync(file); }
        const uri: string = fileUri.getUriFromPath(root);
        const first: ActionOutcome = await copyIntoDirectory(source, uri, 'photo.png', '素材页');
        const second: ActionOutcome = await copyIntoDirectory(source, uri, 'photo.png', '素材页');
        expect(first.message + ' | ' + second.message).assertEqual(' | ');
        expect(first.ok).assertTrue(); expect(second.ok).assertTrue();
        expect(fs.readTextSync(root + '/素材页/photo.png')).assertEqual('image-bytes');
        expect(fs.readTextSync(root + '/素材页/photo (2).png')).assertEqual('image-bytes');
      } finally { LivePhoto.removeTree(root); }
    });
  });
}
