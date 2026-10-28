# 通透玻璃材质接入与验收（2026-10-28）

## 实现

- 项目保持 API 26 / Stage；复用已有应用级 `ohos.arkui.UIMaterial.state=enable`。
- `TransparentGlass.ets` 统一创建并缓存 `ImmersiveMaterial`：`REGULAR`、固定 `#33FFFFFF`、
  `colorInvert: true`、`applyShadow: true`。不通过深浅色资源改变材质赋色。
- 设备能力统一走 `MaterialSupport.immersiveSupported()`；不支持时返回 `undefined`，配普通不透明背景。
  材质生效时背景色返回 `undefined`，直接位于玻璃上的文字和图标使用特殊系统前景资源。
- 发现页使用标准 `Navigation` 标题栏；底部导航使用原生横向 `Tabs` 的底部 TabBar builder，
  其中四个自定义导航按钮沿用 Index 的事件和页面状态。普通图片网格不再挂无效 `systemMaterial`。
- 系统半模态面板和确认弹窗复用固定赋色。浏览首页底栏、收藏历史面板使用不透明背景，
  避免材质持续叠在网页的视频/动画上。动图、实况照片、未落盘静态图片和文件丢失后的远程回退详情同样降级。
- 标题栏、底栏与图库分段响应「沉浸光感」和「无材质效果」；系统弹层按设备能力降级。
- 材质等级改为设备只读能力；旧 `materialLevel` 存储字段保留兼容，不再作为可修改的设备算力选项。

## 验证

设备：HUAWEI PLR-AL00，API 26，1316 × 2832。最终包重新安装并冷启动，进程 PID 50049。

| 项目 | 结果 |
| --- | --- |
| `./scripts/build.sh assembleHap` | 通过，存在 ArkTS 警告，不是零警告构建 |
| `./scripts/check-guards.sh` | 通过 |
| `git diff --check` | 通过 |
| 独立源码审查 | 已修复发现的动态媒体材质和前景问题，无剩余必要修改 |
| 四项底栏切页 | 发现、任务、图库、设置均可切换，原有图库数据正常 |
| 浅色玻璃底栏 | 整条圆角材质生效，图像模糊，导航文字清晰 |
| 关闭沉浸光感 | 图库底栏回退不透明背景 |
| 浏览首页 | 标题完整，底栏为不透明背景 |
| 深色玻璃底栏 | 设置和图库文字清晰 |
| 深色静态 JPG 详情 | 标题、分辨率、大小、来源及操作可读 |

本地证据在忽略目录 `.screenshots/`：

- `glass-20261028-build.log`、`glass-20261028-guards.log`
- `glass-20261028-final-gallery-light.jpeg`：修正后的浅色底栏
- `glass-20261028-final-gallery-material-off.jpeg`：关闭材质后的不透明底栏
- `glass-20261028-final2-settings-dark-restored.jpeg`、`glass-20261028-final2-gallery-dark.jpeg`
- `glass-20261028-final2-detail-dark.jpeg`：深色静态图片详情
- `glass-20261028-final2-app-pid50049.log`：最终包日志

## 验证边界

- 最终进程日志仍有 1 条冷启动 `Material inactive: out of scope`，位于日志第 1606 行，来源尚未定位。
  真机已观察到底栏和静态图片详情材质实际生效，未观察到对应的交互异常；不能据此宣称零错误日志。
  日志另有 AceSheet/RS 框架错误；本次检查未发现 `jscrash` / `FATAL`。
- 仅在上述真机验收。未覆盖低算力、不支持材质设备及用户系统光感强弱的全部组合。
- 未专造纯白图片、动图或实况照片 fixture；动态媒体降级和远程回退分支完成源码审查，未逐项实机注入验证。
- 保留实施前的预览相关未提交修改；本次未暂存、提交或推送。
