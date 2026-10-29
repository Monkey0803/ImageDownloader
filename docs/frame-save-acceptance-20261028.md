# 当前帧保存：2026-10-28 验证记录

## 实现

“保存当前帧”先暂停并锁定来源、文件名和帧号，再显示系统菜单：保存到相册 / 保存到文件夹。
图库与发现预览共用此流程；取消保持暂停且不提示失败。菜单和保存过程均防止重复进入。
输出为 PNG，沿用已有尺寸策略和“原文件名-第N帧.png”命名，不修改原动图或下载记录。
系统保存面板前后台切换保留保存占用；换源和销毁隔离过期回调；临时 PNG 在所有结果路径清理。

## 自动检查

- `node scripts/test-workflows.cjs`：102/102 通过，新增覆盖两目标分流、默认文件夹兼容、帧号与命名、取消标记、异常与资源清理。
- 主包 `assembleHap` 成功；代码及测试审查通过，`git diff --check` 通过。
- 初轮日志：`/tmp/frame-save-tests-final.log`、`/tmp/frame-save-build-final.log`。
- 协调后的共享代码复验：工作流 103/103、首帧加载 11/11；主包构建成功。对应日志为 `/tmp/frame-save-coordinated-tests.log`、`/tmp/frame-save-coordinated-load-tests.log`、`/tmp/frame-save-coordinated-build.log`。

## 已完成设备验证

受控夹具为 600×600、三帧、每帧 400 ms 的 GIF / WebP。GIF 第三帧为蓝色 GIF3，WebP 第三帧为绿色 WEBP3。

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 模拟器发现页菜单 | 两目标和取消正常；点击后暂停，保存按钮不可重复进入 | `sim-menu.jpeg` |
| 菜单取消 | 保持“继续”，没有失败提示 | `sim-cancelled.jpeg` |
| 文件面板前后台 | Home 后恢复仍显示“正在保存…”，完成后提示已保存到文件夹 | `sim-folder-returned.jpeg`、`sim-gif-saved.jpeg` |
| GIF 保存到文件夹 | 系统文件管理器中实际存在 PNG，8.59 KB；打开为蓝色 GIF3 | `sim-gif-png-open.jpeg` |
| 独立模拟器 WebP 文件夹保存 | 系统文件管理实际打开为绿色 WEBP3；详情为 image/png、600×600、11.73 KB。导出源 PNG 为单帧、11,728 B，与 WebP 第三帧逐像素完全一致 | `.screenshots/frame-save-folder-webp-output-20261028.jpeg`、`.screenshots/frame-save-folder-webp-details-20261028.jpeg`、`independent-webp-frame3-export-source.png` |
| 独立模拟器七按钮回归 | 七项按钮纵坐标一致；暂停/继续响应，菜单取消保持暂停且无错误 | `independent-toolbar.jpeg`、`independent-cancelled.jpeg` |
| 真机 GIF 保存相册 | 系统确认后成功；系统图库详情为 PNG、600×600、8.59 KB，第三帧蓝色 GIF3 | `device-album-gif-details.jpeg` |
| 真机 WebP 保存相册 | 系统确认后成功；系统图库详情为 PNG、600×600、11.46 KB，第三帧绿色 WEBP3 | `device-album-webp-details.jpeg` |

临时证据根目录：`/tmp/frame-save-qa-20261028/`；以 `.screenshots/` 开头的证据位于仓库同名目录。真机为 PLR-AL00，模拟器目标为 `127.0.0.1:5555`。
系统目录拒绝 shell 直接读取目标文件，本轮通过系统文件管理器/图库实际打开及详情确认。独立模拟器另拉取了导出源 PNG，其 RGB 与 WebP 第三帧像素完全一致（各通道差值全为 0），但不将它当成目标文件字节比对。

补验使用独立临时实例 `FrameSaveQA_20261028`（`127.0.0.1:10088`），通过 HDC 传入真实 WebP 并添加单条测试种子记录，图库真实解码；该步骤验证帧保存，不作为网络下载验收。安装的固定 HAP 快照为 `/tmp/frame-save-qa-20261028/entry-coordinated.hap`，SHA-256 `5554ef13711f0b1e8df3b94792db6d826aa9e2764d08161ae29073c61fe45b28`。

## 协调、清理与证据边界

- 用户授权后已协调两个 ImageDownloader 聊天释放设备与共享文件；发现其他项目仍使用原实例后改用独立实例完成 WebP 与七按钮回归，原暂停请求已解除。
- 原模拟器已按名称、大小、创建时间和蓝色 GIF3 画面核对后，单独删除 `Download/frame-save-qa-gif-frame3.png`，Download 目录 14→13 项；历史仅删除本轮 8768 GIF 一条（17→16），保留另外 16 条历史及 2 条书签。指定的旧预览缓存已不存在。没有恢复旧整份 JSON；差异报告为 `/tmp/frame-save-qa-20261028/old-sim-latest/cleanup-report.json`。
- 原模拟器 29 条下载、23 条阅读记录与清理前最新基线完全一致；真机测试夹具已从应用移除并回到原 10 项，三个备份 JSON 与清理后内容一致。本轮两张系统相册测试 PNG 已逐张永久删除，最近删除为空，原有资产未改动。
- 本轮 HTTP 服务与 8768 转发已关闭；临时模拟器 `FrameSaveQA_20261028` 已停止并删除，里面的测试种子及导出文件随实例移除，本地验收证据保留。其他任务的资源没有主动清理。
- 功能实现与验收阶段没有暂存、提交或推送代码，其他聊天的暂存状态保持；后续交付按用户确认后的 Git 流程执行。
