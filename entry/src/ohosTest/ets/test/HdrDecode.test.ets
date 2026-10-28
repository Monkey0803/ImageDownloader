import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { describe, it, expect } from '@ohos/hypium';

/**
 * HDR probe: the synthetic 64x64 HEIC carries a gain map. Every device must
 * report the source as HDR; the decoded PixelMap becomes HDR only where the
 * decoder supports it, otherwise the platform falls back to SDR. Devices
 * without HEIC support report `heicSupported: false` and skip the assertions.
 */
export default function hdrDecodeTest() {
  describe('HdrDecodeProbe', () => {
    it('detects_hdr_source_and_requests_hdr_decode', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const resources = context.getApplicationContext().createModuleContext('entry_test').resourceManager;
      const root: string = context.filesDir;
      const path: string = root + '/hdr-probe-' + Date.now().toString() + '.heic';
      const bytes: Uint8Array = resources.getRawFileContentSync('hdr/gainmap-hevc-16x16.heic');
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { expect(fs.writeSync(file.fd, bytes.buffer)).assertEqual(bytes.byteLength); }
      finally { fs.closeSync(file); }

      const formats: string[] = image.getImageSourceSupportedFormats();
      let sourceHdr: boolean = false;
      let decodedHdr: boolean = false;
      let pixelFormat: number = -1;
      let alphaType: number = -1;
      let width: number = 0;
      let height: number = 0;
      let problem: string = '';
      try {
        const source: image.ImageSource = image.createImageSource(path);
        try {
          const info: image.ImageInfo = await source.getImageInfo();
          sourceHdr = info.isHdr === true;
          const options: image.DecodingOptions = { desiredDynamicRange: image.DecodingDynamicRange.HDR };
          const frame: image.PixelMap = await source.createPixelMap(options);
          try {
            const decoded: image.ImageInfo = await frame.getImageInfo();
            decodedHdr = decoded.isHdr === true;
            pixelFormat = decoded.pixelFormat;
            alphaType = decoded.alphaType;
            width = decoded.size.width;
            height = decoded.size.height;
          } finally { await frame.release(); }
        } finally { await source.release(); }
      } catch (error) {
        problem = String(error);
      }

      const report: string = root + '/hdr-decode-probe.json';
      const output: fs.File = fs.openSync(report, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(output.fd, JSON.stringify({ heicSupported: formats.includes('image/heic'),
          sourceHdr: sourceHdr, decodedHdr: decodedHdr, pixelFormat: pixelFormat,
          alphaType: alphaType, width: width, height: height, problem: problem }));
      } finally { fs.closeSync(output); }
      try { fs.unlinkSync(path); } catch (error) {}

      if (!formats.includes('image/heic')) { return; }
      expect(problem).assertEqual('');
      expect(sourceHdr).assertTrue();
      expect(width).assertEqual(64);
      expect(height).assertEqual(64);
    });
  });
}
