# 图片浏览性能、加载与工具栏（2026-10-26）

本轮完整范围：超长图图形内存、大文件加载体验、工具栏布局。保留发现页与图库共用浏览能力、默认显示控件/点图隐藏、选择与预览分离、本地原图优先、阅读位置记忆。

## 验收依据

| 目标 | 需要成立的行为 | 验证 |
| --- | --- | --- |
| 超长图内存 | 缩略图明确限制解码像素；大图只保留底图与可见区域细节；原图不变、透明图和动图不回归 | 同一真机、同一5图页面和1000×50000夹具，冷启动→网格→长图→关闭，比较PSS/Graph/Native；再重复相同场景检查增长 |
| 大文件加载 | 超过旧8MiB限制的有效图片可以预览；分块写入临时文件，显示已收字节/已知总量，明确连接、传输与解码阶段；可取消/重试；切图与后台不接纳旧结果 | 12MiB有效图、慢速已知长度/未知长度、取消/重试、断流、超限、HTTP拒绝、写盘失败及本地优先；检查临时文件清理 |
| 工具栏 | 顶部负责标题/导航/工具，底部将阅读控件与主要操作集中；高对比色、触点至少40vp；横屏和长文件名不遮挡/截断主要操作；危险操作保留确认 | 发现/图库、静图/长图/GIF、横竖屏、全部/已选、工具弹层、缩放后显隐与选择独立性 |

实际改善以真机对照为准，输出PixelMap预算不等同于进程峰值。验收记录见[本轮真机报告](image-preview-performance-acceptance.md)。

## API依据

- [ArkUI Image.sourceSize](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-image.md#sourcesize)：限制解码尺寸，PixelMap不适用；实际绑定以本机API26 SDK为准。
- [HTTP流式传输](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/network/http-request.md)：大文件按数据块接收并报告进度，避免持有整份网络响应。
- [图片解码内存](https://github.com/openharmony/docs/blob/master/en/application-dev/media/image/image-allocator-type.md)：解码输出、原生中间分配与图形内存分别观察，及时释放不再使用的PixelMap。

## 实现边界

- `ThumbnailImages` 对网格执行先裁剪后缩放，输出PNG保留透明度；不改变原图。两个并发任务、相同资源共享请求、所有消费者离开取消；本地修改时间参与缓存键。网格不发送网页身份信息。
- `PreviewTransfer` 每块直接写入文件，已知长度在响应头阶段检查64MiB上限，未知长度逐块检查；关闭请求不依赖原生回调才能完成取消。在线预览5项/128MiB会话磁盘缓存；缩略图另有64项/32MiB磁盘缓存。解码输出预算不等于原生解码峰值。
- `PreviewChrome` 统一预览按钮对比度与40vp触点；发现与图库测量底部实际高度，图片内阅读/动图控件据此避让；图库52vp文件操作保留原来的删除、覆盖确认。
- 候选A仅靠整图sourceSize压缩，真机出现长图模糊和未知尺寸图片压扁，已弃用。候选B中心区域裁剪恢复质量，网络/本地网格Graph均约14MiB；最终以候选D及验收记录为准。
- 构建和92项主机逻辑测试通过。仓库通用守卫仍有两项原有问题：桌面卡片使用V1组件，既有TODO记录含设备地址；不将这两项归为本轮代码通过，也不改写无关模块。

非认证网格缩略图保留普通网络图片的重定向能力（最多5次）；认证预览仍禁止跳转，不把Cookie/Referer带到其他来源。候选C到D仅此项差异。
