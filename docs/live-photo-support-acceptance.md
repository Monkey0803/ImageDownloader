# 实况照片 / livepic 支持验收

2026-10-28。范围：`.livp` / `.livephoto` 批量直链导入，以及酷安网页 `livepic` 静图的标识。

## 酷安网页的事实

- 帖子 HTML 里只有 `<img class="message-image" src="…-livepic@1440x2560.jpg.m.jpg">`；
  页面没有 `<video>`、`.mp4`、`.m3u8` 或任何播放数据。
- `image.coolapk.com` 对 `.mp4` 一律返回 **403**（不存在的路径也一样），不能据此推导视频地址。
- `api.coolapk.com/v6/feed/detail` 无应用签名返回 **403**；网页版没有可用公开接口。
- 因此应用只能拿到静图。新增标识：扫描卡片/图库角标写 **“实况静图”**，详情写明
  “实况照片：网页只提供静图，动态部分不可用”，不把普通图片伪装成可播放的实况包。

## `.livp` 批量导入

代码原有的批量解析已把 `.livp` / `.livephoto` 标为“实况照片包”；本次补了固定夹具和真机验证。

- 夹具：`entry/src/ohosTest/resources/rawfile/livephoto/sample.livp`（ZIP：`cover.jpg` 9,910 B +
  `motion.mov` 6,305 B；SHA-256 `4297bd9a…f905`）。
- 原生 `LivePhoto.unpack` 测试：解出 cover/motion，`auxSize=16215`，原包保留、临时 `.zip` 删除。
- 真机批量导入（PLR-AL00，API 26）：
  - 单张模式：同时导入 `sample.livp` + `still.jpg`，两条均完成；`.livp` 落在
    `livephotos/<id>/cover.jpg`、`motion.mov`，SHA 分别为
    `f9e2f5d1…13ac0`、`05602bcd…22507`，与原素材一致；预览页显示封面并启动系统
    `MovingPhotoView` 播放，截图 `.screenshots/livp-batch-play-20261028.jpeg`。
  - ZIP 模式：先切到 ZIP 再批量导入同一对链接；`still.jpg` 打成 `批量链接.zip`，
    包内**只有** `still.jpg`（9,910 B，SHA 一致），`.livp` 不进入 ZIP，单独下载并解包；
    打包完成后 `batches` 为空，ZIP 记录 1 条。
- 角标/详情：酷安帖扫描结果出现 3 个“实况静图”角标；打开 livepic 原图详情同时显示
  HDR 与“实况照片：网页只提供静图，动态部分不可用”。截图
  `.screenshots/coolapk-livepic-still-20261028.jpeg`。

## 构建与测试

- 原生套件最终 **158/158**（新增 MediaFormat.livepic 判定与 LivePhoto.unpack 各 1 项）。
- 主包 SHA-256 `aa37ff4ab2d4b7e36801c0e7a7d2caee37d146a064ad4ef420b3b34aec2fee9e`；
  测试包 SHA-256 `a99efe688abbc2100678d991aa697537ac1958cfd261e4a0ea5820fd197f3ca9`。
- 宿主测试沿用 93/93、87/87、6/6。

## 数据恢复

批量与界面复验后恢复为 10 条下载、4 个 ZIP、20 条历史、9 个图片文件；
`livephotos` 与 `staging` 为空，新增的 `still.jpg`、`sample.livp`、`sample (2).livp` 与
`批量链接.zip` 均已删除。应用已重新启动。
