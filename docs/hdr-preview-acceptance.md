# HDR 预览验收记录

2026-10-27。范围：只做预览（全屏大图与放大细节）的 HDR 解码和显示，以及详情页的动态范围标记。
下载仍按原文件保存；网格缩略图、OCR、相似分析和编辑副本继续使用 SDR。

## 实现

- `view/ImageSurface.ets`：源图 `ImageInfo.isHdr` 为真时，用
  `image.DecodingDynamicRange.HDR` 解码；解码结果 `PixelMap.isHdr` 为真才把
  `Image.dynamicRangeMode` 设为 `HIGH`，否则 `STANDARD`。HDR 解码抛错时自动退回 SDR。
- `view/PreviewRegionImage.ets`：放大后的局部细节沿用同一动态范围解码，失败同样退回 SDR；
  视图的 `hdr` 参数纳入 `@Monitor`，避免底图与细节的动态范围不一致。
- `service/ImageTools.ets` + `view/PreviewTools.ets`：详情面板新增「动态范围」，显示
  `HDR（高动态范围）` / `SDR（标准动态范围）`，未知时显示「未知」。
- `ImageSurface` 的透明判定：HEIF/HEIC 与 HDR 解码结果按不透明照片处理。真机探测显示
  HDR HEIC 的 `alphaType` 是 `UNPREMUL`（3），旧逻辑会误画棋盘格。
- 新增原生夹具 `entry/src/ohosTest/resources/rawfile/hdr/gainmap-hevc-16x16.heic`
  （google/libultrahdr 合成夹具，Apache-2.0 OR MIT，SHA-256
  `6dd810ee6d118d3ce876936d9b265338b94d44cde187bce2ba384ce93edb1b8e`），
  以及 `HdrDecode.test.ets`。

## 构建与自动测试

- `node scripts/test-workflows.cjs`：93/93，含新增「HDR sources are reported in the details metadata」。
- `node scripts/test-library-enhancements.cjs`：87/87。
- `node scripts/test-batch-links.cjs`：6/6。
- 主包 `assembleHap` 与 `ohosTest` 包构建成功。
  最终主包 SHA-256 `4e33979bfa2bf192f2587ebe39e7fa45a85a391497b8a9571c9e1ba182f910ec`，
  最终测试包 SHA-256 `8fdde4a2da76dab667cc4f9716d077d5e6c978db01d0014c931ab8c220410946`
  （两包在酷安 UA/原图升级修复后重新构建，HDR 代码未再改动）。
- 真机 PLR-AL00（HarmonyOS 7.0.0.111，API 26，USB `3ZF0225604005962`）跑完整原生套件：
  **155/155 通过，0 失败、0 错误**（新增 HDR 探针 1 项）。这次运行安装的是主包
  `8aa872f32982b3bc5eed468409e96d582994c55bbd68abde440a993c237cdc12` 与测试包
  `6287ab708e1d1c12a4ac9b70dfded1162618bef72349ff2795648cee027da00f`。此后主包仅补了
  HEIF/HDR 不透明判定；后续又加入酷安 UA 与原图升级，重装最终包后原生套件 **156/156** 通过。

## 真机 HDR 探测

`aa test` 写出的 `files/hdr-decode-probe.json`：

```json
{"heicSupported":true,"sourceHdr":true,"decodedHdr":true,"pixelFormat":10,"alphaType":3,"width":64,"height":64,"problem":""}
```

说明：系统识别该 HEIC 为 HDR 源，按 HDR 请求解码后得到的 `PixelMap` 仍为 HDR，
像素格式 10 为 `RGBA_1010102`，尺寸 64×64。这个结果只证明解码链路，不等于屏幕观感。

## 真机界面复验与边界

- 2026-10-28 在酷安 HDR 原图上完成界面复验：扫描选中 2494×3325 的 HDR JPEG，预览正常，
  下载文件 189,207 B 且 SHA-256 与服务器一致，详情面板显示
  **动态范围 HDR（高动态范围）**。证据见 [酷安链接下载验收](coolapk-cdn-acceptance.md) 与
  `.screenshots/coolapk-hdr-details-20261028.jpeg`。
- 高光亮度观感仍是主观项：截图不能还原 HDR 屏幕亮度；本轮没有做亮度计或对比屏拍摄。
- 早前经本机 HTTP 服务下载的 Apple gainmap JPEG（CC-BY-4.0，仅本机测试，不进入仓库）
  已不在当前下载记录或 images 目录中；复验前后应用数据为 10 条下载、20 条历史、9 个图片文件。
- 模拟器没有 HDR 显示能力，未用它宣称 HDR 观感；不支持 HDR 的设备按上述回落路径解码为 SDR。
- 尚未下载完成的远程预览仍使用现有的会话缩略图/远端图片路径，不在本次 HDR 范围内；
  下载、导出、分享与 ZIP 条目继续按原始文件字节处理，HDR 不被转码。
