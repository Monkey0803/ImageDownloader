# 酷安链接的预览与下载修复

2026-10-28。对象：`https://www.coolapk.com/feed/74641755?s=…`。只记录实际执行证据。

## 现象

- 应用内嵌浏览器能打开帖子，扫描到 23 个 `<img>`：站点图标、头像、表情，加上正文 10 张图片。
- 正文图片的缩略图全部显示“预览不可用”；点开详情也是“图片请求失败”，可回退“下载原文件”。
- 点“下载原文件”后任务卡失败，界面提示“下载失败，请检查链接或登录状态”。
- 真机状态文件里此前已经有一张来自另一个酷安帖子的同样失败记录，说明不是偶发。

## 根因

### 1. 图片 CDN 拒绝非浏览器请求（HTTP 567）

`image.coolapk.com` 对没有浏览器 User-Agent 的请求返回 HTTP **567** 和 7,352 B 的 HTML 反爬页，
而不是图片。应用原来的下载、预览、缩略图和 HEAD 探测只带 Referer / Cookie，没有 User-Agent。
实测同一地址：

```bash
# 无 UA
curl -sS -o /dev/null -w '%{http_code} %{size_download} %{content_type}\n' "$URL"
# 567 7352 text/html; charset=UTF-8

# 浏览器 UA
curl -sS -A 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/114.0 Mobile Safari/537.36' \
  -o /dev/null -w '%{http_code} %{size_download} %{content_type}\n' "$URL"
# 200 33039 image/jpeg
```

Referer 不是必要条件；UA 才是。下载代理、`http.requestInStream`、HEAD 探测都走同一条规则，
所以“预览不可用”和下载失败同时出现。

### 2. 页面只暴露 `.m.jpg` 缩略图

酷安网页的 `<img src>` 是 `…uhdr@2494x3325.jpg.m.jpg`，去掉 `.m.jpg` 才是原图：

| 地址 | 尺寸 | 字节 | HDR |
| --- | --- | --- | --- |
| `…uhdr@2494x3325.jpg.m.jpg` | 1080×1440 | 33,039 | 无 gain map |
| `…uhdr@2494x3325.jpg` | 2494×3325 | 189,207 | 含 ISO 21496-1 gain map（`urn:iso`） |

原来的 `SiteRules` 只有微博图床规则，因此即使 UA 修好，也只会下载 1080×1440 的 SDR 缩略图。
这正好也是本仓库刚接入的 HDR 预览最需要原图的场景。

## 修复

- 新增 `service/WebIdentity.ets`：优先取 `WebviewController.getDefaultUserAgent()`，取不到时回落
  `Mozilla/5.0 (Phone; OpenHarmony 6.1) … ArkWeb/4.1.6.1 Mobile`，进程内缓存。
- 下载 `DownloadStore`、在线预览/缩略图 `PreviewTransfer`、原图仲裁 `SizeArbiter`、
  批量链接探测 `BatchLinkProbe` 统一带上 `User-Agent`。
- `ImageCandidates.SiteRules` 增加酷安后缀规则：`coolapk.com` 且地址以 `.m.jpg` 结尾时，
  去掉后缀生成原图候选，仍由 `SizeArbiter` 的 HEAD `Content-Length` 决定是否采用。
- 新增原生用例覆盖酷安后缀展开与查询串保留，并覆盖“未知域名 / 非 `.m.jpg` 不猜”。

## 验证

- 宿主：`node scripts/test-workflows.cjs` 93/93、`test-library-enhancements.cjs` 87/87、
  `test-batch-links.cjs` 6/6。
- 原生：最终测试包套件 **156/156**（含酷安规则用例）；主包与 ohosTest 构建通过。
  主包 SHA-256 `4e33979bfa2bf192f2587ebe39e7fa45a85a391497b8a9571c9e1ba182f910ec`，
  测试包 SHA-256 `b261d1c58ee81649fba280b9526c0a9c84b577ccdc442049df8ce3b8b27c105a`。
- 真机 PLR-AL00（API 26）临时网络探针（验证后已移除，避免把外网依赖留在套件里）：

```json
{"userAgent":"Mozilla/5.0 (Phone; OpenHarmony 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile","best":"https://image.coolapk.com/feed/2026/1027/03/27167986_5e6db78f_2793_9069_796-uhdr@2494x3325.jpg","code":200,"length":189207}
```

说明：生产 `SizeArbiter` 与 `SiteRules` 在真机上选中了原图，原图 HEAD 返回 200 / 189,207 B；
UA 是真正的 WebView 默认值。探针期间套件为 157/157，移除临时用例后最终套件 156/156。

## 真机界面复验（2026-10-28）

在 PLR-AL00 上重新打开同一链接，实际操作结果：

- 扫描结果仍为 23 项；正文图 04 的地址已升级为
  `…-uhdr@2494x3325.jpg`（不再是 `.m.jpg`），打开后分辨率显示 **2494 × 3325**。
- 缩略图格不再出现“预览不可用”，大图正常加载，没有“图片请求失败”。
- 点“下载当前”后任务卡完成；应用内文件 189,207 B，拉回宿主机 SHA-256
  `978df528db3fd1797a839fe8fa1860e034a9ca9bece84e029dd59c2b17d45ed6`，与服务器原图逐字节一致。
- 图片详情显示：分辨率 2494 × 3325、格式 image/jpeg、**动态范围 HDR（高动态范围）**、185 KB、
  来源链接为原图地址。截图：`.screenshots/coolapk-hdr-details-20261028.jpeg`。
- 另抽查第 5 张 HDR 原图（`27167986_54a1277d…jpg`）：预览正常，详情同样为
  **HDR（高动态范围）**、2494 × 3325；下载 161,171 B，SHA-256
  `c4906ec3d9200a60b9564fb356b50ead395abc23fc0dc99c2e70d27aa4ac1a87` 与服务器一致。
  详情截图：`.screenshots/coolapk-hdr-details2-20261028.jpeg`。
- 点“原始像素”触发放大后的区域解码，未出现“局部细节加载失败”；截图：
  `.screenshots/coolapk-hdr-native-20261028.jpeg`。
- 用本机脚本逐张拉取该帖 9 张原图：全部为 2494×3325 且都含 ISO 21496-1 gain map
  （`urn:iso`），说明该帖确实是 HDR 图集。

## 第二个链接（feed 74263773）真机复验

同一台 PLR-AL00 上打开 `https://www.coolapk.com/feed/74263773?s=…`：

- 该帖正文 9 张图在页面上都只有 `.m.jpg`；修复后全部升级为原图，扫描结果不再显示缩略图尺寸。
- 第 1 张正是此前失败记录里的 `…-livepic@1440x2560.jpg.m.jpg`。现在打开预览，标题变为原图
  `…-livepic@1440x2560.jpg`，分辨率 1440×2560，预览正常。
- 点“下载当前”完成：应用内文件 **402,689 B**，拉回宿主机 SHA-256
  `4cf747a29213fca97bba8436661a7125ee77325c0568da60ef64cdcb1b1990bb`，与服务器原图一致。
- 详情显示 **SDR（标准动态范围）**、393 KB、来源为原图地址；截图
  `.screenshots/coolapk-feed2-sdr-20261028.jpeg`。
- **这个帖子的 9 张原图都没有 HDR gain map（`urn:iso` / `HDRGainMap` 均不存在）**，因此该链接
  无法用于 HDR 显示验收；它验证的是酷安 UA、原图升级和 SDR 分支。HDR 显示仍以 feed 74641755
  的 2494×3325 原图为准（见上一节）。
- 复验后恢复 10 条下载、20 条历史、9 个图片文件；用户原有的失败记录保留，应用已重新启动。

## 数据清理

- 复验前备份了下载状态、浏览历史与图片清单；复验后 `aa force-stop` 主应用，用一次性清理用例
  写回备份并删除本轮图片。核对后下载记录 10 条、历史 20 条、书签 1 条、images 目录 9 个文件，
  打开酷安链接前的新增记录与文件均已消失；应用已重新启动。
- 用户原有的那条酷安失败记录（feed 74263773，`.m.jpg` 缩略图）保持不动；如需保留原图，重试该任务即可。
- 扫描结果仍会包含站点图标、头像、表情等图片，可用“最小宽/高”或来源筛选排除；这不在本次修复范围内。
- `request.agent` 的测试态用例因测试进程只有应用级 `Context` 无法创建任务（“Get context fail”），
  已移除；上面的真实界面下载已经覆盖同一条生产下载路径。
