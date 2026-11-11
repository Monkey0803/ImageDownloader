/*
 * AppSegmentButton.ets — 全应用唯一的分段控件（基于系统 SegmentButtonV2，状态管理 V2）。
 *
 * 改造前工程里有三套并存实现：`Widgets.Segmented`（手写）、`Widgets.LibrarySegment`
 * （内联 CapsuleSegmentButtonV2）、以及各面板里成组的 `PillButton`。它们各自处理选中配色、
 * 材质降级和宽度，改一处要跟着改一片。这里收成一个组件，调用方只给「标签 + 当前下标」。
 *
 * 颜色策略（AGENT.md 坑 10 真机实测的结论，不要为了「统一」改掉）：
 *   - 选中项永远是设计稿的品牌色字 + segOn 药丸，**开不开材质都一样**。系统材质只管组件背景板，
 *     选中项不会跟着反色；留空就会掉回系统蓝底 + 近黑字。
 *   - 未选中项：材质档用 sys.color.font_primary（跟随反色），兜底档用 Palette.fontSecondary。
 *
 * 材质（config.material）：
 *   由调用方按「用户开关 + 材质类型」决定；设备能力与应用级开关由 MaterialController 兜底。
 *   官方 FAQ：组件级沉浸材质只在 Navigation / NavDestination 标题栏、横向 Tabs 底部 TabBar 内渲染，
 *   页面内容区设置后没有视觉效果也不报错。所以内容区调用方保持 false，走玻璃兜底。
 *
 * 宽度（AGENT.md 坑 10）：
 *   SegmentButtonV2 不支持通用属性 / 通用事件，直接挂 .width() / .padding() 无效且不报错；
 *   它内部把宽度撑满父容器、再按项数平分。所以宽度由本组件的外层 Column 承担（config.width），
 *   需要「跟着文字走」的窄胶囊时，用 segmentCapsuleWidth() 按最宽标签算好再传。
 */

import {
  CapsuleSegmentButtonV2,
  ColorMetrics,
  LengthMetrics,
  SegmentButtonV2ItemOptions,
  SegmentButtonV2Items
} from '@kit.ArkUI';
import { MaterialController } from '../service/MaterialController';
import { Font, Palette, Radius, Space } from '../theme/Tokens';

export interface SegmentConfig {
  /**
   * 是否启用系统材质背景板；默认 false。
   * 只在标题栏 / 底部 TabBar 等生效区域传 true，内容区传了也不会渲染（见文件头）。
   */
  material?: boolean;
  /**
   * 紧凑档：12fp 字、28vp 项高、32vp 容器高、项内边距 12、项间距 2、容器内边距 2，
   * 并钳住字体缩放 —— 对齐改造前手写 Segmented / 图库分段的观感。
   */
  dense?: boolean;
  /** 组件根宽度；默认 '100%'，作用在外层容器上。 */
  width?: Length;
  /** 背板圆角（vp）；默认 Radius.full。 */
  radius?: number;
}

/** 一段文字的显示宽度估算（vp）：CJK 占满一个字号的宽度，Latin / 数字约六成。 */
function advanceOf(text: string, size: number): number {
  let width: number = 0;
  for (let i: number = 0; i < text.length; i += 1) {
    width += text.charCodeAt(i) > 0x2e80 ? size : size * 0.6;
  }
  return width;
}

/**
 * 「跟着文字走」的胶囊宽度。
 *
 * 为什么要按**最宽**标签 × 项数算：系统组件内部按项数平分可用宽度，按各项内容求和会让
 * 长标签被截断（坑 10 里「压缩包」被截成「压…」就是按内容求和导致的）。再给每项留 2vp 余量 ——
 * 个别字体下 CJK 的字形步进会比字号大一丁点，刚好卡满也会截字。
 */
export function segmentCapsuleWidth(labels: string[], fontSize: number, itemPadding: number): number {
  if (labels.length === 0) {
    return 0;
  }
  let widest: number = 0;
  for (let i: number = 0; i < labels.length; i += 1) {
    widest = Math.max(widest, advanceOf(labels[i], fontSize) + itemPadding * 2);
  }
  return Space.s2 * 2
    + (widest + Space.s2) * labels.length
    + Space.s2 * (labels.length - 1);
}

@ComponentV2
export struct AppSegmentButton {
  @Param labels: string[] = [];
  @Param selectedIndex: number = 0;
  @Param config: SegmentConfig = {};
  @Event onSelectedIndexChange: (index: number) => void = (index: number): void => {
  };

  /**
   * items 只在标签变化时重建。
   *
   * 直接每次 build 都 new 一个 SegmentButtonV2Items 会让系统组件反复吃新数组（切换时闪），
   * 而「历史 12 / 收藏 3」这种带计数的标签又必须能刷新，所以用标签串做缓存键。
   */
  private cachedKey: string = '';
  private cachedItems: SegmentButtonV2Items = new SegmentButtonV2Items([]);

  private items(): SegmentButtonV2Items {
    const key: string = this.labels.join('\u0001');
    if (key !== this.cachedKey) {
      const options: SegmentButtonV2ItemOptions[] = [];
      for (let i: number = 0; i < this.labels.length; i += 1) {
        const option: SegmentButtonV2ItemOptions = { text: this.labels[i] };
        options.push(option);
      }
      this.cachedItems = new SegmentButtonV2Items(options);
      this.cachedKey = key;
    }
    return this.cachedItems;
  }

  private dense(): boolean {
    return this.config.dense === true;
  }

  /**
   * 是否真的走材质模式。
   *
   * 三个条件：调用方要开、设备支持沉浸材质、应用级没被 DISABLE。
   * 内容区即使传了 true 也只会退回系统默认背板（官方限制），所以调用方不要图省事一律传 true。
   */
  private materialMode(): boolean {
    return this.config.material === true && MaterialController.glassSupported()
      && MaterialController.appMaterialOn();
  }

  private itemFontColor(material: boolean): ColorMetrics {
    return material
      ? ColorMetrics.resourceColor($r('sys.color.font_primary'))
      : ColorMetrics.resourceColor(Palette.fontSecondary);
  }

  /** 选中项字色：材质档不反色，两档都按设计稿写死。 */
  private itemSelectedFontColor(): ColorMetrics {
    return ColorMetrics.resourceColor(Palette.brand);
  }

  /** 选中项底色：两档都按设计稿写死，留空会掉回系统蓝药丸。 */
  private itemSelectedBackgroundColor(): ColorMetrics {
    return ColorMetrics.resourceColor(Palette.segOn);
  }

  /** 背板兜底：材质模式不再设背景色，避免盖住材质。 */
  private buttonBackgroundColor(material: boolean): ColorMetrics | undefined {
    return material ? undefined : ColorMetrics.resourceColor(Palette.cardSunken);
  }

  private itemFontSize(): LengthMetrics | undefined {
    return this.dense() ? LengthMetrics.vp(Font.caption) : undefined;
  }

  private itemFontWeight(): FontWeight | undefined {
    return this.dense() ? FontWeight.Bold : undefined;
  }

  private itemMinHeight(): LengthMetrics | undefined {
    return this.dense() ? LengthMetrics.vp(28) : undefined;
  }

  private itemPadding(): LocalizedPadding | undefined {
    return this.dense()
      ? { start: LengthMetrics.vp(Space.s12), end: LengthMetrics.vp(Space.s12) }
      : undefined;
  }

  private itemSpace(): LengthMetrics | undefined {
    return this.dense() ? LengthMetrics.vp(Space.s2) : undefined;
  }

  private buttonMinHeight(): LengthMetrics | undefined {
    return this.dense() ? LengthMetrics.vp(28 + Space.s2 * 2) : undefined;
  }

  private buttonPadding(): LengthMetrics | undefined {
    return this.dense() ? LengthMetrics.vp(Space.s2) : undefined;
  }

  /** 宽度是按标签算出来的定值，文字再随系统放大就会被挤掉，所以紧凑档钳住字体缩放。 */
  private fontScaleClamp(): number | undefined {
    return this.dense() ? 1 : undefined;
  }

  private buttonRadius(): LengthMetrics {
    return LengthMetrics.vp(this.config.radius ?? Radius.full);
  }

  build() {
    Column() {
      CapsuleSegmentButtonV2({
        items: this.items(),
        selectedIndex: this.selectedIndex,
        $selectedIndex: (index: number): void => {
          this.onSelectedIndexChange(index);
        },
        itemFontColor: this.itemFontColor(this.materialMode()),
        itemSelectedFontColor: this.itemSelectedFontColor(),
        itemFontSize: this.itemFontSize(),
        itemSelectedFontSize: this.itemFontSize(),
        itemFontWeight: this.itemFontWeight(),
        itemSelectedFontWeight: this.itemFontWeight(),
        itemMinFontScale: this.fontScaleClamp(),
        itemMaxFontScale: this.fontScaleClamp(),
        itemMinHeight: this.itemMinHeight(),
        itemPadding: this.itemPadding(),
        itemSpace: this.itemSpace(),
        itemSelectedBackgroundColor: this.itemSelectedBackgroundColor(),
        buttonBackgroundColor: this.buttonBackgroundColor(this.materialMode()),
        buttonMinHeight: this.buttonMinHeight(),
        buttonPadding: this.buttonPadding(),
        buttonBorderRadius: this.buttonRadius(),
        backgroundSystemMaterial: MaterialController.segmentMaterial(this.materialMode())
      })
    }
    .width(this.config.width ?? '100%')
  }
}
