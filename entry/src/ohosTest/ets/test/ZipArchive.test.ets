import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { describe, expect, it } from '@ohos/hypium';
import nativeArchive, { ArchiveInfo } from 'libarchiveextract.so';
import { LivePhoto } from '../../../main/ets/service/LivePhoto';
import { ZipItem } from '../../../main/ets/model/Models';
import { ZipArchiveService, ZipExtractResult } from '../../../main/ets/service/ZipArchiveService';

async function withFixture(name: string, run: (path: string, output: string) => Promise<void>): Promise<void> {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const resources = context.getApplicationContext().createModuleContext('entry_test').resourceManager;
  const root: string = context.filesDir + '/zip-test-' + Date.now().toString();
  fs.mkdirSync(root, true);
  const path: string = root + '/' + name;
  const output: string = root + '/output';
  try {
    const bytes: Uint8Array = resources.getRawFileContentSync('archive-extract/' + name);
    const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
    try { fs.writeSync(file.fd, bytes.buffer); } finally { fs.closeSync(file); }
    await run(path, output);
  } finally { LivePhoto.removeTree(root); }
}

export default function zipArchiveTest() {
  describe('ZipArchiveNative', () => {
    it('inspects_and_extracts_plain_zip', 0, async () => {
      await withFixture('plain.zip', async (path: string, output: string): Promise<void> => {
        const info: ArchiveInfo = nativeArchive.inspect(path);
        expect(info.count).assertEqual(2);
        expect(info.encrypted).assertFalse();
        await nativeArchive.extract(path, output, '');
        expect(fs.statSync(output + '/photo.png').size > 0).assertTrue();
        expect(fs.readTextSync(output + '/docs/readme.txt')).assertEqual('zip test document\n');
      });
    });

    it('extracts_traditional_and_aes_password_zips', 0, async () => {
      for (const name of ['traditional.zip', 'aes.zip']) {
        await withFixture(name, async (path: string, output: string): Promise<void> => {
          expect(nativeArchive.inspect(path).encrypted).assertTrue();
          await nativeArchive.extract(path, output, 'pass-1234');
          expect(fs.statSync(output + '/photo.png').size > 0).assertTrue();
          expect(fs.readTextSync(output + '/docs/readme.txt')).assertEqual('zip test document\n');
        });
      }
    });

    it('rejects_wrong_password_and_removes_output', 0, async () => {
      await withFixture('aes.zip', async (path: string, output: string): Promise<void> => {
        let failed: boolean = false;
        try { await nativeArchive.extract(path, output, 'incorrect'); } catch (error) { failed = true; }
        expect(failed).assertTrue();
        expect(fs.accessSync(output)).assertFalse();
      });
    });

    it('rejects_traversal_and_broken_zip', 0, async () => {
      for (const name of ['traversal.zip', 'damaged.zip', 'symlink.zip', 'too-many.zip', 'oversize.zip']) {
        await withFixture(name, async (path: string, output: string): Promise<void> => {
          let failed: boolean = false;
          try { nativeArchive.inspect(path); } catch (error) { failed = true; }
          expect(failed).assertTrue();
          expect(fs.accessSync(output)).assertFalse();
        });
      }
    });

    it('saves_all_files_with_hierarchy_and_unique_folder', 0, async () => {
      await withFixture('plain.zip', async (path: string, output: string): Promise<void> => {
        fs.mkdirSync(output);
        const zip: ZipItem = new ZipItem();
        zip.id = 'test'; zip.name = 'plain.zip'; zip.path = path;
        const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
        const first: ZipExtractResult = await ZipArchiveService.extractIntoFolder(context, zip, '', output);
        const second: ZipExtractResult = await ZipArchiveService.extractIntoFolder(context, zip, '', output);
        expect(first.location === second.location).assertFalse();
        expect(fs.readTextSync(first.location + '/docs/readme.txt')).assertEqual('zip test document\n');
        expect(fs.statSync(first.location + '/photo.png').size > 0).assertTrue();
        expect(fs.readTextSync(second.location + '/docs/readme.txt')).assertEqual('zip test document\n');
      });
    });
  });
}
