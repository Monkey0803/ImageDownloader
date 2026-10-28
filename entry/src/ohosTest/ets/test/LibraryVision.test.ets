import { describe, it, expect } from '@ohos/hypium';
import { LibraryImageReader } from '../../../main/ets/service/LibraryImageReader';
import { PerceptualHash } from '../../../main/ets/util/PerceptualHash';
import { DownloadItem } from '../../../main/ets/model/Models';
import { AssetStamp, VisualFeature, SimilarGroup } from '../../../main/ets/model/LibraryAsset';
import { EditRect, PreviewSize } from '../../../main/ets/model/ImageEditDocument';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';

// Isolated SDK probe: one JPEG payload, varying only its EXIF orientation value.
const JPEG: string = '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAEAAAAAAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAAwAFADAREAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD8X6/ynP8Av4CgAoAKACgD+lCv8tz/AMK8KACgAoAKAP5r6/1IP/dQCgAoAKACgD+lCv8ALc/8K8KACgAoAKAP5r6/1IP/AHUAoAKACgAoA/pQr/Lc/wDCvCgAoAKACgD+Dev/AGmD/qwCgAoAKACgD/Yor/wBz/VAKACgAoAKAP8AHXr/AN/g/wArwoAKACgAoA/2KK/8Ac/1QCgAoAKACgD/AB16/wDf4P8AK8KACgAoAKAP9iiv/AHP9UAoAKACgAoA/9k=';
const ALPHA: string = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVR4nGP8z8DQwMjwnwEADIwCgcdJDg0AAAAASUVORK5CYII=';
const ODD: string = 'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAGUlEQVR4nGP4z8DQwPCf4T8Dw/8GJgYkAABf5gT/mRZNpgAAAABJRU5ErkJggg==';
const ORIENTATION_BYTE: number = 49;

async function frameReport(frame: image.PixelMap): Promise<string> {
  const info: image.ImageInfo = await frame.getImageInfo();
  const bytes: ArrayBuffer = new ArrayBuffer(frame.getPixelBytesNumber());
  await frame.readPixelsToBuffer(bytes);
  const raw: Uint8Array = new Uint8Array(bytes);
  const corners: number[][] = [];
  const width: number = info.size.width;
  const height: number = info.size.height;
  for (const y of [Math.floor(height / 4), Math.floor(height * 3 / 4)]) {
    for (const x of [Math.floor(width / 4), Math.floor(width * 3 / 4)]) {
      const offset: number = y * info.stride + x * 4;
      corners.push(Array.from(raw.slice(offset, offset + 4)));
    }
  }
  return JSON.stringify({ info: info, byteCount: raw.length, rowBytes: frame.getBytesNumberPerRow(), packedRowBytes: width * 4, corners: corners,
    raw: raw.length <= 64 ? Array.from(raw) : [] });
}


function patternedRgba(brightness: number, slight: boolean = false): Uint8Array {
  const rgba: Uint8Array = new Uint8Array(4096);
  for (let y: number = 0; y < 32; y++) {
    for (let x: number = 0; x < 32; x++) {
      const value: number = 20 + ((x * 37 + y * 53 + x * y * 11) % 150) + brightness;
      const offset: number = (y * 32 + x) * 4;
      rgba[offset] = value; rgba[offset + 1] = value; rgba[offset + 2] = value;
      rgba[offset + 3] = 255;
    }
  }
  if (slight) { rgba[(13 * 32 + 17) * 4] += 2; }
  return rgba;
}

export default function libraryVisionTest() {
  describe('LibraryVisionProbe', () => {
    it('reports_orientation_and_alpha_from_native_decoder', 0, async () => {
      const lines: string[] = [];
      const helper: util.Base64Helper = new util.Base64Helper();
      for (let orientation: number = 1; orientation <= 8; orientation++) {
        const bytes: Uint8Array = helper.decodeSync(JPEG);
        bytes[ORIENTATION_BYTE] = orientation;
        const source: image.ImageSource = image.createImageSource(bytes.buffer);
        let frame: image.PixelMap | undefined;
        try {
          const info: image.ImageInfo = await source.getImageInfo();
          const exif: string = await source.getImageProperty(image.PropertyKey.ORIENTATION);
          frame = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
          lines.push(JSON.stringify({ kind: 'exif', orientation: orientation, exif: exif,
            sourceInfo: info, frame: await frameReport(frame) }));
          expect(info.size.width).assertEqual(80);
        } finally {
          try { if (frame !== undefined) { await frame.release(); } } finally { await source.release(); }
        }
      }
      for (const explicit of [false, true]) {
        const source: image.ImageSource = image.createImageSource(helper.decodeSync(ALPHA).buffer);
        let frame: image.PixelMap | undefined;
        try {
          const info: image.ImageInfo = await source.getImageInfo();
          frame = explicit ? await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 }) :
            await source.createPixelMap();
          lines.push(JSON.stringify({ kind: 'alpha_png', explicitRGBA: explicit, sourceInfo: info,
            frame: await frameReport(frame) }));
        } finally {
          try { if (frame !== undefined) { await frame.release(); } } finally { await source.release(); }
        }
      }
      // Probe both input magnitudes explicitly; alphaType may describe output conversion.
      for (const alphaType of [image.AlphaType.PREMUL, image.AlphaType.UNPREMUL]) {
        for (const channel of [128, 255]) {
          const raw: Uint8Array = new Uint8Array([channel, 0, 0, 128, 0, 0, channel, 128]);
          const frame: image.PixelMap = await image.createPixelMap(raw.buffer, {
            size: { width: 2, height: 1 }, srcPixelFormat: image.PixelMapFormat.RGBA_8888,
            pixelFormat: image.PixelMapFormat.RGBA_8888, alphaType: alphaType });
          try {
            lines.push(JSON.stringify({ kind: 'raw_pixelmap', inputAlphaType: alphaType,
              inputRaw: Array.from(raw), frame: await frameReport(frame) }));
          } finally { await frame.release(); }
        }
      }
      const path: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir +
        '/library-vision-probe.jsonl';
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, lines.join('\n')); } finally { fs.closeSync(file); }
      expect(lines.length).assertEqual(14);
    });
    it('normalizes_reader_orientation_crops_alpha_and_odd_rows', 0, async () => {
      const root: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const folder: string = root + '/library-test-vision-' + Date.now().toString();
      fs.mkdirSync(folder, true);
      const path: string = folder + '/fixture.jpg';
      const lines: string[] = [];
      const helper: util.Base64Helper = new util.Base64Helper();
      const expected: number[][] = [[0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
        [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]];
      const colors: number[][] = [[254, 0, 0], [0, 255, 1], [0, 0, 254], [255, 255, 0]];
      const item: DownloadItem = new DownloadItem();
      item.id = 'vision-probe'; item.path = path; item.kind = 'image'; item.status = 'completed';
      try {
        for (let orientation: number = 1; orientation <= 8; orientation++) {
          const bytes: Uint8Array = helper.decodeSync(JPEG);
          bytes[ORIENTATION_BYTE] = orientation;
          const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try { fs.writeSync(file.fd, bytes.buffer); } finally { fs.closeSync(file); }
          const stamp: AssetStamp = await LibraryImageReader.stamp(item);
          expect(stamp.orientation).assertEqual(orientation);
          expect(stamp.bytes).assertEqual(bytes.byteLength);
          const size: PreviewSize = await LibraryImageReader.info(stamp);
          expect(size.width).assertEqual(orientation >= 5 ? 48 : 80);
          expect(size.height).assertEqual(orientation >= 5 ? 80 : 48);
          const region: EditRect = new EditRect();
          region.width = size.width; region.height = size.height;
          const frame: image.PixelMap = await LibraryImageReader.decode(stamp, region, size, false);
          try {
            const info: image.ImageInfo = await frame.getImageInfo();
            const rgba: Uint8Array = await LibraryImageReader.rgba(frame);
            lines.push(JSON.stringify({ kind: 'reader_full', orientation: orientation, stamp: stamp,
              frame: await frameReport(frame) }));
            expect(info.size.width).assertEqual(size.width);
            expect(info.size.height).assertEqual(size.height);
            let corner: number = 0;
            for (const y of [Math.floor(size.height / 4), Math.floor(size.height * 3 / 4)]) {
              for (const x of [Math.floor(size.width / 4), Math.floor(size.width * 3 / 4)]) {
                const offset: number = (y * size.width + x) * 4;
                for (let channel: number = 0; channel < 3; channel++) {
                  expect(Math.abs(rgba[offset + channel] - colors[expected[orientation - 1][corner]][channel]) <= 2).assertTrue();
                }
                corner++;
              }
            }
          } finally { await frame.release(); }
          region.x = size.width / 8; region.y = size.height / 8;
          region.width = size.width / 4; region.height = size.height / 4;
          const output: PreviewSize = new PreviewSize(); output.width = 7; output.height = 5;
          const crop: image.PixelMap = await LibraryImageReader.decode(stamp, region, output, true);
          try {
            const cropInfo: image.ImageInfo = await crop.getImageInfo();
            expect(cropInfo.size.width).assertEqual(7);
            expect(cropInfo.size.height).assertEqual(5);
            const rgba: Uint8Array = await LibraryImageReader.rgba(crop);
            lines.push(JSON.stringify({ kind: 'reader_crop', orientation: orientation, frame: await frameReport(crop) }));
            expect(rgba.length).assertEqual(140);
            for (let channel: number = 0; channel < 3; channel++) {
              expect(Math.abs(rgba[68 + channel] - colors[expected[orientation - 1][0]][channel]) <= 2).assertTrue();
            }
          } finally { await crop.release(); }
        }
        for (const odd of [false, true]) {
          const bytes: Uint8Array = helper.decodeSync(odd ? ODD : ALPHA);
          const file: fs.File = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try { fs.writeSync(file.fd, bytes.buffer); } finally { fs.closeSync(file); }
          const stamp: AssetStamp = await LibraryImageReader.stamp(item);
          const size: PreviewSize = await LibraryImageReader.info(stamp);
          const region: EditRect = new EditRect(); region.width = size.width; region.height = size.height;
          const frame: image.PixelMap = await LibraryImageReader.decode(stamp, region, size, false);
          try {
            const rgba: Uint8Array = await LibraryImageReader.rgba(frame);
            lines.push(JSON.stringify({ kind: 'reader_alpha', odd: odd, rgba: Array.from(rgba),
              frame: await frameReport(frame) }));
            const want: number[] = odd ? [255,0,0,128,0,255,0,255,0,0,255,128,255,0,0,128,0,255,0,255,0,0,255,128] :
              [255,0,0,128,0,0,255,128];
            expect(Array.from(rgba).join(',')).assertEqual(want.join(','));
          } finally { await frame.release(); }
        }
      } finally {
        const report: fs.File = fs.openSync(root + '/library-vision-reader.jsonl',
          fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { fs.writeSync(report.fd, lines.join('\n')); } finally { fs.closeSync(report); }
        try { fs.unlinkSync(path); } finally { fs.rmdirSync(folder); }
      }
      expect(lines.length).assertEqual(18);
    });

    it('extracts_and_matches_real_rgba_with_representative_only_groups', 0, () => {
      const redPixels: Uint8Array = new Uint8Array(4096);
      const bluePixels: Uint8Array = new Uint8Array(4096);
      for (let i: number = 0; i < 4096; i += 4) {
        redPixels[i] = 255; redPixels[i + 3] = 255;
        bluePixels[i + 2] = 255; bluePixels[i + 3] = 255;
      }
      const red: VisualFeature = PerceptualHash.feature(redPixels, 32, 32);
      const blue: VisualFeature = PerceptualHash.feature(bluePixels, 32, 32);
      expect(red.red).assertEqual(255); expect(red.blue).assertEqual(0);
      expect(blue.red).assertEqual(0); expect(blue.blue).assertEqual(255);
      expect(red.lowBits.length).assertEqual(64); expect(red.edgeBits.length).assertEqual(64);
      expect(PerceptualHash.matches(red, blue)).assertFalse();
      expect(PerceptualHash.matches(red, PerceptualHash.feature(redPixels, 32, 32))).assertTrue();
      const verticalPixels: Uint8Array = new Uint8Array(4096).fill(255);
      const horizontalPixels: Uint8Array = new Uint8Array(4096).fill(255);
      for (let y: number = 0; y < 32; y++) {
        for (let x: number = 0; x < 32; x++) {
          const offset: number = (y * 32 + x) * 4;
          for (let channel: number = 0; channel < 3; channel++) {
            if (x === 15 || x === 16) { verticalPixels[offset + channel] = 0; }
            if (y === 15 || y === 16) { horizontalPixels[offset + channel] = 0; }
          }
        }
      }
      const vertical: VisualFeature = PerceptualHash.feature(verticalPixels, 32, 32);
      const horizontal: VisualFeature = PerceptualHash.feature(horizontalPixels, 32, 32);
      const a: VisualFeature = PerceptualHash.feature(patternedRgba(0), 32, 32);
      const similar: VisualFeature = PerceptualHash.feature(patternedRgba(0, true), 32, 32);
      const b: VisualFeature = PerceptualHash.feature(patternedRgba(16), 32, 32);
      const c: VisualFeature = PerceptualHash.feature(patternedRgba(32), 32, 32);
      const features: Map<string, VisualFeature> = new Map<string, VisualFeature>();
      features.set('A', a); features.set('B', b); features.set('C', c);
      const groups: SimilarGroup[] = PerceptualHash.groups(['A', 'B', 'C', 'A', 'missing'], features);
      const reversed: SimilarGroup[] = PerceptualHash.groups(['C', 'B', 'A'], features);
      const root: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const file: fs.File = fs.openSync(root + '/library-vision-hash.json',
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, JSON.stringify({ red: red, blue: blue, a: a, b: b, c: c,
        similar: similar, groups: groups, reversed: reversed, vertical: vertical, horizontal: horizontal,
        linesMatch: PerceptualHash.matches(vertical, horizontal),
        ab: PerceptualHash.matches(a, b), bc: PerceptualHash.matches(b, c),
        ac: PerceptualHash.matches(a, c), slight: PerceptualHash.matches(a, similar) })); }
      finally { fs.closeSync(file); }
      expect(PerceptualHash.matches(vertical, horizontal)).assertFalse();
      expect(PerceptualHash.matches(a, similar)).assertTrue();
      expect(PerceptualHash.matches(a, b)).assertTrue();
      expect(PerceptualHash.matches(b, c)).assertTrue();
      expect(PerceptualHash.matches(a, c)).assertFalse();
      expect(groups.length).assertEqual(1);
      expect(groups[0].representativeId).assertEqual('A');
      expect(groups[0].ids.join(',')).assertEqual('A,B');
      expect(reversed.length).assertEqual(1);
      expect(reversed[0].representativeId).assertEqual('C');
      expect(reversed[0].ids.join(',')).assertEqual('C,B');
    });

    it('hdr_decode_request_falls_back_to_sdr_for_plain_jpeg', 0, async () => {
      const helper: util.Base64Helper = new util.Base64Helper();
      const source: image.ImageSource = image.createImageSource(helper.decodeSync(JPEG).buffer);
      let frame: image.PixelMap | undefined = undefined;
      try {
        const before: image.ImageInfo = await source.getImageInfo();
        expect(before.isHdr).assertFalse();
        frame = await source.createPixelMap({ desiredDynamicRange: image.DecodingDynamicRange.HDR });
        const decoded: image.ImageInfo = await frame.getImageInfo();
        expect(decoded.isHdr).assertFalse();
        expect(decoded.size.width).assertEqual(80);
        expect(decoded.size.height).assertEqual(48);
      } finally {
        if (frame !== undefined) { await frame.release(); }
        await source.release();
      }
    });

  });
}
