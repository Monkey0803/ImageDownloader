# 图片预览增强：2026-10-28 真机复验

设备：PLR-AL00（HarmonyOS 7.0.0.111，API 26）。主包 SHA-256
`7dbfe27f3d46033f9d947402eb519557f295812079759173635d1e15e29341e6`，
测试包 `d891d69f0568505e4647bc7ee0feab16add5448931006d4038c3e3ab44b5bc89`；
原生套件 158/158。

夹具通过本机 HTTP 服务 + 批量直链导入 6 张：1200×800 静态图、1000×50000 长图、
600×600 半透明 PNG、三帧 GIF、三帧 WebP、900×480 中英文字图。全部下载完成后在真机操作。

## 已复验

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 双击缩放 / 单指拖动 | 双击后画面放大；长图原始像素下上滑，画面区域明显位移（像素差 bbox 非空、差值 19,014,792） | `preview-qa-double-20261028.jpeg`、`preview-qa-fit-20261028.jpeg`、`preview-qa-long-pan-before-20261028.png` / `preview-qa-long-pan-after-20261028.png` |
| 长图顶部 / 中部 / 底部 | 初始 0%，进度条中点 50%，底部 100%；画面分别显示对应 band，无空白或错位 | `preview-qa-long-mid-20261028.jpeg`、`preview-qa-long-bottom-20261028.jpeg` |
| 原生像素 / 区域解码 | 长图 50% 点“原始像素”后显示 BAND 24/25 清晰文字，无“局部细节加载失败” | `preview-qa-long-native-20261028.jpeg` |
| 透明图背景 | 棋盘格与黑色背景切换正常；50% 红圆透出棋盘格，说明 alpha 合成正确 | `preview-qa-alpha-checker-20261028.jpeg`、`preview-qa-alpha-black-20261028.jpeg` |
| GIF 时序 | 播放中两帧像素差 883,135,990；暂停后两帧差 0；继续后再次出现差值 | 截图对 gifA/B/C/D/E |
| WebP 时序 | 播放中差值 881,282,068；暂停后 0；继续后恢复差值 | 截图对 wpA/B/C/D/E |
| 真实 OCR | `preview-text.png` 识别出“订单号 EAST-2048 / 发票编号 INVOICE-7A”，可选择并复制 | UI 层级记录 |
| 系统导出入口 | 点“导出”打开系统“选择路径”页面（我的手机 / Download 等），随后取消 | UI 层级记录 |
| 离散内存采样 | 图库 PSS 207,369 KiB（Graph 39,988 / native 86,508）；长图预览 239,405 KiB；长图原始像素 239,209 KiB，未见放大后继续增长 | `hidumper --mem` |

## 未在本轮重跑

- **真实双指 PointerMatrix**：本轮未重新启动手势驱动；沿用 2026-10-26 的驱动证据
  （`image-preview-reading-acceptance.md`），且手势代码本轮未改。双击/拖动已在本轮覆盖。
- **导出副本的独立字节校验**：只确认系统选择器打开并取消，没有写入系统 Download；
  历史真机记录中的独立副本校验仍是当前有效证据。
- 快速连续切图、前后台组合、选中范围复查、二维码识别、双图对比未在本轮重跑；
  历史记录分别在 `image-preview-device-acceptance.md` 与 `image-preview-reading-acceptance.md`。

## 数据恢复

复验前备份状态/历史/图片清单；结束后恢复为 10 条下载、4 个 ZIP、20 条历史、9 个图片文件、
`preview-reading.json` 10 条；6 张夹具图片全部删除，fixture HTTP 服务已停止，应用已重新启动。
