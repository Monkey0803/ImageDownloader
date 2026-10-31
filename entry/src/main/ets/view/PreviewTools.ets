import { PreviewAsset } from '../model/PreviewAsset';
import { PreviewToolsViewModel } from '../viewmodel/PreviewToolsViewModel';
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
  @Local private vm: PreviewToolsViewModel = new PreviewToolsViewModel();
  @Local private tagDialogOpen: boolean = false;
  @Local private activeTab: string = 'details';
  private sheetMaterial: SystemUiMaterial | undefined = SheetStyle.material();
  private loadedId: string = '';
  private loadedPath: string = '';

  aboutToAppear(): void {
    this.loadedId = this.asset.id;
    this.loadedPath = this.asset.localPath;
    this.vm.start(this.asset);
  }

  aboutToDisappear(): void { this.vm.stop(); }

  @Monitor('asset')
  private onAssetChanged(monitor: IMonitor): void {
    if (this.asset.id === this.loadedId && this.asset.localPath === this.loadedPath) { return; }
    this.loadedId = this.asset.id;
    this.loadedPath = this.asset.localPath;
    this.activeTab = 'details';
    this.tagDialogOpen = false;
    this.vm.load(this.asset);
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
      Text(key === 'dimensions' ? this.vm.dimensions() :
        key === 'format' ? (this.vm.metadata.format || '未知') :
        key === 'range' ? (this.vm.metadata.width > 0
          ? (this.vm.metadata.isHdr ? 'HDR（高动态范围）' : 'SDR（标准动态范围）') : '未知') :
        key === 'bytes' ? ((this.vm.metadata.bytes || this.asset.bytes) > 0
          ? formatBytes(this.vm.metadata.bytes || this.asset.bytes) : '未知') :
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
          accessibilityLabel: '复制' + label, onAction: (): void => { this.vm.copy(value); } })
        if (sourcePage && this.vm.isLink(value)) {
          IconButton({ glyph: 'arrowRight', tone: Palette.brand, plain: true, diameter: 36,
            accessibilityLabel: '打开来源网页', onAction: (): void => { this.vm.open(value); } })
        }
      }.width('100%')
      Text(value).fontSize(Font.caption).fontColor(TransparentGlass.foreground())
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .copyOption(CopyOptions.LocalDevice).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private status(group: string) {
    if (this.vm.noticeGroup === group && this.vm.notice.length > 0) {
      Text(this.vm.notice).fontSize(Font.caption).fontColor(TransparentGlass.foreground()).width('100%')
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
    ImageTagDialog({ current: this.vm.tags,
      onSave: (add: string[], remove: string[]): void => { this.tagDialogOpen = false; this.vm.saveTags(add, remove); },
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
                accessibilityLabel: '复制文件名', onAction: (): void => { this.vm.copy(this.asset.name); } })
            }
          }.width('100%').alignItems(VerticalAlign.Center)
          this.metadataRow('分辨率', 'dimensions')
          this.metadataRow('格式', 'format')
          this.metadataRow('动态范围', 'range')
          this.metadataRow('文件大小', 'bytes')
          this.metadataRow('下载时间', 'downloadedAt')
          if (this.vm.isLivepicStill()) {
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
              PillButton({ label: this.vm.favorite ? '已收藏' : '收藏图片', small: true,
                variant: this.vm.favorite ? 'primary' : 'tonal',
                onAction: (): void => { this.vm.toggleFavorite(); } })
              PillButton({ label: '编辑标签', small: true, variant: 'tonal',
                onAction: (): void => { this.tagDialogOpen = true; } })
            }
            Text(this.vm.tags.length > 0 ? this.vm.tags.join('、') : '尚无标签')
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
                this.vm.mediaKind() === 'livephoto' ? '编辑封面副本' : '编辑副本',
                small: true, block: true, variant: 'tonal',
                active: this.asset.libraryId.length > 0 && this.vm.localReady(),
                onAction: (): void => { this.onEdit(this.asset.libraryId); } })
            }.layoutWeight(1)
            Column() {
              PillButton({ label: this.asset.animated ? '超分首帧' :
                this.vm.mediaKind() === 'livephoto' ? '超分封面' : '图片超分',
                small: true, block: true, variant: 'tonal',
                active: !this.vm.busy && this.asset.libraryId.length > 0 && this.vm.localReady() &&
                  this.vm.canSuperResolve(),
                onAction: (): void => { this.vm.superResolve(); } })
            }.layoutWeight(1)
          }.width('100%')
          if (this.asset.libraryId.length === 0) {
            Text('下载后可编辑并生成超分副本').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          } else if (!this.vm.localReady()) {
            Text('本地图片不可读，重新下载后可使用').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          } else if (!this.vm.canSuperResolve()) {
            Text(this.vm.superResolutionHint()).fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          }
          if (this.vm.busy && this.vm.noticeGroup === 'edit') {
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
              active: !this.vm.busy && this.asset.localPath.length > 0,
              onAction: (): void => { this.vm.recognize(true); } })
            PillButton({ label: '识别二维码', small: true, variant: 'tonal',
              active: !this.vm.busy && this.asset.localPath.length > 0,
              onAction: (): void => { this.vm.recognize(false); } })
          }
          if (this.asset.localPath.length === 0) {
            Text('加载预览或下载图片后可使用识别工具').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          }
          if (this.vm.busy && this.vm.noticeGroup === 'recognize') {
            LoadingProgress().width(28).height(28).color(Palette.brand)
          }
          this.status('recognize')
          if (this.vm.recognizedText.length > 0) {
            Text(this.vm.recognizedText).fontSize(Font.body).fontColor(TransparentGlass.foreground())
              .copyOption(CopyOptions.LocalDevice).width('100%')
            PillButton({ label: '复制全部文字', small: true, variant: 'tonal',
              onAction: (): void => { this.vm.copy(this.vm.recognizedText, 'recognize'); } })
          }
          ForEach(this.vm.codes, (value: string) => {
            Column({ space: Space.s8 }) {
              Text(value).fontSize(Font.caption).fontColor(TransparentGlass.foreground())
                .copyOption(CopyOptions.LocalDevice).width('100%')
              Row({ space: Space.s8 }) {
                PillButton({ label: '复制内容', small: true, variant: 'tonal',
                  onAction: (): void => { this.vm.copy(value, 'recognize'); } })
                if (this.vm.isLink(value)) {
                  PillButton({ label: '打开链接', small: true, variant: 'primary',
                    onAction: (): void => { this.vm.open(value, 'recognize'); } })
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
