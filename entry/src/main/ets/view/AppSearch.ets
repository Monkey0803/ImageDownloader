/*
 * AppSearch.ets — 基于系统 Search 的统一搜索框（状态管理 V2）。
 *
 * 为什么包装 Search 而不是继续用 TextInput：
 * 搜索场景需要左侧搜索图标、右侧清除按钮与回车提交语义，系统 Search 已内置这些能力，
 * 这里只做项目级统一：主题色光标/文字、沉浸玻璃兜底、焦点与文本事件上报。
 *
 * 沉浸光感：Search 不在应用级 UIMaterial 自动清单内，必须在标题栏等生效区域做组件级
 * systemMaterial；写法与 TwoFactor 一致——Stack 承载材质背景，内部 Search 透明。
 * 注意：普通组件的组件级材质只在 Navigation 标题栏 / End 位 TabBar 生效，页面内容区
 * 设置后既无视觉效果也不报错；本工程调用点均在内容区，该分支目前是预留能力，视觉回落 chip。
 */
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { DownloadStore } from '../service/DownloadStore';
import { MaterialController } from '../service/MaterialController';
import { Palette } from '../theme/Tokens';

@ComponentV2
export struct AppSearch {
  @Param text: string = '';
  @Param placeholder: ResourceStr = '';
  @Param inputId: string = '';
  @Param useImmersiveMaterial: boolean = false;
  /** 兼容旧调用：出现即请求焦点（DiscoverScreen 结果搜索依赖）。 */
  @Param focusOnAppear: boolean = false;
  @Event onChange: (value: string) => void = (value: string): void => {};
  @Event onSubmit: (value: string) => void = (value: string): void => {};
  @Event onSearchFocus: () => void = (): void => {};
  @Event onSearchBlur: () => void = (): void => {};
  private controller: SearchController = new SearchController();

  /** 与 TransparentGlass 同一口径：materialType 为 'none' 即用户关闭材质效果。 */
  private materialEnabled(): boolean {
    return DownloadStore.materialType !== 'none';
  }

  private materialActive(): boolean {
    return this.useImmersiveMaterial && MaterialController.uiActive(this.materialEnabled());
  }

  private placeholderColor(): ResourceColor {
    return this.materialActive() ? $r('sys.color.font_secondary') : $r('app.color.hm_text_secondary');
  }

  private textColor(): ResourceColor {
    return this.materialActive() ? $r('sys.color.font_primary') : $r('app.color.hm_text_primary');
  }

  private searchSymbol(): SymbolGlyphModifier {
    const symbol: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.magnifyingglass'));
    symbol.fontColor([this.materialActive() ? $r('sys.color.font_secondary') : Palette.brand]);
    return symbol;
  }

  private clearSymbol(): SymbolGlyphModifier {
    const symbol: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.xmark_circle_fill'));
    symbol.fontColor([this.materialActive() ? $r('sys.color.font_primary') : Palette.brand]);
    return symbol;
  }

  @Builder
  SearchField(background: ResourceColor) {
    Search({ value: this.text, placeholder: this.placeholder, controller: this.controller })
      .id(this.inputId)
      .width('100%')
      .height($r('app.float.form_field_height'))
      .borderRadius($r('app.float.radius_chip'))
      .backgroundColor(background)
      .placeholderColor(this.placeholderColor())
      .placeholderFont({ size: $r('app.float.font_size_body') })
      .textFont({ size: $r('app.float.font_size_body') })
      .fontColor(this.textColor())
      .caretStyle({ color: Palette.brand })
      .selectedBackgroundColor(Palette.brandSoft)
      .searchIcon(this.searchSymbol())
      .cancelButton({ style: CancelButtonStyle.INPUT, icon: this.clearSymbol() })
      .onChange((value: string): void => {
        this.onChange(value);
      })
      .onSubmit((value: string): void => {
        this.onSubmit(value);
      })
      .onFocus((): void => {
        this.onSearchFocus();
      })
      .onBlur((): void => {
        this.onSearchBlur();
      })
      .onAppear((): void => {
        if (this.focusOnAppear) {
          focusControl.requestFocus(this.inputId);
        }
      })
  }

  build() {
    if (this.useImmersiveMaterial) {
      Stack() {
        this.SearchField(Color.Transparent)
      }
      .width('100%')
      .height($r('app.float.form_field_height'))
      .backgroundColor($r('app.color.hm_value_chip_background'))
      .borderRadius($r('app.float.radius_chip'))
      .systemMaterial(MaterialController.glassMaterial(this.materialEnabled()))
    } else {
      this.SearchField($r('app.color.hm_value_chip_background'))
    }
  }
}
