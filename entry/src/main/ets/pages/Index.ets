import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { display, uiMaterial } from '@kit.ArkUI';
import { BatchItem, DownloadItem, PictureItem, ZipItem } from '../model/Models';
import { DownloadStore } from '../service/DownloadStore';
import { Font, formatBytes, kindOf, Layout, Palette, Radius, Shadow, Space } from '../theme/Tokens';
import { Glyph } from '../view/Icons';
import { ArchiveCard, batchViewOf, BatchCard, BatchView, ImageViewer, SelectTile, ShotTile, TaskCard } from '../view/Cards';
import {
  Card, EmptyState, HintRow, IconButton, ListRow, MATERIAL_OPTIONS, MODE_OPTIONS, PillButton, RenameDialog,
  SectionHead, Segmented, StackedRow, TabBar, THEME_OPTIONS, TitleBar, ToastPill
} from '../view/Widgets';

interface ScanImage {
  url: string;
  description: string;
}

interface ScanData {
  title: string;
  url: string;
  images: ScanImage[];
}

@Entry
@Component
struct Index {
  private browser: webview.WebviewController = new webview.WebviewController();
  private noticeTimer: number = -1;
  /** Viewport height in vp — see the minHeight guard on each screen's scroller. */
  private screenHeight: number =
    display.getDefaultDisplaySync().height / display.getDefaultDisplaySync().densityPixels;

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  @State private currentTab: number = 0;
  @State private address: string = '';
  @State private pageUrl: string = '';
  @State private pageTitle: string = '';
  @State private pictures: PictureItem[] = [];
  @State private downloads: DownloadItem[] = [];
  @State private zips: ZipItem[] = [];
  @State private batches: BatchItem[] = [];
  @State private concurrency: number = 3;
  @State private mode: string = 'single';
  @State private query: string = '';
  @State private density: number = 2;
  @State private scanning: boolean = false;
  @State private previewId: string = '';
  @State private notice: string = '';
  @State private themeMode: string = 'system';
  @State private materialType: string = 'adaptive';
  @State private lightEffect: boolean = true;
  /** Rename overlay: shown while renameId is non-empty. */
  @State private renameKind: string = '';
  @State private renameId: string = '';
  @State private renameName: string = '';

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    DownloadStore.initialize(context, (): void => {
      this.sync();
    });
    this.sync();
    this.applyTheme();
  }

  private sync(): void {
    this.downloads = DownloadStore.downloads.slice();
    this.zips = DownloadStore.zips.slice();
    this.batches = DownloadStore.batches.slice();
    this.concurrency = DownloadStore.concurrency;
    this.themeMode = DownloadStore.themeMode;
    this.materialType = DownloadStore.materialType;
    this.lightEffect = DownloadStore.lightEffect;
  }

  private say(text: string): void {
    this.notice = text;
    if (this.noticeTimer >= 0) {
      clearTimeout(this.noticeTimer);
    }
    this.noticeTimer = setTimeout((): void => {
      this.notice = '';
    }, 2600);
  }

  // ---------------------------------------------------------------- geometry

  private topInset(tall: boolean): number {
    return this.safeTop + (tall ? Layout.tbLayerSecondary : Layout.tbLayerNormal) + Layout.tbGap;
  }

  /** Vertical space the floating tab bar occupies. */
  private tabBarSpace(): number {
    return Layout.tabBarHeight + Layout.tabBarTopPad + this.safeBottom;
  }

  private bottomInset(extra: number): number {
    return this.tabBarSpace() + Space.s12 + extra;
  }

  // ---------------------------------------------------------------- browsing

  private visit(): void {
    let input: string = this.address.trim();
    if (input.length === 0) {
      return;
    }
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      input = 'https://' + input;
    }
    this.address = input;
    this.pageUrl = input;
    this.pictures = [];
    if (new RegExp('\\.(png|jpe?g|webp|gif|heic|avif)(\\?|#|$)', 'i').test(input)) {
      const picture: PictureItem = new PictureItem();
      picture.id = input;
      picture.url = input;
      picture.selected = true;
      picture.name = DownloadStore.suggestedName(input, '', 1);
      this.pictures = [picture];
      this.pageTitle = '图片';
      this.say('这是一个图片地址');
      return;
    }
    this.pageTitle = '';
    this.scanning = true;
    try {
      this.browser.loadUrl(input);
    } catch (error) {
      this.scanning = false;
      this.say('无法打开该链接：' + String(error));
    }
  }

  private static parseScan(raw: string): ScanData {
    let parsed: Object = JSON.parse(raw) as Object;
    if (typeof parsed === 'string') {
      parsed = JSON.parse(parsed as string) as Object;
    }
    const data: ScanData = parsed as ScanData;
    if (typeof data.url !== 'string') {
      data.url = '';
    }
    if (typeof data.title !== 'string') {
      data.title = '';
    }
    if (!Array.isArray(data.images)) {
      data.images = [];
    }
    return data;
  }

  private async scan(): Promise<void> {
    const script: string = `(() => {
      const found = new Map();
      for (const img of document.images) {
        const sources = [img.currentSrc, img.getAttribute('data-src'), img.getAttribute('data-original'), img.src];
        for (const raw of sources) {
          if (!raw) continue;
          try {
            const url = new URL(raw, document.baseURI).href;
            if (url.startsWith('http://') || url.startsWith('https://'))
              found.set(url, { url: url, description: img.alt || img.title || '' });
          } catch (_) {}
        }
      }
      return JSON.stringify({ title: document.title || '', url: location.href, images: Array.from(found.values()) });
    })()`;
    this.scanning = true;
    try {
      const result: webview.JsMessageExt = await this.browser.runJavaScriptExt(script);
      const data: ScanData = Index.parseScan(result.getString());
      // about:blank and error pages report a non-http URL; scanning one would
      // both mislabel the page and overwrite the address the user typed.
      if (!data.url.startsWith('http://') && !data.url.startsWith('https://')) {
        this.scanning = false;
        return;
      }
      this.pageUrl = data.url;
      this.address = data.url;
      this.pageTitle = data.title;
      const found: Map<string, PictureItem> = new Map<string, PictureItem>();
      for (const old of this.pictures) {
        found.set(old.url, old);
      }
      for (let i: number = 0; i < data.images.length; i++) {
        const image: ScanImage = data.images[i];
        if (found.has(image.url)) {
          continue;
        }
        const picture: PictureItem = new PictureItem();
        picture.id = image.url;
        picture.url = image.url;
        picture.description = image.description;
        picture.name = DownloadStore.suggestedName(image.url, image.description, i + 1);
        found.set(image.url, picture);
      }
      this.pictures = Array.from(found.values());
      this.say('找到 ' + this.pictures.length.toString() + ' 张图片');
    } catch (error) {
      this.say('扫描失败，请等待页面加载后重试');
    }
    this.scanning = false;
  }

  private selectedCount(): number {
    return this.pictures.filter((item: PictureItem): boolean => item.selected).length;
  }

  private togglePicture(picture: PictureItem): void {
    picture.selected = !picture.selected;
    this.pictures = this.pictures.slice();
  }

  private selectAll(selected: boolean): void {
    for (const item of this.pictures) {
      item.selected = selected;
    }
    this.pictures = this.pictures.slice();
  }

  private enqueue(): void {
    if (this.selectedCount() === 0) {
      this.say('请先选择图片');
      return;
    }
    const zipMode: boolean = this.mode === 'zip';
    DownloadStore.add(this.pictures, this.pageUrl, this.pageTitle, zipMode);
    this.currentTab = 1;
    this.say(zipMode ? '已把所选图片加入打包队列' : '已加入下载任务');
  }

  // ---------------------------------------------------------------- tasks

  private plainTasks(): DownloadItem[] {
    return this.downloads.filter((item: DownloadItem): boolean => item.batchId.length === 0);
  }

  private activeTasks(): DownloadItem[] {
    return this.plainTasks().filter((item: DownloadItem): boolean =>
      item.status === 'running' || item.status === 'starting' || item.status === 'queued');
  }

  private settledTasks(): DownloadItem[] {
    return this.plainTasks().filter((item: DownloadItem): boolean =>
      item.status === 'completed' || item.status === 'failed' || item.status === 'cancelled');
  }

  private batchViews(): BatchView[] {
    const views: BatchView[] = [];
    for (const batch of this.batches) {
      const members: DownloadItem[] =
        this.downloads.filter((item: DownloadItem): boolean => item.batchId === batch.id);
      const done: number = members.filter((item: DownloadItem): boolean => item.status === 'completed').length;
      const failed: number = members.filter((item: DownloadItem): boolean =>
        item.status === 'failed' || item.status === 'cancelled').length;
      views.push(batchViewOf(batch, members, done, failed));
    }
    return views;
  }

  /** Downloads waiting to run plus packs in flight — the tab badge. */
  private runningCount(): number {
    return this.downloads.filter((item: DownloadItem): boolean =>
      item.status === 'running' || item.status === 'starting' || item.status === 'queued').length
      + this.batches.length;
  }

  private cancelTask(task: DownloadItem): void {
    DownloadStore.cancel(task);
    this.say('已取消 ' + task.name);
  }

  private retryTask(task: DownloadItem): void {
    DownloadStore.retry(task);
    this.say('重新加入队列');
  }

  private locate(task: DownloadItem): void {
    this.currentTab = 2;
    this.query = task.name.replace(new RegExp('\\.[^.]+$'), '');
    this.say('已在图库中定位');
  }

  // ---------------------------------------------------------------- gallery

  private galleryItems(): DownloadItem[] {
    const needle: string = this.query.trim().toLowerCase();
    return this.downloads.filter((item: DownloadItem): boolean => item.status === 'completed'
      && item.batchId.length === 0
      && item.name.toLowerCase().includes(needle));
  }

  private galleryCount(): number {
    return this.downloads.filter((item: DownloadItem): boolean =>
      item.status === 'completed' && item.batchId.length === 0).length;
  }

  private galleryBytes(): number {
    let total: number = 0;
    for (const item of this.downloads) {
      if (item.status === 'completed' && item.batchId.length === 0) {
        total += item.size;
      }
    }
    return total;
  }

  private previewItem(): DownloadItem | undefined {
    return this.downloads.find((item: DownloadItem): boolean => item.id === this.previewId);
  }

  private previewSrc(): string {
    const item: DownloadItem | undefined = this.previewItem();
    return item === undefined ? '' : fileUri.getUriFromPath(item.path);
  }

  private previewName(): string {
    const item: DownloadItem | undefined = this.previewItem();
    return item === undefined ? '' : item.name;
  }

  private previewKind(): string {
    const item: DownloadItem | undefined = this.previewItem();
    return item === undefined ? 'IMG' : kindOf(item.name);
  }

  // ---------------------------------------------------------------- actions

  private startRename(kind: string, id: string, name: string): void {
    this.renameKind = kind;
    this.renameId = id;
    this.renameName = name;
  }

  private applyRename(name: string): void {
    const kind: string = this.renameKind;
    const id: string = this.renameId;
    this.renameKind = '';
    this.renameId = '';
    if (id.length === 0) {
      return;
    }
    if (kind === 'zip') {
      const zip: ZipItem | undefined = this.zips.find((item: ZipItem): boolean => item.id === id);
      if (zip !== undefined) {
        this.say(DownloadStore.renameZip(zip, name) ? '重命名完成' : '名称已存在');
      }
      return;
    }
    const download: DownloadItem | undefined = this.downloads.find((item: DownloadItem): boolean => item.id === id);
    if (download !== undefined) {
      this.say(DownloadStore.renameDownload(download, name) ? '重命名完成' : '名称已存在');
    }
  }

  private confirmDeleteImage(item: DownloadItem): void {
    this.getUIContext().showAlertDialog({
      title: '删除图片',
      message: '将同时删除应用内文件和下载记录，已导出的副本不受影响。',
      primaryButton: {
        value: '取消', action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除', action: (): void => {
          DownloadStore.deleteDownload(item);
          if (this.previewId === item.id) {
            this.previewId = '';
          }
          this.say('已删除图片');
        }
      }
    });
  }

  private confirmDeleteZip(item: ZipItem): void {
    this.getUIContext().showAlertDialog({
      title: '删除压缩包',
      message: '将同时删除压缩包文件和记录，已导出的副本不受影响。',
      primaryButton: {
        value: '取消', action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除', action: (): void => {
          DownloadStore.deleteZip(item);
          this.say('已删除压缩包');
        }
      }
    });
  }

  private confirmClearAll(): void {
    this.getUIContext().showAlertDialog({
      title: '清空全部记录',
      message: '将删除应用内的全部图片、压缩包与下载记录。已导出的副本不受影响。',
      primaryButton: {
        value: '取消', action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除', action: (): void => {
          this.previewId = '';
          DownloadStore.clearAll();
          this.say('已清空全部记录');
        }
      }
    });
  }

  private cleanTemp(): void {
    const freed: number = DownloadStore.cleanStaging();
    this.say('暂存目录已清理 · 释放 ' + formatBytes(freed));
  }

  private async exportFile(path: string, name: string): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const savePicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = { newFileNames: [name] };
      const targets: string[] = await savePicker.save(options);
      if (targets.length === 0) {
        return;
      }
      const source: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const target: fs.File = fs.openSync(targets[0], fs.OpenMode.WRITE_ONLY);
      await fs.copyFile(source.fd, target.fd);
      fs.closeSync(source);
      fs.closeSync(target);
      this.say('已导出文件');
    } catch (error) {
      this.say('导出失败：' + String(error));
    }
  }

  private async saveToGallery(item: DownloadItem): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const dot: number = item.name.lastIndexOf('.');
      const extension: string = dot > 0 ? item.name.substring(dot + 1).toLowerCase() : 'jpg';
      // @SuppressWarnings permission
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, extension);
      const source: fs.File = fs.openSync(item.path, fs.OpenMode.READ_ONLY);
      const target: fs.File = fs.openSync(uri, fs.OpenMode.WRITE_ONLY);
      await fs.copyFile(source.fd, target.fd);
      fs.closeSync(source);
      fs.closeSync(target);
      this.say('已保存到系统相册');
    } catch (error) {
      this.say('保存相册失败：' + String(error));
    }
  }

  private async shareFile(path: string, name: string, isZip: boolean): Promise<void> {
    try {
      const typeId: string = isZip ? utd.UniformDataType.ZIP_ARCHIVE : utd.UniformDataType.IMAGE;
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: typeId,
        uri: fileUri.getUriFromPath(path),
        title: name
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (error) {
      this.say('分享失败：' + String(error));
    }
  }

  // ---------------------------------------------------------------- settings

  private pickTheme(value: string): void {
    DownloadStore.setThemeMode(value);
    this.sync();
    this.applyTheme();
  }

  private applyTheme(): void {
    const mode: ConfigurationConstant.ColorMode = DownloadStore.themeMode === 'dark'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : DownloadStore.themeMode === 'light'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(mode);
    } catch (error) {
    }
  }

  /** Device compute tier; the app reads it but cannot change it. */
  private deviceLevelName(): string {
    try {
      const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      if (level === uiMaterial.MaterialLevel.EXQUISITE) {
        return '精致 · 高算力';
      }
      if (level === uiMaterial.MaterialLevel.GENTLE) {
        return '均衡 · 中算力';
      }
      return '轻盈 · 低算力';
    } catch (error) {
      return '未知';
    }
  }

  private immersiveSupported(): boolean {
    try {
      return uiMaterial.isImmersiveMaterialSupported();
    } catch (error) {
      return false;
    }
  }

  // ---------------------------------------------------------------- grid math

  private rowsOfPicture(items: PictureItem[], columns: number): PictureItem[][] {
    const rows: PictureItem[][] = [];
    for (let start: number = 0; start < items.length; start += columns) {
      rows.push(items.slice(start, start + columns));
    }
    return rows;
  }

  private rowsOfDownload(items: DownloadItem[], columns: number): DownloadItem[][] {
    const rows: DownloadItem[][] = [];
    for (let start: number = 0; start < items.length; start += columns) {
      rows.push(items.slice(start, start + columns));
    }
    return rows;
  }

  private filler(count: number, columns: number): number[] {
    const missing: number = (columns - (count % columns)) % columns;
    const cells: number[] = [];
    for (let i: number = 0; i < missing; i++) {
      cells.push(i);
    }
    return cells;
  }

  // ---------------------------------------------------------------- 发现

  @Builder
  private browserCard() {
    Column() {
      Row({ space: Space.s4 }) {
        Row({ space: Space.s4 }) {
          Circle().width(7).height(7).fill(Palette.divider)
          Circle().width(7).height(7).fill(Palette.divider)
          Circle().width(7).height(7).fill(Palette.divider)
        }
        .flexShrink(0)

        Row({ space: Space.s6 }) {
          Glyph({ glyph: 'globe', glyphSize: 12, glyphTone: Palette.fontTertiary, glyphWeight: 2 })
          Text(this.pageUrl.length > 0 ? this.pageUrl : '输入网址后在这里浏览网页')
            .fontSize(11.5)
            .fontColor(Palette.fontTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .height(26)
        .padding({ left: Space.s10, right: Space.s10 })
        .borderRadius(Radius.full)
        .backgroundColor(Palette.cardSunken)
        .layoutWeight(1)

        IconButton({
          glyph: 'refresh', glyphSize: 16, diameter: 30, plain: true,
          onAction: (): void => {
            this.scan();
          }
        })
      }
      .width('100%')
      .height(42)
      .padding({ left: Space.s14, right: Space.s10 })

      Stack({ alignContent: Alignment.Bottom }) {
        Web({ src: 'about:blank', controller: this.browser })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .width('100%')
          .height('100%')
          .onPageEnd((): void => {
            this.scan();
          })

        if (this.scanning) {
          Row({ space: Space.s6 }) {
            LoadingProgress().width(16).height(16).color(Palette.white)
            Text('正在扫描当前网页…')
              .fontSize(Font.caption)
              .fontColor(Palette.white)
          }
          .padding({ left: Space.s10, right: Space.s12, top: Space.s6, bottom: Space.s6 })
          .borderRadius(Radius.full)
          .backgroundColor('#8C000000')
          .margin({ bottom: Space.s8 })
        }
      }
      .width('100%')
      .height(200)
      .backgroundColor(Palette.cardSunken)

      Row({ space: Space.s8 }) {
        Text(this.pageTitle.length > 0 ? this.pageTitle : '尚未打开网页')
          .fontSize(Font.body)
          .lineHeight(Font.bodyLine)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Row({ space: Space.s2 }) {
          Glyph({ glyph: 'image', glyphSize: 13, glyphTone: Palette.fontTertiary, glyphWeight: 2 })
          Text(this.pictures.length.toString() + ' 张')
            .fontSize(Font.caption)
            .fontColor(Palette.fontTertiary)
        }
      }
      .width('100%')
      .padding({ left: Space.s12, right: Space.s12, top: Space.s10, bottom: Space.s12 })
    }
    .width('100%')
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
    .clip(true)
  }

  @Builder
  private discoverScreen() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: Space.s16 }) {
          Row({ space: Space.s8 }) {
            Glyph({ glyph: 'globe', glyphSize: 18, glyphTone: Palette.fontTertiary, glyphWeight: 1.7 })
            TextInput({ placeholder: '输入网页或图片链接', text: this.address })
              .placeholderColor(Palette.fontSecondary)
              .caretColor(Palette.brand)
              .fontSize(Font.body)
              .fontColor(Palette.fontPrimary)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .height(36)
              .layoutWeight(1)
              .onChange((value: string): void => {
                this.address = value;
              })
              .onSubmit((key: EnterKeyType): void => {
                this.visit();
              })
            PillButton({
              label: '打开', variant: 'primary', active: this.address.trim().length > 0,
              onAction: (): void => {
                this.visit();
              }
            })
          }
          .width('100%')
          .height(44)
          .padding({ left: Space.s14, right: Space.s4 })
          .borderRadius(Radius.full)
          .backgroundColor(Palette.card)
          .shadow(Shadow.card())

          this.browserCard()

          Column({ space: Space.s10 }) {
            SectionHead({
              heading: '选择要下载的图片',
              meta: this.selectedCount() > 0
                ? '已选 ' + this.selectedCount().toString()
                : this.pictures.length.toString() + ' 张',
              actionLabel: '全选',
              secondLabel: '清空',
              onAction: (): void => {
                this.selectAll(true);
              },
              onSecond: (): void => {
                this.selectAll(false);
              }
            })

            if (this.pictures.length > 0) {
              Column({ space: Space.s8 }) {
                ForEach(this.rowsOfPicture(this.pictures, 3), (row: PictureItem[], rowIndex: number) => {
                  Row({ space: Space.s8 }) {
                    ForEach(row, (cell: PictureItem, colIndex: number) => {
                      Column() {
                        SelectTile({
                          picture: cell,
                          index: rowIndex * 3 + colIndex,
                          onToggle: (picture: PictureItem): void => {
                            this.togglePicture(picture);
                          }
                        })
                      }
                      .layoutWeight(1)
                    }, (cell: PictureItem) => cell.id)

                    ForEach(this.filler(row.length, 3), (pad: number) => {
                      Column().layoutWeight(1)
                    }, (pad: number) => 'pad' + pad.toString())
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }, (row: PictureItem[], rowIndex: number) => rowIndex.toString()
                  + ':' + row.map((cell: PictureItem): string => cell.id).join(','))
              }
              .width('100%')
            } else {
              Text('还没有扫描到图片。在上面的浏览器中打开网页，加载完成后会自动扫描。')
                .fontSize(Font.aux)
                .lineHeight(Font.subtitleLine)
                .fontColor(Palette.fontTertiary)
                .textAlign(TextAlign.Center)
                .width('100%')
                .padding({ top: Space.s20, bottom: Space.s20 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          HintRow({
            glyph: 'sparkle',
            text: '扫描只读取当前页面的图片地址；滚动页面后重新扫描可以发现更多。'
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: this.screenHeight })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: this.topInset(true),
          bottom: this.bottomInset(this.selectedCount() > 0 ? 68 : 0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      TitleBar({
        heading: '发现',
        caption: this.scanning ? '正在扫描当前网页…' : '',
        layer: Layout.tbLayerSecondary
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private selectionDock() {
    Row({ space: Space.s10 }) {
      Column({ space: 1 }) {
        Text('已选 ' + this.selectedCount().toString() + ' 张')
          .fontSize(Font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontPrimary)
        Text(this.mode === 'zip' ? '打包为 ZIP' : '保存为单独文件')
          .fontSize(Font.chip)
          .fontColor(Palette.fontTertiary)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Segmented({
        options: MODE_OPTIONS,
        selected: this.mode,
        onSelect: (value: string): void => {
          this.mode = value;
        }
      })

      PillButton({
        label: '下载',
        variant: 'primary',
        icon: this.mode === 'zip' ? 'layers' : 'download',
        onAction: (): void => {
          this.enqueue();
        }
      })
    }
    .width('100%')
    .padding({ left: Space.s16, right: Space.s8, top: Space.s8, bottom: Space.s8 })
    .borderRadius(Radius.full)
    .backgroundColor(Palette.glassStrong)
    .backdropBlur(30)
    .shadow(Shadow.float())
  }

  // ---------------------------------------------------------------- 任务

  @Builder
  private concurrencyCard() {
    Card({ pad: Space.s12 }) {
      Column({ space: Space.s10 }) {
        Row({ space: Space.s8 }) {
          Text('同时下载')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.fontPrimary)
          Blank()
          Text('超过并发的任务自动排队')
            .fontSize(Font.caption)
            .lineHeight(Font.captionLine)
            .fontColor(Palette.fontTertiary)
        }
        .width('100%')

        Slider({ value: this.concurrency, min: 1, max: 10, step: 1, style: SliderStyle.OutSet })
          .width('100%')
          .trackThickness(4)
          .selectedColor(Palette.brand)
          .trackColor(Palette.cardSunken)
          .blockColor(Palette.white)
          .blockBorderWidth(5)
          .blockBorderColor(Palette.brand)
          .onChange((value: number): void => {
            DownloadStore.setConcurrency(Math.round(value));
          })

        Text(this.concurrency.toString() + ' 个任务同时进行')
          .fontSize(Font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.brand)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private taskList(tasks: DownloadItem[]) {
    Column({ space: Space.s12 }) {
      ForEach(tasks, (task: DownloadItem) => {
        TaskCard({
          task: task,
          onCancel: (item: DownloadItem): void => {
            this.cancelTask(item);
          },
          onRetry: (item: DownloadItem): void => {
            this.retryTask(item);
          },
          onLocate: (item: DownloadItem): void => {
            this.locate(item);
          },
          onRename: (item: DownloadItem): void => {
            this.startRename('task', item.id, item.name);
          }
        })
      }, (task: DownloadItem) => task.id)
    }
    .width('100%')
  }

  @Builder
  private tasksScreen() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: Space.s16 }) {
          this.concurrencyCard()

          if (this.batchViews().length > 0) {
            Column({ space: Space.s10 }) {
              SectionHead({ heading: '打包任务', meta: 'ZIP' })
              Column({ space: Space.s12 }) {
                ForEach(this.batchViews(), (view: BatchView) => {
                  BatchCard({ view: view })
                }, (view: BatchView) => view.id + '|' + view.status + '|'
                  + view.done.toString() + '|' + view.failed.toString())
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          if (this.activeTasks().length > 0) {
            Column({ space: Space.s10 }) {
              SectionHead({ heading: '进行中', meta: this.activeTasks().length.toString() })
              this.taskList(this.activeTasks())
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          if (this.settledTasks().length > 0) {
            Column({ space: Space.s10 }) {
              SectionHead({ heading: '已完成 / 失败', meta: this.settledTasks().length.toString() })
              this.taskList(this.settledTasks())
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          if (this.runningCount() === 0 && this.settledTasks().length === 0) {
            EmptyState({
              glyph: 'inbox',
              heading: '还没有下载任务',
              body: '回到「发现」，扫描网页并选择要保存的图片。'
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: this.screenHeight })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: this.topInset(true),
          bottom: this.bottomInset(0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      TitleBar({
        heading: '任务',
        caption: this.runningCount() > 0
          ? this.runningCount().toString() + ' 个任务进行中 · 并发 ' + this.concurrency.toString()
          : '队列为空',
        layer: Layout.tbLayerSecondary
      })
    }
    .width('100%')
    .height('100%')
  }

  // ---------------------------------------------------------------- 图库

  @Builder
  private searchPill() {
    Row({ space: Space.s8 }) {
      Glyph({ glyph: 'search', glyphSize: 18, glyphTone: Palette.fontTertiary, glyphWeight: 1.7 })
      TextInput({ placeholder: '搜索文件名', text: this.query })
        .placeholderColor(Palette.fontSecondary)
        .caretColor(Palette.brand)
        .fontSize(Font.body)
        .fontColor(Palette.fontPrimary)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .height(36)
        .layoutWeight(1)
        .onChange((value: string): void => {
          this.query = value;
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: Space.s14, right: Space.s14 })
    .borderRadius(Radius.full)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }

  @Builder
  private galleryGrid() {
    Column({ space: Space.s12 }) {
      ForEach(this.rowsOfDownload(this.galleryItems(), this.density),
        (row: DownloadItem[], rowIndex: number) => {
          Row({ space: this.density === 3 ? Space.s6 : Space.s12 }) {
            ForEach(row, (cell: DownloadItem, colIndex: number) => {
              Column() {
                ShotTile({
                  image: cell,
                  dense: this.density === 3,
                  onOpen: (item: DownloadItem): void => {
                    this.previewId = item.id;
                  }
                })
              }
              .layoutWeight(1)
            }, (cell: DownloadItem) => cell.id)

            ForEach(this.filler(row.length, this.density), (pad: number) => {
              Column().layoutWeight(1)
            }, (pad: number) => 'pad' + pad.toString())
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (row: DownloadItem[], rowIndex: number) => rowIndex.toString()
          + ':' + row.map((cell: DownloadItem): string => cell.id).join(','))
    }
    .width('100%')
  }

  @Builder
  private galleryScreen() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: Space.s16 }) {
          this.searchPill()

          if (this.galleryItems().length > 0) {
            this.galleryGrid()
          } else {
            EmptyState({
              glyph: 'image',
              heading: this.query.length > 0 ? '没有匹配的图片' : '图库还是空的',
              body: this.query.length > 0 ? '换一个关键词试试。' : '下载完成的图片会出现在这里。'
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: this.screenHeight })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: this.topInset(true),
          bottom: this.bottomInset(0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      TitleBar({
        heading: '图库',
        caption: this.galleryCount().toString() + ' 张图片 · ' + formatBytes(this.galleryBytes()),
        actionGlyph: 'grid',
        layer: Layout.tbLayerSecondary,
        onAction: (): void => {
          this.density = this.density === 2 ? 3 : 2;
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  // ---------------------------------------------------------------- 打包

  @Builder
  private archivesScreen() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: Space.s12 }) {
          if (this.zips.length === 0) {
            EmptyState({
              glyph: 'archive',
              heading: '还没有压缩包',
              body: '在「发现」里打开 ZIP 模式，把选中的图片打包成一个压缩包。'
            })
          }

          ForEach(this.zips, (zip: ZipItem) => {
            ArchiveCard({
              zip: zip,
              onRename: (item: ZipItem): void => {
                this.startRename('zip', item.id, item.name);
              },
              onExport: (item: ZipItem): void => {
                this.exportFile(item.path, item.name);
              },
              onShare: (item: ZipItem): void => {
                this.shareFile(item.path, item.name, true);
              },
              onDelete: (item: ZipItem): void => {
                this.confirmDeleteZip(item);
              }
            })
          }, (zip: ZipItem) => zip.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: this.screenHeight })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: this.topInset(true),
          bottom: this.bottomInset(0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      TitleBar({
        heading: '打包',
        caption: this.zips.length.toString() + ' 个压缩包',
        layer: Layout.tbLayerSecondary
      })
    }
    .width('100%')
    .height('100%')
  }

  // ---------------------------------------------------------------- 设置

  @Builder
  private sliderRow() {
    Slider({ value: this.concurrency, min: 1, max: 10, step: 1, style: SliderStyle.OutSet })
      .width('100%')
      .trackThickness(4)
      .selectedColor(Palette.brand)
      .trackColor(Palette.cardSunken)
      .blockColor(Palette.white)
      .blockBorderWidth(5)
      .blockBorderColor(Palette.brand)
      .onChange((value: number): void => {
        DownloadStore.setConcurrency(Math.round(value));
      })
  }

  @Builder
  private settingsScreen() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: Space.s20 }) {
          Column({ space: Space.s10 }) {
            SectionHead({ heading: '外观' })
            Card({ pad: 0 }) {
              StackedRow({
                glyph: this.themeMode === 'dark' ? 'moon' : 'sun',
                heading: '主题',
                aux: this.themeMode === 'system'
                  ? '跟随系统'
                  : (this.themeMode === 'dark' ? '固定为深色' : '固定为浅色')
              }) {
                Segmented({
                  options: THEME_OPTIONS,
                  selected: this.themeMode,
                  onSelect: (value: string): void => {
                    this.pickTheme(value);
                  }
                })
              }
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: Space.s10 }) {
            SectionHead({ heading: '系统特性', meta: 'HarmonyOS' })
            Card({ pad: 0 }) {
              Column() {
                ListRow({
                  glyph: 'sparkle',
                  brandTone: true,
                  heading: '沉浸光感',
                  aux: '触摸时材质表面被点亮，并带交互形变'
                }) {
                  Toggle({ type: ToggleType.Switch, isOn: this.lightEffect })
                    .selectedColor(Palette.brand)
                    .onChange((value: boolean): void => {
                      DownloadStore.setLightEffect(value);
                      this.sync();
                    })
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                StackedRow({
                  glyph: 'layers',
                  heading: '材质类型',
                  aux: this.materialType === 'immersive'
                    ? (this.immersiveSupported()
                      ? '沉浸式材质 · 含边缘流光'
                      : '本机不支持沉浸式材质，将回退为静态模糊')
                    : '由系统按场景自动选择材质风格'
                }) {
                  Segmented({
                    options: MATERIAL_OPTIONS,
                    selected: this.materialType,
                    onSelect: (value: string): void => {
                      DownloadStore.setMaterialType(value);
                      this.sync();
                    }
                  })
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'sliders',
                  heading: '材质等级',
                  aux: '由设备算力决定，应用只读取、不修改'
                }) {
                  Text(this.deviceLevelName())
                    .fontSize(Font.aux)
                    .fontColor(Palette.fontSecondary)
                }
              }
              .width('100%')
            }

            HintRow({
              glyph: 'sparkle',
              text: '沉浸光感与材质来自 UI Design Kit 的 uiMaterial：按设备算力等级生效，'
                + '低算力设备会自动降级为静态模糊。'
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: Space.s10 }) {
            SectionHead({ heading: '下载' })
            Card({ pad: 0 }) {
              Column() {
                StackedRow({
                  glyph: 'download',
                  heading: '同时下载数量',
                  aux: '超出的任务自动排队，范围 1–10'
                }) {
                  this.sliderRow()
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'folder',
                  heading: '文件名来源',
                  aux: '优先用服务器返回的文件名，其次用网页描述'
                }) {
                  Text('服务器优先')
                    .fontSize(Font.aux)
                    .fontColor(Palette.fontSecondary)
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'archive',
                  heading: '下载位置',
                  aux: '应用文件 · 图片与压缩包分开存放'
                }) {
                  Text('应用文件')
                    .fontSize(Font.aux)
                    .fontColor(Palette.fontSecondary)
                }
              }
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: Space.s10 }) {
            SectionHead({
              heading: '数据',
              meta: DownloadStore.usedBytes() > 0 ? '占用 ' + formatBytes(DownloadStore.usedBytes()) : ''
            })
            Card({ pad: 0 }) {
              Column() {
                ListRow({
                  glyph: 'trash',
                  heading: '清理临时文件',
                  aux: '打包中断后残留在暂存目录的图片',
                  onAction: (): void => {
                    this.cleanTemp();
                  }
                }) {
                  Text('清理')
                    .fontSize(Font.aux)
                    .fontColor(Palette.brand)
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'xCircle',
                  heading: '清空全部下载记录',
                  aux: '删除应用内的文件与记录，已导出的副本不受影响',
                  onAction: (): void => {
                    this.confirmClearAll();
                  }
                }) {
                  Text('清空')
                    .fontSize(Font.aux)
                    .fontColor(Palette.warning)
                }
              }
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Text('图片下载管理 · 1.0.0')
            .fontSize(Font.caption)
            .fontColor(Palette.fontTertiary)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: this.screenHeight })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: this.topInset(false),
          bottom: this.bottomInset(0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      TitleBar({ heading: '设置', layer: Layout.tbLayerNormal })
    }
    .width('100%')
    .height('100%')
  }

  // ---------------------------------------------------------------- shell

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // The browser tab stays mounted so the page in it survives a tab switch.
      Column() {
        this.discoverScreen()
      }
      .width('100%')
      .height('100%')
      .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.None)

      if (this.currentTab === 1) {
        this.tasksScreen()
      }
      if (this.currentTab === 2) {
        this.galleryScreen()
      }
      if (this.currentTab === 3) {
        this.archivesScreen()
      }
      if (this.currentTab === 4) {
        this.settingsScreen()
      }

      if (this.previewId.length > 0 && this.previewItem() !== undefined) {
        ImageViewer({
          src: this.previewSrc(),
          heading: this.previewName(),
          label: this.previewKind(),
          onClose: (): void => {
            this.previewId = '';
          },
          onRename: (): void => {
            const item: DownloadItem | undefined = this.previewItem();
            if (item !== undefined) {
              this.startRename('image', item.id, item.name);
            }
          },
          onSaveToGallery: (): void => {
            const item: DownloadItem | undefined = this.previewItem();
            if (item !== undefined) {
              this.saveToGallery(item);
            }
          },
          onShare: (): void => {
            const item: DownloadItem | undefined = this.previewItem();
            if (item !== undefined) {
              this.shareFile(item.path, item.name, false);
            }
          },
          onExport: (): void => {
            const item: DownloadItem | undefined = this.previewItem();
            if (item !== undefined) {
              this.exportFile(item.path, item.name);
            }
          },
          onDelete: (): void => {
            const item: DownloadItem | undefined = this.previewItem();
            if (item !== undefined) {
              this.confirmDeleteImage(item);
            }
          }
        })
      }

      if (this.currentTab === 0 && this.selectedCount() > 0) {
        Column() {
          this.selectionDock()
        }
        .width('100%')
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          bottom: this.tabBarSpace() + Space.s12
        })
      }

      TabBar({
        active: this.currentTab,
        badge: this.runningCount(),
        onSelect: (index: number): void => {
          this.currentTab = index;
        }
      })

      if (this.notice.length > 0) {
        Column() {
          ToastPill({ text: this.notice })
        }
        .width('100%')
        .padding({ left: Layout.pagePad, right: Layout.pagePad, bottom: this.tabBarSpace() + 88 })
      }

      if (this.renameId.length > 0) {
        RenameDialog({
          heading: this.renameKind === 'zip' ? '重命名压缩包' : '重命名图片',
          initial: this.renameName,
          onSave: (name: string): void => {
            this.applyRename(name);
          },
          onClose: (): void => {
            this.renameId = '';
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.bg)
  }
}
