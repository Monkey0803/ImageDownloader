import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { PreviewNavigation } from '../util/PreviewNavigation';
import { IconButton, PillButton } from './Widgets';
import { Thumb } from './Thumb';

export interface PreviewThumbnail {
  id: string;
  src: string;
  name: string;
  localPath?: string;
}

class ThumbnailDataSource implements IDataSource {
  private items: PreviewThumbnail[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): PreviewThumbnail { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
  replace(items: PreviewThumbnail[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }
}

/** Open on demand: thumbnails do not request or decode while the strip is closed. */
@ComponentV2
export struct PreviewStrip {
  @Require @Param items: PreviewThumbnail[];
  @Require @Param currentIndex: number;
  @Event onJump: (index: number) => void = (): void => {};
  @Event onClose: () => void = (): void => {};
  private dataSource: ThumbnailDataSource = new ThumbnailDataSource();
  aboutToAppear(): void { this.dataSource.replace(this.items); }
  @Monitor('items')
  private onItemsChanged(monitor: IMonitor): void { this.dataSource.replace(this.items); }
  @Local private pageDraft: string = '';
  @Local private invalidPage: boolean = false;

  private jump(): void {
    const index: number = PreviewNavigation.jump(this.pageDraft, this.items.length);
    this.invalidPage = index < 0;
    if (index >= 0) { this.onJump(index); }
  }

  build() {
    Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        Text('跳转到').fontSize(Font.aux).fontColor(Palette.white)
        TextInput({ text: this.pageDraft, placeholder: '页码' })
          .type(InputType.Number).width(88).height(36).fontSize(Font.aux)
          .onChange((value: string): void => { this.pageDraft = value; this.invalidPage = false; })
          .onSubmit((): void => { this.jump(); })
        PillButton({ label: '跳转', small: true, variant: 'tonal', onAction: (): void => { this.jump(); } })
        Blank()
        IconButton({ glyph: 'close', plain: true, tone: Palette.white, diameter: 36,
          accessibilityLabel: '收起缩略图', onAction: this.onClose })
      }.width('100%')
      if (this.invalidPage) {
        Text('请输入 1–' + this.items.length.toString() + ' 的页码')
          .fontSize(Font.aux).fontColor('#FFB4A9')
      }
      List({ space: Space.s8, initialIndex: Math.max(0, this.currentIndex - 1) }) {
        LazyForEach(this.dataSource, (item: PreviewThumbnail, index: number) => {
          ListItem() {
            Column({ space: Space.s4 }) {
              Thumb({ src: item.src, firstFramePath: item.localPath ?? '', label: '', fit: ImageFit.Contain, fallbackText: '图片' })
                .width(64).height(64).borderRadius(Radius.r6)
                .border({ width: index === this.currentIndex ? 2 : 0, color: '#0A59F7' })
              Text((index + 1).toString()).fontSize(Font.aux).fontColor(Palette.white)
            }.width(68)
            .accessibilityText('第 ' + (index + 1).toString() + ' 张，' + item.name)
            .accessibilitySelected(index === this.currentIndex)
            .onClick((): void => { this.onJump(index); })
          }
        }, (item: PreviewThumbnail) => item.id)
      }.listDirection(Axis.Horizontal).height(92).width('100%').scrollBar(BarState.Off)
    }.width('100%').padding(Space.s12).backgroundColor('#EE222222')
    .hitTestBehavior(HitTestMode.Default)
  }
}
