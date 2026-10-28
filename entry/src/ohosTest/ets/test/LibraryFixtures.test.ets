import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { describe, it, expect } from '@ohos/hypium';
import { LibraryImageReader } from '../../../main/ets/service/LibraryImageReader';

class FixtureCase {
  name: string = '';
  caseId: string = '';
  width: number = 0;
  height: number = 0;
  sha256: string = '';
  orientation: number = 0;
}

class FixtureManifest {
  version: number = 0;
  cases: FixtureCase[] = [];
}

export default function libraryFixturesTest() {
  describe('LibraryFixtureNative', () => {
    it('rawfile_manifest_matches_all_pixels_and_exif_images', 0, async () => {
      const resources = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .getApplicationContext().createModuleContext('entry_test').resourceManager;
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const manifest: FixtureManifest = JSON.parse(decoder.decodeToString(
        resources.getRawFileContentSync('library-enhancements/manifest.json'))) as FixtureManifest;
      expect(manifest.version).assertEqual(1);
      expect(manifest.cases.length).assertEqual(15);
      const root: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const folder: string = root + '/library-fixture-test-' + Date.now().toString();
      fs.mkdirSync(folder, true);
      try {
        for (const entry of manifest.cases) {
          const path: string = folder + '/' + entry.name;
          const bytes: Uint8Array = resources.getRawFileContentSync('library-enhancements/' + entry.name);
          const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try { expect(fs.writeSync(file.fd, bytes.buffer)).assertEqual(bytes.byteLength); }
          finally { fs.closeSync(file); }
          expect((await hash.hash(path, 'sha256')).toLowerCase()).assertEqual(entry.sha256);
          const source: image.ImageSource = image.createImageSource(path);
          try {
            const info: image.ImageInfo = await source.getImageInfo();
            expect(info.size.width).assertEqual(entry.width);
            expect(info.size.height).assertEqual(entry.height);
            if (entry.orientation > 0) {
              const value: string = await source.getImageProperty(image.PropertyKey.ORIENTATION);
              expect(value.length > 0).assertTrue();
            }
          } finally { await source.release(); }
          if (entry.name === 'edit-oracle.png') {
            const oracle: image.ImageSource = image.createImageSource(path);
            let frame: image.PixelMap | undefined = undefined;
            try {
              frame = await oracle.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
              const pixels: Uint8Array = await LibraryImageReader.rgba(frame);
              const sample: number = (10 * entry.width + 10) * 4;
              expect(pixels[sample]).assertEqual(255);
              expect(pixels[sample + 1]).assertEqual(0);
              expect(pixels[sample + 2]).assertEqual(0);
            } finally {
              if (frame !== undefined) { await frame.release(); }
              await oracle.release();
            }
          }
        }
      } finally {
        for (const entry of manifest.cases) {
          try { fs.unlinkSync(folder + '/' + entry.name); } catch (error) {}
        }
        try { fs.rmdirSync(folder); } catch (error) {}
      }
    });
  });
}
