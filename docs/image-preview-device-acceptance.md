# 图片浏览真机验收（2026-10-23）

实际连接 PLR-AL00 手机、API 26，竖屏物理分辨率 1316×2832，横屏 2832×1316；排除了同时在线的模拟器。通过 HDC / UiTest 操作真实手机，每次交互前后留存 UI 层级与截图；双指使用测试模块的 PointerMatrix 注入两个触点，不以单指拖动代替捏合。

**验收已收尾：六处真机发现的问题均已修复并实际复验。连接恢复后按用户要求通过 WiFi 完成最新包、鉴权、100图导航、缓存淘汰和长图末端验收，原数据与设置已精确恢复。11组均有真实交互证据，但部分边界未覆盖，不能理解为全部清单完全通过。**

证据原件位于 `/tmp/image-preview-device-20261023/`，同名前缀对应 `.json` UI 布局和 `.jpeg` 截图。受控服务请求记录为 `/tmp/image-preview-fault-server/requests.jsonl`。证据路径属于本机临时目录，不随仓库提交分发。

## 版本与数据保护

- 真机最后实际安装主包 SHA-256：`05678c3c9e983499e94b09aa582bc867a8cdc4be16e0d897d1e5d7131e5dd124`。包含工具触摸、多码、预览方向、底栏遮罩、预览批量入口与9MiB错误分类六项修复，全部有真机复验。
- 覆盖安装，没有清除应用数据。先备份 `baseline-state.json`、`baseline-browser.json`：原图片 0、压缩包 4、收藏 1、历史 16，并记录完整设置。
- `after-zip-state.json` 中原 4 个压缩包对象逐项相同；本轮新增 3 张 QA 图片和 1 个 QA 压缩包，文件名均以 `preview-qa-` 开头。
- 原系统旋转锁开启。横屏测试以显式原状态 `autoRotate=false` 启动，最终 `qa-finish-stop` 成功还原竖屏，`final-rotation-lock` 控制中心确认旋转锁仍开启；没有更改用户网络开关。
- 受控服务通过设备回环地址及临时反向转发访问；仓库未新增设备私网地址。没有使用或发送用户真实账号、Cookie 或图片到外部服务。

## 真机发现与修复复验

| 问题 | 实际表现与处理 | 当前复验结果 |
| --- | --- | --- |
| 工具/对比按钮不响应 | `HitTestMode.Block` 阻止子节点触摸。改为 Default 并消费面板空白点击；同时修复工具内容顶部大空白 | OCR、二维码、背景切换、对比等按钮实际可用；`fixed-ocr-result`、`alpha-background-*`、`final-compare-*` |
| 多码只显示一条 | ScanKit 多码选项默认关闭，改为明确开启 | 两码结果同时显示，普通文本仅复制，HTTP 另提供主动打开；`final-qr-multi-*` |
| 预览不随方向变化 | 仅预览期间启用遵从旋转锁的方向策略，退出恢复原偏好 | 对比真实横屏左右布局，退出预览恢复竖屏；`final-compare-landscape`、`final-rotation-back-*` |
| 浅色图片底栏图标不清楚 | 图库/发现预览底部增加暗色遮罩 | 最新包图库浅色图真实双指放大3倍，顶/底暗色遮罩上的图标与文字清楚；`final-gallery-3x-controls` |
| 缺少预览内已选批量按钮 | 复用已有批量方法，增加「下载已选 N / 打包已选 N」 | 「打包已选 2」真实生成 ZIP，保持页码和勾选；`final-zip-*`、`zip-submit-*` |
| 9MiB 被描述为网络错误 | 真实 native HTTP 体积限制走通用错误，原文案不准确 | 最新包显示「图片超过 8 MiB 预览限制，请下载原文件后查看」；恢复服务后点重试同页正常；`final-size-open-3-wait`、`final-size-recover-gallery-*` |

独立手势测试驱动最初因 UiTest 在框架注册前导入而初始化失败，改为动态导入后才真正注入双指。该问题是测试工具问题，不作为生产交互失败。最终成功记录和画面变化同时作为手势证据。

## 11 组验收结果

“部分验证”表示已完成表中交互，但没有覆盖该组清单的全部边界，不能用构建/单元测试补作真机通过。

| 组 | 状态 | 实际操作与观察 | 证据前缀与剩余项 |
| --- | --- | --- | --- |
| 1. 发现/图库共享手势 | 部分验证 | 发现双击局部放大；图库真实双指半径 100→300、中心移动(80,80)，画面明显放大；四向拖动、适合屏幕/原始像素切换；对比真实双指、横竖屏及退出恢复 | `zoom-double`、`gallery-pinch-confirmed`、`gallery-pan-*`、`final-compare-pinch`。尚未完整验证快速切图与前后台组合 |
| 2. 1000×50000 长图 | 部分验证 | 适合宽度从 band01 连续40次真实拖动至 band50/Y49999，末端网格与文字清晰；查看全图恢复整图，关闭后预览文件清空；40个进程PSS离散样本为510.2–609.7MiB | `long-final-width-*`、`long-read-01-15-*`至`long-read-31-40-9-cmd`、`long-final-reset-*`、`memory-long-samples.json`。采样不是瞬时峰值，未真实注入裁剪失败 |
| 3. 透明图背景 | 部分验证 | 半透明 PNG 切白、黑、棋盘背景，放大拖动后没有明显重复加深或接缝；透明 WebP 在对比显示棋盘背景 | `alpha-background-*`、`alpha-contact.png`、`compare-alpha`。WebP 尚未逐一覆盖所有背景与相位边界 |
| 4. 下载/批量与原图升级 | 部分验证 | 静图局部放大后下载，预览升级为本地原图；前后同一区域 RGB 差为 0，位置与缩放保持。预览内 ZIP 两张完成，原页码和两张勾选保留；ZIP 两成员 CRC 检查通过，临时原图清理后仍可浏览 | `zoom-download`、`final-zip-*`、`zip-submit-*`、`after-zip-state.json`。在途去重与下载失败重试未独立真机注入 |
| 5. 已选范围与缩略导航 | 部分验证 | 页码输入 4 跳到长图 4/12；已选三张时取消中间进下一张、取消末尾退前一张、取消最后变 0/0 空态；点「浏览全部图片」回到 1/12 原范围。100张扫描完成后滚动缩略条、跳至100/100与1/100，缩略条分别显示末端和首端 | `strip-jump`、`selected-remove-*`、`empty-return-all`、`many-open-*`、`many-nav-*`。筛选范围组合尚未完成 |
| 6. 动图与当前帧 | 部分验证 | 网络 GIF 连续截图帧变化，暂停 3 秒图片区域逐像素不变，继续恢复变化；WebP 播放/暂停正常；控制点击不隐藏工具栏。GIF、WebP 下载后切到本地。真实导出第1帧 PNG，900×700 RGBA、alpha0..255，与源GIF第1帧逐像素相同；再次取消导出后无 image-tool 临时文件 | `gif-play-*`、`gif-export-*`、`gif-cancel-webp-*`、`gif-save-picker`、`exported-frame1.png`。后台停播/恢复与本地动图完整组合尚未覆盖 |
| 7. 详情与返回 | 部分验证 | PNG1600×1200、81KB与原素材一致；下载前显示未下载，下载后显示实际时间；系统返回先关闭工具或对比，保持主浏览页 | `fixed-detail`、`tools-back`、`compare-back`、`final-rotation-back-*`。完整文件名/链接复制的独立粘贴核对尚未完成 |
| 8. OCR | 部分验证 | CoreVision 实际识别中文、英文及数字五行，复制全部后独立系统剪贴板提示包含五行；纯色图显示无文字并可重试 | `fixed-ocr-result`、`ocr-copy`、`animation-load-2-cmd`、`no-result-*`。长图小字、能力不可用、迟到结果竞态未真实注入 |
| 9. 二维码 | 通过已测分类 | 实测单HTTP码、多码、普通文本、weixin协议、无码。识别不会自动打开；仅HTTP结果提供打开按钮，主动点击进入系统浏览器；普通文本与非网页协议仅可复制 | `qr7-result`、`qr7-browser`、`qr8-test-*`、`qr9-test-*`、`final-qr-multi-*`、`no-result-*`。没有伪造系统能力不可用；取消竞态仍无专项覆盖 |
| 10. 双图对比 | 部分验证 | 选择透明参考图，竖屏上下、横屏左右；主图双击后参考图区域仅 JPEG 压缩级微小差异，主图真实双指放大；返回关闭对比恢复原 1/12 范围 | `compare-alpha`、`compare-double`、`final-compare-pinch`、`final-compare-landscape`。登录参考图、加载失败重试与内存释放量化尚未覆盖 |
| 11. 缓存/故障 | 部分验证 | 真实访问直接故障原图：401、403、302、15秒超时、9MiB、损坏、传输截断。七项均保留重试/下载原文件/来源页入口；分别恢复服务后点重试可显示图片。预览自己的302请求未跟随目标 | 详见下表。A→B→A命中、5张/32MiB淘汰、关闭重开与alpha/beta/注销均已完成，详见后文；未注入磁盘满与同一来源页面内仅Cookie改变的独立组合 |

原需求补充：发现网格已没有左上角重复选中标识；预览选择使用圆形 HMSymbol，点击后选择数量更新。证据 `grid`、`preview01`、`selected01`。

## 受控故障明细

初始 `/faults` 页面允许正常缩略图回退，不能证明错误分支。因此改用 `/direct-faults`，图片 src 直接指向故障端点，没有可替代的正常候选。服务日志区分 WebView、网格以及带来源 Referer 的 native 预览请求。

| 故障 | 实际提示 | 错误与恢复证据 |
| --- | --- | --- |
| 401 | 来源网站拒绝预览，建议确认登录 | `direct-401-*` → `recover401-next403-*` |
| 403 | 来源网站拒绝预览，建议确认登录 | `recover401-next403-*` → `recover403-next302-*` |
| 302 | 网络连接失败；预览请求未跟随目标 | `recover403-next302-*` → `recover302-nexttimeout-*` |
| 超时 | 预览请求超时 | `recover302-nexttimeout-*` → `recovertimeout-nextoversize-*` |
| 9MiB | 最新包准确提示超过8MiB预览限制，恢复后重试成功 | `final-size-open-3-wait` → `final-size-recover-gallery-0-text/1-wait` |
| 损坏文件 | 图片格式不支持或文件已损坏 | `recoveroversize-nextcorrupt-*` → `recovercorrupt-nextdisconnect-*` |
| 传输截断 | 网络连接失败 | `recovercorrupt-nextdisconnect-*` → `recoverdisconnect-cacheload-0-text/1-wait` |

本轮没有为302请求配置登录Cookie，因此“未跟随目标”已实测，携凭据302的完整组合仍未实测。没有把 WebView 初次加载正常跟随目标算作预览凭据泄漏。

## 鉴权、缓存与长图补充证据

- 同一 `/auth.png` URL：alpha登录显示文字图，beta登录显示透明图，退出测试登录后显示来源拒绝（服务器实际403）。对应 `auth-alpha-valid-5-wait`、`auth-beta-9-wait`、`auth-logout-9-wait`。服务日志确认 native 请求带对应测试Cookie和 `/login` Referer；注销后Cookie消失。这验证跨登录/来源页面重建会话后的正确性，不能单独证明同一会话仅Cookie变化的缓存键行为。
- 100张页的A→B→A：首次001仅一次native请求，返回时命中；超过5个不同来源后返回001产生第二次请求；关闭并重新打开后第三次请求。`many-nav-*`、`many-eviction-*`、`many-reopen-valid-*`与服务器日志交叉佐证。关闭后 `cache-many-closed.json` 为0文件/0字节。
- 7MiB原图逐张串行预览：前四张缓存总字节分别为7,414,962、14,829,924、22,244,886、29,659,848；第五、第六张均维持4个来源、29,659,848字节并淘汰早先文件，未越32MiB预算。每个来源包括7,340,032字节原文件及74,930字节派生预览。`cache-large-1.json`至`cache-large-6.json`；关闭后 `cache-large-closed.json` 为0。此阶段WiFi连接保持正常。
- 1000×50000长图已实际拖到最后一段，末端清晰可见，复位与返回仍响应，未观察到崩溃或黑屏。`long-read-31-40-9-cmd.jpeg` 展示 band49/50及Y49000–49999，`cache-long-closed.json` 为0。约237秒内40个PSS样本522,424–624,319kB（510.2–609.7MiB），包括整个应用和验收驱动状态；不是解码器独占内存、瞬时峰值或跨版本改善证据，也没有据此宣称帧率达标。

## 连接中断与WiFi续验

15:29 打开旧 `/cache` 夹具时，WebView并发请求6个7MiB响应，经HDC反向转发后控制命令与文件接收停滞。主机HDC日志显示 `HdcForwardBase::ReadForwardBuf` 与 `ReadCtrlFromMain` 子循环挂起约14分钟、发送缓冲 Resource temporarily unavailable，而WiFi TCP端口仍可达；不能归为应用崩溃或手机完全断网。证据 `hdc-host-stall.txt`。

在父任务此前条件授权与随后等待确认消息存在时序交叉的情况下，15:45主机共享HDC重启已发生，父任务已向用户说明并道歉。用户随后明确要求等待模拟器任务完成后再重启，此后没有再次重启共享服务，没有重启模拟器或手机。15:46后定向连接原物理WiFi目标并重新确认PLR-AL00，按用户最新要求完成剩余验收，未改用模拟器或USB代替。新版夹具只向带来源Referer的native预览请求提供7MiB，逐张操作避免WebView并发大响应。

## 最终数据恢复与清理

- 应用停止后从当前状态仅移除本轮3张QA图片、1个QA压缩包和8条QA历史，恢复文件再次从设备读回。`final-state.json` 与 `baseline-state.json` 完全相等，`final-browser.json` 与 `baseline-browser.json` 完全相等：原图片0、压缩包4、收藏1、历史16以及全部设置均保留。原4个压缩包实体仍存在。
- 已删除本轮 `preview-qa-01-text.png`、`preview-qa-05-animation.gif`、`preview-qa-06-animation.webp`、`preview-qa-20261023.zip` 实体，images目录为0；系统导出的 `preview-qa-05-animation-第1帧.png` 已删除，原 `folder-qa.jpg` 保留。最初虚拟沙箱路径删除被拒，改用已经确认的真实应用路径定向删除成功；没有清空整个应用或缓存。
- 手势runner已stop，测试命令/结果/旋转备份文件均不存在；只卸载 `entry_test`。`final-bundle.txt` 确认生产entry仍在、entry_test已无，生产应用重新启动正常；`final-clean-start` 显示收藏1、历史16。最终控制中心 `final-rotation-lock` 确认原旋转锁仍开启。
- 仅注销本轮preview_qa测试Cookie；没有清除其他登录Cookie。18743/18744两条反向转发已移除，列表为空；本轮18743素材服务已停止；父任务已关闭18744并确认无监听。共享HDC与其他任务服务保持不动。
- 测试复制改变了系统剪贴板，原剪贴板未备份，**未恢复原剪贴板内容**。主动打开HTTP二维码留下的系统浏览器example.com验收访问，没有通过清空全局历史处理。
- 设备临时目录中与本轮主机证据精确匹配的122个截图/层级文件已删除，复查剩余0；主机证据保留，清单为 `device-evidence-cleanup.json`。没有清空设备临时目录。
- 无法安全或完整覆盖的边界仍以上表为准，包括系统能力不可用、磁盘满、裁剪故障、取消/迟到竞态及部分前后台组合；不以构建、离线测试或工具返回success替代真实交互结果。
