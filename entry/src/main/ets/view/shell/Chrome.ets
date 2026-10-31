import { DiscoverViewModel } from '../../viewmodel/DiscoverViewModel';
import { DeviceViewModel } from '../../viewmodel/DeviceViewModel';
import { Font, Layout, Palette, Radius, Shadow, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { Glyph } from '../Icons';
import { IconButton, MODE_OPTIONS, PillButton, Segmented } from '../Widgets';
import { SCREEN_INSETS } from '../../theme/Metrics';

/**
 * 发现页的三块浮层与全局的返回顶部按钮。
 *
 * 它们必须由**页面壳**（Index）而不是发现页自己来画：都定位在滚动内容之外
 * （选择条压着页签栏、返回顶部按钮对齐屏幕边、防窥遮罩要盖住整屏但不盖页签栏），
 * 放在滚动容器里会被滚走。抽成独立组件只是为了让 Index 的 build 读起来是一张“层列表”。
 */

/**
 * 底部选择条：已选张数 + 单张 / ZIP 分段 + 下载按钮。
 *
 * 智感握姿：左手握持时整行反向，下载按钮落到左手拇指一侧，内边距跟着镜像。
 * 这里用 `reverse` 是刻意的 —— 要的就是整行换边（见 AGENT.md 坑 4）。
 */
@ComponentV2
export struct SelectionDock {
  @Require @Param discover: DiscoverViewModel;
  @Require @Param device: DeviceViewModel;

  build() {
    Row({ space: Space.s10 }) {
      Column({ space: 1 }) {
        Text('可加入 ' + this.discover.eligibleSelectedCount().toString() + ' 张')
          .fontSize(Font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontPrimary)
        Text('已选 ' + this.discover.selectedTotal.toString() + ' · '
          + (this.discover.mode === 'zip' ? '打包 ZIP' : '单独文件'))
          .fontSize(Font.chip)
          .fontColor(Palette.fontTertiary)
          .maxLines(1)
      }
      .alignItems(this.device.gripLeft() ? HorizontalAlign.End : HorizontalAlign.Start)
      .layoutWeight(1)

      Segmented({
        options: MODE_OPTIONS,
        selected: this.discover.mode,
        onSelect: (value: string): void => {
          this.discover.mode = value;
        }
      })

      // 图标按钮：`PillButton` 的图标在 label 为空时不渲染文字，方块也就自然收成圆形。
      // 这个按钮只做一件事 —— 把选中的图片下载下来；ZIP 只是打包方式，模式已经由左边的
      // 分段控件和上方的「打包为 ZIP / 保存为单独文件」说清楚了，不再用图标区分一次。
      PillButton({
        variant: 'primary',
        small: true,
        icon: 'download',
        active: this.discover.eligibleSelectedCount() > 0,
        onAction: (): void => {
          this.discover.enqueue();
        }
      })
    }
    .width('100%')
    .reverse(this.device.gripLeft())
    .padding({
      left: this.device.gripLeft() ? Space.s8 : Space.s16,
      right: this.device.gripLeft() ? Space.s16 : Space.s8,
      top: Space.s8,
      bottom: Space.s8
    })
    .borderRadius(Radius.full)
    .backgroundColor(Palette.glassStrong)
    .backdropBlur(30)
    .shadow(Shadow.float())
  }
}

/**
 * 智感握姿的当前状态提示，只在真的认出一只手时才画（见 `gripChipVisible`）。
 *
 * 「识别中 / 未握持」不再显示：系统第一次订阅时要连点数次才上报，这段时间里
 * 「识别中」等同于没有信息；手机平放时更是常驻的「未握持」。两种都只会变成噪音。
 */
@ComponentV2
export struct GripChip {
  @Require @Param device: DeviceViewModel;

  build() {
    Row({ space: Space.s4 }) {
      Glyph({ glyph: 'grip', glyphSize: 14, glyphTone: Palette.fontSecondary, glyphWeight: 1.8 })
      Text('握姿 · ' + this.device.handName())
        .fontSize(Font.chip)
        .fontWeight(FontWeight.Bold)
        .fontColor(Palette.fontSecondary)
        .maxLines(1)
    }
    .height(28)
    .padding({ left: Space.s10, right: Space.s12 })
    .borderRadius(Radius.full)
    .backgroundColor(Palette.glassStrong)
    .backdropBlur(30)
    .shadow(Shadow.card())
  }
}

/**
 * 检测到窥视时盖住全部内容的那一层（原型 .privacy-veil）。
 *
 * 只盖内容不盖页签栏：在 Index 的 build 里这层排在 TabBar 之前，后画的页签栏落在它上面，
 * 用户始终能切走（对齐原型 z-index 96 < 100）。遮罩本身吃掉所有点击，所以底下的
 * 图片、文件名、按钮都点不到也看不到。
 *
 * 轻点即 `acknowledge()`：识别会误报（海报、路人扫一眼都可能触发），必须给用户一个
 * 一键解除的出口，不能变成单向陷阱。
 */
@ComponentV2
export struct PrivacyVeil {
  @Require @Param device: DeviceViewModel;

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。
  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  build() {
    Column({ space: Space.s6 }) {
      Stack() {
        Glyph({ glyph: 'shield', glyphSize: 28, glyphTone: Palette.fontTertiary, glyphWeight: 1.6 })
      }
      .width(64)
      .height(64)
      .borderRadius(Radius.full)
      .backgroundColor(Palette.cardSunken)

      Text('内容已隐藏')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Palette.fontSecondary)

      Text('防窥保护检测到他人可能正在注视屏幕，图片与压缩包已暂时遮罩。')
        .fontSize(Font.aux)
        .lineHeight(Font.auxLine)
        .fontColor(Palette.fontTertiary)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 240 })

      Text('轻点任意位置继续')
        .fontSize(Font.caption)
        .fontColor(Palette.fontFourth)
        .margin({ top: Space.s2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 内容居中在「标题栏下沿到页签栏上沿」之间，和原型一样不压住这两条。
    .padding({
      left: 40,
      right: 40,
      top: ScreenMetrics.topInset(SCREEN_INSETS.safeTop, false),
      bottom: ScreenMetrics.tabBarSpace(SCREEN_INSETS.safeBottom)
    })
    .backgroundColor(Palette.privacyVeil)
    .backdropBlur(30)
    .onClick((): void => {
      this.device.acknowledgePeeking();
    })
  }
}

/**
 * 「返回顶部」按钮。
 *
 * 这一层横跨整屏、只为一颗按钮存在：让空白处退出命中测试（`HitTestMode.Transparent`），
 * 否则它会盖住下面那一条内容（浮动的下载条、页签栏）点不动。
 */
@ComponentV2
export struct ToTopButton {
  /** 智感握姿的左手镜像：按钮贴左上而不是右上。 */
  @Param mirror: boolean = false;
  /** 离底边的距离，由 Index 按当前页签与浮层情况算好。 */
  @Param bottomSpace: number = 0;
  @Event onTap: () => void = (): void => {
  };

  build() {
    Column() {
      IconButton({
        glyph: 'chevronUp', glyphSize: 21, diameter: 42,
        onAction: (): void => {
          this.onTap();
        }
      })
    }
    .width('100%')
    .alignItems(this.mirror ? HorizontalAlign.Start : HorizontalAlign.End)
    .padding({
      left: Layout.pagePad,
      right: Layout.pagePad,
      bottom: this.bottomSpace
    })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
