# 多个鸿蒙 App 如何共用一套设计系统

这份文档回答一个具体的问题：**要做 N 个鸿蒙 App，是不是每个都要把设计系统拷一遍？**

结论是 **不需要**，但前提是先看清「设计系统」其实是**两件消费方不同的事** —— 它们必须用两套分发机制，混在一起谈就会觉得处处要拷贝。

---

## 一 · 三层结构

```
ImageDownloader/
├── designs/harmonyos-mobile/     ① 设计时系统 —— 唯一真源（token / 组件 / 卡片）
├── harmonyos-tokens/             ② 构建时 HAR —— 全部由 ① 生成，不要手改
└── apps/harmony-starter/         ③ App —— 只写屏幕
```

| | ① 设计时系统 | ② 构建时 HAR |
|---|---|---|
| **消费方** | agent 与设计项目 | 每一个 ArkTS App |
| **分发机制** | `glob designs/*/_ds_manifest.json` → `import-design-system.mjs` 在 `<项目>/_ds/<slug>/` 落一份**版本锁定副本** | `ohpm` 依赖：`"@yostar/harmony-tokens": "file:…"` |
| **拷贝是否是问题** | **不是。** 这是官方通道，副本自包含、可版本锁定，`re-run` 脚本即更新路径。它叫 vendoring。 | **是。** 在 HAR 之前，每个 App 要跑发射器改写自己的 `resources/` 并手写绑定类 —— 成本随 App 数线性增长，且必然漂移。 |

### 为什么 skill 解决不了②

两者是不同层次的产物，**skill ≠ package**：

- **Skill（`SKILL.md`）** 把**知识与产物交给 agent**，让设计系统能跨机器、跨仓库、跨 agent 使用。它天生属于「设计时」。
- **HAR** 把**代码与资源交给 App**，让编译器有东西可依赖、可链接、可版本化。

本设计系统已经有 `SKILL.md`（可下载为 Agent Skill）。官方文档也明确：本仓库内它**不注册为 skill**，应按 manifest 发现 —— 所以它是「可携带的产物 + 人类可读说明」，不是构建依赖。

**两个都要，谁也不替代谁。**

---

## 二 · HAR 是怎么生成的

```bash
cd designs/harmonyos-mobile
node tools/build-token-har.mjs            # 写入
node tools/build-token-har.mjs --check    # CI：证明 HAR 与 token 同步
```

产出全部是**生成物**（文件夹自己的 README 就写着不要手改）：

```
harmonyos-tokens/
├── oh-package.json5              main: src/main/ets/Index.ets
├── build-profile.json5           模块级
├── hvigorfile.ts                 harTasks
├── README.md
└── src/main/
    ├── module.json5              "type": "har"      ← HAR 是模块，不是普通包
    ├── ets/Index.ets             Palette + Metrics
    └── resources/{base,dark}/element/{color,float}.json
```

```ts
import { Palette, Metrics } from '@yostar/harmony-tokens';

Text('标题').fontColor(Palette.fontPrimary).fontSize(Metrics.fontSizeTitleL)
```

`Palette.*` 是 `Resource`（明暗靠 `resources/dark` 由平台自动切换）；
`Metrics.*` 是**纯数字**，因为这套系统的底部几何依赖运行时安全区
（`100 = 16 + 56 + 28`，其中 28 由系统上报），屏幕必须做加法，而 `Resource + Resource` 是 ArkTS 编译错误 —— 这是实测撞出来的，不是推测。

---

## 三 · 更新路径

```
改 tokens/*.css  →  node tools/build-token-har.mjs  →  各 App: ohpm install --all
```

一条真源，零份拷贝。迁移到私有 ohpm registry 只是 `oh-package.json5` 里**一行**的变化
（`file:…` → `^1.0.0`），其余不动。

---

## 四 · 四条实测结论（都不是从文档读来的）

这几条各自让构建失败或被静默忽略过，所以写下来 —— 它们决定了 HAR 方案的形状。

### 1 · `ohpm` 把 `file:` 依赖处理成**符号链接**，不是拷贝

```
apps/harmony-starter/entry/oh_modules/@yostar/harmony-tokens
  -> ../../../../../harmonyos-tokens
```

磁盘上**只有一份** token。这比「零拷贝」的字面预期还要好：改 token、重装，所有 App 立即一致。

### 2 · App **无法**用同名资源覆盖 HAR 的值

故意在 App 里声明 `hm_brand = 绿色`，构建输出：

```
WARN: Warning: 'hm_brand' conflict, first declared.
BUILD SUCCESSFUL
```

**HAR 赢，App 的值被静默丢弃，只有一条 warning。** 所以「App 可以覆盖任意 token」是**错的**
（我原先就是这么写的，靠这次实测纠正）。资源名归**第一个声明它的模块**所有。

需要局部不同值时：用 App 自己的资源名，或在该组件调用处直接覆盖；
整套配色都不同，那本来就是另一套设计系统，fork token 比 shadow 一个共享包诚实。

`tools/check-app-drift.mjs` 把这种情况报成 **error**，因为它的失败是隐形的。

### 3 · HAR 是模块，只有 `oh-package.json5` 不够

只生成 `oh-package.json5` + 源码会得到：

```
10311002 Failed to resolve OhmUrl ... the module which …/Theme.ets belongs to is not correctly configured
```

HAR 必须自带 `src/main/module.json5`（`"type": "har"`）、模块级 `build-profile.json5`、
`hvigorfile.ts`（`harTasks`）。

入口文件还**必须在模块内**：ArkTS 从 `src/main/module.json5` 推导模块归属，
放在包根目录的 `Index.ets` 不属于任何模块。同时**不能**用相对路径从包根跳进 `src/main/`：

```
Cannot import files outside of the current module using relative paths.
```

最终形态就是上面那棵树 —— 入口在 `src/main/ets/Index.ets`，`main` 指向它。

### 4 · `useNormalizedOHMUrl: true` 与 `file:` HAR 不兼容

严格模式下：

```
10311002 ArkTS: ERROR  Failed to resolve OhmUrl ... imported by "null"
```

它按项目根归一化模块 URL，而 `file:` 依赖是**指向项目外**的符号链接。
用 `file:` 期间必须 `false`；等 HAR 走 registry 后再改回 `true`。

### 附：命令行构建需要三个环境变量

DevEco 把工具链装在自己目录里，默认不在 `PATH`：

| 变量 | 不设的后果 |
|---|---|
| `DEVECO_SDK_HOME` | `Invalid value of 'DEVECO_SDK_HOME'` |
| `JAVA_HOME` | 死在 `PackageHap`：`Unable to locate a Java Runtime` |
| `PATH`（含 DevEco 的 node） | `hvigorw` 找不到 |

`apps/harmony-starter/build.sh` 把这几个固化下来，可直接复用。

---

## 五 · 现在怎么用

```bash
# 1. 新 App
cp -R apps/harmony-starter apps/my-new-app
#    改 bundleName、app_name、HAR 相对路径、Index.ets

# 2. 依赖与构建
cd apps/my-new-app && ohpm install --all && ./build.sh

# 3. token 变了
cd ../../designs/harmonyos-mobile && node tools/build-token-har.mjs
cd ../../apps/my-new-app && ohpm install --all

# 4. 体检（CI 可跑）
node tools/build-token-har.mjs --check        # HAR 与 token 同步
node tools/check-app-drift.mjs --app ../../apps/my-new-app   # App 与设计系统不漂移
node tools/verify-harmony.mjs                 # 设计系统自身 12 条规则
```

---

## 六 · 还没做的

| | |
|---|---|
| **私有 ohpm registry** | 现在走 `file:`，适合单仓库多 App。跨独立仓库分发需要 registry；迁移成本一行。 |
| **把现有 ImageDownloader 接入 HAR** | 它目前是手写 token 层。`check-app-drift.mjs --app ../..` 已经给出精确工单：**`font_fourth` 在明暗两套里都是 α 0.259，而规范是 0.200**（源于它从旧原型 `designs/image-downloader-ui` 1:1 移植，旧原型手写了 0.26）。 |
| **真机运行验证** | 已验证到 `assembleHap` 产出 `.hap`。安装到设备需在 DevEco Studio 内操作。 |
| **M 个 App 的 CI 矩阵** | 目前是「每个 App 一条命令」，没有集中编排。 |
