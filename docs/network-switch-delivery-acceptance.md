# 长任务切网、WAITING 与系统副本验收（2026-10-28）

设备：PLR-AL00（API 26）。USB 保持控制，关闭 Wi-Fi 前确认 `3ZF0225604005962` USB 在线。
主包 SHA-256 `7dbfe27f3d46033f9d947402eb519557f295812079759173635d1e15e29341e6`，
测试包 `8efd70a183e49e0ccd257a1f2f569bdfb0d0f37dea61f16314f9c684a08be03e`；
原生套件 158/158。

## 长任务：仅 Wi-Fi、WAITING、重启与恢复

- 夹具：本机限速 HTTP 服务提供 `large.png`，大小 **10,485,760 B**，SHA-256
  `86c1eee06896f53afc792c0167f7768da120d83d4d79409d6e8e98976d8e8fa7`。
- 设置开启「仅 Wi-Fi 下载」后启动该任务；约 1.1 MB 时用 `svc wifi disable` 关闭 Wi-Fi。
  任务页显示 **「等待中 / 等待网络或系统资源 · 1.1 MB / 10.0 MB」**，状态文件为
  `waiting`、`processed=1,179,648`。
- 等待状态下 `aa force-stop` 并重启应用，状态仍为 `waiting`、进度 1,179,648 B；
  重新打开 Wi-Fi 后任务自动继续并完成，`processed=size=10,485,760`。
- 回传应用内文件 SHA-256 与源文件一致；Wi-Fi 关闭期间通过 USB 保持操作，没有丢失控制。

## 自定义目录副本

- 设置下载位置为已有的 `ImageDownloader-QA`（目录授权仍在）。
- 下载 `custom-qa.png`（2,668 B）；记录 `receipt.target=custom`、`status=saved`。
- 独立读取 `/storage/media/100/local/files/Docs/ImageDownloader-QA/custom-qa.png`，
  SHA-256 `dc1d9c19ca3912a8571674e1be1d12fded66360e6be3a122f0a045695ed1ca69`，
  与应用内原件及源文件完全相同；副本随后删除，目录里保留原有 `folder-qa.jpg`。

## 系统相册副本

- 下载位置切到「系统相册」，保存一张 2,668 B 的测试图（系统确认框点「允许」）。
  因地址栏保留了上一条直链，这次资产名为 `custom-qa (2).png`，内容与源文件相同；
  不影响字节验收。
- 用系统 `mediatool` 独立接收资产：

```bash
mediatool query 'custom-qa (2).png' -p
# /storage/cloud/100/files/Photo/1/IMG_1793171303_10337.png
mediatool query 'custom-qa (2).png' -u
# file://media/Photo/12540/IMG_1793171303_10337/custom-qa%20(2).png
mediatool recv '<上面的 URI>' /data/local/tmp/album-copy.png
```

- 回传的相册副本 2,668 B，SHA-256 同为
  `dc1d9c19ca3912a8571674e1be1d12fded66360e6be3a122f0a045695ed1ca69`。
- `mediatool delete` 删除该资产后再次 query 返回 `find 0 result`，没有留下测试照片。

## 多任务切网

- 两个 1.2 MiB 文件（`multi-1.png` 1,230,946 B、`multi-2.png` 1,231,193 B）通过批量直链同时入队，
  仅 Wi-Fi 开启；约 147,456 B 时关闭 Wi-Fi，两个任务均进入 `waiting`。
- 强停并重启应用后两个任务仍为 `waiting`；Wi-Fi 恢复后均完成，应用内文件 SHA 分别为
  `83d9e8a9…8cf31d`、`49285017…8e8666e4`，与源文件一致。

## ZIP 批次切网

- 受控页面 3 张 788 KB PNG 全选、ZIP 模式下载；约 147,456 B 时关闭 Wi-Fi，
  批次状态 `Batch QA.zip` 为 downloading，3 个成员均为 `waiting`。
- 强停重启后批次与成员仍保持等待；Wi-Fi 恢复后完成，`Batch QA.zip` 2,365,233 B，
  包内 3 条（2,364,194 B 解压总量），`zip-a/b/c.png` SHA 分别
  `37c7d4df…8ca3e`、`2516c09c…1c071`、`237dcae6…01453`，与源文件逐一一致。

## 自定义目录重启授权

- 设置自定义目录 `ImageDownloader-QA` 后下载 `custom-qa2.png`（2,341 B），
  目录内副本 SHA `0a94dae4…db3d93` 与应用内/源一致。
- 强停重启后应用把下载位置退回 **应用文件**，状态 `downloadLocation=app`；
  设置页显示“自定义目录授权已失效，已改回应用文件，请重新选择”。目录 URI 与名称仍保留，
  但平台没有接受长期授权；副本随后删除。

## 暂停 / 恢复组合

- 单任务在约 147 KB 时手动暂停，强停重启后仍为 `paused`、进度 196,608 B；点继续后完成，
  文件 SHA `529cd66d…ee7af` 与源一致。
- 另一任务暂停后关闭 Wi-Fi，状态保持 paused；Wi-Fi 恢复后继续，完成文件 SHA
  `3362df3e…6ac02` 与源一致。暂停状态没有被网络切换或重启误改成运行中。
- 暂停/恢复仍为**重新请求**，不宣称断点续传；文件内容正确。

## 资源不足型 WAITING（未触发）

- 将并发调到 10，同时启动 10 个 788 KB 文件；10 个任务全部进入 `running` 并最终
  `completed`，没有出现资源不足型 `waiting`。
- 本机下载服务可以同时承载这 10 个任务；没有为了制造资源不足去填满磁盘或压缩系统内存。
  因此资源不足分支仍未被真实触发，保留待验；已验证的是网络条件不匹配型 WAITING。

## 恢复与边界

- 结束后恢复 10 条下载、4 个 ZIP、20 条历史、10 条 reading、9 个图片文件；
  `wifiOnly=false`、`downloadLocation=app`、原自定义目录 URI 与名称保留；
  应用内 `large.png`、`custom-qa.png`、`custom-qa (2).png`、系统相册资产和自定义目录副本均已删除；
  两个测试 HTTP 服务已停止，应用已重新启动。
- 单任务、多任务和 ZIP 批次在切网/强停重启下的状态、恢复与文件散列均已验证；暂停/恢复组合未在本轮重跑。
- `WAITING` 是通过「仅 Wi-Fi + 关闭 Wi-Fi」触发的网络条件分支，不等同于磁盘/系统资源不足分支。
- 自定义目录重启授权已验证为**失败回退**：平台未接受长期授权，应用退回应用文件并保留目录 URI/名称；没有伪造“持久化成功”。
