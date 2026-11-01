import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LivePhoto } from '../../../main/ets/service/LivePhoto';
import { TrashEntry, TrashStore } from '../../../main/ets/service/TrashStore';

function write(path: string, value: string): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, value); fs.closeSync(file);
}

export default function trashStoreTest() {
  describe('TrashStore', () => {
    it('moves_and_restores_without_overwriting_same_named_file', 0, () => {
      const root: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const folder: string = root + '/trash-test-' + Date.now().toString();
      fs.mkdirSync(folder, true);
      try {
        const source: string = folder + '/sample.png';
        write(source, 'old-image');
        const trash: TrashStore = new TrashStore(); trash.initialize(folder);
        const entry: TrashEntry = new TrashEntry();
        entry.id = 'image-1'; entry.name = 'sample.png'; entry.snapshot = '{}'; entry.originals = [source];
        entry.deletedAt = Date.now(); entry.bytes = 9;
        expect(trash.move(entry)).assertTrue();
        expect(fs.accessSync(source)).assertFalse();
        const reopened: TrashStore = new TrashStore(); reopened.initialize(folder);
        expect(reopened.count()).assertEqual(1);
        write(source, 'new-image');
        const paths: string[] | undefined = reopened.restoreFiles(reopened.get(entry.id)!);
        expect(paths !== undefined).assertTrue();
        expect(paths![0]).assertEqual(folder + '/sample-restored-1.png');
        expect(fs.readTextSync(source)).assertEqual('new-image');
        expect(fs.readTextSync(paths![0])).assertEqual('old-image');
        expect(reopened.rollbackRestore(reopened.get(entry.id)!)).assertTrue();
        expect(fs.accessSync(paths![0])).assertFalse();
        const retried: string[] | undefined = reopened.restoreFiles(reopened.get(entry.id)!);
        expect(retried !== undefined).assertTrue();
        expect(fs.readTextSync(retried![0])).assertEqual('old-image');
        reopened.finish(entry.id);
        expect(reopened.count()).assertEqual(0);
      } finally { LivePhoto.removeTree(folder); }
    });

    it('purges_files_older_than_thirty_days', 0, () => {
      const root: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const folder: string = root + '/trash-expiry-test-' + Date.now().toString();
      fs.mkdirSync(folder, true);
      try {
        const source: string = folder + '/old.zip'; write(source, 'archive');
        const trash: TrashStore = new TrashStore(); trash.initialize(folder);
        const entry: TrashEntry = new TrashEntry();
        entry.id = 'zip-1'; entry.kind = 'zip'; entry.name = 'old.zip'; entry.snapshot = '{}';
        entry.originals = [source]; entry.deletedAt = Date.now() - 31 * 24 * 60 * 60 * 1000;
        expect(trash.move(entry)).assertTrue();
        expect(trash.purgeExpired()).assertEqual(1);
        expect(trash.count()).assertEqual(0);
        expect(fs.accessSync(entry.stored[0])).assertFalse();
      } finally { LivePhoto.removeTree(folder); }
    });
  });
}
