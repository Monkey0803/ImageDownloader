# 图片下载管理 — 工程结构

鸿蒙 stage 模型应用，界面按原型 `designs/image-downloader-ui/` 实现。**改动界面时先读下面三个文件**。

## Must-read files

| File | Why |
|------|-----|
| `entry/src/main/ets/pages/Index.ets` | `@Entry @Component`，持有全部状态与五个页面 |
| `entry/src/main/ets/theme/Tokens.ets` | 设计令牌；颜色在 `resources/{base,dark}/element/color.json` |
| `entry/src/main/resources/base/profile/main_pages.json` | 页面路由，新增页面时必须同步更新 |

## 分层

- `view/` — 纯展示组件。`Icons.ets` 的 `ICON_PATHS` 由 `designs/image-downloader-ui/tools/gen-icons.cjs` 生成，
  不要手改路径数据；`SYMBOL_RES`（图标名 → `sys.symbol.*`）是手写的，生成器会原样保留。
  **加图标时先在这里找系统符号**，找不到才回落路径。
- `service/DownloadStore.ets` — 下载队列、打包、持久化；界面只通过它改数据。
- `model/Models.ets` — `@Observed` 模型，卡片用 `@ObjectLink` 绑定。
- `EntryAbility.ets` — 开全屏布局并读取系统栏高度，写入 `AppStorage` 的 `safeTop` / `safeBottom`。

## 两个容易踩的坑

1. `Path.commands` 单位是 **px**，`Shape.viewPort` 是 **vp**；`Glyph` 已按密度换算，改图标时别丢。
2. ArkUI `Scroll` 在内容比视口短时会把内容居中，所以每个页面的滚动内容都加了
   `.constraintSize({ minHeight: this.screenHeight })`。

## Invariants (do NOT change)

- `module.json5`: `module.type` = `"entry"`, `module.mainElement` = `"EntryAbility"`
- `module.json5`: `abilities[0].skills` 保留 `entity.system.home` + `ohos.want.action.home`
- `EntryAbility.ets` 继承 `UIAbility`；`entry/build-profile.json5`: `apiType` = `"stageMode"`
