import { DownloadItem } from '../model/Models';
import { AnalysisProgress, AnalysisToken, AssetStamp, LibraryIndex, RecognizedLine, SimilarGroup, VisualFeature } from '../model/LibraryAsset';
import { EditRect, PreviewSize } from '../model/ImageEditDocument';
import { LibraryText } from '../util/LibraryText';
import { LIBRARY_CATALOG } from './LibraryCatalog';
import { LibraryImageReader } from './LibraryImageReader';
import { ImageTools } from './ImageTools';
import { image } from '@kit.ImageKit';
import { PerceptualHash } from '../util/PerceptualHash';

/** Explicit, cancellable local OCR. No recognition starts while simply browsing. */
export class LibraryAnalysis {
  static sameStamp(a: AssetStamp, b: AssetStamp): boolean {
    return a.id === b.id && a.path === b.path && a.sourceKind === b.sourceKind &&
      a.bytes === b.bytes && a.modified === b.modified && a.changed === b.changed &&
      a.orientation === b.orientation;
  }

  static async ocr(items: DownloadItem[], force: boolean, token: AnalysisToken,
    progress: (value: AnalysisProgress) => void): Promise<void> {
    const report: AnalysisProgress = new AnalysisProgress();
    report.total = items.length;
    LibraryAnalysis.emit(report, progress);
    let serviceReady: boolean = false;
    for (const item of items) {
      if (token.cancelled) { break; }
      if (item.status !== 'completed') { report.done++; LibraryAnalysis.emit(report, progress); continue; }
      try {
        const stamp: AssetStamp = await LibraryImageReader.stamp(item);
        if (token.cancelled) { break; }
        const prior: LibraryIndex | undefined = LIBRARY_CATALOG.getIndex(item.id);
        if (!force && prior !== undefined && LibraryAnalysis.sameStamp(prior.stamp, stamp) &&
          prior.ocrVersion === 1 && (prior.ocrStatus === 'ready' || prior.ocrStatus === 'empty')) {
          report.done++; LibraryAnalysis.emit(report, progress); continue;
        }
        if (!serviceReady) {
          try {
            await ImageTools.withTextEngine(async (): Promise<void> => {});
            serviceReady = true;
          } catch (error) {
            if (token.cancelled) { return; }
            report.message = '系统文字识别服务不可用：' + String(error);
            LibraryAnalysis.emit(report, progress);
            return;
          }
        }
        if (token.cancelled) { break; }
        const size: PreviewSize = await LibraryImageReader.info(stamp);
        const tiles: EditRect[] = LibraryText.tiles(size.width, size.height);
        const lines: RecognizedLine[] = [];
        await ImageTools.withTextEngine(async (): Promise<void> => {
          for (const tile of tiles) {
            if (token.cancelled) { break; }
            const output: PreviewSize = new PreviewSize();
            output.width = tile.width; output.height = tile.height;
            const frame: image.PixelMap = await LibraryImageReader.decode(stamp, tile, output, false);
            try {
              if (token.cancelled) { break; }
              const found: RecognizedLine[] = await ImageTools.textLines(frame);
              for (const line of found) {
                const global: RecognizedLine = new RecognizedLine();
                global.text = line.text; global.x = line.x + tile.x; global.y = line.y + tile.y;
                global.width = line.width; global.height = line.height;
                lines.push(global);
              }
            } finally { await frame.release(); }
            if (token.cancelled) { break; }
            const current: AssetStamp = await LibraryImageReader.stamp(item);
            if (!LibraryAnalysis.sameStamp(stamp, current)) {
              throw new Error('图片已改变，请重新识别');
            }
          }
        });
        if (token.cancelled) { break; }
        const latest: AssetStamp = await LibraryImageReader.stamp(item);
        if (!LibraryAnalysis.sameStamp(stamp, latest)) { throw new Error('图片已改变，请重新识别'); }
        const index: LibraryIndex = LIBRARY_CATALOG.getIndex(item.id) ?? new LibraryIndex();
        index.id = item.id; index.stamp = stamp;
        index.text = LibraryText.mergeLines(lines);
        index.ocrVersion = 1; index.ocrError = '';
        index.ocrStatus = index.text.length > 0 ? 'ready' : 'empty';
        if (await LIBRARY_CATALOG.putIndex(index, (): boolean => !token.cancelled)) {
          if (index.ocrStatus === 'ready') { report.success++; } else { report.empty++; }
        } else { report.failed++; }
      } catch (error) {
        if (token.cancelled) { break; }
        report.failed++;
        if (report.message.length === 0) { report.message = String(error); }
        await LibraryAnalysis.recordFailure(item, String(error), token);
      }
      report.done++;
      LibraryAnalysis.emit(report, progress);
    }
  }

  static async similar(items: DownloadItem[], token: AnalysisToken,
    progress: (value: AnalysisProgress) => void): Promise<SimilarGroup[]> {
    const report: AnalysisProgress = new AnalysisProgress();
    report.kind = 'similar'; report.total = items.length;
    LibraryAnalysis.emit(report, progress);
    const features: Map<string, VisualFeature> = new Map();
    const order: string[] = [];
    for (const item of items) {
      if (token.cancelled) { return []; }
      if (item.status !== 'completed') { report.done++; LibraryAnalysis.emit(report, progress); continue; }
      try {
        const stamp: AssetStamp = await LibraryImageReader.stamp(item);
        const prior: LibraryIndex | undefined = LIBRARY_CATALOG.getIndex(item.id);
        let feature: VisualFeature | undefined = prior !== undefined &&
          LibraryAnalysis.sameStamp(prior.stamp, stamp) && prior.feature !== undefined &&
          PerceptualHash.matches(prior.feature, prior.feature) ?
          prior.feature : undefined;
        if (feature === undefined) {
          const size: PreviewSize = await LibraryImageReader.info(stamp);
          const region: EditRect = new EditRect();
          region.width = size.width; region.height = size.height;
          const target: PreviewSize = new PreviewSize(); target.width = 32; target.height = 32;
          const frame: image.PixelMap = await LibraryImageReader.decode(stamp, region, target, false);
          try {
            const rgba: Uint8Array = await LibraryImageReader.rgba(frame);
            feature = PerceptualHash.feature(rgba, 32, 32);
            feature.width = size.width; feature.height = size.height;
          } finally { await frame.release(); }
          if (token.cancelled) { return []; }
          const latest: AssetStamp = await LibraryImageReader.stamp(item);
          if (!LibraryAnalysis.sameStamp(stamp, latest)) { throw new Error('图片已改变，请重新检查'); }
          const index: LibraryIndex = LIBRARY_CATALOG.getIndex(item.id) ?? new LibraryIndex();
          index.id = item.id; index.stamp = stamp; index.feature = feature;
          if (!await LIBRARY_CATALOG.putIndex(index, (): boolean => !token.cancelled)) {
            throw new Error('图片检查结果已过期');
          }
        }
        if (token.cancelled) { return []; }
        const current: AssetStamp = await LibraryImageReader.stamp(item);
        if (!LibraryAnalysis.sameStamp(stamp, current)) { throw new Error('图片已改变，请重新检查'); }
        features.set(item.id, feature);
        order.push(item.id); report.success++;
      } catch (error) { if (token.cancelled) { return []; } report.failed++; }
      report.done++;
      LibraryAnalysis.emit(report, progress);
    }
    return LibraryAnalysis.groupSimilar(order, features, token);
  }

  private static async groupSimilar(ids: string[], features: Map<string, VisualFeature>,
    token: AnalysisToken): Promise<SimilarGroup[]> {
    const candidates: SimilarGroup[] = [];
    let comparisons: number = 0;
    for (const id of ids) {
      if (token.cancelled) { return []; }
      const current: VisualFeature | undefined = features.get(id);
      if (current === undefined) { continue; }
      let found: SimilarGroup | undefined = undefined;
      for (const candidate of candidates) {
        comparisons++;
        if (comparisons % 128 === 0) {
          await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); });
          if (token.cancelled) { return []; }
        }
        const representative: VisualFeature | undefined = features.get(candidate.representativeId);
        if (representative !== undefined && PerceptualHash.matches(representative, current)) {
          found = candidate; break;
        }
      }
      if (found === undefined) {
        found = new SimilarGroup(); found.representativeId = id; found.ids = [id];
        candidates.push(found);
      } else { found.ids.push(id); }
    }
    return candidates.filter((group: SimilarGroup): boolean => group.ids.length > 1);
  }

  private static async recordFailure(item: DownloadItem, message: string, token: AnalysisToken): Promise<void> {
    try {
      const stamp: AssetStamp = await LibraryImageReader.stamp(item);
      const index: LibraryIndex = LIBRARY_CATALOG.getIndex(item.id) ?? new LibraryIndex();
      index.id = item.id; index.stamp = stamp;
      index.text = ''; index.ocrVersion = 1; index.ocrStatus = 'failed';
      index.ocrError = message.slice(0, 180);
      await LIBRARY_CATALOG.putIndex(index, (): boolean => !token.cancelled);
    } catch (error) { }
  }

  private static emit(current: AnalysisProgress, callback: (value: AnalysisProgress) => void): void {
    const copy: AnalysisProgress = new AnalysisProgress();
    copy.kind = current.kind; copy.done = current.done; copy.total = current.total;
    copy.success = current.success; copy.empty = current.empty; copy.failed = current.failed;
    copy.message = current.message;
    callback(copy);
  }
}
