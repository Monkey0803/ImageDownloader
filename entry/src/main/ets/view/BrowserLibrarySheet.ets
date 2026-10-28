import { TransparentGlass } from '../theme/TransparentGlass';
import { BrowserEntry } from '../service/BrowserCollection';
import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { Font, Layout, Palette, Space } from '../theme/Tokens';
import { SCREEN_INSETS } from '../theme/Metrics';
import { IconButton, PillButton } from './Widgets';

/** 收藏与历史的内容，由 Index 的系统 bindSheet 承载。 */
@ComponentV2
export struct BrowserLibrarySheet {
  @Require @Param discover: DiscoverViewModel;
  @Event onClose: () => void = (): void => {};

  private entries(): BrowserEntry[] {
    return this.discover.browserPanel === 'bookmarks' ? this.discover.bookmarks : this.discover.history;
  }

  build() {
    Column({ space: Space.s12 }) {
      Row({ space: Space.s8 }) {
        Text('收藏与历史').fontSize(Font.body).fontWeight(FontWeight.Bold)
          .fontColor(TransparentGlass.foreground()).layoutWeight(1)
        IconButton({ glyph: 'close', diameter: 36, plain: true, tone: TransparentGlass.foreground(),
          accessibilityLabel: '关闭收藏与历史', onAction: this.onClose })
      }.width('100%')

      Row({ space: Space.s8 }) {
        PillButton({ label: '历史 ' + this.discover.history.length.toString(), small: true,
          variant: this.discover.browserPanel === 'history' ? 'tonal' : 'ghost',
          onAction: (): void => { this.discover.browserPanel = 'history'; } })
        PillButton({ label: '收藏 ' + this.discover.bookmarks.length.toString(), small: true,
          variant: this.discover.browserPanel === 'bookmarks' ? 'tonal' : 'ghost',
          onAction: (): void => { this.discover.browserPanel = 'bookmarks'; } })
      }.width('100%')

      Row() {
        Text(this.discover.browserPanel === 'bookmarks' ? '收藏的网址' : '浏览记录')
          .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.foreground())
          .layoutWeight(1)
        if (this.discover.browserPanel === 'history' && this.discover.history.length > 0) {
          PillButton({ label: '清空历史', variant: 'danger', small: true,
            onAction: (): void => { this.discover.clearHistory(); } })
        }
      }.width('100%')

      Scroll() {
        if (this.entries().length === 0) {
          Text(this.discover.browserPanel === 'bookmarks' ? '还没有收藏网页' : '还没有浏览记录')
            .fontSize(Font.caption).fontColor(TransparentGlass.secondary()).padding({ top: Space.s8 })
        } else {
          Column() {
            ForEach(this.entries(), (item: BrowserEntry) => {
              Row({ space: Space.s8 }) {
                Column({ space: Space.s4 }) {
                  Text(item.title).fontSize(Font.body).fontColor(TransparentGlass.foreground())
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.url).fontSize(Font.caption).fontColor(TransparentGlass.secondary())
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
                .onClick((): void => {
                  this.onClose();
                  this.discover.address = item.url;
                  this.discover.visit();
                })
                IconButton({ glyph: 'copy', diameter: 36, glyphSize: 20, plain: true,
                  accessibilityLabel: '复制网址',
                  onAction: (): void => { this.discover.copyBrowserUrl(item.url); } })
                IconButton({ glyph: 'trash', diameter: 36, glyphSize: 20, plain: true,
                  tone: Palette.warning,
                  accessibilityLabel: this.discover.browserPanel === 'bookmarks' ? '移除收藏' : '删除浏览记录',
                  onAction: (): void => {
                    if (this.discover.browserPanel === 'bookmarks') {
                      this.discover.removeBookmark(item.url);
                    } else {
                      this.discover.removeHistory(item.url);
                    }
                  } })
              }
              .width('100%').padding({ top: Space.s10, bottom: Space.s10 })
            }, (item: BrowserEntry) => item.url)
          }.width('100%').padding({ bottom: SCREEN_INSETS.safeBottom + Space.s16 })
        }
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .padding({ left: Layout.pagePad, right: Layout.pagePad, top: Space.s16 })
  }
}
