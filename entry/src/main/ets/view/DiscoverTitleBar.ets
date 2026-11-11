import { BusinessError } from '@kit.BasicServicesKit';
import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { Font, Palette, Radius, Shadow, Space } from '../theme/Tokens';
import { Glyph } from './Icons';
import { IconButton, PillButton } from './Widgets';
import { SCREEN_INSETS, ScreenMetrics } from '../theme/Metrics';

/** The discover title content hosted by the root HdsNavigation. */
@ComponentV2
export struct DiscoverTitleBar {
  @Require @Param discover: DiscoverViewModel;
  @Param browserOpen: boolean = true;
  @Event onOpenBrowser: () => void = (): void => {};

  @Builder
  private addressEntry() {
    Row({ space: Space.s8 }) {
      Glyph({ glyph: 'globe', glyphSize: 18, glyphTone: Palette.fontTertiary, glyphWeight: 1.7 })
      TextInput({ placeholder: '输入网页或图片链接', text: this.discover.address })
        .placeholderColor(Palette.fontSecondary)
        .caretColor(Palette.brand)
        .fontSize(Font.body)
        .fontColor(Palette.fontPrimary)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .height(36)
        .layoutWeight(1)
        .onChange((value: string): void => { this.discover.address = value; })
        .onSubmit((): void => { this.discover.visit(); })
      if (this.discover.address.length > 0) {
        IconButton({ glyph: 'xCircle', glyphSize: 18, diameter: 32, plain: true,
          tone: Palette.fontTertiary, accessibilityLabel: '清空输入链接',
          onAction: (): void => { this.discover.address = ''; } })
      }
      PasteButton({ icon: PasteIconStyle.LINES, buttonType: ButtonType.Capsule })
        .iconSize(18).iconColor(Palette.brand).backgroundColor(Palette.brandSoft)
        .width(40).height(40)
        .onClick((_event: ClickEvent, result: PasteButtonOnClickResult,
          error?: BusinessError<void>): void => {
          if (result === PasteButtonOnClickResult.SUCCESS) { this.discover.pasteAddress(); }
          else { this.discover.pasteAuthorizationFailed(error?.code ?? 0); }
        })
      PillButton({ icon: 'arrowRight', variant: 'primary', small: true,
        active: this.discover.address.trim().length > 0,
        onAction: (): void => { this.discover.visit(); } })
    }
    .width('100%').height(44)
    .padding({ left: Space.s14, right: Space.s4 })
    .borderRadius(Radius.full)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }

  build() {
    Row({ space: Space.s6 }) {
      if (this.browserOpen) {
        Column() { this.addressEntry() }.layoutWeight(1)
        IconButton({ glyph: this.discover.isBookmarked() ? 'bookmarkFill' : 'bookmark',
          glyphSize: 20, diameter: 36, plain: true, tone: Palette.fontPrimary,
          accessibilityLabel: this.discover.isBookmarked() ? '取消收藏当前网页' : '收藏当前网页',
          onAction: (): void => { this.discover.toggleBookmark(); } })
      } else {
        IconButton({ glyph: 'chevronRight', glyphSize: 18, diameter: 36, plain: true,
          tone: Palette.fontPrimary, accessibilityLabel: '返回浏览扫描',
          onAction: this.onOpenBrowser }).rotate({ angle: 180 })
        Text('查看图片').fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(Palette.fontPrimary)
      }
    }
    .width('100%').padding({ left: ScreenMetrics.sideInset(SCREEN_INSETS.safeLeft),
      right: ScreenMetrics.sideInset(SCREEN_INSETS.safeRight) })
  }
}
