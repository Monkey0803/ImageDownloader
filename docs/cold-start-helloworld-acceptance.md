# 冷启动 HelloWorld 排查与测试模块清理

2026-10-28。设备：PLR-AL00（API 26，USB `3ZF0225604005962`）。

## 根因

`Hello World` 不是生产页面，唯一来源是测试模块：

- `entry/src/ohosTest/ets/testability/pages/Index.ets:4` — 测试页 `@State message = 'Hello World'`。
- `entry/src/ohosTest/ets/testability/TestAbility.ets:35` — `TestAbility` 启动时
  `windowStage.loadContent('testability/pages/Index')`。
- `entry/src/ohosTest/module.json5` — 测试模块 `mainElement` 是 `TestAbility`。
- 生产 `entry/src/main/resources/base/profile/main_pages.json` 只有 `pages/Index`、`pages/Viewer`、
  `pages/ImageEditor`，没有 Hello World。

当时设备同时安装了生产 `entry` 和测试 `entry_test`；测试 Ability 留在设备任务中，冷启动时被带到前台，
所以看到了测试页。

## 处理

```bash
bm dump -n com.example.imagedownloader          # 卸载前：同时有 entry 和 entry_test
bm uninstall -n com.example.imagedownloader -m entry_test -k
bm dump -n com.example.imagedownloader          # 卸载后：只剩 entry
aa force-stop com.example.imagedownloader
aa start -b com.example.imagedownloader -a EntryAbility
```

卸载前后应用数据未清空：`images` 仍为 9 个文件。

## 冷启动验证

连续两次执行「强停 → 启动 EntryAbility」，`uitest dumpLayout` 均未出现 `Hello World`，
首页为发现页：

```text
first:  ['重扫图片','收藏/历史','批量链接','about:blank','查看图片 · 0 张','发现',...]
second: ['重扫图片','收藏/历史','批量链接','about:blank','查看图片 · 0 张','发现',...]
```

截图：`.screenshots/cold-start-no-helloworld.jpeg`。
`bm dump` 中 `entry_test` 已不存在，`ps` 无 `aa test`/`TestAbility` 残留。

## 数据与构建

- 用户数据：10 条下载、4 个 ZIP、20 条历史、9 个图片文件；设置仍为仅 Wi-Fi 关闭、下载位置应用文件。
- 测试模块只从设备移除，仓库中的 `ohosTest` 代码/夹具保留，下次测试前重新安装测试 HAP 即可。
- 主包未重装/未修改；本次没有改生产页面、启动页、`main_pages.json` 或 `EntryAbility`。
- 最近一次原生套件为 158/158（卸载测试模块前），本次仅做设备清理与文档说明。

## 防止复发

`AGENT.md` 的「单测可以真的在设备上跑」一节已补充：验收结束后只卸载 `entry_test`（保留生产 `entry`），
强停并冷启动确认首页不是测试页；下次跑 `ohosTest` 前再安装测试包。
