# ImageDownloader 的 MVVM 边界

应用使用 ArkUI V2：页面和组件用 `@ComponentV2`、`@Local`、`@Param`、`@Event`，可观察业务状态用 `@ObservedV2`、`@Trace`。不为 MVVM 改换状态管理范式。

| 层 | 位置 | 职责 |
| --- | --- | --- |
| View | `pages/`、`view/` | 绘制、触摸与手势、弹窗、导航、组件生命周期；向 ViewModel 传递用户动作 |
| ViewModel | `viewmodel/` | 页面状态、派生展示数据、下载与图库动作、异步结果归属和取消 |
| Model | `model/` | 图片、下载任务、预览页与编辑文档等数据结构 |
| Service | `service/` | 网络、文件、系统相册、媒体编解码、持久化和可复用工作流 |

主页面 `Index` 是装配入口，持有发现、任务、图库、设置和设备 ViewModel，并把系统 UI 能力接到 `UiPort`。独立大图页由 `ViewerViewModel` 管理列表顺序、文件可用性及操作；详情工具面板由 `PreviewToolsViewModel` 管理元数据、收藏、标签、识别和超分；双图对比加载由 `ComparisonPaneViewModel` 管理；动图当前帧导出由 `FrameSaveViewModel` 管理。编辑页的原图校验与副本登记由 `ImageEditorWorkflow` 完成。

View 可以直接使用显示专用的原生句柄和效果服务，例如 PixelMap 解码、动态照片播放、系统栏、屏幕方向及 UI 弹窗。这些对象与组件生命周期绑定，不应被当作可复制的业务模型。View 不直接修改下载队列、图库目录或文件；业务结果通过 ViewModel 的状态、返回值或 UI 端口反馈。

修改 ViewModel 时，先处理异步结果的代际检查和销毁后的回调，再运行：

```bash
node scripts/test-mvvm.cjs
node scripts/test-workflows.cjs
./scripts/build.sh assembleHap --mode module -p module=entry@default -p buildMode=debug
```

构建与离线测试不能证明设备上的弹窗、手势和媒体解码行为；这些交互需另做模拟器或真机验收。
