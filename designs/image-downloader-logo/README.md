# 图片下载管理 · App 图标与文字标

给 `com.example.imagedownloader`（鸿蒙手机应用，`entry` 模块）做的应用图标、文字标与配套资源。
**当前落地的是方案 A**：「相片卡 + 镂空下载箭头」，品牌蓝 `#0A59F7` + 白色单色图形。

打开 `index.html` 看全部内容（三方案对比、遮罩测试、分层拆解、文字标、落地约束），
右下角「显示控制」可切换遮罩 / 安全区 / 深浅色，也支持查询串定住视图：

```
?theme=dark&mask=mask-circle&guides=1
```

## 文件

| 文件 | 说明 |
|------|------|
| `index.html` | 展示页：三个方案、四种遮罩、分层结构、文字标、落地约束 |
| `concepts/concept-a-photo-card.svg` | 方案 A 母版（背景层 + 前景层同文件，用 id 分组） |
| `concepts/concept-b-photo-stack.svg` | 方案 B 母版：相片叠放 + 下载箭头 |
| `concepts/concept-c-arrow-tray.svg` | 方案 C 母版：箭头落入收纳托盘 |
| `wordmark-horizontal.svg` | 横版锁定（浅色底） |
| `wordmark-horizontal-dark.svg` | 横版锁定（深色底） |
| `wordmark-stacked.svg` | 竖版锁定 |
| `wordmark-monochrome.svg` | 单色锁定（改一处 `fill` 即可反白） |
| `app-icon/` | 方案 A 的导出产物：`foreground.png` / `background.png` / `startIcon.png` / `icon-composite.png` / `icon-216.png`，以及每层的矢量源 `.svg` |
| `tools/render-assets.mjs` | 由母版 SVG 导出 PNG 的脚本（无头 Chrome 光栅化） |

## 母版怎么组织

每个概念 SVG 里有且只有两层，用 id 标好，脚本据此拆图：

```svg
<g id="layer-background">  背景层：品牌蓝满幅，不含图形
<g id="layer-foreground">  前景层：白色图形 + 透明底，镂空处透出背景层的蓝
```

图形都居中，外接框 ≈ 画布 46%（1024 上 470px），与 DevEco 模板前景层的 45%（456px）同档。
两层**都不自己切圆角**，遮罩交给系统。

## 导出与落地

```bash
cd designs/image-downloader-logo

# 1. 导出到本目录 app-icon/（只是预览产物，不动工程）
node tools/render-assets.mjs --concept concepts/concept-a-photo-card.svg --out app-icon

# 2. 换方案：把 --concept 指向另一个母版即可，产物同名
node tools/render-assets.mjs --concept concepts/concept-b-photo-stack.svg --out app-icon

# 3. 落地到工程（覆盖下面的资源文件）
cp app-icon/foreground.png app-icon/background.png ../../AppScope/resources/base/media/
cp app-icon/foreground.png app-icon/background.png app-icon/startIcon.png \
   ../../entry/src/main/resources/base/media/
```

工程侧引用不用改：`AppScope/app.json5` 与 `entry/src/main/module.json5` 的 `icon` 都指向
`$media:layered_image`（`layered_image.json` = `background` + `foreground`），
`startWindowIcon` 指向 `$media:startIcon`。

导出后建议再跑一次构建确认：

```bash
./scripts/build.sh assembleHap --mode module -p module=entry@default -p buildMode=debug
```

`icon-216.png` 不进工程，是给 AGC 的应用市场图标位（216×216 直角）。

## 规范依据

- DevEco Studio 模板实测（`/Applications/DevEco-Studio.app/Contents/plugins/harmony/lib/templates/ability/common/media/`）：
  `foreground.png` 1024×1024，图形外接框 456×456 居中（占画布 44.5%）；`startIcon.png` 144×144 圆角方形。
- [分层图标配置指南（DevEco Image Asset）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/ide-apply-generated-icon-V5)：前景层推荐 1024×1024。
- [鸿蒙应用上架审核要求：图标的设置方法](https://www.cnblogs.com/guangzhiruijie/p/19162370)：前景层为 1024×1024 透明底 PNG，**禁止自行添加圆角、内边距或阴影**；背景层只允许纯色/渐变，不可含图形文字；AGC 另需 216×216 直角图标。

## 想调图形大小

图形占比由概念 SVG 里前景层那一个 `transform` 的 `scale` 决定（`translate(512 512) scale(S) translate(-512 -512)`）：

| 方案 | 现在的 S | 图形占画布 |
|------|---------|-----------|
| A | 0.839 | 45.9% |
| B | 0.839 | 45.9% |
| C | 0.839 | 45.9% |

想让图标在桌面上更有存在感（第三方图标普遍在 55%~65%），把 S 调到 `0.95` 即 ≈ 52%。
系统遮罩沿画布中轴留到 512，图形外接框到 620（60%）都还不会被裁到。

## 已知取舍

- 方案 B 的叠形在 32px 以下层次会并成一块；方案 C 的托盘壁 88（24px 上约 2px）偏细。三个方案里 A 的小尺寸表现最好。
- 文字标用的是系统 CJK 字体（HarmonyOS Sans SC / PingFang SC）字重 600，没有画字形 —— 要跨平台字形一致的话需要把中文转成轮廓。
- 没做桌面壁纸/主题换色（华为主题可换图标底）的适配：镂空处透出的是背景层的蓝，若系统对背景层做换色，箭头会跟着变色，这是分层图标的预期行为。
