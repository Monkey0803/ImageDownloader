import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { Font, Layout, Palette, Radius, Shadow, Space } from '../theme/Tokens';
import { AppMenu } from './AppMenu';
import { MenuItemSpec, MenuSpec } from './MenuSpec';
import { Glyph } from './Icons';
import { IconButton } from './Widgets';

/**
 * 图库选择态的底部操作条。
 *
 * 之前这些操作长在网格上方（`selectionControls()` + `selectionActions()`，四五排按钮），
 * 一进入选择模式就把图片挤走 —— 恰恰是最需要看图的时候。现在收成一条压在页签栏上方的玻璃条：
 * 左边是计数，右边是高频动作，「收藏 / 标签 / 相册 / 碰一碰」收进「更多」菜单。
 *
 * 命中测试：最外层 Column 横跨整屏只为定位，必须 `HitTestMode.Transparent`，
 * 否则它会吃掉网格最后一行的触摸（同 AGENT.md 坑 23 的现象）。
 */
@ComponentV2
export struct LibrarySelectionBar {
  @Require @Param library: LibraryViewModel;
  /** 离屏幕底边的距离；由页面按浮动页签栏高度算好。 */
  @Param bottomSpace: number = 0;
  @Event onEditTags: () => void = (): void => {};
  @Event onOpenAlbums: () => void = (): void => {};

  private menuSpec(): MenuSpec {
    const items: MenuItemSpec[] = [];
    items.push(new MenuItemSpec('clear', '清空选择', (): void => {
      this.library.clearVisibleSelection();
    }).withIcon('xCircle'));
    items.push(new MenuItemSpec('tap',
      this.library.tapSharing ? '取消碰一碰' : '碰一碰分享', (): void => {
        if (this.library.tapSharing) { this.library.stopTapShare(); }
        else { this.library.startTapShare(); }
      }).withIcon('share'));
    if (!this.library.isZips()) {
      items.push(new MenuItemSpec('favorite', '收藏', (): void => {
        this.library.setSelectedFavorite(true);
      }).withIcon('bookmark'));
      items.push(new MenuItemSpec('unfavorite', '取消收藏', (): void => {
        this.library.setSelectedFavorite(false);
      }).withIcon('bookmark'));
      items.push(new MenuItemSpec('tags', '编辑标签', (): void => {
        this.onEditTags();
      }).withIcon('pencil'));
      items.push(new MenuItemSpec('albums', '加入或移出相册', (): void => {
        this.onOpenAlbums();
      }).withIcon('image'));
    }
    return new MenuSpec(items);
  }

  @Builder
  private moreMenu() {
    AppMenu(this.menuSpec());
  }

  @Builder
  private moreButton() {
    Button({ type: ButtonType.Circle }) {
      Glyph({ glyph: 'list', glyphSize: 20, glyphTone: Palette.fontPrimary, glyphWeight: 1.8 })
    }
    .width(40)
    .height(40)
    .backgroundColor(Color.Transparent)
    .accessibilityText('更多操作')
    .bindMenu(this.moreMenu(), { placement: Placement.TopRight })
  }

  build() {
    Column() {
      Row({ space: Space.s2 }) {
        Column({ space: 1 }) {
          Text('已选 ' + this.library.visibleSelectedCount.toString())
            .fontSize(Font.body)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.fontPrimary)
            .maxLines(1)
          Text(this.library.isZips() ? '个压缩包' : '共 ' + this.library.images.length.toString() + ' 张')
            .fontSize(Font.chip)
            .fontColor(Palette.fontTertiary)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        IconButton({ glyph: 'checkCircle', glyphSize: 20, diameter: 40, plain: true,
          accessibilityLabel: '全选', onAction: (): void => { this.library.selectVisible(); } })
        if (this.library.visibleSelectedCount > 0) {
          IconButton({ glyph: 'share', glyphSize: 20, diameter: 40, plain: true,
            accessibilityLabel: '分享', onAction: (): void => { this.library.shareSelected(); } })
          IconButton({ glyph: 'export', glyphSize: 20, diameter: 40, plain: true,
            accessibilityLabel: '导出', onAction: (): void => { this.library.exportSelected(); } })
          IconButton({ glyph: 'trash', glyphSize: 20, diameter: 40, plain: true, tone: Palette.warning,
            accessibilityLabel: '删除', onAction: (): void => { this.library.deleteSelected(); } })
        }
        this.moreButton()
      }
      .width('100%')
      .padding({ left: Space.s12, right: Space.s4, top: Space.s4, bottom: Space.s4 })
      .borderRadius(Radius.full)
      .backgroundColor(Palette.glassStrong)
      .backdropBlur(30)
      .shadow(Shadow.float())
    }
    .width('100%')
    .padding({ left: Layout.pagePad, right: Layout.pagePad, bottom: this.bottomSpace })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
