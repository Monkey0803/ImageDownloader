import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BatchItem, DownloadItem, PictureItem, ZipItem } from '../model/Models';
import { DownloadStore } from '../service/DownloadStore';

interface ScanImage { url: string; description: string; }
interface ScanData { title: string; url: string; images: ScanImage[]; }

@Entry
@Component
struct Index {
  private browser: webview.WebviewController = new webview.WebviewController();
  @State currentTab: number = 0;
  @State address: string = '';
  @State pageUrl: string = '';
  @State pageTitle: string = '';
  @State pictures: PictureItem[] = [];
  @State downloads: DownloadItem[] = [];
  @State zips: ZipItem[] = [];
  @State batches: BatchItem[] = [];
  @State concurrency: number = 3;
  @State zipMode: boolean = false;
  @State revision: number = 0;
  @State query: string = '';
  @State editingId: string = '';
  @State editingName: string = '';
  @State previewId: string = '';
  @State notice: string = '';

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    DownloadStore.initialize(context, (): void => { this.sync(); });
  }

  private sync(): void {
    this.downloads = DownloadStore.downloads.slice();
    this.zips = DownloadStore.zips.slice();
    this.batches = DownloadStore.batches.slice();
    this.concurrency = DownloadStore.concurrency;
    this.revision += 1;
  }

  private visit(): void {
    let input: string = this.address.trim();
    if (input.length === 0) { return; }
    if (!input.startsWith('http://') && !input.startsWith('https://')) { input = 'https://' + input; }
    this.address = input;
    this.pageUrl = input;
    this.pictures = [];
    if (new RegExp('\\.(png|jpe?g|webp|gif|heic|avif)(\\?|#|$)', 'i').test(input)) {
      const picture: PictureItem = new PictureItem();
      picture.id = input; picture.url = input; picture.selected = true;
      picture.name = DownloadStore.suggestedName(input, '', 1);
      this.pictures = [picture]; this.pageTitle = '图片';
    } else {
      try {
        this.browser.loadUrl(input);
      } catch (error) {
        this.notice = '无法打开该链接：' + String(error);
      }
    }
  }

  private static parseScan(raw: string): ScanData {
    let parsed: Object = JSON.parse(raw) as Object;
    if (typeof parsed === 'string') { parsed = JSON.parse(parsed as string) as Object; }
    const data: ScanData = parsed as ScanData;
    if (typeof data.url !== 'string') { data.url = ''; }
    if (typeof data.title !== 'string') { data.title = ''; }
    if (!Array.isArray(data.images)) { data.images = []; }
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
    try {
      const result: webview.JsMessageExt = await this.browser.runJavaScriptExt(script);
      const data: ScanData = Index.parseScan(result.getString());
      if (data.url.length > 0) { this.pageUrl = data.url; }
      this.pageTitle = data.title;
      const found: Map<string, PictureItem> = new Map<string, PictureItem>();
      for (const old of this.pictures) { found.set(old.url, old); }
      for (let i: number = 0; i < data.images.length; i++) {
        const image: ScanImage = data.images[i];
        if (found.has(image.url)) { continue; }
        const picture: PictureItem = new PictureItem();
        picture.id = image.url; picture.url = image.url; picture.description = image.description;
        picture.name = DownloadStore.suggestedName(image.url, image.description, i + 1);
        found.set(image.url, picture);
      }
      this.pictures = Array.from(found.values());
      this.notice = '找到 ' + this.pictures.length.toString() + ' 张图片';
    } catch (error) { this.notice = '扫描失败，请等待页面加载后重试'; }
  }

  private enqueue(): void {
    if (!this.pictures.some((item: PictureItem): boolean => item.selected)) { this.notice = '请先选择图片'; return; }
    DownloadStore.add(this.pictures, this.pageUrl, this.pageTitle, this.zipMode);
    this.currentTab = 1; this.notice = '已加入下载任务';
  }

  private async exportFile(path: string, name: string): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const savePicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = { newFileNames: [name] };
      const targets: string[] = await savePicker.save(options);
      if (targets.length === 0) { return; }
      const source: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const target: fs.File = fs.openSync(targets[0], fs.OpenMode.WRITE_ONLY);
      await fs.copyFile(source.fd, target.fd);
      fs.closeSync(source); fs.closeSync(target);
      this.notice = '已导出文件';
    } catch (error) { this.notice = '导出失败：' + String(error); }
  }

  private async saveToGallery(item: DownloadItem): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const extension: string = item.name.substring(item.name.lastIndexOf('.') + 1).toLowerCase();
      // @SuppressWarnings permission
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, extension);
      const source: fs.File = fs.openSync(item.path, fs.OpenMode.READ_ONLY);
      const target: fs.File = fs.openSync(uri, fs.OpenMode.WRITE_ONLY);
      await fs.copyFile(source.fd, target.fd);
      fs.closeSync(source); fs.closeSync(target);
      this.notice = '已保存到系统相册';
    } catch (error) { this.notice = '保存相册失败：' + String(error); }
  }

  private async shareFile(path: string, name: string, isZip: boolean): Promise<void> {
    try {
      const typeId: string = isZip ? utd.UniformDataType.ZIP_ARCHIVE : utd.UniformDataType.IMAGE;
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: typeId, uri: fileUri.getUriFromPath(path), title: name
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (error) { this.notice = '分享失败：' + String(error); }
  }

  private confirmDeleteImage(item: DownloadItem): void {
    this.getUIContext().showAlertDialog({
      title: '删除图片', message: '将同时删除应用内文件和下载记录，已导出的副本不受影响。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '删除', action: (): void => { DownloadStore.deleteDownload(item); } }
    });
  }

  private confirmDeleteZip(item: ZipItem): void {
    this.getUIContext().showAlertDialog({
      title: '删除 ZIP', message: '将同时删除压缩包文件和记录，已导出的副本不受影响。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '删除', action: (): void => { DownloadStore.deleteZip(item); } }
    });
  }

  private renameCurrent(): void {
    const download: DownloadItem | undefined = DownloadStore.downloads.find((item: DownloadItem): boolean => item.id === this.editingId);
    if (download !== undefined) { this.notice = DownloadStore.renameDownload(download, this.editingName) ? '重命名完成' : '名称已存在'; }
    const zip: ZipItem | undefined = DownloadStore.zips.find((item: ZipItem): boolean => item.id === this.editingId);
    if (zip !== undefined) { this.notice = DownloadStore.renameZip(zip, this.editingName) ? '重命名完成' : '名称已存在'; }
    this.editingId = '';
  }

  private statusText(status: string): string {
    if (status === 'queued') { return '排队中'; }
    if (status === 'starting') { return '正在启动'; }
    if (status === 'running') { return '下载中'; }
    if (status === 'packing') { return '打包中'; }
    if (status === 'completed') { return '已完成'; }
    if (status === 'failed') { return '失败'; }
    if (status === 'cancelled') { return '已取消'; }
    return status;
  }

  @Builder private discovery(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入网页或图片链接', text: this.address }).onChange((value: string): void => { this.address = value; }).layoutWeight(1)
        Button('打开').onClick((): void => { this.visit(); })
      }.padding({ left: 16, right: 16 })
      Row({ space: 8 }) {
        Button('扫描当前页').onClick((): void => { this.scan(); })
        Button('全选').onClick((): void => { for (const item of this.pictures) { item.selected = true; } this.pictures = [...this.pictures]; })
        Button('清空').onClick((): void => { for (const item of this.pictures) { item.selected = false; } this.pictures = [...this.pictures]; })
      }
      Web({ src: this.pageUrl.length > 0 ? this.pageUrl : 'about:blank', controller: this.browser })
        .javaScriptAccess(true).domStorageAccess(true).onPageEnd((): void => { this.scan(); }).height('36%')
      Row({ space: 8 }) {
        Text('发现 ' + this.pictures.length.toString() + ' 张').layoutWeight(1).fontSize(13)
        Toggle({ type: ToggleType.Switch, isOn: this.zipMode }).onChange((value: boolean): void => { this.zipMode = value; })
        Text('ZIP').fontSize(13)
      }.padding({ left: 16, right: 16 })
      List({ space: 6 }) {
        ForEach(this.pictures, (item: PictureItem) => {
          ListItem() {
            Row({ space: 8 }) {
              Toggle({ type: ToggleType.Checkbox, isOn: item.selected }).onChange((value: boolean): void => { item.selected = value; this.pictures = [...this.pictures]; })
              Image(item.url).width(48).height(48).objectFit(ImageFit.Cover).borderRadius(6)
              Column() {
                Text(item.description.length > 0 ? item.description : item.url).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                TextInput({ text: item.name }).onChange((value: string): void => {
                  // TextInput 初始化时也会回调 onChange，只有内容真的变了才算用户改名，
                  // 否则会误标 userNamed 并让服务器返回的文件名（content-disposition）失效
                  if (value !== item.name) { item.name = value; item.userNamed = true; }
                })
              }.layoutWeight(1)
            }.padding(8).backgroundColor('#F4F7FB').borderRadius(10)
          }
        }, (item: PictureItem): string => item.id + '|' + item.selected.toString())
      }.layoutWeight(1).width('100%').padding({ left: 16, right: 16 })
      Button(this.zipMode ? '打包下载所选图片' : '下载所选图片').width('90%').onClick((): void => { this.enqueue(); })
    }.layoutWeight(1).width('100%')
  }

  @Builder private tasks(): void {
    List({ space: 8 }) {
      ForEach(this.downloads, (item: DownloadItem) => {
        ListItem() {
          Column({ space: 6 }) {
            Text(item.name).fontSize(15).fontWeight(FontWeight.Medium)
            Text(this.statusText(item.status) + (item.error.length > 0 ? ' · ' + item.error : '')).fontSize(12).fontColor('#667890')
            if (item.status === 'running' && item.total > 0) { Progress({ value: item.processed, total: item.total, type: ProgressType.Linear }) }
            Row({ space: 8 }) {
              if (item.status === 'failed' || item.status === 'cancelled') { Button('重试').onClick((): void => { DownloadStore.retry(item); }) }
              if (item.status === 'running' || item.status === 'queued' || item.status === 'starting') { Button('取消').onClick((): void => { DownloadStore.cancel(item); }) }
              if (item.batchId.length > 0) { Text('ZIP 批次').fontSize(11) }
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor('#F4F7FB').borderRadius(12)
        }
      }, (item: DownloadItem): string => item.id + '|' + item.status + '|' + item.processed.toString() + '|' + item.total.toString() + '|' + item.name + '|' + item.error)
      ForEach(this.batches, (batch: BatchItem) => {
        ListItem() {
          Column() {
            Text(batch.name).fontSize(15)
            Text('打包：' + this.statusText(batch.status) + (batch.error.length > 0 ? ' · ' + batch.error : '')).fontSize(12)
          }.width('100%').padding(12).backgroundColor('#EAF2FF').borderRadius(12)
        }
      }, (batch: BatchItem): string => batch.id + '|' + batch.status + '|' + batch.name + '|' + batch.error)
    }.layoutWeight(1).width('100%').padding({ left: 16, right: 16 }).id('tasks-' + this.revision.toString())
  }

  @Builder private gallery(): void {
    Column() {
      TextInput({ placeholder: '搜索文件名', text: this.query }).onChange((value: string): void => { this.query = value; }).margin({ left: 16, right: 16 })
      List({ space: 8 }) {
        ForEach(this.downloads.filter((item: DownloadItem): boolean => item.status === 'completed' && item.batchId.length === 0 && item.name.toLowerCase().includes(this.query.toLowerCase())), (item: DownloadItem) => {
          ListItem() {
            Column({ space: 8 }) {
              Row({ space: 10 }) {
                Image(fileUri.getUriFromPath(item.path)).width(58).height(58).objectFit(ImageFit.Cover).borderRadius(8).onClick((): void => { this.previewId = item.id; })
                Text(item.name).fontSize(14).layoutWeight(1)
              }
              Flex({ wrap: FlexWrap.Wrap }) {
                Button('重命名').onClick((): void => { this.editingId = item.id; this.editingName = item.name; })
                SaveButton({ text: SaveDescription.SAVE_IMAGE }).onClick((_event: ClickEvent, result: SaveButtonOnClickResult): void => {
                  if (result === SaveButtonOnClickResult.SUCCESS) { this.saveToGallery(item); }
                })
                Button('分享').onClick((): void => { this.shareFile(item.path, item.name, false); })
                Button('导出').onClick((): void => { this.exportFile(item.path, item.name); })
                Button('删除').onClick((): void => { this.confirmDeleteImage(item); })
              }
            }.width('100%').padding(10).backgroundColor('#F4F7FB').borderRadius(12)
          }
        }, (item: DownloadItem): string => item.id + '|' + item.name + '|' + item.path)
      }.layoutWeight(1).width('100%').padding({ left: 16, right: 16 }).id('gallery-' + this.revision.toString())
    }.layoutWeight(1)
  }

  @Builder private archives(): void {
    List({ space: 8 }) {
      ForEach(this.zips, (item: ZipItem) => {
        ListItem() {
          Column({ space: 8 }) {
            Text(item.name).fontSize(16).fontWeight(FontWeight.Medium)
            Text(item.imageCount.toString() + ' 张图片 · ' + item.failedCount.toString() + ' 张失败').fontSize(12)
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('重命名').onClick((): void => { this.editingId = item.id; this.editingName = item.name; })
              Button('导出').onClick((): void => { this.exportFile(item.path, item.name); })
              Button('分享').onClick((): void => { this.shareFile(item.path, item.name, true); })
              Button('删除').onClick((): void => { this.confirmDeleteZip(item); })
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor('#F4F7FB').borderRadius(12)
        }
      }, (item: ZipItem): string => item.id + '|' + item.name + '|' + item.imageCount.toString() + '|' + item.failedCount.toString())
    }.layoutWeight(1).width('100%').padding({ left: 16, right: 16 }).id('archives-' + this.revision.toString())
  }

  @Builder private settings(): void {
    Column({ space: 18 }) {
      Text('同时下载数量').fontSize(18).fontWeight(FontWeight.Medium)
      Text(this.concurrency.toString() + ' 个任务').fontSize(16).fontColor('#356BCE')
      Slider({ value: this.concurrency, min: 1, max: 10, step: 1 }).onChange((value: number): void => { DownloadStore.setConcurrency(Math.round(value)); })
      Text('单批选择数量不限，超过并发数的任务自动排队。').fontSize(13).fontColor('#667890')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(20).layoutWeight(1).id('settings-' + this.revision.toString())
  }

  build() {
    Column() {
      Column() {
        Text('图片下载管理').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#18243A')
        Text('浏览网页，收集图片，轻松归档').fontSize(13).fontColor('#62738B')
        if (this.notice.length > 0) { Text(this.notice).fontSize(12).fontColor('#2357A4') }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
      if (this.editingId.length > 0) {
        Row({ space: 8 }) {
          TextInput({ text: this.editingName }).onChange((value: string): void => { this.editingName = value; }).layoutWeight(1)
          Button('保存').onClick((): void => { this.renameCurrent(); })
          Button('取消').onClick((): void => { this.editingId = ''; })
        }.padding({ left: 16, right: 16 })
      }
      if (this.previewId.length > 0) {
        Column() {
          Image(fileUri.getUriFromPath(DownloadStore.downloads.find((item: DownloadItem): boolean => item.id === this.previewId)?.path ?? '')).width('90%').height(220).objectFit(ImageFit.Contain)
          Button('关闭预览').onClick((): void => { this.previewId = ''; })
        }.width('100%').backgroundColor('#EAF2FF')
      }
      if (this.currentTab === 0) { this.discovery() }
      if (this.currentTab === 1) { this.tasks() }
      if (this.currentTab === 2) { this.gallery() }
      if (this.currentTab === 3) { this.archives() }
      if (this.currentTab === 4) { this.settings() }
      Row() {
        ForEach(['发现', '任务', '图库', 'ZIP', '设置'], (label: string, index: number) => {
          Text(label).fontSize(14).fontColor(this.currentTab === index ? '#FFFFFF' : '#355070')
            .backgroundColor(this.currentTab === index ? '#356BCE' : '#EFF3FA').borderRadius(16)
            .padding({ left: 12, right: 12, top: 9, bottom: 9 }).onClick((): void => { this.currentTab = index; })
        }, (label: string): string => label)
      }.width('100%').justifyContent(FlexAlign.SpaceAround).padding({ bottom: 14 })
    }.width('100%').height('100%').backgroundColor('#FFFFFF')
  }
}
