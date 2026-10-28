import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DownloadItem } from '../model/Models';
import { AssetStamp, LibraryIndex, LibraryMeta, LibrarySearchEntry, VisualFeature } from '../model/LibraryAsset';
import { LibraryText } from '../util/LibraryText';

class CatalogWire {
  version: number = 1;
  metas: LibraryMeta[] = [];
}

/** User metadata is small; recognition text and visual features live in per-image shards. */
export class LibraryCatalog {
  private dir: string = '';
  private indexDir: string = '';
  private initTask: Promise<void> | undefined = undefined;
  private pending: Promise<void> = Promise.resolve();
  private metas: Map<string, LibraryMeta> = new Map();
  private indexes: Map<string, LibraryIndex> = new Map();
  private active: Map<string, AssetStamp> = new Map();
  private listeners: Set<() => void> = new Set();
  loading: boolean = false;
  loadError: string = '';

  initialize(filesDir: string): Promise<void> {
    if (this.initTask !== undefined) { return this.initTask; }
    this.dir = filesDir;
    this.indexDir = filesDir + '/library-index';
    this.loading = true;
    this.loadError = '';
    this.initTask = this.load().catch((): void => {
      this.loadError = '图库整理信息读取失败';
      this.metas.clear();
      this.indexes.clear();
      this.initTask = undefined;
      this.emit();
      throw new Error(this.loadError);
    });
    return this.initTask;
  }

  retry(): Promise<void> {
    if (this.dir.length === 0) { throw new Error('图库目录尚未初始化'); }
    return this.initialize(this.dir);
  }

  private async load(): Promise<void> {
    try {
      if (!fs.accessSync(this.indexDir)) { fs.mkdirSync(this.indexDir, true); }
      const catalogPath: string = this.dir + '/library-catalog.json';
      if (fs.accessSync(catalogPath)) {
        const wire: CatalogWire = JSON.parse(fs.readTextSync(catalogPath));
        if (wire.version !== 1 || !Array.isArray(wire.metas)) {
          throw new Error('图库目录版本不受支持');
        }
        for (const raw of wire.metas) {
          if (typeof raw.id !== 'string' || raw.id.length === 0) { continue; }
          const meta: LibraryMeta = this.restoreMeta(raw);
          this.metas.set(meta.id, meta);
        }
      }
      let loaded: number = 0;
      for (const name of fs.listFileSync(this.indexDir)) {
        if (!name.endsWith('.json')) { continue; }
        try {
          const raw: LibraryIndex = JSON.parse(fs.readTextSync(this.indexDir + '/' + name));
          const index: LibraryIndex | undefined = this.restoreIndex(raw);
          if (index !== undefined && this.shardName(index.id) === name) {
            this.indexes.set(index.id, index);
          }
        } catch (error) {
          // One corrupt shard cannot hide healthy images or their metadata.
        }
        loaded += 1;
        if (loaded % 32 === 0) {
          await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); });
        }
      }
    } finally {
      this.loading = false;
      this.emit();
    }
  }

  private restoreMeta(raw: LibraryMeta): LibraryMeta {
    const meta: LibraryMeta = new LibraryMeta();
    meta.id = raw.id;
    meta.favorite = raw.favorite === true;
    meta.tags = Array.isArray(raw.tags) ? LibraryText.tags(raw.tags.filter((tag: string): boolean =>
      typeof tag === 'string')) : [];
    return meta;
  }

  private copyStamp(source: AssetStamp): AssetStamp {
    const stamp: AssetStamp = new AssetStamp();
    stamp.id = source.id; stamp.path = source.path; stamp.sourceKind = source.sourceKind;
    stamp.bytes = source.bytes; stamp.modified = source.modified; stamp.changed = source.changed;
    stamp.orientation = source.orientation;
    return stamp;
  }

  private sameStamp(a: AssetStamp, b: AssetStamp): boolean {
    return a.id === b.id && a.path === b.path && a.sourceKind === b.sourceKind &&
      a.bytes === b.bytes && a.modified === b.modified && a.changed === b.changed;
  }

  private restoreIndex(raw: LibraryIndex): LibraryIndex | undefined {
    if (raw.version !== 1 || typeof raw.id !== 'string' || raw.id.length === 0 ||
      raw.stamp === undefined || typeof raw.stamp.path !== 'string') { return undefined; }
    const index: LibraryIndex = new LibraryIndex();
    index.id = raw.id; index.stamp = this.copyStamp(raw.stamp);
    index.ocrVersion = raw.ocrVersion === 1 ? 1 : 0;
    index.ocrStatus = typeof raw.ocrStatus === 'string' ? raw.ocrStatus : 'unindexed';
    index.text = typeof raw.text === 'string' ? raw.text : '';
    index.ocrError = typeof raw.ocrError === 'string' ? raw.ocrError : '';
    if (raw.feature !== undefined && raw.feature.version === 1) {
      const source: VisualFeature = raw.feature;
      const feature: VisualFeature = new VisualFeature();
      feature.lowBits = source.lowBits; feature.edgeBits = source.edgeBits;
      feature.red = source.red; feature.green = source.green; feature.blue = source.blue;
      feature.alpha = source.alpha; feature.width = source.width; feature.height = source.height;
      index.feature = feature;
    }
    return index;
  }

  private shardName(id: string): string {
    if (id.length === 0 || id.length > 100) { throw new Error('无效图片ID'); }
    return encodeURIComponent(id) + '.json';
  }

  private writeAtomic(target: string, payload: string): void {
    const temp: string = target + '.tmp';
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(payload);
    const file: fs.File = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      if (fs.writeSync(file.fd, bytes.buffer) !== bytes.byteLength) {
        throw new Error('图库数据写入不完整');
      }
    } catch (error) {
      fs.closeSync(file);
      try { fs.unlinkSync(temp); } catch (cleanupError) { }
      throw new Error('图库数据写入失败');
    }
    fs.closeSync(file);
    try {
      fs.renameSync(temp, target);
    } catch (error) {
      try { fs.unlinkSync(temp); } catch (cleanupError) { }
      throw new Error('图库数据替换失败');
    }
  }

  private saveMetas(next: Map<string, LibraryMeta>): void {
    const wire: CatalogWire = new CatalogWire();
    wire.metas = Array.from(next.values()).map((meta: LibraryMeta): LibraryMeta => this.restoreMeta(meta));
    this.writeAtomic(this.dir + '/library-catalog.json', JSON.stringify(wire));
    this.metas = next;
    this.emit();
  }

  private enqueue(action: () => void): Promise<void> {
    const next: Promise<void> = this.pending.then(action, action);
    this.pending = next.then((): void => {}, (): void => {});
    return next;
  }

  private emit(): void {
    for (const listener of this.listeners) { listener(); }
  }

  subscribe(listener: () => void): void { this.listeners.add(listener); }
  unsubscribe(listener: () => void): void { this.listeners.delete(listener); }

  getMeta(id: string): LibraryMeta {
    const current: LibraryMeta | undefined = this.metas.get(id);
    return current === undefined ? new LibraryMeta() : this.restoreMeta(current);
  }

  getIndex(id: string): LibraryIndex | undefined {
    const current: LibraryIndex | undefined = this.indexes.get(id);
    return current === undefined ? undefined : this.restoreIndex(current);
  }

  entries(items: DownloadItem[]): LibrarySearchEntry[] {
    const result: LibrarySearchEntry[] = [];
    for (const item of items) {
      if (item.status !== 'completed') { continue; }
      const meta: LibraryMeta = this.getMeta(item.id);
      const index: LibraryIndex | undefined = this.getIndex(item.id);
      const entry: LibrarySearchEntry = new LibrarySearchEntry();
      entry.id = item.id; entry.favorite = meta.favorite; entry.tags = meta.tags;
      entry.text = index === undefined ? '' : index.text;
      entry.ocrStatus = index === undefined ? 'unindexed' : index.ocrStatus;
      result.push(entry);
    }
    return result;
  }

  /** Resolve a web preview to a real saved original, never to a temporary UID or edited copy. */
  assetForPreview(items: DownloadItem[], url: string, kind: string): string {
    if (url.length === 0) { return ''; }
    for (const item of items) {
      if (item.origin === 'edited' || item.url !== url || item.kind !== kind ||
        item.status !== 'completed') { continue; }
      const path: string = kind === 'livephoto' ? item.stillPath : item.path;
      if (path.length > 0 && fs.accessSync(path)) { return item.id; }
    }
    return '';
  }

  async setFavorite(ids: string[], value: boolean): Promise<void> {
    await this.ready();
    return this.enqueue((): void => {
      const next: Map<string, LibraryMeta> = new Map(this.metas);
      for (const id of ids) {
        if (!this.active.has(id)) { throw new Error('图片文件尚未进入图库'); }
      }
      for (const id of ids) {
        const meta: LibraryMeta = this.getMeta(id);
        meta.id = id; meta.favorite = value; next.set(id, meta);
      }
      this.saveMetas(next);
    });
  }

  async changeTags(ids: string[], add: string[], remove: string[]): Promise<void> {
    await this.ready();
    return this.enqueue((): void => {
      const next: Map<string, LibraryMeta> = new Map(this.metas);
      for (const id of ids) {
        if (!this.active.has(id)) { throw new Error('图片文件尚未进入图库'); }
      }
      for (const id of ids) {
        const meta: LibraryMeta = this.getMeta(id);
        meta.id = id;
        const removeKeys: string[] = remove.map((tag: string): string => LibraryText.normalize(tag));
        const tags: string[] = meta.tags.filter((tag: string): boolean =>
          !removeKeys.includes(LibraryText.normalize(tag)));
        meta.tags = LibraryText.tags(tags.concat(add));
        next.set(id, meta);
      }
      this.saveMetas(next);
    });
  }

  async putIndex(index: LibraryIndex, valid?: () => boolean): Promise<boolean> {
    await this.ready();
    let accepted: boolean = false;
    await this.enqueue((): void => {
      const current: AssetStamp | undefined = this.active.get(index.id);
      if (current === undefined || !this.sameStamp(current, index.stamp) ||
        (valid !== undefined && !valid())) { return; }
      try {
        const actual: fs.Stat = fs.statSync(current.path);
        if (actual.size !== current.bytes || actual.mtime !== current.modified ||
          actual.ctime !== current.changed) { return; }
      } catch (error) { return; }
      const copy: LibraryIndex | undefined = this.restoreIndex(index);
      if (copy === undefined || (valid !== undefined && !valid())) { return; }
      this.writeAtomic(this.indexDir + '/' + this.shardName(index.id), JSON.stringify(copy));
      this.indexes.set(index.id, copy);
      accepted = true;
      this.emit();
    });
    return accepted;
  }

  async clearText(ids: string[]): Promise<void> {
    await this.ready();
    return this.enqueue((): void => {
      for (const id of ids) {
        const current: LibraryIndex | undefined = this.getIndex(id);
        if (current === undefined) { continue; }
        current.text = ''; current.ocrStatus = 'unindexed'; current.ocrError = '';
        this.writeAtomic(this.indexDir + '/' + this.shardName(id), JSON.stringify(current));
        this.indexes.set(id, current);
      }
      this.emit();
    });
  }

  async reconcile(items: DownloadItem[]): Promise<void> {
    await this.ready();
    return this.enqueue((): void => {
      const nextActive: Map<string, AssetStamp> = new Map();
      for (const item of items) {
        if (item.status !== 'completed' || item.id.length === 0) { continue; }
        const path: string = item.kind === 'livephoto' ? item.stillPath : item.path;
        if (path.length === 0 || !fs.accessSync(path)) { continue; }
        try {
          const stat: fs.Stat = fs.statSync(path);
          const stamp: AssetStamp = new AssetStamp();
          stamp.id = item.id; stamp.path = path; stamp.sourceKind = item.kind;
          stamp.bytes = stat.size; stamp.modified = stat.mtime; stamp.changed = stat.ctime;
          nextActive.set(item.id, stamp);
        } catch (error) { }
      }
      const nextMetas: Map<string, LibraryMeta> = new Map();
      for (const id of nextActive.keys()) {
        const meta: LibraryMeta | undefined = this.metas.get(id);
        if (meta !== undefined) { nextMetas.set(id, meta); }
      }
      if (nextMetas.size !== this.metas.size) { this.saveMetas(nextMetas); }
      for (const id of this.indexes.keys()) {
        const index: LibraryIndex | undefined = this.indexes.get(id);
        const stamp: AssetStamp | undefined = nextActive.get(id);
        if (index === undefined || stamp === undefined || !this.sameStamp(index.stamp, stamp)) {
          this.indexes.delete(id);
          try { fs.unlinkSync(this.indexDir + '/' + this.shardName(id)); } catch (error) { }
        }
      }
      this.active = nextActive;
      this.emit();
    });
  }

  async relocate(id: string, from: string, to: string): Promise<void> {
    await this.ready();
    return this.enqueue((): void => {
      const stamp: AssetStamp | undefined = this.active.get(id);
      if (stamp === undefined || stamp.path !== from) { return; }
      const next: AssetStamp = this.copyStamp(stamp); next.path = to;
      const actual: fs.Stat = fs.statSync(to);
      next.bytes = actual.size; next.modified = actual.mtime; next.changed = actual.ctime;
      const index: LibraryIndex | undefined = this.getIndex(id);
      if (index !== undefined && stamp.bytes === next.bytes && stamp.modified === next.modified) {
        index.stamp.path = to;
        index.stamp.bytes = next.bytes;
        index.stamp.modified = next.modified;
        index.stamp.changed = next.changed;
        this.writeAtomic(this.indexDir + '/' + this.shardName(id), JSON.stringify(index));
        this.indexes.set(id, index);
      } else if (index !== undefined) {
        this.indexes.delete(id);
        try { fs.unlinkSync(this.indexDir + '/' + this.shardName(id)); } catch (error) { }
      }
      this.active.set(id, next);
      this.emit();
    });
  }

  private async ready(): Promise<void> {
    if (this.initTask === undefined) { throw new Error('图库目录尚未初始化'); }
    await this.initTask;
  }
}

export const LIBRARY_CATALOG: LibraryCatalog = new LibraryCatalog();
