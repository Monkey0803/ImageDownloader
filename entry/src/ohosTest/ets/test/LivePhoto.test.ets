import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { describe, it, expect } from '@ohos/hypium';
import { LivePhoto, LivePhotoContent } from '../../../main/ets/service/LivePhoto';

export default function livePhotoTest() {
  describe('LivePhotoPackage', () => {
    it('unpacks_still_and_motion_and_removes_the_temporary_zip', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const resources = context.getApplicationContext().createModuleContext('entry_test').resourceManager;
      const root: string = context.filesDir;
      const stamp: string = Date.now().toString();
      const packagePath: string = root + '/livephoto-probe-' + stamp + '.livp';
      const targetDir: string = root + '/livephoto-probe-' + stamp;
      const bytes: Uint8Array = resources.getRawFileContentSync('livephoto/sample.livp');
      const file: fs.File = fs.openSync(packagePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { expect(fs.writeSync(file.fd, bytes.buffer)).assertEqual(bytes.byteLength); }
      finally { fs.closeSync(file); }
      try {
        const result: LivePhotoContent = await LivePhoto.unpack(packagePath, targetDir);
        expect(result.ok).assertTrue();
        expect(result.stillPath.endsWith('/cover.jpg')).assertTrue();
        expect(result.motionPath.endsWith('/motion.mov')).assertTrue();
        expect(result.auxSize).assertEqual(16215);
        expect(fs.accessSync(packagePath)).assertTrue();
        expect(fs.accessSync(targetDir + '.zip')).assertFalse();
      } finally {
        LivePhoto.removeTree(targetDir);
        try { fs.unlinkSync(packagePath); } catch (error) {}
      }
    });
  });
}
