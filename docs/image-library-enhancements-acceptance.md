# 图库增强验收记录

日期：2026-10-26。只记录实际执行证据；“构建通过”不等于触控或 OCR 已验收。

模拟器完整操作、错误边界及恢复对照见 [最终设备报告](/tmp/image-library-enhancements-20261026/final-device/result.md)。

后续在同一模拟器独立验证了 ARM64 Tesseract 命令行原型，详见 [本地 OCR 原型报告](/tmp/image-library-enhancements-20261026/local-ocr-runtime/result.md)：它能运行并读出部分中英文，但把“发票编号”误识别为“上肥票编号”。原型未接入应用，不能作为下方 OCR 内容搜索通过的证据；测试临时文件已清理。

进一步只读诊断见 [系统 OCR 服务报告](/tmp/image-library-enhancements-20261026/system-ocr-diagnostic/result.md)：模拟器中的 `com.huawei.hmsapp.hiai` 已启用，但 BundleManager 列出的模块没有 `textService`，识别日志请求 `TextServiceAbility` 时返回无匹配。因此当前模拟器缺少已注册的系统 OCR 服务；不能仅凭能力参数为 true 认定可用。另用更大的 Tesseract 中文模型在宿主机复核同一测试图，仍误识别“发票编号”，不把该原型直接替换为产品实现。

官方 Tesseract 标准中文模型（原始约 42 MiB，压缩约 20 MiB）在模拟器 CLI 原型上正确读出短图中英文，单次最大 RSS 约 168 MiB，详见 [标准模型报告](/tmp/image-library-enhancements-20261026/local-ocr-standard/result.md)。但同模型在宿主机以产品一致的 2048 像素切片识别长图时，把预期“末尾”识别为“未尾”；更大模型则在短图中误识别“发票编号”。这两个原型尚不满足既定的短图与长图搜索验收，也未集成到应用。

进一步验证了 RapidOCRLite C++ 引擎与 PP-OCRv6 tiny 两个 ONNX 模型、字典的组合：它们已由当前鸿蒙工具链构建为 ARM64 库，在模拟器独立命令行上依次返回短图 4/4、空白图 0、长图 6/6 个预期结果，单次进程最大 RSS 约 27–49 MiB，详见 [PP-OCRv6 tiny 原型报告](/tmp/image-library-enhancements-20261026/ppocrv6-tiny-runtime/report.md)。该结果只证明本地引擎与模型在模拟器可运行，不能替代后来完成的系统 OCR 产品验收；模型没有复制到应用，ArkTS 原生桥接、取消与搜索交互、最终许可材料和产品包体积也均未继续验证。RapidOCRLite 仓库另附的 Indra/lite 权重有用途及分发限制，**不作为产品模型**；其独立研究结果见 [受限模型原型报告](/tmp/image-library-enhancements-20261026/rapidocr-lite-runtime/report.md)。

用户在 2026-10-26 明确选择**保留系统 OCR，接受当前模拟器不能识别**。上述离线引擎只作为研究证据，没有接入应用。系统 OCR 成功路径随后在真机完成验收，详见 [真机 OCR 与文字搜索报告](/tmp/image-library-enhancements-20261026/phone-system-ocr/result.md)。

## 固定输入与构建

- 15 张合成测试图片由 `node scripts/make-library-fixtures.cjs` 生成，manifest 包含尺寸、SHA-256、预期文字/像素及 EXIF 值，见 `entry/src/ohosTest/resources/rawfile/library-enhancements/manifest.json`。
- 宿主图库测试：83/83，含“登记途中原图删除”、并发删除、裁剪扩展、同路径图片替换、OCR 取消和相似检查完成提示回归，`/tmp/image-library-enhancements-20261026/host-tests.log`。
- 既有流程回归：92/92，`/tmp/image-library-enhancements-20261026/regression-tests.log`。
- 模拟器原生套件：最终主/测试包重装后再次 143/143，0 Failure、0 Error；首次运行的测试模块资源路径问题已修复。初次修正日志 `/tmp/image-library-enhancements-20261026/final-device/native-fixed.log`；最终包日志 `/tmp/image-library-enhancements-20261026/final-device/native-final.log`。测试前后下载状态与新基线相同。
- 主包构建通过：`/tmp/image-library-enhancements-20261026/final-main-build.log`；测试包构建通过：`/tmp/image-library-enhancements-20261026/final-test-build.log`。
- 当前固定主包 `/tmp/image-library-enhancements-20261026/library-main.hap` SHA-256 `a40b88372ca1ef3e0a37380b3eaf1bad3bc0bea6d8053991cfe31e7328176540`；测试包 `/tmp/image-library-enhancements-20261026/library-test.hap` SHA-256 `538b00afedd70adbfb3219658163c90375dd3105ad7ff7f51dfcbf4acb882385`。最终包已安装并复跑原生 143/143；OCR 取消和相似完成提示均已实测修正。
- 真机覆盖安装本次源码构建的签名主包，SHA-256 `0c2bcb9ca654fda0b1093a1e953e148d6d557d9d6a28ae804112f36e74ca618e`；保留用户数据。当前宿主图库测试再次通过 83/83，`git diff --check` 通过。

## 功能验收矩阵

| 功能 | 宿主/构建证据 | 模拟器交互 | 当前结论 |
| --- | --- | --- | --- |
| 本地按需 OCR 与文字搜索 | 索引、取消、长图切片和搜索组合测试通过 | 模拟器缺系统服务，真实 OCR 超时；取消和重试边界已验证 | 真机系统 OCR 3/3：双语图 4 个短语正确，长图顶中尾 6 个短语均包含，空白图状态为无文字；7 个中文/英文/长图查询分别命中对应图片，无匹配查询为空；重启后索引和末尾短语搜索仍有效。长图中段多一条近似重复识别，不能称全文准确无误 |
| 相似图片候选分组 | 特征、缓存、分组阈值和取消测试通过 | 3 张固定图实测 3/3、失败 0；原 PNG 与重编码 JPG 组成 1 组 2 图，不同图未入组；组内浏览与双图对比可用。最终版返回后仍显示“找到 1 组”；QA 数据已精确清理 | 已通过 |
| 收藏与标签 | 持久化、组合筛选和迁移测试通过 | 本轮实测单张收藏与中英文标签、三张批量收藏和标签；文件名+仅收藏+标签组合筛选为预期 1/3；长文件名改名后详情仍显示收藏/标签，原 URL 保留；重启后 4 条收藏及标签数据仍在；QA 数据已精确清理 | 已通过 |
| 裁剪/旋转/标注另存 PNG | 原始像素、Alpha、BGRA、日志恢复和登记测试通过 | 四角裁剪、1:1、区域移动、旋转/撤销、蓝笔黑框、清空撤销、退出保留草稿和保存双击均实测；只登记 1 份 1200×800 独立 PNG，蓝线、黑框与半透明红的像素核对通过。GIF/WebP 显示“编辑首帧副本”；GIF 裁剪旋转后输出 400×400 单帧 PNG、首帧红像素正确；WebP 放弃后无副本。2232×1320 横屏长文件名、详情与工具无重叠，横屏裁剪、旋转、蓝笔另存成功。Live Photo 预览能播放测试视频，详情“编辑封面副本”进入静态封面编辑；1:1 裁剪及 90° 旋转后导出 480×480 独立 PNG，四角像素正确，原包/封面/视频哈希不变，重启后副本仍可打开。QA 数据已精确清理。见 `/tmp/image-library-enhancements-20261026/final-device/edited-pixels.json` 和 [Live Photo 最终补验](/tmp/image-library-enhancements-20261026/livephoto-final/result.md) | 已通过所测路径 |
| 原件及记录安全 | 短写/改名失败回滚、独立删除、清空保留副本、后台取消测试通过 | 保存后 `origin=edited`、`originalId` 正确，双击仅 1 份副本，原件 SHA 不变；重启后副本仍在。最终清理后四份生产 JSON 与原始用户基线语义一致，文件无额外/缺失项 | 已通过 |

## 设备边界

模拟器 `127.0.0.1:5555` 曾在 Task 11 操作间被另一应用占用，后恢复独占。原生套件最终版实跑 143/143；测试进程已停止。设备列表仅见该模拟器，未见真机；用户选择本次按模拟器结果交付，因此真实 OCR 成功路径明确保留为未通过。首次验收结束时已精确移除 8 条 QA 原件、3 条编辑副本、相关索引和阅读记录；四份生产 JSON 与 Task11 原始用户基线语义一致，文件清单无额外/缺失项。最终主包当时保留并正常启动，21 下载、3 ZIP、13 历史、1 收藏及原设置、竖屏和旋转锁均保留。普通应用缓存未清除；系统剪贴板无法可靠恢复，不声称已恢复。

之后为 Live Photo 补验生成了有效 JPEG 封面、2 秒 H.264 视频与 `.livp` 包，应用自动解包后的两文件 SHA 均与原素材相同；但另一项正在活动的任务占用共享前台，编辑 UI 尚未操作，见 [Live Photo 补验记录](/tmp/image-library-enhancements-20261026/livephoto-device/result.md)。本轮 QA 记录和 3 个文件已精确清理。并发任务更新了一条既有浏览历史的访问时间，已保留该用户变化；因此**当前**不再声称浏览记录 JSON 与首次基线全等。ImageDownloader 当前已停止，未抢占另一任务前台。

共享设备空闲后，使用当时已安装的新版应用完成 [Live Photo 最终补验](/tmp/image-library-enhancements-20261026/livephoto-final/result.md)，没有回装旧包。按并发历史更新后的新基线验收并清理 2 条 QA 记录与 4 个文件；四份生产 JSON、catalog 状态和文件清单均与新基线全等。当前应用已正常启动。工作区最新签名包哈希仅作为候选记录，未声称它已与设备安装包哈希核对。

上述为此前模拟器验收的阶段状态。用户之后连接了真机 `3ZF0225604005962`（PLR-AL00，HarmonyOS 7.0.0.111），其系统 `textService/TextServiceAbility` 已注册并启用。当前源码主包在真机保留数据安装后，3 张真实 PNG 完成系统 OCR；短图中英文和长图顶中尾查询、无匹配状态与重启后的持久化搜索均经 UI 验证。真机原先 0 图片、4 ZIP、16 历史、1 书签；本轮 3 张 QA 图片和索引已精确清理，原 8 个文件清单及 SHA-256 逐项全等，新版应用正常启动。没有修改模拟器的服务，也没有接入离线 OCR。真机输入过程中使用过剪贴板，原剪贴板无法可靠恢复。
