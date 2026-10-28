import { PreviewAsset } from '../model/PreviewAsset';
import { ImageMetadata, ImageTools } from '../service/ImageTools';
import { MediaFormat } from '../service/MediaFormat';
import { DownloadStore } from '../service/DownloadStore';
import { LIBRARY_CATALOG } from '../service/LibraryCatalog';
import { LibraryAnalysis } from '../service/LibraryAnalysis';
import { ImageSuperResolution } from '../service/ImageSuperResolution';
import { AnalysisToken, LibraryIndex } from '../model/LibraryAsset';
import { DownloadItem } from '../model/Models';
import { Font, formatBytes, Palette, Space } from '../theme/Tokens';
import { SCREEN_INSETS } from '../theme/Metrics';
import { SheetStyle } from '../theme/SheetStyle';
import { TransparentGlass } from '../theme/TransparentGlass';
import { IconButton, PillButton } from './Widgets';
import { ImageTagDialog } from './ImageTagDialog';

@ComponentV2
export struct PreviewTools {
  @Require @Param asset: PreviewAsset;
  @Param backgroundMode: string = 'auto';
  @Event onBackground: (mode: string) => void = (): void => {};
  @Event onCompare: () => void = (): void => {};
  @Event onEdit: (id: string) => void = (id: string): void => {};
  @Event onClose: () => void = (): void => {};
  @Local private metadata: ImageMetadata = new ImageMetadata();
  @Local private busy: boolean = false;
  @Local private notice: string = '';
  @Local private recognizedText: string = '';
  @Local private codes: string[] = [];
  @Local private favorite: boolean = false;
  @Local private tags: string[] = [];
  @Local private tagDialogOpen: boolean = false;
  @Local private activeTab: string = 'details';
  @Local private noticeGroup: string = 'details';
  private sheetMaterial: SystemUiMaterial | undefined = SheetStyle.material();
  private generation: number = 0;
  private alive: boolean = false;
  private superResolutionToken: AnalysisToken | undefined = undefined;

  private catalogListener: () => void = (): void => { this.refreshMeta(); };
  aboutToAppear(): void {
    this.alive = true;
    LIBRARY_CATALOG.subscribe(this.catalogListener);
    this.load();
  }
  aboutToDisappear(): void {
    this.alive = false; this.generation++;
    this.superResolutionToken?.cancel();
    this.superResolutionToken = undefined;
    LIBRARY_CATALOG.unsubscribe(this.catalogListener);
  }
  private loadedId: string = '';
  private loadedPath: string = '';
  @Monitor('asset')
  private onAssetChanged(monitor: IMonitor): void {
    if (this.asset.id !== this.loadedId || this.asset.localPath !== this.loadedPath) { this.load(); }
  }

  private load(): void {
    this.superResolutionToken?.cancel();
    this.superResolutionToken = undefined;
    this.loadedId = this.asset.id;
    this.loadedPath = this.asset.localPath;
    const token: number = ++this.generation;
    this.metadata = new ImageMetadata();
    this.activeTab = 'details';
    this.noticeGroup = 'details';
    this.busy = false;
    this.notice = '';
    this.recognizedText = '';
    this.codes = [];
    this.refreshMeta();
    if (this.asset.localPath.length === 0) { return; }
    ImageTools.metadata(this.asset.localPath).then((value: ImageMetadata): void => {
      if (this.alive && token === this.generation) { this.metadata = value; }
    }).catch((): void => {
      if (this.alive && token === this.generation) {
        this.noticeGroup = 'details';
        this.notice = '文件信息暂不可读';
      }
    });
  }

  private refreshMeta(): void {
    const id: string = this.asset.libraryId;
    if (id.length === 0) { this.favorite = false; this.tags = []; return; }
    const meta = LIBRARY_CATALOG.getMeta(id);
    this.favorite = meta.favorite;
    this.tags = meta.tags;
  }

  private async toggleFavorite(): Promise<void> {
    if (this.asset.libraryId.length === 0) { return; }
    try {
      await LIBRARY_CATALOG.setFavorite([this.asset.libraryId], !this.favorite);
      this.refreshMeta();
    } catch (error) { this.noticeGroup = 'manage'; this.notice = '收藏保存失败，请重试'; }
  }

  private async saveTags(add: string[], remove: string[]): Promise<void> {
    this.tagDialogOpen = false;
    if (this.asset.libraryId.length === 0) { return; }
    try {
      await LIBRARY_CATALOG.changeTags([this.asset.libraryId], add, remove);
      this.refreshMeta();
    } catch (error) { this.noticeGroup = 'manage'; this.notice = '标签保存失败，请重试'; }
  }

  private async copy(value: string, group: string = 'details'): Promise<void> {
    const token: number = this.generation;
    this.noticeGroup = group;
    try {
      await ImageTools.copy(value);
      if (this.alive && token === this.generation) { this.notice = '已复制'; }
    } catch (error) {
      if (this.alive && token === this.generation) { this.notice = '复制失败，请重试'; }
    }
  }

  private async recognize(text: boolean): Promise<void> {
    if (this.busy || this.asset.localPath.length === 0) { return; }
    const token: number = this.generation;
    const path: string = this.asset.localPath;
    this.busy = true;
    this.noticeGroup = 'recognize';
    this.notice = text ? '正在识别文字…' : '正在识别二维码…';
    try {
      if (text) {
        let value: string = '';
        const item: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
          entry.id === this.asset.libraryId && entry.status === 'completed');
        if (this.asset.libraryId.length > 0 && item !== undefined) {
          await LibraryAnalysis.ocr([item], true, new AnalysisToken(), (): void => {});
          const index: LibraryIndex | undefined = LIBRARY_CATALOG.getIndex(item.id);
          if (index?.ocrStatus === 'failed') { throw new Error(index.ocrError); }
          value = index?.text ?? '';
        } else {
          value = await ImageTools.text(path);
        }
        if (!this.alive || token !== this.generation) { return; }
        this.recognizedText = value;
        this.notice = value.trim().length > 0 ? '文字识别完成，可选择或复制' : '未识别到文字，可下载原图后重试';
      } else {
        const values: string[] = await ImageTools.codes(path, DownloadStore.context.cacheDir);
        if (!this.alive || token !== this.generation) { return; }
        this.codes = values;
        this.notice = values.length > 0 ? '识别完成，请选择复制或打开' : '未识别到二维码，可下载原图后重试';
      }
    } catch (error) {
      if (this.alive && token === this.generation) { this.notice = '识别失败：' + String(error); }
    } finally {
      if (this.alive && token === this.generation) { this.busy = false; }
    }
  }

  private async superResolve(): Promise<void> {
    if (!ImageSuperResolution.available()) {
      this.noticeGroup = 'edit';
      this.notice = ImageSuperResolution.unavailableHint();
      return;
    }
    if (this.busy || this.asset.libraryId.length === 0) { return; }
    const id: string = this.asset.libraryId;
    const item: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
      entry.id === id && entry.status === 'completed');
    if (item === undefined || !DownloadStore.exists(item.path) || this.asset.localPath.length === 0) {
      this.notice = '请先下载图片，再使用超分';
      return;
    }
    const generation: number = this.generation;
    const token: AnalysisToken = new AnalysisToken();
    this.superResolutionToken = token;
    this.busy = true;
    this.noticeGroup = 'edit';
    this.notice = '正在处理图片超分…';
    try {
      await ImageSuperResolution.createCopy(id, token);
      if (this.alive && generation === this.generation && !token.cancelled) {
        this.notice = '已生成超分副本，可在图库查看';
      }
    } catch (error) {
      if (this.alive && generation === this.generation && !token.cancelled) {
        this.notice = '图片超分失败：' + (error instanceof Error ? error.message : String(error));
      }
    } finally {
      if (this.superResolutionToken === token) { this.superResolutionToken = undefined; }
      if (this.alive && generation === this.generation) { this.busy = false; }
    }
  }

  private async open(value: string, group: string = 'details'): Promise<void> {
    const token: number = this.generation;
    this.noticeGroup = group;
    try { await ImageTools.open(DownloadStore.context, value); }
    catch (error) {
      if (this.alive && token === this.generation) { this.notice = '无法打开链接，可复制后使用浏览器打开'; }
    }
  }

  private dimensions(): string {
    const width: number = this.metadata.width || this.asset.width;
    const height: number = this.metadata.height || this.asset.height;
    return width > 0 && height > 0 ? width.toString() + ' × ' + height.toString() : '未知';
  }

  private localReady(): boolean {
    return this.asset.localPath.length > 0 && DownloadStore.exists(this.asset.localPath);
  }

  private mediaKind(): string {
    return DownloadStore.downloads.find((entry: DownloadItem): boolean =>
      entry.id === this.asset.libraryId)?.kind ?? '';
  }

  @Builder
  private sectionTitle(label: string) {
    Text(label).fontSize(Font.aux).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.secondary())
      .width('100%')
  }

  @Builder
  private metadataRow(label: string, key: string) {
    Row({ space: Space.s8 }) {
      Text(label).fontSize(Font.aux).fontColor(TransparentGlass.secondary()).width(72)
      Text(key === 'dimensions' ? this.dimensions() :
        key === 'format' ? (this.metadata.format || '未知') :
        key === 'range' ? (this.metadata.width > 0
          ? (this.metadata.isHdr ? 'HDR（高动态范围）' : 'SDR（标准动态范围）') : '未知') :
        key === 'bytes' ? ((this.metadata.bytes || this.asset.bytes) > 0
          ? formatBytes(this.metadata.bytes || this.asset.bytes) : '未知') :
        (this.asset.downloadedAt > 0 ? new Date(this.asset.downloadedAt).toLocaleString()
          : this.asset.downloaded ? '未记录' : '尚未下载'))
        .fontSize(Font.aux).fontColor(TransparentGlass.foreground()).layoutWeight(1)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  private linkRow(label: string, value: string, sourcePage: boolean) {
    Column({ space: Space.s4 }) {
      Row() {
        Text(label).fontSize(Font.aux).fontColor(TransparentGlass.secondary()).layoutWeight(1)
        IconButton({ glyph: 'copy', tone: Palette.brand, plain: true, diameter: 36,
          accessibilityLabel: '复制' + label, onAction: (): void => { this.copy(value); } })
        if (sourcePage && ImageTools.link(value).length > 0) {
          IconButton({ glyph: 'arrowRight', tone: Palette.brand, plain: true, diameter: 36,
            accessibilityLabel: '打开来源网页', onAction: (): void => { this.open(value); } })
        }
      }.width('100%')
      Text(value).fontSize(Font.caption).fontColor(TransparentGlass.foreground())
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .copyOption(CopyOptions.LocalDevice).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private status(group: string) {
    if (this.noticeGroup === group && this.notice.length > 0) {
      Text(this.notice).fontSize(Font.caption).fontColor(TransparentGlass.foreground()).width('100%')
    }
  }

  @Builder
  private backgroundButton(mode: string, name: string) {
    Column() {
      PillButton({ label: name, small: true, block: true,
        variant: this.backgroundMode === mode ? 'primary' : 'tonal',
        onAction: (): void => { this.onBackground(mode); } })
    }.layoutWeight(1)
  }

  @Builder
  private tagContent() {
    ImageTagDialog({ current: this.tags,
      onSave: (add: string[], remove: string[]): void => { this.saveTags(add, remove); },
      onClose: (): void => { this.tagDialogOpen = false; } })
  }

  @Builder
  private detailsContent() {
    Scroll() {
      Column({ space: Space.s16 }) {
        Column({ space: Space.s8 }) {
          this.sectionTitle('文件信息')
          Row({ space: Space.s8 }) {
            Text(this.asset.name.length > 0 ? this.asset.name : '未命名图片')
              .fontSize(Font.body).fontWeight(FontWeight.Medium).fontColor(TransparentGlass.foreground())
              .layoutWeight(1).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              .copyOption(CopyOptions.LocalDevice)
            if (this.asset.name.length > 0) {
              IconButton({ glyph: 'copy', tone: Palette.brand, plain: true, diameter: 40,
                accessibilityLabel: '复制文件名', onAction: (): void => { this.copy(this.asset.name); } })
            }
          }.width('100%').alignItems(VerticalAlign.Center)
          this.metadataRow('分辨率', 'dimensions')
          this.metadataRow('格式', 'format')
          this.metadataRow('动态范围', 'range')
          this.metadataRow('文件大小', 'bytes')
          this.metadataRow('下载时间', 'downloadedAt')
          if (MediaFormat.isLivepicStill(this.asset.url)) {
            Text('实况照片：网页只提供静图，动态部分不可用')
              .fontSize(Font.caption).fontColor(TransparentGlass.secondary()).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
        if (this.asset.url.length > 0 || this.asset.sourcePage.length > 0) {
          Column({ space: Space.s12 }) {
            this.sectionTitle('来源')
            if (this.asset.url.length > 0) { this.linkRow('图片链接', this.asset.url, false) }
            if (this.asset.sourcePage.length > 0) { this.linkRow('来源网页', this.asset.sourcePage, true) }
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        this.status('details')
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ bottom: SCREEN_INSETS.safeBottom + Space.s16 })
    }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
  }

  @Builder
  private toolsContent() {
    Scroll() {
      Column({ space: Space.s20 }) {
        Column({ space: Space.s8 }) {
          this.sectionTitle('收藏与标签')
          if (this.asset.libraryId.length > 0) {
            Row({ space: Space.s8 }) {
              PillButton({ label: this.favorite ? '已收藏' : '收藏图片', small: true,
                variant: this.favorite ? 'primary' : 'tonal',
                onAction: (): void => { this.toggleFavorite(); } })
              PillButton({ label: '编辑标签', small: true, variant: 'tonal',
                onAction: (): void => { this.tagDialogOpen = true; } })
            }
            Text(this.tags.length > 0 ? this.tags.join('、') : '尚无标签')
              .fontSize(Font.caption).fontColor(TransparentGlass.secondary()).width('100%')
          } else {
            Text('下载后可收藏和添加标签').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          }
          this.status('manage')
        }.width('100%').alignItems(HorizontalAlign.Start)

        Column({ space: Space.s8 }) {
          this.sectionTitle('编辑与超分')
          Row({ space: Space.s8 }) {
            Column() {
              PillButton({ label: this.asset.animated ? '编辑首帧副本' :
                this.mediaKind() === 'livephoto' ? '编辑封面副本' : '编辑副本',
                small: true, block: true, variant: 'tonal',
                active: this.asset.libraryId.length > 0 && this.localReady(),
                onAction: (): void => { this.onEdit(this.asset.libraryId); } })
            }.layoutWeight(1)
            Column() {
              PillButton({ label: this.asset.animated ? '超分首帧' :
                this.mediaKind() === 'livephoto' ? '超分封面' : '图片超分',
                small: true, block: true, variant: 'tonal',
                active: !this.busy && this.asset.libraryId.length > 0 && this.localReady() &&
                  ImageSuperResolution.available(),
                onAction: (): void => { this.superResolve(); } })
            }.layoutWeight(1)
          }.width('100%')
          if (this.asset.libraryId.length === 0) {
            Text('下载后可编辑并生成超分副本').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          } else if (!this.localReady()) {
            Text('本地图片不可读，重新下载后可使用').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          } else if (!ImageSuperResolution.available()) {
            Text(ImageSuperResolution.unavailableHint()).fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          }
          if (this.busy && this.noticeGroup === 'edit') {
            LoadingProgress().width(28).height(28).color(Palette.brand)
          }
          this.status('edit')
        }.width('100%').alignItems(HorizontalAlign.Start)

        Column({ space: Space.s8 }) {
          this.sectionTitle('查看背景')
          Row({ space: Space.s4 }) {
            this.backgroundButton('auto', '自动')
            this.backgroundButton('black', '黑色')
            this.backgroundButton('white', '白色')
            this.backgroundButton('checker', '棋盘格')
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)

        Column({ space: Space.s8 }) {
          this.sectionTitle('文字与二维码')
          Row({ space: Space.s8 }) {
            PillButton({ label: '识别文字', small: true, variant: 'tonal',
              active: !this.busy && this.asset.localPath.length > 0,
              onAction: (): void => { this.recognize(true); } })
            PillButton({ label: '识别二维码', small: true, variant: 'tonal',
              active: !this.busy && this.asset.localPath.length > 0,
              onAction: (): void => { this.recognize(false); } })
          }
          if (this.asset.localPath.length === 0) {
            Text('加载预览或下载图片后可使用识别工具').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          }
          if (this.busy && this.noticeGroup === 'recognize') {
            LoadingProgress().width(28).height(28).color(Palette.brand)
          }
          this.status('recognize')
          if (this.recognizedText.length > 0) {
            Text(this.recognizedText).fontSize(Font.body).fontColor(TransparentGlass.foreground())
              .copyOption(CopyOptions.LocalDevice).width('100%')
            PillButton({ label: '复制全部文字', small: true, variant: 'tonal',
              onAction: (): void => { this.copy(this.recognizedText, 'recognize'); } })
          }
          ForEach(this.codes, (value: string) => {
            Column({ space: Space.s8 }) {
              Text(value).fontSize(Font.caption).fontColor(TransparentGlass.foreground())
                .copyOption(CopyOptions.LocalDevice).width('100%')
              Row({ space: Space.s8 }) {
                PillButton({ label: '复制内容', small: true, variant: 'tonal',
                  onAction: (): void => { this.copy(value, 'recognize'); } })
                if (ImageTools.link(value).length > 0) {
                  PillButton({ label: '打开链接', small: true, variant: 'primary',
                    onAction: (): void => { this.open(value, 'recognize'); } })
                }
              }
            }.width('100%')
          }, (value: string) => value)
        }.width('100%').alignItems(HorizontalAlign.Start)

        Column({ space: Space.s8 }) {
          this.sectionTitle('图片对比')
          PillButton({ label: '选择图片进行对比', small: true, variant: 'tonal',
            onAction: this.onCompare })
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ bottom: SCREEN_INSETS.safeBottom + Space.s16 })
    }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
  }

  build() {
    Column({ space: Space.s12 }) {
      Row() {
        Text('图片详情').fontSize(Font.body).fontColor(TransparentGlass.foreground())
          .fontWeight(FontWeight.Bold).layoutWeight(1)
        IconButton({ glyph: 'close', tone: TransparentGlass.foreground(), plain: true, diameter: 36,
          accessibilityLabel: '关闭图片详情', onAction: this.onClose })
      }.width('100%')
      Row({ space: Space.s8 }) {
        Column() {
          PillButton({ label: '详情', small: true, block: true,
            variant: this.activeTab === 'details' ? 'primary' : 'tonal',
            onAction: (): void => { this.activeTab = 'details'; } })
        }.layoutWeight(1)
        Column() {
          PillButton({ label: '工具', small: true, block: true,
            variant: this.activeTab === 'tools' ? 'primary' : 'tonal',
            onAction: (): void => { this.activeTab = 'tools'; } })
        }.layoutWeight(1)
      }.width('100%')
      if (this.activeTab === 'details') { this.detailsContent() }
      else { this.toolsContent() }
    }.height('100%').width('100%')
      .padding({ left: Space.s16, right: Space.s16, top: Space.s16 })
      .bindSheet(this.tagDialogOpen, this.tagContent(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        backgroundColor: SheetStyle.background(),
        systemMaterial: this.sheetMaterial,
        onDisappear: (): void => { this.tagDialogOpen = false; }
      })
  }
}
