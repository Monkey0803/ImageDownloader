# 图片下载管理

[![CI](https://github.com/Monkey0803/ImageDownloader/actions/workflows/ci.yml/badge.svg)](https://github.com/Monkey0803/ImageDownloader/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![ArkTS](https://img.shields.io/badge/ArkTS-state%20management%20V2-blue)
![Platform](https://img.shields.io/badge/platform-HarmonyOS%20%2F%20API%2026-lightgrey)

鸿蒙手机应用，可在内置浏览器中扫描当前网页图片，选择单张保存或打包为 ZIP。支持 1–10 个同时下载任务、失败重试、图片与 ZIP 重命名、图库预览、分享和导出，下载位置可选应用文件 / 系统相册 / 自定义目录。
发现页优先展示扫描结果、选图与下载；格式、尺寸及来源筛选按需展开，启用后即使收起仍会显示筛选状态。
点击“继续浏览”进入全屏浏览视图，可返回、前进、重载、重扫、收藏及查看最近 100 条浏览记录。扫描完成后点击“查看图片”返回结果，浏览过程不会被自动打断。收藏和历史保存在本机，重启后可恢复；清空浏览记录不影响收藏。
图库可分别查看同来源 URL、同来源文件名和同内容图片。文件内容检查由用户手动启动，先按文件大小筛选，再计算 SHA-256；不会自动删除文件，也不会保存散列缓存。

## 仓库结构

这个仓库不只装着一个应用，还装着它的设计系统与起新应用用的脚手架 —— 四块内容各有各的文档：

| 目录 | 是什么 | 文档 |
|------|--------|------|
| `entry/` | **图片下载管理**应用本体（ArkTS，状态管理 V2 + MVVM 分层） | 本 README 的「界面 / 构建」两节 |
| `designs/image-downloader-ui/` | 本应用的高保真原型（HTML/JSX），界面就是照它实现的 | 浏览器打开 `index.html`（字体自备，见下）|
| `designs/harmonyos-mobile/` | HarmonyOS 设计系统：设计令牌、组件模板、一致性校验工具 | `designs/harmonyos-mobile/readme.md`、`compliance.md` |
| `apps/harmony-starter/` | 起新应用用的脚手架（`cp -R apps/harmony-starter apps/<新应用>`） | `apps/harmony-starter/README.md` |
| `harmonyos-tokens/` | 把设计令牌打成 HAR 供其它工程依赖 | `harmonyos-tokens/README.md` |
| `scripts/` | 构建、设备操作（`device.sh`）、仓库守卫（`check-guards.sh`） | 脚本头部注释 |

两点注意：

- **设备地址走环境变量**：`device.sh` 默认连模拟器（`127.0.0.1:5555`），真机用
  `DEVICE_TARGET=<设备>:<端口> ./scripts/device.sh ...`，仓库里不留私网地址。
- **`HMSymbolVF_1.ttf` 不随仓库分发**（HarmonyOS 字体资产）。设计系统与原型按相对路径引用
  `assets/HMSymbolVF_1.ttf`，把你的副本放进对应的 `assets/` 目录即可生效。

CI 只跑**不依赖 SDK** 的部分（设计系统生成物一致性 + 仓库守卫）；ArkTS 编译与单测要
DevEco Studio 的 HarmonyOS SDK，按「构建」一节在本地跑。

## 界面

界面沿用 `designs/image-downloader-ui/` 的设计令牌，四个页签：**发现 / 任务 / 图库 / 设置**。发现页在结果与全屏浏览视图之间切换，浏览器和扫描结果保留同一份页面状态；
「图库」用分段控件在 **图片 / 压缩包** 之间切换（两种都是已经落到本机的内容，合成一个页签后
底部少一个入口，进行中的打包任务仍然留在「任务」页）。
配色、间距、圆角、字号等设计令牌集中在 `entry/src/main/ets/theme/Tokens.ets`，颜色以资源形式落在
`resources/base/element/color.json` 与 `resources/dark/element/color.json`，深浅色随系统或设置页切换。

```
entry/src/main/ets/
├─ theme/Tokens.ets      设计令牌：调色板、间距、圆角、字号、格式化工具
├─ theme/Metrics.ets     页面几何：安全区 + 标题栏 / 页签栏 / 滚动阈值
├─ util/GridMath.ets     纯计算：网格切行与补空格
├─ view/Icons.ets        线性图标集（由原型 icons.jsx 生成，见下）
├─ view/Widgets.ets      标题栏、底部页签、分段控件、按钮、卡片、开关行、重命名弹窗
├─ view/Cards.ets        图片格子、任务卡、打包卡、压缩包卡、图片预览
├─ view/screens/         四个页面：Discover / Tasks / Library / Settings（纯展示）
├─ view/shell/Chrome.ets 浮层：选择条、握姿胶囊、防窥遮罩、返回顶部
├─ viewmodel/            @ObservedV2 ViewModel（@Trace 字段 + @Computed 派生）
├─ model/Models.ets      @ObservedV2 数据模型（逐字段 @Trace）
├─ model/SettingsOptions.ets  设置选项表（ChoiceSet）与说明文案策略
├─ model/BatchView.ets   打包卡要显示的派生投影
├─ model/Navigation.ets  页签下标与图库分段常量
├─ service/DownloadStore.ets  下载队列、打包、记录增删改、投递结果落地
├─ service/StoreState.ets     落盘状态的 parse / normalized（补默认值 + 实例化 + 归一）
├─ service/Naming.ets         文件名与扩展名的纯计算
├─ service/Delivery.ets       第二落点：系统相册 / 自定义目录（含 800ms 防抖）
├─ service/FileActions.ets    单个文件的系统操作：导出 / 存相册 / 分享 / 拷进目录
├─ service/PageScanner.ets    网页图片扫描：取址策略 + 重扫到张数稳定
├─ service/BrowserCollection.ets 浏览历史与收藏的本机存储
├─ service/DuplicateFinder.ets 重复来源提示与手动内容检查
├─ service/PictureFactory.ets PictureItem 的构造与按 url 合并
├─ service/Clipboard.ets      剪贴板读取（含权限申请顺序）
├─ service/ThemeController.ets / MaterialSupport.ets  主题映射 / 材质能力探测
├─ service/UiPort.ets         ViewModel 反向依赖界面的唯一出口
├─ service/GripSensor.ets     智感握姿：订阅系统握持手感知
├─ service/AntiPeep.ets       防窥保护：订阅系统窥视状态
├─ util/Toast.ets             提示闩（2.6 秒自动消失；销毁后不再弹）
├─ pages/Index.ets       @Entry：**外壳**（页签、Toast、浮层、装配 ViewModel）
└─ pages/Viewer.ets      @Entry：图片大图预览（独立页面，见「大图预览」）
```

依赖方向是单向的：`pages → view → viewmodel → service → model`，`theme` / `util` 谁都能用。
ViewModel 不碰界面：要弹提示、推页面、拿 `UIAbilityContext` 时走 `service/UiPort.ets`，由
`Index.aboutToAppear` 注入。改界面前先读 `AGENT.md` 的「Must-read files」与「几个容易踩的坑」。

### 智感握姿

设置页「系统特性」里的**智感握姿**开关来自 Multimodal Awareness Kit 的 motion 模块
（[获取用户动作开发指导](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/motion-guidelines)）：
打开后订阅 `holdingHandChanged`，系统识别出握持手时把**主操作移到拇指够得着的一侧**——
发现页的「全选 / 反选 / 清空」整组换到左边，底部选择条 `Row.reverse` 反向让下载按钮落到左侧，
并在选择条上方显示一枚「握姿 · 左手/右手」状态胶囊。只镜像**左手握持**：右手握持就是界面
本来的排布，未握持 / 双手 / 未识别一律保持原样，避免系统上报抖动时界面来回翻；
那颗胶囊也只在真的认出一只手时才画（`gripChipVisible()`）——「识别中」「未握持」不显示，
手机平放时它只会变成常驻噪音。三页的「回到顶部」按钮（见下一节）同样跟着这条规则换边。

- 订阅状态由 `service/GripSensor.ets` 统一持有（`hand` / `supported` / `problem`），开关和订阅同生共死，
  不做常驻监听；开关本身随 `DownloadStore` 的状态文件持久化，重启后自动恢复订阅。
- 权限是 `ohos.permission.DETECT_GESTURE`（normal + `system_grant`）：装机即授予，**不需要运行时弹窗，
  也不需要证书 ACL**，与下面的 `READ_PASTEBOARD` 不是一回事。
- 设备不支持时订阅返回 **801**；这时开关仍按用户意愿保存，但**不弹任何提示** ——
  「未生效：设备不支持智感握姿」写在设置页那一行的说明里（`gripHint()`），要查的时候看得见。
  文档里「设备不支持」与「系统开关未开」两种情况现象相同，应用侧区分不了，错误码只写进日志，不暴露给用户。
  模拟器上走的就是这条路径，实测不崩、只是不生效。
- **设置页尽量不放说明文案**：`系统特性` 卡片里没有 HintRow，多数行只留标题（+ 控件/取值），kit 名、801、
  系统开关位置都只留在代码注释和本 README 里；需要用户知道的「会降级」在操作的那一刻用一次 Toast 说
  （沉浸式材质在本机降级），平时不占版面。**「防窥保护」与「智感握姿」两行是例外，各自保留一句 aux**：
  它们都可能「开关开着但没生效」，而这个状态没有第二个落点，必须在行内说清楚，否则用户分不清
  「开关开了」和「真的在保护我 / 真的在跟随握持手」。握姿原来用「拨动时弹一次 Toast」承担这句，
  现已改成常驻 aux —— 开关自身的状态不需要再 Toast 一遍，常驻文案也不会为了一次勾选打断操作。

### 防窥保护

设置页「系统特性」里的**防窥保护**开关来自 Device Security Kit 的 dlpAntiPeep 模块
（[防窥保护开发指导](https://developer.huawei.com/consumer/cn/doc/doccenter-advanced-features/bpta-antipeep-protection)）：
系统用前置摄像头判断屏幕前是否有机主以外的人在看，把结果以 `DlpAntiPeepStatus` 回调给应用；
应用在拿到 `HIDE` 时用 `privacyVeil()` 盖住**除底部页签栏以外的全部内容**，并调一次
`publishAntiPeepInformation()` 让系统再出一条 live view 说明原因，`PASS` 时自动恢复。

- 订阅状态由 `service/AntiPeep.ets` 统一持有（`peeking` / `supported` / `subscribed` / `systemSwitchOn`
  / `problem` / `liveViewFailed`），开关和订阅同生共死，不做常驻监听；开关随 `DownloadStore` 的状态
  文件持久化，重启后自动恢复订阅。
- **三层 gating，缺一不可**：应用开关打开 → 系统「设置 > 隐私和安全」里的防窥保护开关也打开
  （`isDlpAntiPeepSwitchOn()`）→ 才 `on('dlpAntiPeep')`。系统开关没开时不订阅，`problem` 记
  「请在系统设置中开启防窥保护」。
- **调任何接口前先 `canIUse('SystemCapability.Security.DlpAntiPeep')`**：文档明确，在不支持该 syscap 的
  设备上直接调用会抛异常把应用冲崩，而不是返回失败。
- **但 `canIUse` 单独不够**：实测模拟器上 `canIUse` 照样返回 `true`，真正挡住我们的是
  `isDlpAntiPeepSwitchOn()` 抛的 **801**（`hilog`：`[IsDlpAntiPeepSwitchOn]:… called` 后紧跟
  `failed: 801`）。所以 `801` 被当作**设备级终态**：一旦探到就把 `supported` 翻下去，后续探测直接短路，
  不再重复举手（`supported` 是"已知不支持"的粘性标记，不只是"还没探过"）。少了这道短路，界面会把
  「设备不支持防窥保护」覆盖成「请在系统设置中开启防窥保护」，用户照着去找一个根本不存在的能力。
  模拟器上走的就是这条路径：开关仍可开关、照常存盘，行内写「未生效：设备不支持防窥保护」，界面不崩。
- 用户**主动打开**开关时才会带 `context` 调一次 `AntiPeep.setEnabled(true, context)`，系统开关没开的话顺手
  拉起 `requestAntiPeepOptions()` 把用户送到系统开关上（API 23 起可用）；启动恢复订阅那次**不带 context**，
  绝不弹窗打扰用户。**一次点击只调一次 setEnabled**：早先「先无 context 探一次、再带 context 调一次」的写法里，
  第一次会占住服务在飞行状态，第二次直接搭便车复用它的结果，弹窗永远弹不出来（真机实测踩到），
  所以现在不做两次调用、也没有 `pending` 合并层。
- **轻点遮罩即解除**：识别不是确定性的（暗光/强光/逆光、角度过大都会降低成功率，人像海报也可能误报），
  所以遮罩上有「轻点任意位置继续」，点一下会调 `passDlpAntiPeepInfo()` 把隐藏状态钉成固定值并立即恢复，
  等下次解锁后系统感知重新生效，不做成单向陷阱。遮罩排在 `TabBar` 之前绘制，被盖住时页签栏仍然可点。
- 权限是 `ohos.permission.DLP_GET_HIDE_STATUS`：**`system_grant`，没有运行时授权框，但 `availableLevel`
  是 `system_basic`**，所以调试证书的 `allowed-acls` 里必须有它——见下面的「签名 / 权限」。
- 错误码只写进日志（`201` 权限被拒、`801` 无能力、`1020600004` 系统里没录人脸、`1020600001` 内部错误），
  界面只说用户看得懂的话；`publishAntiPeepInformation()` 发不出去（系统开关关了 / 应用不在前台 / 已发过 /
  这次没判出风险）不算故障，遮罩才是主体，提醒只是解释，失败时用一次 Toast 兜底。

### 列表返回顶部

**发现 / 任务 / 图库**三页各有一颗浮动的「回到顶部」按钮（`chevronUp` 的圆形玻璃按钮，
和标题栏操作按钮同一套 `IconButton` 观感）：

- **滚过半屏才浮出**（`topThreshold()` = 视口高的一半），滚回阈值以内自动收起，不占版面；
  设置页没有长列表，不挂这颗按钮。
- **跟随智感握姿**：默认贴右下；左手握持（`gripLeft()`）时整层改成左对齐，按钮落到拇指够得着的左下角，
  和「全选 / 反选 / 清空」、底部选择条是同一条镜像规则 —— **只镜像左手**。
- 点击对当前页签自己的 `Scroller` 做 `scrollTo(0, 0)`（320ms FastOutSlowIn），三个列表页各持一个
  Scroller；四个页面都是「常驻挂载 + 切 visibility」，所以控制器始终绑在组件上。
- 按钮那一层横跨整屏、只为放一颗按钮，所以设了 `hitTestBehavior(HitTestMode.Transparent)`：
  不设的话浮动的下载条和页签栏会被它盖住点不动（toast 踩过同一个坑）。
- **坑：`Scroll.onDidScroll` 回调里的两个 offset 不是「当前总偏移」，而是这一帧的增量。** 真机实测
  一次滑动里回调出的是 0.37 / 0.36 / 0.33… 这种小数值，直接拿去比阈值永远是 false（按钮永不出现，
  第一版就是这么写的）。总偏移只能从 `Scroller.currentOffset().yOffset` 取，见 `scrolledPast()`。

### 大图预览（独立页面）

图库 / 任务里点图片打开的大图，是 **`pages/Viewer.ets` 这个独立页面**（`router` 推栈），
不是 Index 上的一层浮层：

- **为什么必须换页面**：系统返回键只处理页面栈。原来是浮层时页面栈里始终只有 Index，
  在大图里按返回键会直接退出应用；现在返回键（和右上角关闭按钮）都是 `back()`，只退回图库。
- **入口与权限**：图库网格 → `openViewer(item, true, <本次显示的整批 id>)`（可改名、**可左右滑动换图**）；
  任务卡缩略图 → `openViewer(item, false, [item.id])`（**不给改名**、也滑不动）。
  任务页只管下载队列，改名归图库；任务卡上的文件名也**不再**是改名入口。
- **滑动换图**：图库里点开大图后，左右滑动就是**前后翻这一批图**（`Swiper`，`loop(false)` 不绕圈）。
  翻页范围就是点进来时图库**正在显示**的那一批 —— 搜索后只在结果里翻。头部右侧的「3 / 12」说明当前
  是第几张，只有一张时不显示。翻页只换数据：标题、操作区和文件操作的目标都跟着当前这一张走，
  滑到哪张就改 / 存 / 分享 / 导出 / 删除哪张。任务页进来只带一张 id，因而没有这条计数器。
- **参数**：`{ id, rename, ids }`。页面自己按 id 从 `DownloadStore.downloads` 取记录，并订阅商店的刷新回调
  （`subscribe` / `unsubscribe`，Index 与预览页可以同时挂），所以改名、删除会即时反映在这一页上；
  `ids` 里已经删掉的记录会在刷新时被剔掉，索引随之收敛到相邻一张。
- **任务还没下完也能看**：文件没落盘（进行中 / 已失败）时用远程 URL 显示大图，操作区收起并写一句
  「图片还没下载完成…」；落盘后才给出存相册 / 分享 / 导出 / 删除。
- 两个页面都挂着商店的刷新回调，所以「待弹提示」（如投递失败）指定由**当前可见的那一页**取走：
  Index 用 `onPageShow` / `onPageHide` 维护可见性，被预览页盖住时不再抢提示。

### 下载位置

设置页「下载」里的**下载位置**是个三档下拉（`DOWNLOAD_LOCATIONS`），
每档都只多出一个「第二落点」，**应用内的那份副本永远保留** —— 图库、预览、改名、导出、分享都指着它，
所以投递失败绝不会反过来把下载判成失败，只在设置页那行和一次 Toast 里说明。

| 档位 | 语义 id | 落点 |
|------|---------|------|
| 应用文件（默认） | `app` | 图片 `filesDir/images`、压缩包 `filesDir/archives`（原行为） |
| 系统相册 | `gallery` | 下载完成的图片再存一份进相册（压缩包不收） |
| 自定义目录 | `custom` | 用户挑一个目录，图片与压缩包都再拷一份进去 |

- **自定义目录的临时授权会失效**：目录选择用 `DocumentViewPicker.select({ selectMode: FOLDER })`，
  再把这次的临时授权 `fileShare.persistPermission()` 持久化。**但平台普遍拒绝持久化用户目录**：
  真机（PLR-AL00，HarmonyOS 7）对 `.../Download` 和 `.../Pictures/hiddenAlbum` 都返回
  `13900001 / PolicyErrorCode=1「URI forbid to be persisted!」`。所以：能持久化就持久化；
  不能也不拦着用户选（本次会话照样写得进去，实测能落盘），只是一句 Toast 说明「重启后需要重选」；
  启动时 `rearmFolder()` 调 `activatePermission()`，失败就把档位**退回应用文件**并在行内写
  「自定义目录授权已失效，已改回应用文件，请重新选择」，而不是留着 custom 档让之后每个下载都弹一次失败。
- **写进用户目录必须先把 docs URI 换成真实路径**：`fs.openSync('file://docs/.../xxx.png', CREATE)`
  会 ENOENT（真机日志 `Open failed, path is: file://docs/...`）。官方「保存文件到 Download 目录」示例的
  写法是 `new fileUri.FileUri(uri).path` 再交给 fs，`FileActions.resolvedPath()` 照做。
- **同名探测不能用 `accessSync`**：在用户目录的真实路径上它会把不存在的文件报成存在，一份文件被排到
  `xxx (3).png`。改用 `openSync(READ_ONLY)`（打不开就是没有），见 `FileActions.hasFile()`。
- **存相册走 `showAssetsCreationDialog`，不是 `createAsset`**：`createAsset` 需要
  `ohos.permission.WRITE_IMAGEVIDEO`（user_grant + `availableLevel: system_basic`，声明后调试证书的
  allowed-acls 还得带上它，否则装不上），本应用没有这个权限，真机上直接
  `Permission denied / js errcode:201`。免权限的官方替代就是 `showAssetsCreationDialog`：把源文件 URI
  与目标配置交给系统弹一次确认。**多张一起传，所以一次下载批次只点一次确认**；
  `DownloadStore.queueToGallery()` 用 800ms 防抖把相邻完成的图片攒成一批。
  大图预览页的「存相册」也换成同一条路径（原来那个 `createAsset` 版本在这台真机上是坏的）。
  两个已知边界：该接口**单次上限 100 张**（`GALLERY_BATCH_LIMIT` 里截断，不让整批失败）；
  用户在确认框上点「禁止」**不算投递失败**（`ActionOutcome.cancelled`），不会在设置页留下故障文案。
  真机上确认框里能看到源图缩略图（沙箱 URI 传进去是可预览的）。
- **下拉被取消时要把控件刷回去**：原生 `Select` 被点选后会自己改显示文字；用户在目录选择器里取消时，
  父组件并没有接受这次选择，仅改状态刷不回去（真机实测：store 里还是「系统相册」，胶囊写着「自定义目录」）。
  `SettingSelect.revision` 就是给这种情况准备的重建号，取消时 +1 让控件重跑一次 build。
- 三档都只存**语义 id**：`downloadLocation` + `customDirUri` / `customDirName`，
  旧状态文件读到缺失字段一律退回 `app`；`custom` 却没有 URI 时也退回 `app`（`normalizeLocation()`），
  否则每次下载都会往空 URI 上拷。

### 下载图片质量

设置页「下载」里的**下载图片质量**是个三档下拉（`PICTURE_QUALITIES`）。它管的是**扫描时每个 `img`
取哪个地址去下载**，不涉及本地重编码或缩放（没有引入 ImageKit，也没有新权限 / 新 syscap）：
真正的文件字节始终是服务器给的那张图，这一行只是决定「挑哪一张」。

| 档位 | 语义 id | 每个 `img` 走哪条路 | 效果 |
|------|---------|---------------------|------|
| 原图优先（默认） | `original` | 采集全部候选 → 择优 → HEAD 仲裁取最大 | 尽量拿到服务器上最大的那张；缩略图不再重复出现，代价是要多花几秒核对 |
| 网页显示图 | `display` | 只取 `currentSrc` → `src` | 只取浏览器当前真正渲染出来的那张；还没懒加载出来的图会被跳过 |
| 全部 | `all` | `currentSrc` + `data-src` + `data-original` + `src` **各收一条** | 改动前的行为，同一张图的缩略图与大图会同时出现在列表里 |

**为什么需要「升级地址」这一步**：很多站点在 DOM 里只暴露缩略图 URL，原图 URL 藏在别处
（响应式 `srcset` 描述符、`<picture><source>`、外层 `<a href>`、懒加载 `data-*`、内嵌 JSON 属性），
或者同一张图在 CDN 上有可推导的尺寸阶梯（Wikimedia 的 `250px-` → 原图、微博的 `orj360` → `large`）。
只挑一个属性名是不可能通用的，所以「原图优先」档拆成四层，前三层与站点无关：

1. **采集（`PageScanner.ScanProtocol` 注入脚本，完全通用）**：对每个 `img` 收集候选地址 ——
   `currentSrc` 与 `src`；`srcset` / `data-srcset` 的全部条目（带 `w` / `x` 描述符，`x` 折算成
   `×1000` 的宽度分参与排序）；`<picture><source>`；往上三层内指向图片文件（按扩展名判断）的
   外层 `<a href>`（例如「点缩略图看原图」）；13 个懒加载属性白名单；页面级 `og:image` 与 JSON-LD；
   以及**属性里内嵌的 JSON**（按 `m` / `data-m` / `data-json` / `data-info` / `data-obj` / `data-item`
   逐层下钻，深度 ≤ 3、单串 ≤ 20 KB、总预算 40 次），后者正是 Bing 图片搜索这类「`src` 是 base64
   占位图、真地址在 `m="…"` 里」的页面唯一能取到图的路。注入脚本只产出 `{ url, declared }`，
   `declared` 是站点自己声明的大小分（没有就是 0），**只用于排序**。
2. **择优（`ImageCandidates.Candidates`，完全通用）**：按 URL 去重、按 `declared` 降序排，
   只把前 `SizeArbiter.PER_IMAGE`（= 4）个送进下一步；全部未声明时保持采集顺序。
3. **仲裁（`SizeArbiter`，机制通用）**：对候选逐个发 `HEAD`，取 `Content-Length` 最大的那个。
   自动推测出的替代地址有 **32 MB** 上限；页面已明确给出的原地址即使超过上限，也不会被较小的缩略图替换。并发 5、单请求超时 2 s、
   整轮预算 90 次请求 / 3 s 挂钟，先到先停；结果按 URL 进静态缓存（上限 4096 条），
   所以扫描的稳定性重试轮不会把 HEAD 重发一遍。`HEAD` 走 `@kit.NetworkKit` 的 `http`，
   `INTERNET` 权限本来就有，无需改 `module.json5`；`content-length` 拿不到或请求失败一律记为 0（未知），
   未知的不会被选中，也不会影响其它候选。
4. **站点规则（`SiteRules`，不通用，就是一张小表）**：目前只有一条 —— 微博图床 `sinaimg.cn` 的
   路径尺寸 token（`thumbnail` / `orj360` / `mw690` / …）可以互相推导，于是额外生成 6 个更大的
   兄弟地址交给第 3 层仲裁。**这张表只写实测能用的规则**：IT之家那种「猜后缀全 404」的站点一律不写，
   宁可少一个规则，也不要凭空生成死链去浪费 HEAD。

- **默认档改成了「原图优先」**：`original` 现在是 `PICTURE_QUALITIES` 表里的默认档，旧状态文件缺
  `pictureQuality` 字段、或读到认不出的值时都归一到它（`normalizeQuality()` → `ChoiceSet.normalize()`
  → 表里的 default）。改默认档意味着**升级后扫描结果会变**：以前只拿到缩略图，现在会去取原图，
  单张可能从几十 KB 变成十几 MB。想回到旧行为请手动切到「全部」。
- **带宽代价是真实存在的**：微博一条 9 图长贴按原图取是 ≈ 105 MB（单张 `large`/`original` 约 11.7 MB）。
  32 MB 上限只限制自动推测地址；页面已给出的大原图仍可供用户选择。移动网络下可切到「网页显示图」。
- 前两档里**一个 `img` 最多产出一条记录**；`all` 档没有任何优先级，把每个候选地址都塞进以 URL 为键的
  Map（行为逐字保留，零回归）。
- **`data-src` 优先是经验规则，不是保证**：个别站点的 `data-src` 指小图，也可能懒加载尚未触发，
  所以「原图优先」是择优策略，不承诺一定是页面上分辨率最大的那张。**但 `srcset` / `<picture>` /
  外层 `<a>` / 内嵌 JSON 现在都会采**，比只认四个属性名宽得多。
- **只在扫描的那一刻读档位，而且换档不会自动清列表**：右上角刷新走的是 `scan()`，它按 URL **合并**进
  `this.pictures`（已扫到的条目不会因为换档消失），所以切换后弹的 Toast 说的是「重新打开网页后生效」
  —— `openAddress()` 会先清空 `pictures`，重新打开才是干净的对比。本次不做「切档自动清列表重扫」，
  免得丢掉用户已有的勾选。
- 注入脚本里的优先级表由 `PageScanner` 的三份**白名单常量**经 `JSON.stringify` 序列化而来，
  没有用户输入进脚本的路径。
- **三档差别已在模拟器上端到端验证**（`hdc rport` 把本机 8123 反代进设备，页面里放三张图：
  `src=small-a` + `data-src=full-a`、`src=small-b` + `data-original=full-b`、以及一张
  `src` 是 data: 占位图 + `data-src=full-c` 的未懒加载图）：同一页面「全部」扫到 **5 张**、
  「原图优先」**3 张**（small 换成 full，data: 占位那张取到了 data-src）、
  「网页显示图」**2 张**（只剩两张真正渲染出来的 small，data: 占位那张被跳过）。
  行内下拉与 aux 跟随档位（`.screenshots/emu2-settings-quality.jpeg`「全部」、
  `emu3-quality-original.jpeg`「原图优先」），`aa force-stop` 重启后档位保留
  （`download-state.json` 里 `pictureQuality: original`）。

### 下拉式设置行（主题 / 材质类型 / 沉浸光感材质 / 下载位置）

设置页这三行都用系统设置里同款的**下拉选择**：原生 `Select`，收起时是「当前值 ▾」胶囊，点开是选项菜单、
当前项高亮。控件抽成了 `view/Widgets.ets` 的 `SettingSelect`（`@Param` 传选项表 / 当前下标 / 当前文字，
`onPick` 回下标），三行只差一张选项表和一次落盘：

| 行 | 选项（默认项在前/后见下） | 落盘字段 |
|----|---------------------------|----------|
| 主题 | 跟随系统（默认）/ 浅色 / 深色 | `DownloadStore.themeMode` |
| 材质类型 | 自适应（默认）/ 沉浸式 / 无材质效果 | `DownloadStore.materialType` |
| 沉浸光感材质 | 精美 / 轻柔 / 流畅 / 自适应（默认） | `DownloadStore.materialLevel` |

- 主题行原来用 `StackedRow` + 分段控件，现在也是「标题 + 下拉」；它那句「跟随系统 / 固定为深色」的 aux
  与胶囊上的当前值重复，一并去掉了。切深浅色时左侧图标要在 sun / moon 之间换，所以 `ListRow.glyph`
  也是 `@Param`（V2 里没有装饰器的普通成员父组件根本传不进来，见 AGENT.md 坑 3）。
- 换控件后 `THEME_OPTIONS`、`MATERIAL_OPTIONS` 两份分段选项表就没人用了，已删除；手写的 `Segmented`
  只剩发现页的选择条在用（那边是 2–3 项平铺更合适的场景）；「图库」的 图片 / 压缩包 走系统组件，
  见下节。
- 三行都只存**语义 id**，读到旧值 / 脏值退回各自表的默认项（`choiceOf(list, id, fallback)`）。
- **选中项的底色用独立令牌 `select_on_bg`，不跟 `brand_faint` 走**：浅色那层半透明品牌蓝
  （`#190A59F7`）叠在白卡片上是清楚的 `#E7EFFE`，同一层叠到深色卡片 `#202224` 上几乎是黑的，
  深色下选中项根本看不出来。所以深色直接给不透明值 `#E7EFFE` —— 两个主题渲染出来一样
  （模拟器实测：浅色 `#E7EEFE` / 深色 `#E6EFFE`，差在 JPEG 压缩噪声）。
  `SettingSelect` 的 `selectedOptionBgColor` 用它，其余图标底仍然用 `brand_faint`。
- **未选中项的 `optionBgColor` 必须是透明**。菜单浮层的底色（`menuBackgroundColor` = `card`）
  会被弹窗的 elevation 再提亮一档：深色下浮层实际是 `#2D2E32`，而 `card` 是 `#212224`。
  给未选中项涂 `Palette.card`，就等于在浮层里印出一块块更深的选项块，行与行之间还夹着两条
  没盖住的浅线（`.screenshots/` 的深浅色对比可复现）。透明以后浮层是一片底色、只有选中项
  有药丸，和浅色一致；浅色侧逐点取样与改前完全相同。

### 图库分段（图片 / 压缩包）

用系统的 `CapsuleSegmentButtonV2`（`view/Widgets.ets` 的 `LibrarySegment`），背景板交给
`backgroundSystemMaterial` —— 材质只影响**组件背景板**这一层，「无材质效果」或本机不支持沉浸式材质时
退回设计稿原来的浅底胶囊。三个真机上踩过的点：

- **选中项的底色 / 字色不能留空**。`itemSelectedBackgroundColor` 的默认值是
  `$r('sys.color.segment_button_v2_tab_selected_item_background')`（系统蓝），
  `itemSelectedFontColor` 的默认值是 `sys.color.font_primary`。原来在材质档把这两个 override 一起留空，
  声称「底色由材质决定、留空才不盖掉材质」—— 材质管不到选中项，真机上就是**整块蓝药丸 + 近黑字**，
  和设计稿的「白药丸 + 品牌色字」完全不是一回事（`.screenshots/library-segment-zips.jpeg`）。
  现在两个颜色**开不开材质都按设计稿写死**（`Palette.segOn` / `Palette.brand`），只有
  `buttonBackgroundColor` 那一层随材质走；未选中的字色也统一回设计稿的次级灰。
- **宽度得自己算**。文档写明该组件不支持通用属性、也没有宽度参数：它内部把宽度撑满父容器，
  外面只套一层自适应宽度的 `Row` 也没用（测量时拿到的还是父级的 maxWidth，回落的仍是满宽）。
  所以 `capsuleWidth()` 按 `.seg` 的盒模型算出宽度、把 `Row` 钉上去；同时因为组件在内部
  **按项数平分**，宽度要按*最宽*的那一项 × 项数算（按内容求和会把「压缩包」截成「压…」），
  每项再留 2vp 余量，并钳住 `itemMinFontScale` / `itemMaxFontScale`。
- **材质对象不进状态**。`uiMaterial.Material` 是带 native 句柄的框架对象，不做跨组件传递；
  所以只传一个布尔量 `materialOff`（`@Param`），材质在组件内按需现算并缓存。
  （V1 时代这条写的是「`@Prop` 深拷贝会把句柄拷坏」；V2 的 `@Param` 对对象是引用传递，
  具体失效场景变了，但「句柄不进状态」这个结论不变。）
- **容器的最小高度 `buttonMinHeight` 必须和 `itemMinHeight` 一起压**。两者是两套默认值：
  `itemMinHeight` 默认 `sys.float.segment_button_v2_singleline_selected_height`（28vp），
  `buttonMinHeight` 默认 `sys.float.segment_button_v2_singleline_background_height`（40vp）。
  只把选项压到 28vp、容器仍是 40vp 时，多出来的高度**全堆在底部**（顶 2vp、底 10vp），
  胶囊看起来就是「内容被顶到上面、底下空一条」—— 这块空带比周围亮 4 个色阶，深色下很显眼；
  浅色下只差 2 个色阶，所以一直没人发现（`.screenshots/emu-library-segment.jpeg` 里就有）。
  设计稿 `.seg` 是 `padding: 2px` + `item height: 28px`，容器就该是 **32vp**，所以补上
  `buttonMinHeight: LengthMetrics.vp(28 + Space.s2 * 2)`；改后容器 96px、选项 84px、上下各 6px，
  对称（`.screenshots/verify5-lib-dark.jpeg`）。

### 发现页图片网格的选中态（不要重建磁贴）

「全选 / 反选 / 清空 / 单点」都不应该重建磁贴。原来这套是靠「把选中状态拼进 `ForEach` 的 key」
来让界面刷新——状态一变 key 就变，ArkUI 把磁贴连同里面的 `Image` 一起销毁重建，远程缩略图
重新下载解码，于是**每次点选中都会闪一下**（真机实测：19 张图点一次「全选」新建 19 个
`SelectTile`）。现在的做法是三条：

- **key 只认实例身份**：`PictureItem.uid`（`Index.nextPictureUid()` 逐张发号）。选中状态变它不变，
  所以磁贴原地刷新；换实例（换页、本轮扫出新对象）它才变，该重建就重建。用 url 当 key 不行：
  换页后新旧页面若有同一个地址，`scan()` 会建新实例，而 ForEach 见 key 没变就复用旧组件，
  `@Param` 还收着上一页的对象。
- **选中态由 `@Trace` 原地刷新**：`SelectTile` 的 `picture: PictureItem` 是 `@Param`，
  里面直接读 `if (this.picture.selected)` —— 字段标了 `@Trace`，读它就算订阅，不需要专门绑定。
- **头部的「已选 N」是 `@Computed`**（`DiscoverViewModel.selectedTotal`），从 `pictures` 里
  每张的 `selected` 派生，嵌套字段一变就自动重算。V1 时代这里是一个手写的 `selectedTotal`
  计数器，还必须「在 build 里被真正读到」才会重刷；那套约束在 V2 下都不需要了。

验证：四个操作各点一轮，`SelectTile` 新建数 **+0**（改前「全选」是 +19），蒙层、勾选角标、
头部计数、底部选择条全部正确（`.screenshots/fix5-selectall.jpeg`、`fix6-invert.jpeg`）。

### 沉浸光感材质

**材质类型**对应
[hdsMaterial.MaterialType](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ui-design-hdsmaterial#materialtype)，
三档齐全（原来只有自适应 / 沉浸式两档，漏了 `NONE`）：

| 界面 | 语义 id | `hdsMaterial.MaterialType` |
|------|---------|-----------------------------|
| 自适应（默认） | `adaptive` | `ADAPTIVE = 100`，文档说默认就按沉浸式材质生效 |
| 沉浸式 | `immersive` | `IMMERSIVE = 101` |
| 无材质效果 | `none` | `NONE = 0`，关掉材质，不是一档效果，所以排最后 |

**沉浸光感材质**替代了原来只读的「材质等级」行：旧实现只把设备的算力档位读出来，现在可以自己选，
四档对应
[hdsMaterial.MaterialLevel](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ui-design-hdsmaterial#materiallevel)：

| 界面 | 语义 id（状态文件里存这个） | `hdsMaterial.MaterialLevel` |
|------|------------------------------|------------------------------|
| 精美 | `exquisite` | `EXQUISITE = 0` |
| 轻柔 | `gentle` | `GENTLE = 1` |
| 流畅 | `smooth` | `SMOOTH = 2` |
| 自适应（默认） | `adaptive` | `ADAPTIVE = 10`，由系统按设备算力自适应 |

- **两行的默认值都是 `ADAPTIVE`**：文档明确推荐这个档位（系统按算力动态调整，性能与效果平衡最好）。
- **按文档给的规则提示，但不替用户改**：选沉浸式（或精美 / 轻柔）前先看 `isImmersiveMaterialSupported()`，
  不支持就用 Toast 说一次「本机不支持沉浸式材质，将回退为静态模糊」/「建议改为流畅」（精美 / 轻柔吃性能，
  流畅最省，文档建议此时用流畅以降低卡顿与发热）；选沉浸光感材质的自适应时用 Toast 报一下本机对应的档位
  （「已跟随系统 · 本机为精美」），因为「自适应」的结果本来不可见。
- 两行都只存**语义 id**，不存枚举数值：状态文件可读，SDK 枚举重排也不会错位；读到旧值 / 脏值统一退回
  `adaptive`。`DownloadStore.setMaterialType()` / `setMaterialLevel()` 负责落盘，重启后两枚胶囊各显各的选择。
- **现状说明**：本应用的卡片是自绘的 ArkUI 组件，还没有接 HDS 组件的 `systemMaterialEffect`
  （`SystemMaterialParams { materialType, materialLevel }`）或 ArkUI 的材质对象，所以这两项目前是
  应用内持久化的材质策略；等这些组件真的挂上材质时，按这两个值下发即可，界面和存储都不用再改。

### 图标

全 app 的图标都走 `view/Icons.ets` 的 `Glyph`，它**优先使用系统 HMSymbol**（`sys.symbol.*`）：

- `SYMBOL_RES` 把 34 个图标名映射到系统符号，且**只用官方 HarmonyOS Symbol 词典里公布过的名字**
  （`designs/harmonyos-mobile/assets/hmsymbol-map.json`，404 个）。这不是保守，是为了和 HTML 原型对齐：
  原型用同一份词典把名字翻成码点、再用 HMSymbol 字体画出来，两边因此是同一个字形。
  其中「分享 / 导出 / 重命名 / 下载」等按设计套件 `designs/harmonyos-mobile/components/controls/IconMap.jsx`
  给出的规范符号（`share` / `arrow_up_and_rectangle_on_rectangle` / `square_and_pencil` / `arrow_down_circle`）取用。
  「返回顶部」用的 `chevronUp`（`sys.symbol.chevron_up`，码点 `0xF00D8`）是后加的，`icons.jsx` 的
  `HMSYMBOL` / `ICONS` 两份表都补了同样的条目。
- 符号按 `glyphSize`（vp）设置 `fontSize`，所以不受系统字体缩放影响；原有的 `glyphWeight` 折算成
  Regular / Medium / Bold 三档字重。
- 词典里没有对应符号的图标（`globe`、`window`、`copy`、`grip`、`shield`、`dot`）回落到下面的线性路径，
  任何图标都不会消失。原型对这几个名字同样用 SVG，所以「有符号的一起用符号、没符号的一起用路径」。
- 原型的 `designs/image-downloader-ui/icons.jsx` 里有一份镜像的 `HMSYMBOL`（名字 → 码点）；改图标名时两边一起改。

**设置页每一行的图标只有一种观感**：36×36 的 `brandFaint` 底 + `brand` 色字形。原来只有
「沉浸光感 / 智感握姿 / 防窥保护」三行是品牌色（`brandTone: true`），其余行是灰底灰字，
同一个卡片里两种观感；现在把 `ListRow` / `StackedRow` 的 `brandTone` 开关**删掉**，
两个组件固定用品牌色 —— 从代码结构上就不可能再出现不一致（这两个组件只用在设置页）。
对照截图里那一列红框：主题、沉浸光感、材质类型、沉浸光感材质、智感握姿、防窥保护、
同时下载数量、文件名来源、下载图片质量、下载位置、清理临时文件、清空全部下载记录，
现在全部是「沉浸光感」那一版的观感。

`ICON_PATHS` 里的路径数据仍由原型的 SVG 图标集生成（含上面几个回落图标）：

```bash
node designs/image-downloader-ui/tools/gen-icons.cjs \
  designs/image-downloader-ui/icons.jsx entry/src/main/ets/view/Icons.ets
```

> 注意：ArkUI `Path.commands` 的单位是 **px**，而 `Shape.viewPort` 是 **vp**，所以 `Glyph` 把 24 单位的
> 视口按屏幕密度换算成 vp 声明，形状再自行放大到目标尺寸；改 `SYMBOL_RES` 时手改即可，重跑生成器不会丢。

### 动图与实况照片

**动图（GIF / WebP）**：ArkUI 的 `Image` 会自己播放动图，而且**没有「只播首帧」的开关**。图库里一格一格
全都在动既费电又晃眼，所以：

- 下载完成时读一次**文件头**判断它是不是动图（`service/MediaFormat.ets`：GIF 看 `NETSCAPE2.0` 循环块或
  ≥2 个图形控制扩展；WebP 看 `VP8X` 扩展块的 ANIMATION 位），结果存进 `DownloadItem.animated`；
- 图库磁贴对动图改画**解码出来的第 0 帧**（`service/StillFrames.ets`：长边封顶 512、按路径缓存最多 64 帧、
  淘汰时 `release()`），**只有大图预览页才真的播动画**；
- 角标分两种口径：图库标「动图」（读过文件头，是确定结论），发现页只标格式名「GIF」/「WEBP」
  （远程图拿不到字节，不断言它会动）。任务卡沿用原有的格式角标。

**动图存相册**：免权限的 `showAssetsCreationDialog` 不接受 WebP / GIF 时，
`FileActions.saveImagesToGallery` 会把首帧用 `image.ImagePacker` 重新编码成 JPEG 再存一次
（临时文件落 `cacheDir`，用完即删），并如实说「已按静态图存入系统相册（相册不接受 GIF / WEBP 动图，
动画没有保留）」。

**实况照片（Apple `.livp` / `.livephoto`）**：Apple 在文件层的现实是「静图 + 视频」一对
（HEIC/JPEG + HEVC MOV），导出包 `.livp` 就是内含两者的 ZIP。应用按**整包单文件**处理：

- 地址栏直链被识别成「实况照片包」（`MediaFormat.mediaKindOf`），它**不进 ZIP 批次** ——
  打完包只剩一个压缩包，解包、播放、存相册都无从谈起；混合选择时批次里只装真正的图片；
- 落盘在 `filesDir/livephotos/`，完成后立刻解包到 `filesDir/livephotos/<记录 id>/`
  （`service/LivePhoto.ets`；`zlib.decompressFile` 要求入参扩展名是 `.zip`，所以先把包复制成
  `<目录>.zip` 再解，解完即删）。目录按**记录 id** 命名，改名不会连累它；
- 静图当封面（图库磁贴 + 大图页底图），角标「实况」；大图预览页用系统的 `MovingPhotoView` 播放动态部分。
  **必须显式 `startPlayback()`**：真机（PLR-AL00，HarmonyOS 7）实测只写 `.autoPlay(true)` 不会自己开播，
  画面停在封面上，看着就是个静态图；现在在 `onPrepared` 里显式开播，点一下画面也能重播；
- 存相册 = 静图与视频**各存一份**（免权限的相册确认框只支持 DEFAULT 图片，而能建实况照片的
  `MediaAssetChangeRequest` 需要 `ohos.permission.WRITE_IMAGEVIDEO`，本应用没有这个权限，
  理由见 `FileActions.saveImagesToGallery` 的注释）；
  分享同理，两条记录（图片 + 视频）一起交给系统分享面板；导出仍导出原始 `.livp`，一对文件不拆散；
- 占用统计把 `size`（原始包）与 `auxSize`（解出来的静图 + 视频）一起算，图库标题与设置页「占用」口径一致；
- **解包失败不算下载失败**：包已经完好落盘，用户仍能导出 / 分享，所以只记一句 `note`
  （预览页的提示 + 一次 Toast）。启动时 `recover()` 会补课：进程中途被杀导致的半成品会重解一次，
  已经判定「解不出内容」的包（`note` 非空）不再反复重试。

### 内置浏览器的空白画布（深色）

发现页的 `Web` 组件必须显式写 `.backgroundColor(Palette.card)`：`about:blank` 的默认画布是**纯白**的，
深色模式下会在卡片里留一块白板（浅色下和卡片同色，看不出来）。ArkWeb 的空白画布认这个通用属性
（模拟器实测：深色视口中央 `#212224` = `card`，与卡片脚完全同色；浅色仍是 `#FFFFFF`，与改前逐点一致）。

这里**没有**开 `darkMode(WebDarkMode.Auto)` / `forceDarkAccess`：前者只对声明了
`prefers-color-scheme` 的页面生效，后者会**强制反色所有网页**——本应用是靠页面里的图片干活，
把第三方页面整体压暗会连图片一起改样，所以网页内容保持它本来的样子，只修应用自己的底盘。

## 构建

工程使用 DevEco Studio SDK 26。`build-profile.json5` 是本机文件，包含调试签名配置，已被 Git 忽略；在新机器上复制 `build-profile.example.json5` 为 `build-profile.json5`，再通过 DevEco Studio 的 **Project Structure → Signing Configs** 配置调试签名。

> **签名证书需要带 ACL**：两个权限在设备端的 `availableLevel` 都是 `system_basic`，比普通应用高一级，
> 所以 `apl: normal` 的调试证书装不上（`hdc install` 报 `code:9568289 … grant request permissions failed`），
> 必须在 Signing Configs 里让证书的 `allowed-acls` 同时包含：
>
> - `ohos.permission.READ_PASTEBOARD`（地址栏「粘贴」，`user_grant`，首次点粘贴还会弹一次授权框）
> - `ohos.permission.DLP_GET_HIDE_STATUS`（防窥保护，`system_grant`，**没有授权框**，但同样需要 ACL）
>
> 「没有授权框」很容易让人以为不需要 ACL，装不上时也容易误判成代码问题。重签后可用
> `openssl cms -inform DER -in xxx.p7b -verify -noverify | python3 -m json.tool` 打开 profile 确认
> `acls.allowed-acls` 里两条都在。

命令行构建用 `scripts/build.sh`（它把 `JAVA_HOME` 指向 DevEco 自带的 JBR，hvigor 的打包步骤需要 JDK）：

```bash
./scripts/build.sh assembleHap --mode module -p module=entry@default -p buildMode=debug
```

在真机/模拟器上跑一遍并截图，用 `scripts/device.sh`：

```bash
./scripts/device.sh install <serial>                 # 装最新构建产物（-r 覆盖安装）
./scripts/device.sh launch  <serial>
./scripts/device.sh shot discover <serial>
./scripts/device.sh tap 345 950 <serial>             # 坐标是 px，和截图同一套
./scripts/device.sh swipe 1000 1100 250 1100 <serial> # 左右滑（翻图 / 验手势）
```

## 设备与验证范围

**当前只做 phone**（`module.json5` 的 `deviceTypes` 为 `["phone"]`），已在 HarmonyOS 7.0.0(26.0.0) 手机模拟器上完成功能验证。

地址栏「粘贴」已在真机（PLR-AL00）验证通过：点击 → 系统弹出 `READ_PASTEBOARD` 授权框（文案取
`pasteboard_reason`）→ 授权后经 `PasteboardService` 读到剪贴板文本 → 填入地址栏并打开。

智感握姿在真机（PLR-AL00，HarmonyOS 7.0.0.109）上订阅成功、能拿到握持手状态；镜像布局用
「把手识别结果临时钉成左手」的构建截图确认过（见 `.screenshots/grip-left-mirror-*.jpeg`，
该临时改动已还原）。后来在 Mate 70 Pro 上用真实握持又验了一轮：左手 / 右手 / 平放三档的胶囊文案与镜像
（靠 `uitest dumpLayout` 坐标判读，镜像时 `全选` 的 x 从 940 变到 52）都对。
**模拟器不支持这套感知能力**，走 801 分支：开关仍在、该行 aux 显示「未生效：设备不支持智感握姿」，界面照常可用。

沉浸光感材质在真机（PLR-AL00）上验证过：下拉展开是「精美 / 轻柔 / 流畅 / 自适应」四档、当前档位高亮，
选中后胶囊文字立即跟随、`hdc` 强停重启后仍是上次选的档位；本机算力为精美档，选自适应时 Toast 打出
「已跟随系统 · 本机为精美」。**材质类型**同样验证：三档「自适应 / 沉浸式 / 无材质效果」可选、
与材质等级各自独立存盘（强停重启后一行是「无材质效果」、另一行是「精美」，互不干扰）；本机支持沉浸式
材质，所以选它不弹降级提示。**主题**在模拟器上验证：三档「跟随系统 / 浅色 / 深色」可选，选深色后整页立刻
换深色、左侧图标同时从 sun 变 moon，`aa force-stop` 重启后仍是深色；三行各自独立，复位回默认值。

防窥保护的**接入链路与降级路径已在真机（PLR-AL00）验完**，**真实窥视触发（`HIDE`）未验**：

- 签名：`DLP_GET_HIDE_STATUS` 是 `system_basic`，旧调试证书的 `allowed-acls` 只有 `READ_PASTEBOARD`，
  `hdc install` 直接失败（`code:9568289 … PermissionName: ohos.permission.DLP_GET_HIDE_STATUS`）。
  用 `devecocli signature generate --force` 重新自动签名后，profile 的 `allowed-acls` 变成
  `[READ_PASTEBOARD, DLP_GET_HIDE_STATUS]`，装机成功；设备日志可见
  `[CheckPermission]:Check permission ohos.permission.DLP_GET_HIDE_STATUS pass`。
  注意 `build-profile.json5` 里的 `keyPassword` / `storePassword` 会被重新加密（证书与 profile 路径不变），
  该文件本身是 gitignore 的本机文件。
- 设置页那行在真机（PLR-AL00）和模拟器上都渲染正确（盾牌回落图标、开关、两态 aux）；
  `.screenshots/antipeep-settings-phone.jpeg`、`.screenshots/antipeep-emulator-unsupported.jpeg`。
- **完整开启链路（真机）**：拨开关 → `isDlpAntiPeepSwitchOn()` 为 false → 拉起系统弹窗
  「开启防窥保护 / 开启后，当本应用在前台运行，且被人窥视时，将提醒您留意屏幕隐私。」（取消 / 开启）→
  点「开启」→ 复查通过 → `on('dlpAntiPeep')` → 行内变「已接入 · 检测到窥视时立即隐藏内容」，
  系统 DLP 服务开始为该应用跟踪人脸（`dlp_hide_service_sa` 的 `FACE_TRACKING_CHANGE` 状态机）。
  见 `.screenshots/antipeep-phone-r3-prompt-2s.jpeg`、`.screenshots/antipeep-phone-r4-enabled.jpeg`。
- **冷启动恢复（真机）**：系统开关已开、应用开关存盘为开时，强停重启后**自动订阅、不弹任何弹窗**，
  行内直接是「已接入」。
- 遮罩外观用「把 `peeking` 临时钉成 `true`」的构建截图确认过，深浅色各一张
  （`.screenshots/antipeep-veil-dark.jpeg`、`antipeep-veil-light.jpeg`），遮罩期间**底部页签栏仍然可点**、
  轻点任意位置即解除（`.screenshots/antipeep-veil-dismissed.jpeg`）；该临时改动已还原。
- 模拟器：`canIUse` 返回 `true` 但 `isDlpAntiPeepSwitchOn()` 抛 **801**，界面写
  「未生效：设备不支持防窥保护」，进程存活、无 jscrash。
- **仍未验**：真实窥视（`HIDE`）回调、`HIDE` 时遮罩的实机观感、`publishAntiPeepInformation` 的系统
  实况窗、`passDlpAntiPeepInfo` 的实际效果、以及 `1020600002/3/5/6` 各错误码分支。这些都要真人被窥视
  （暗光 / 逆光 / 角度过大都会降低识别率），本轮没有条件复现，不得据编译通过或订阅成功宣布功能验收完成。

折叠屏 / 阔折叠 / 三折叠 / 平板 / 2in1 的适配与验证**挂起**：需要先扩展 `deviceTypes`，并补充分栏、折叠态重排等布局验证。在此之前不纳入验收范围。

### 本轮（返回顶部 / 大图 / 下载位置 / 图标统一）的验证

真机 PLR-AL00（HarmonyOS 7.0.0.109）逐条验过；真机中途掉线后，又在模拟器上对**合并后的版本**
（同时含本次改动与「下载图片质量」那一批）复核了一遍关键几条，下面各自标注来源：

- **返回顶部**：图库滚动过半屏后按钮浮出（`.screenshots/totop-gallery-phone.jpeg`），
  点它回到顶部且按钮收起（`totop-gallery-returned-phone.jpeg`）；任务页同样验过一遍
  （`.screenshots/totop-tasks-returned-phone.jpeg`，点完停在列表顶部、按钮收起）。
  发现页是同一段代码 + 同一个按钮，只是各自绑自己的 Scroller —— 空库时它本来就没有半屏可滚，
  扫到几行图片、内容长起来之后才会浮出。**左手握持的镜像没有单独验**（要真机左手握持才会触发），
  但它复用的是已经在真机上验过的 `gripLeft()` 规则，只是把浮层对齐方向换成左。
  按钮浮出时底部页签栏仍然可点（靠 `hitTestBehavior(Transparent)`，用「浮着按钮时切页签」验过）。
- **任务页点图标看大图、名称不可改**：点缩略图进独立预览页，操作区没有「重命名」
  （`viewer-from-tasks-phone.jpeg`）；图库进去则有（`viewer-from-gallery-phone.jpeg`）。
- **系统返回键不再退出应用**：在大图页按返回键回到图库，进程仍在（`viewer-back-to-gallery-phone.jpeg`）。
- **下载位置**：
  - 「系统相册」：选完落档、行内说明跟着换（`dl-location-gallery-phone.jpeg`）；下载完成后系统弹出
    「允许"图片下载管理"保存 1 张图片?」（`dl-gallery-save-dialog-phone.jpeg`），点允许落盘成功、无错误日志。
  - 「自定义目录」：能拉起系统「选择路径」目录选择器（`dl-location-folder-picker-phone.jpeg`），选定后
    `file://docs/storage/Users/currentUser/Download` 落档；下载完成后文件确实出现在用户 Download 目录
    （`PCtm_… (6).png`，与任务名一致 —— 序号不再虚跳，见 `hasFile()`）。该目录的授权**持久化被平台拒绝**
    （`URI forbid to be persisted!`），重启后按设计退回「应用文件」并在行内说明
    「自定义目录授权已失效，已改回应用文件，请重新选择」（用布局 dump 确认过那条 aux）。
  - 「取消选择器后胶囊要刷回原档」这条也验了：修复前胶囊停在「自定义目录」而 store 是 `gallery`，
    加上 `SettingSelect.revision` 后两边一致。
- **图标统一**：设置页四张卡片、12 行（含后来加的「下载图片质量」）的图标全部是蓝底蓝字
  （`settings-icons-unified-phone.jpeg`；模拟器上的合并版复核见 `emu-settings-merged.jpeg`）。
- **图库分段（图片 / 压缩包）显示**：修复前是满宽的系统蓝药丸 + 近黑字
  （`.screenshots/library-segment-zips.jpeg`）。修复后 图片 / 压缩包 都收成设计稿的窄胶囊、白药丸 +
  品牌色字、未选中次级灰：浅色两张（`.screenshots/seg-final-phone.jpeg`、
  `.screenshots/seg-verify-zips-phone.jpeg`）、深色一张（`.screenshots/seg-final-dark-phone.jpeg`）；
  再把「材质类型」切到**无材质效果**验回落分支（`.screenshots/seg-nomat-dark-phone.jpeg`）。

真机掉线又回来之后，对**合并后的版本**（含「下载图片质量」那一批）又复验了一遍：

- 返回顶部：图库滚过半屏浮出（`phone-totop-gallery-merged.jpeg`，这时系统是深色）、点完回到顶部并收起；
  任务页同样验过。浮着按钮时页签栏仍可点。
- 任务页两个入口都验了：**单任务卡**缩略图进预览没有「重命名」
  （`phone-final-viewer-task.jpeg`）；**打包任务卡**那摞缩略图同样能进预览
  （`phone-batch-card.jpeg` → `phone-viewer-from-batch.jpeg`，成员还在下载中，所以只给远程大图 +
  「图片还没下载完成…」）。返回键都只回上一页，进程还在（`pidof` 有值）。
- 「存相册」取消不记失败（真机复验）：下载完成后弹「允许"图片下载管理"保存 1 张图片？」→ 点「禁止」→
  设置页那行仍是正常说明（`phone-final-h2-cancel.jpeg`），没有「上次存入系统相册失败」。
- **`Thumb` 失败后复位的修复，用一台本地图床做了确定性验证**：Mac 上起一个「带 `Referer` 才返回 200、
  否则 403 并延迟 25 秒返回」的小服务，让「远程地址在预览里取不到、但 FTA 下载（带 Referer）能成功」
  这个真实场景稳定复现 —— 下载中截图是回落文字块 + 「图片还没下载完成…」（`h1-a-remote.jpeg`），
  同一页在下载完成后自己换成落盘的图 + 完整操作条（`h1-b-local.jpeg`）。
  没有 `Thumb` 的 `@Watch` 复位，这一步会永远停在文字块上。

模拟器（`127.0.0.1:5555`，HarmonyOS 7 手机镜像）上对**合并后的版本**复核的几条：
- 单元测试 `Tests run: 40, Failure: 0, Error: 0, Pass: 40`（本轮新增下载位置 / 取图策略归一用例）。
- 返回顶部：图库灌到 13 张后滚过半屏，按钮浮在页签栏上方；点它回到顶部、按钮收起。
- 大图预览：图库进预览有「重命名」，按系统返回键退回图库且**进程还在**（`pidof` 仍有值）。
- **「存相册」取消不再记成失败**：下载完成后系统弹「允许…保存 1 张图片？」→ 点「禁止」→
  设置页那行仍是正常说明「图片下载完成后存入相册（系统会弹一次确认），压缩包仍留应用文件」，
  没有出现「上次存入系统相册失败」。
- 图标统一在合并版上依旧成立：`emu-settings-merged.jpeg`（含「下载图片质量」那行）；
  真机最终产物那版见 `phone-final-settings-merged.jpeg`。
- 图库分段在有/无材质两条分支下的观感：`emu-library-segment.jpeg`（模拟器不支持沉浸式材质，
  走的就是回落分支）。

### 图库预览「左右滑动换图」的验证

在模拟器（`127.0.0.1:5555`，HarmonyOS 7 手机镜像）上验完。图库里 13 张图共用同一段文件名前缀，
截图上看不出差别，所以翻到第几张用**头部的「第几张 / 共几张」**加**完整文件名**判定 ——
后者从 `uitest dumpLayout` 的文本读，不受界面上省略号的影响：

- 图库点第一张 → 头部 `PCtm_…d6cf (13).png` + `1 / 13`（`.screenshots/swipe-02-viewer-first.jpeg`）；
- 向左滑 → `…(12).png` + `2 / 13`（`swipe-03-next.jpeg`）→ 再向左 → `…(11).png` + `3 / 13`；
- 向右滑 → 回到 `…(12).png` + `2 / 13`（前进 / 后退都验过）；
- 一路滑到 `13 / 13`（不带序号那张 `…d6cf.png`）后再向左滑，**停在 `13 / 13` 不绕圈**
  （`loop(false)`），说明翻页边界正确；
- 翻页只换数据：标题、计数、操作条都随当前这一张刷新，页面栈不变（返回键仍然只退回图库）。

一个**测试注入手势**的注意点：`uitest uiInput swipe` 给的位移太短（500–600px）时偶发不翻页，
本轮改用 750–900px 就稳定；真手指滑动没有这个门槛，这不是应用逻辑的问题。

从**任务页**进预览的单页分支也验了：任务卡缩略图 → 预览页标题是那一张、操作条**没有「重命名」**、
**不显示「第几张 / 共几张」**，向左滑一次仍停在同一张（滑不动）。
（`uitest dumpLayout` 读的是全文，不受省略号影响。）

### 本轮（动图 / 实况照片）的验证

真机 PLR-AL00（HarmonyOS 7.0.0）上，用一个本机 HTTP 服务（`python3 -m http.server`）托管自制素材完成：

- **动图识别与首帧**：`anim.gif`（PIL 生成的两帧 GIF）与 `anim.webp`（两帧 WebP）下载后，
  状态文件里 `animated=true`（411 B / 294 B，扩展名与内容类型都按原样保留）；`static.gif` / `static.webp`
  与普通 JPG 一律 `animated=false`。判定逻辑与真实素材对得上：动画 GIF 含 `NETSCAPE2.0` + 2 个 `21 F9`，
  动画 WebP 是 `VP8X` + flags `0x02`，静态 WebP 是 `VP8 `。
- **图库首帧**：`anim.gif` 磁贴是静止的红色首帧 + 右下角「动图」角标（`livp-08-gallery.jpeg`），
  同一张图在发现页只标「GIF」（`livp-05-gif-dock.jpeg`）。
- **预览播放**：大图页连拍三张，中心像素在红 `(220,40,41)` 与蓝 `(40,60,219)` 之间切换
  （`livp-11-anim-1..4.jpeg`），即动图在播而不是停在首帧。
- **相册确认框收动图**：`anim.webp` 完成后的自动投递弹出了系统的「允许"图片下载管理"保存 1 张图片?」，
  预览缩略图就是 webp 的首帧（`livp-13-webp-dl.jpeg`）—— 说明这条路径上系统能解码它。
- **实况照片全链路**：`a.livp`（自建 ZIP：JPEG 静图 + H.264/AAC MP4）经地址栏直链下载后
  `kind=livephoto`、`size=3569538`、`auxSize=3589333`，解包结果落在
  `files/livephotos/<记录 id>/IMG_0001.jpg` + `IMG_0001.MOV`；图库磁贴是解出来的静图 + 「实况」角标
  （`livp-29-cover.jpeg`，两枚记录分别显示了彩色封面与「占位空白」封面，正好对照）；
  标题的占用统计是 `size + auxSize`（2 条记录 = 13.7 MB，`livp-29-cover.jpeg`）。
- **动态播放**：预览页连拍四张，画面是视频里的射箭场景且在变（`livp-38-mov-3.jpeg`）。
  这里踩到一个真机坑：**只写 `.autoPlay(true)` 不会自己开播**，画面停在封面上（三张连拍逐点一致）；
  在 `onPrepared` 里显式 `startPlayback()` 后才动起来。`.MOV` / `.mp4` 两种条目名都验了，都能播 ——
  之前的怀疑（扩展名）不成立，问题在自动播放本身。
- **存相册**：确认框是「允许"图片下载管理"保存 **2 个文件**?」（静图 + 视频，`livp-39-save-dialog.jpeg`），
  允许后 Toast 是「已把静图与视频分别存入系统相册（系统暂不支持免权限写入实况照片本身）」。
- **分享**：系统分享面板弹出，附件是那张静图（类型可选「图片」），说明两条记录（图片 + 视频）被接受
  （`livp-41-share.jpeg`）。
- **失败路径**：非 ZIP 的 `.livp`（把 JPEG 改名成 `.livp`）→ `status=completed`、
  `note=这个文件不是实况照片包（不是 ZIP），已保留原文件`；只有静图没有视频的 ZIP →
  `note=实况照片包里缺少静图或视频，已保留原文件`。两种都**没有**把下载判成失败，包留在图库里可导出。
- **回归**：普通 JPG 下载仍是 `kind=image`、`animated=false`；改地址栏识别后，`.bmp` / `.heif` / `.svg`
  这些直链也一并被正确识别（原来只有一条写死的正则，漏了它们）。
- **未在本轮实机验证**：`add()` 里「实况照片不进 ZIP 批次」这条分支只做了代码走查与编译，
  ZIP 打包本身没再跑一遍（改动对普通图片是等价的：`packed = batchId.length > 0 && kind !== 'livephoto'`，
  普通图恒为真）；`Delivery` 的自动相册投递对实况照片的展开逻辑（静图 + 视频两条）只覆盖了
  「Viewer 里手动存相册」这条同源路径，没有把「下载位置 = 系统相册」再切回去验证一次。

## 测试

单元测试在 `entry/src/ohosTest`（hypium），覆盖 `Naming`、`StoreState`、`MediaFormat`、`DownloadStore` 中不依赖真实文件系统的逻辑，以及扫描候选图、发现页筛选、图库查询、分享链接校验、大原图候选仲裁、浏览记录归一、重复文件识别和任务状态分组。当前共 102 条，已在 API 26 真机通过。

```bash
DEVECO=/Applications/DevEco-Studio.app

# 1. 构建测试包
node "$DEVECO/Contents/tools/hvigor/bin/hvigorw.js" assembleHap \
  --mode module -p module=entry@ohosTest -p buildMode=debug

# 2. 安装测试包（主包需已安装）
hdc install entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap

# 3. 运行
hdc shell "aa test -b com.example.imagedownloader -m entry_test \
  -s unittest OpenHarmonyTestRunner -s timeout 60000"
```

结果看 `OHOS_REPORT_RESULT` 一行，例如 `Tests run: 102, Failure: 0, Error: 0, Pass: 102`。

## 使用边界

- 网页扫描读取当前页面 `img` 元素，并收集 `srcset` / `<picture><source>` / 外层 `<a href>` /
  常见懒加载地址 / 内嵌 JSON 里的图片地址；滚动页面后可以重新扫描。
  具体取哪个地址由设置页「下载图片质量」三档决定（原图优先 / 网页显示图 / 全部，**默认「原图优先」**：
  采集候选后发 HEAD 比 `Content-Length` 取最大的一张），见上面「下载图片质量」。
- 打开网页后的首次自动扫描不会一次定论：张数连续几轮不变才算扫完，最多重试 8 次（约 4 秒）。
  微博正文这类在 `onPageEnd` 之后才渲染图片的 SPA 因此不用手动刷新也能扫到图；
  4 秒后仍是 0 张会提示“暂未扫描到图片”，可滚动页面后点浏览器右上角的刷新重试。
- ZIP 下载仅保留压缩包，成功打包后连批次记录和本批次的临时图片一起清理。个别图片失败时仍打包成功项，
  失败张数记在压缩包上；整个批次失败时可在任务页点「重试整批」，或点「解散」把图片交回任务列表单独重试。
- 登录页面的下载会按图片地址读取浏览器 Cookie；站点防盗链、会话过期或不允许外部请求时可能失败。
- **改名入口**：图片改名在大图预览页里，且只有从**图库**进去才有；任务页点缩略图看大图不给改名
  （任务页是下载队列，改名归图库）。压缩包改名仍在图库的「压缩包」段。
- **下载位置的两档「第二落点」都不是唯一副本**：应用文件里始终留一份（图库、大图、改名、导出都指着它）。
  系统相册只收图片，且系统会弹一次保存确认；自定义目录的授权在真机上无法持久化，重启后需要重选。
- 大图预览是独立页面：在预览页按系统返回键只会退回图库 / 任务，不会退出应用。
- **实况照片包只从地址栏直链进入**（发现页的扫描不采集 `<a href>`）：非 ZIP 的 `.livp`、以及包里缺静图或
  缺视频的，都**只保留原始包**并在预览页说明原因，不会当成实况照片播放，也不会把这次下载判成失败。
- 实况照片的动态部分依赖设备的 MOV/HEVC 解码能力：播不了时预览页退回静图并写一句说明
  （`MovingPhotoView.onError`），分享 / 导出 / 存相册这些路径不受影响。
- 「动图」的判定来自文件头：单帧的 GIF / WebP 不会被标成动图，按普通静态图处理（画首帧与直接画原图等价）。
