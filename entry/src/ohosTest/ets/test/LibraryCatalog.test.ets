import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DownloadItem } from '../../../main/ets/model/Models';
import { LibraryCatalog } from '../../../main/ets/service/LibraryCatalog';

export default function libraryCatalogTest() {
  describe('LibraryCatalog', () => {
    it('persists_favorite_and_tags_in_an_isolated_directory', 0, async () => {
      const root: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const folder: string = root + '/library-test-' + Date.now().toString();
      const imagePath: string = folder + '/sample.png';
      fs.mkdirSync(folder, true);
      try {
        const file: fs.File = fs.openSync(imagePath,
          fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, 'sample-image');
        fs.closeSync(file);
        const item: DownloadItem = new DownloadItem();
        item.id = 'sample'; item.name = 'sample.png'; item.path = imagePath; item.status = 'completed';
        const catalog: LibraryCatalog = new LibraryCatalog();
        await catalog.initialize(folder);
        await catalog.reconcile([item]);
        await catalog.setFavorite(['sample'], true);
        await catalog.changeTags(['sample'], ['常用'], []);
        const restored: LibraryCatalog = new LibraryCatalog();
        await restored.initialize(folder);
        expect(restored.getMeta('sample').favorite).assertTrue();
        expect(restored.getMeta('sample').tags[0]).assertEqual('常用');
      } finally {
        try { fs.unlinkSync(imagePath); } catch (error) { }
        try { fs.unlinkSync(folder + '/library-catalog.json'); } catch (error) { }
        try { fs.rmdirSync(folder + '/library-index'); } catch (error) { }
        try { fs.rmdirSync(folder); } catch (error) { }
      }
    });
  });
}
