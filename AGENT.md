# 图片下载管理 — 工程结构

鸿蒙 stage 模型应用，界面按原型 `designs/image-downloader-ui/` 实现。**改动界面时先读下面三个文件**。

## Must-read files

| File | Why |
|------|-----|
| `entry/src/main/ets/pages/Index.ets` | `@Entry` **外壳**：页签、Toast、浮层、装配 ViewModel、订阅商店。四个页面不在这里 |
| `entry/src/main/ets/viewmodel/*.ets` | Discover / Tasks / Library / Settings / Device 及独立的 ImageEditor `@ObservedV2` ViewModel |
| `entry/src/main/ets/view/screens/*.ets` | 四个 `@Component` 页面：Discover / Tasks / Library / Settings（纯展示，事件转给 VM） |
| `entry/src/main/ets/pages/Viewer.ets` | 第二个 `@Entry`：图片大图预览，独立页面（系统返回键只认页面栈；图库进来可左右滑动换图） |
| `entry/src/main/ets/pages/ImageEditor.ets` | 图片编辑副本页面；画布手势在 `view/ImageEditorCanvas.ets`，保存经 EditExport → EditJournal → DownloadStore |
| `entry/src/main/ets/theme/Tokens.ets` | 设计令牌；颜色在 `resources/{base,dark}/element/color.json` |
| `entry/src/main/ets/theme/Metrics.ets` | 页面几何：安全区 + 标题栏 / 页签栏 / 滚动阈值（`ScreenMetrics`） |
| `entry/src/main/resources/base/profile/main_pages.json` | 页面路由，新增页面时必须同步更新 |

## 分层

```
model/     @ObservedV2 数据模型（字段逐个 @Trace）+ 设置选项表（含取值归一）+ 导航常量
util/      纯计算（网格切行 / 补空格）+ 提示闩（ToastLatch）
theme/     设计令牌 + 页面几何
service/   系统能力与业务：DownloadStore / StoreState / Naming / Delivery / FileActions /
           GripSensor / AntiPeep / Clipboard / ThemeController / MaterialSupport /
           PageScanner / PictureFactory / UiPort / MediaFormat（纯格式判定）/
           StillFrames（动图首帧）/ LivePhoto（.livp 解包与动态照片加载）/
           LibraryCatalog（收藏、标签及索引）/ LibraryAnalysis（按需 OCR、相似图）/
           LibraryImageReader（统一 EXIF 解码）/ EditExport、EditJournal（独立 PNG 与恢复）
viewmodel/ @ObservedV2 ViewModel：状态 + 行为 + @Computed 派生，界面只读它
view/      Icons / Widgets / Cards + screens/（四个页面）+ shell/（浮层）
pages/     Index（外壳）、Viewer（大图预览）、ImageEditor（编辑副本）
```

依赖方向是**单向**的：`pages → view → viewmodel → service → model`，`theme` / `util` 谁都能用。
反向的那一步（VM 要弹提示 / 推页面 / 拿 Context）走 `service/UiPort.ets` 这一个端口，由 `Index`
在 `aboutToAppear` 里注入 —— 所以 ViewModel 里没有任何 `getUIContext()`。

- `view/` — 纯展示组件。`Icons.ets` 的 `ICON_PATHS` 由 `designs/image-downloader-ui/tools/gen-icons.cjs` 生成，
  不要手改路径数据；`SYMBOL_RES`（图标名 → `sys.symbol.*`）是手写的，生成器会原样保留。
  **加图标时先在这里找系统符号**，找不到才回落路径；只挑官方 Symbol 词典（`designs/harmonyos-mobile/assets/hmsymbol-map.json`）
  里的名字，因为 HTML 原型 `designs/image-downloader-ui/icons.jsx` 的 `HMSYMBOL` 是这份表的镜像，两边要同步改。
  设置页每行的图标底色/字色由 `ListRow` / `StackedRow` **固定**为品牌色（原来有个 `brandTone` 开关，
  会造成同一个卡片里两种观感，已删）。
- `service/DownloadStore.ets` — 下载队列、打包、记录的增删改、以及投递结果的落地（常驻说明 + Toast）；
  界面只通过它改数据。高频进度走 `notifyProgress()`（写盘合并到每秒一次），
  状态跃迁与用户操作走 `notify()`（立刻落盘）。
  纯计算与其它两层**不在这里**：命名 → `service/Naming.ets`，落盘状态编解码 → `service/StoreState.ets`，
  第二落点（相册 / 自定义目录）→ `service/Delivery.ets`。
- `service/Delivery.ets` — 投递层：投递目标分派、相册投递的 800ms 防抖、退出时取消待弹的系统框。
  它的失败语义是独立的（**投递失败绝不能把下载判成失败**），所以只负责送文件 + 如实报结果；
  「怎么告诉用户」通过注入的 `report` 回到商店的 `noteDelivery`。注入项都是**函数**
  （`target()` / `context()` / `alive()`），因为下载位置用户随时能改，不能在装配时定死。
- `service/Naming.ets` — 文件名 / 扩展名的纯计算（零 IO、零状态）。`uniqueName` **不在**这里：
  它要查磁盘和下载记录，属于商店。
- `service/StoreState.ets` — 落盘状态的 `parse`（坏 JSON → `undefined`）与 `normalized`
  （补默认值 + 把裸对象变成 `@ObservedV2` 实例 + 取值归一）。`DownloadStore.adopt` 只负责赋值。
  写盘则走 `StoreState.serialize()` 的显式线格式 —— **不能直接 stringify 模型实例**，见坑 19。
- `service/FileActions.ets` — 单个已落盘文件的系统操作：导出 / 存相册 / 分享 / 拷进用户目录，
  以及目录选择与授权。**Viewer 与各 ViewModel 都从这里调**，不要各自再写一份。
  「存相册」对动图有兜底（首帧转 JPEG 再存）与实况照片的成对投递，都在这一个文件里。
- `service/MediaFormat.ets` — 媒体格式判定（**纯函数、零 IO**）：扩展名与类型（image / livephoto / video）、
  动图的头部特征（GIF 的 `NETSCAPE2.0` / 多图形控制扩展，WebP 的 `VP8X` ANIM 位）、ZIP 魔数。
  `Naming` 的扩展名白名单、地址栏的直链识别、投递层的视频类型判断都读它这一份。
- `service/BatchLinks.ets` — 批量直链的**纯逻辑**：逐行状态（有效 / 待确认 / 重复 / 无效）、原因、
  重复行指向、HEAD 响应分类和探测结果合并。零 IO，宿主测试可直接加载。
- `service/BatchLinkProbe.ets` — 批量直链的按需 HEAD 探测：并发 4、单请求 2.5s、整轮 8s、最多 60 条，
  **不带 Cookie**；只缓存确定的 image/page 结论，超时/405/403 等一律返回未知由界面保留“仍可导入”。
- `service/StillFrames.ets` — 动图的「静止首帧」：读文件头判动图（带缓存）、解码第 0 帧成 `PixelMap`
  （长边封顶、FIFO 缓存 64 条）。只给 `view/Thumb.ets` 的 `Thumb` 用，见下面坑 17。
- `service/ThumbnailImages.ets` — `Thumb` 的静态缩略图渲染管线：读取真实尺寸、中心裁剪后缩放、PNG临时缓存。
  与 `StillFrames` 一样仅由图片展示组件使用；网格请求不携带网页身份信息，最多2并发，并按组件生命周期取消。
- `service/LivePhoto.ets` — Apple 实况照片包（`.livp` / `.livephoto`）的解包与播放：解成静图 + 视频
  （两个平台硬约束见坑 15）、用 `loadMovingPhoto` 装成 `MovingPhoto`。**不改下载状态**：
  解包失败只回一句 `message`，由商店记进 `DownloadItem.note`。
- `util/Toast.ets` — 「弹一句、2.6 秒后自己消失」的提示闩，Index 与 Viewer 共用；
  `release()` 之后 `show()` 空操作，所以页面销毁后晚到的异步回调不会再写 `@Local`。
- `service/GripSensor.ets` — 智感握姿：订阅 motion 的 `holdingHandChanged`，暴露 `hand` / `supported` / `problem`；
  开关（`DownloadStore.gripEnabled`）就是订阅的开关，界面只读状态，不直接碰 motion。
- `service/AntiPeep.ets` — 防窥保护：订阅 Device Security Kit 的 `dlpAntiPeep`，暴露 `peeking` / `supported` /
  `subscribed` / `systemSwitchOn` / `problem`；三层 gating（应用开关 → 系统开关 → 订阅）和
  `canIUse('SystemCapability.Security.DlpAntiPeep')` 守卫都在这个文件里，界面只读状态。
- `service/PageScanner.ets` — 网页图片扫描：**策略**给三档取址顺序、**模板方法**跑「重扫到张数稳定」，
  并带代次保护（换页后上一页的结果一律丢弃）。界面只收到 `onProgress` 与三个终态事件。
- `service/PictureFactory.ets` — `PictureItem` 的构造与按 url 合并（**工厂方法**）。`uid` 必须在这里
  `new` 之后赋值 —— 见 `model/Models.ets` 里 `PictureItem.uid` 的说明。
- `service/UiPort.ets` — ViewModel 反向依赖界面的唯一出口；默认全是安全空操作。
- `service/Clipboard.ets` — 「检查授权 → 申请 → hasData → getData」这条平台要求的顺序只在这里。
- `service/ThemeController.ets` / `service/MaterialSupport.ets` — 主题映射与设备材质能力探测（只此一份）。
- `model/SettingsOptions.ets` — `ChoiceSet`（表 + 默认项 + 查询 + `normalize` 归一）与五张选项表；
  `normalizeLocation` / `normalizeQuality` 也在这里 —— 它们是**设置取值的合法性判据**，
  存盘的解码（StoreState）与实时 setter（DownloadStore）都调它，所以只能有一份。
  说明文案策略（`QualityHints` / `LocationHints`）同样在这。
- `model/Models.ets` — `@ObservedV2` 模型 + `@Trace` 字段，卡片以 `@Param` 收下、直接读字段即自动订阅。
- `EntryAbility.ets` — 开全屏布局并读取系统栏高度，写入 `AppStorage` 的 `safeTop` / `safeBottom` / `keyboardHeight`；
  销毁时调 `DownloadStore.shutdown()`（清掉待存相册的定时器与合并写盘）。

## 状态管理 V2（整个应用已经迁完）

三十七个组件全部是 `@ComponentV2`，九个模型/ViewModel 全部是 `@ObservedV2` + `@Trace`；
仓库里**没有** `@Component` / `@State` / `@Prop` / `@Link` / `@ObjectLink` / `@Observed` / `@StorageProp` 的声明了
（`grep` 一遍即可确认）。家族映射与实测踩出来的规则：

| V1 | V2 | 备注 |
|---|---|---|
| `@Component` | `@ComponentV2` | 一个 struct 只能属于一个家族 |
| `@State` | `@Local` | |
| `@Prop` | `@Param` | 父组件传值；子组件**不能**写 |
| `@Link` | `@Param` + `@Event` | 由持有状态的一方改自己再传下来（坑 21） |
| `@ObjectLink` | `@Param`（对象是 `@ObservedV2`） | 读 `@Trace` 字段即自动订阅，不需要专门绑定 |
| `@Observed` | `@ObservedV2` + 逐字段 `@Trace` | **漏标一个字段 = 静默冻结**，不会编译报错 |
| `@Watch` | `@Monitor` | 装饰的是处理方法，不是成员（坑 20） |
| `@StorageProp` / `@StorageLink` | `@ObservedV2` 单例 | V2 里非法，报 10905339（坑 18） |
| 手写 `recompute()` | `@Computed` getter | 追踪得到嵌套 `@Trace`（坑 22） |

迁移中另外两条硬规则：普通成员**不能**被父组件初始化（报 10905324，坑 3）；
`@Trace` 字段**不能**直接 `JSON.stringify`（会写成 `__ob_` 前缀，坑 19）。

## 几个容易踩的坑

1. `Path.commands` 单位是 **px**，`Shape.viewPort` 是 **vp**；`Glyph` 已按密度换算，改图标时别丢。
2. ArkUI `Scroll` 在内容比视口短时会把内容居中，所以每个页面的滚动内容都加了
   `.constraintSize({ minHeight: this.screenHeight })`。
3. 组件入参**必须显式声明装饰器**：值是 `@Param`，回调是 `@Event`。V2 比 V1 更严 ——
   没有装饰器的**普通成员父组件根本传不进来**，编译直接报 10905324
   `The 'regular' property 'x' in the custom component 'Y' cannot be initialized here`。
   加一个入参时先想清楚它是「值」还是「回调」。迁移时这条是靠编译器逐条报错收敛完的。
4. **镜像一行不要用 `Row.reverse()` 了事**：它把每个子节点都翻过去，`SectionHead` 的「0 张」会被翻到标题
   前面。`SectionHead` 因此拆成 `title()` / `actions()` 两个 `@Builder`，镜像时只换这两块的位置，
   操作组内部顺序不变。只有底部选择条 `selectionDock()` 用 `reverse`（要的就是下载按钮整体换边）。
5. **防窥保护在不支持 syscap 的设备上直接调 `dlpAntiPeep` 会抛异常把应用冲崩**，不是返回失败。
   任何调用前都必须过 `canIUse('SystemCapability.Security.DlpAntiPeep')`；`service/AntiPeep.ets`
   已统一守卫，界面不要绕开它直接碰 kit。另外页面销毁必须 `off('dlpAntiPeep')`，否则回调会打到
   已销毁的组件上（`DeviceViewModel.stop()` 里先 `detach()` 再 `stop()`，由 `Index.aboutToDisappear` 调）。
6. **`Scroll.onDidScroll` 回调里的两个 offset 是「这一帧的增量」，不是当前总偏移。** 真机实测一次滑动里
   回调出 0.37 / 0.36 / 0.33… 这种小数值，拿去比阈值永远是 false（返回顶部按钮永远不出现）。
   总偏移只能读 `Scroller.currentOffset().yOffset`，见各 ViewModel 的 `markScrolled()`。
7. **写用户目录（下载位置 → 自定义目录）**：`fs.openSync('file://docs/…/x.png', CREATE)` 会 ENOENT，
   必须先 `new fileUri.FileUri(uri).path` 换成真实路径；同名探测不要用 `accessSync`（会把不存在的文件
   报成存在，序号一路虚跳），用 `openSync(READ_ONLY)`；平台通常**拒绝持久化用户目录授权**
   （`URI forbid to be persisted!`），所以 `rearmFolder()` 失败时要退回「应用文件」并在设置页说明。
   细节都在 `service/FileActions.ets`。
8. **存相册不要用 `photoAccessHelper.createAsset`**：它要 `WRITE_IMAGEVIDEO`（system_basic，
   证书 allowed-acls 里得有，否则装不上），本应用没有，真机上是 `Permission denied / 201`。
   免权限路径是 `showAssetsCreationDialog`（可一次多张，只弹一次确认），见 `FileActions.saveImagesToGallery`。
9. **原生 `Select` 被点选后会自己改显示文字**，父组件若最终没接受这次选择（选「自定义目录」在目录
   选择器里取消），只改状态刷不回去 —— 胶囊会停在用户点过的那一项上（模拟器实测：说明文字已经回到
   「应用文件 · 图片与压缩包分开存放」，胶囊却写着「自定义目录」）。这种分支要把
   `SettingSelect.revision` +1 让控件重建一次。
   **两个前提缺一不可**：
   - `revision` 必须真的出现在 `build()` 里 —— ArkUI V1 按「哪个元素读了哪个状态变量」标记脏元素，
     没人读的 `@Param` 变化不会重跑 build。早先只在组件里声明并赋值、build 里从不引用它，
     所以这个「重建」一次都没发生过。
   - 重建要落到**换节点**上。现在用 `if (this.revision % 2 === 0) { this.control() } else { this.control() }`
     两个分支共用一个 `@Builder`：分支切换时 ArkUI 销毁旧 `Select`、建新的，`value(label)` 才重新落回。
     （也试过 `.key('...' + revision)`：效果相同，但编译器 Warn
     「'key' can only be used for testing directories」—— 那是测试框架用来定位节点的 API，不该放在生产路径。）
10. **`CapsuleSegmentButtonV2`（图库的 图片 / 压缩包）不吃通用属性，也不按内容排布**：
   - 它内部把宽度**撑满父容器**，外面套一层自适应宽度的 `Row` 也没用，想要设计稿的窄胶囊只能
     自己算宽度再把 `Row` 钉死（`LibrarySegment.capsuleWidth()`）；
   - 它内部还把可用宽度**按项数平分**，所以宽度得按*最宽*的标签算 —— 按各项内容求和会让
     「压缩包」被截成「压…」；
   - `itemSelectedBackgroundColor` / `itemSelectedFontColor` **不能因为开了 `backgroundSystemMaterial`
     就留空**：材质只管组件背景板，选中项会掉回系统默认（蓝色药丸 + 近黑字）。两个颜色要按设计稿写死。
   细节见 README「图库分段（图片 / 压缩包）」。
11. **`@Component` 的成员名不能和通用属性重名**。给预览页加「第几张 / 共几张」时写了
   `private position(): string`，编译报 `Property 'position' in type 'ImageViewer' is not assignable to
   the same property in base type 'CustomComponent'` —— `position` / `width` / `height` / `opacity` /
   `scale` / `visibility` 这些都是通用属性名，撞上就编译不过。换成领域内的名字（实际用的
   `slideCounter()`）。同类坑还有 `@State opacity`、`@State scale`；加实况照片时又踩了一次：
   `@Prop motionPath: string` 撞上路径动画的 `.motionPath(value: MotionPathOptions)`，
   所以那对入参叫 `stillFile` / `motionFile`。
12. **`ForEach` 的 key 别把「会变的选中状态」拼进去**：每点一次选中就把磁贴整块销毁重建
   （`Thumb` 里的 `Image` 跟着重下、重解码 → **闪**）。key 用「实例身份」（`PictureItem.uid`），
   选中态交给 `@Trace` 原地刷新。详见 README「发现页图片网格的选中态（不要重建磁贴）」。
   （V1 时代这条还有后半句 —— 「改完 `selected` 再 `this.pictures = this.pictures.slice()`
   会把 `@ObjectLink` 的通知掐断」；V2 的 `@Trace` 是**字段级**依赖，数组整体赋值照常通知，
   后半句不再成立。见坑 13。）
13. （**V1 历史，V2 下已不存在，留作背景**）**改选中态时，必须写「父组件自己数组里的那个引用」**。
   这条是**真机上踩出来**的，而且很反直觉：磁贴点击时把 `this.picture` 回传给父组件、
   父组件在这个引用上写 `selected` —— 值**会**变（`selectedTotal` 跟着算对、头部计数与下载条都正确），
   但 `@ObjectLink` 的通知**发不出去**，磁贴自己的已选蒙层会「差一拍」：点一下取消勾选，
   蓝框和勾还留在屏幕上（要等下一次别的写入才刷掉）。同一时刻点「清空」（父组件遍历
   `this.pictures` 里的元素去写）蒙层却立刻消失 —— 两条路径的差别就在这里。
   当时的做法：子组件只回传 `uid`，父组件用 `pictures.find(uid)` **再取一次那个引用**去写。
   V2 的 `@Trace` 按字段记录依赖、不挑引用从哪来，所以这条连同它的修法都不再是必需的；
   `DiscoverViewModel.togglePicture(uid)` 保留 uid 形式只是为了边界清楚 —— 子组件只报「哪一个」，
   由持有列表的一方去查去改，不把模型引用递来递去。
14. **动图（GIF / WebP）没有「只播首帧」的开关**：ArkUI 的 `Image` 一旦看到动图就会自己播，
   组件可见即动。图库格子要静态首帧，只能自己解码第 0 帧成 `PixelMap` 再画（`service/StillFrames.ets`）。
   「是不是动图」必须**读文件头**判断（`service/MediaFormat.ets`），不能只看扩展名 ——
   单帧 GIF / 静态 WebP 都很常见。首帧解码要封顶尺寸（现在 512）并按路径缓存，
   否则一张 1080p 动图一帧就是 8 MB，几十个格子能把内存吃穿。
15. **实况照片（`.livp`）解包有两个平台硬约束**：`zlib.decompressFile` 的入参**扩展名必须是 `.zip`**
   （所以先复制成 `<目录>.zip` 再解、解完即删），且**输出目录必须已存在**（`mkdirSync` 先建）。
   解出来的目录按**下载记录 id** 命名，改名才不会连累它。
16. **`MovingPhotoView` 必须显式开播**：`.autoPlay(true)` 在真机（PLR-AL00，HarmonyOS 7）上不会让画面动起来，
   表现是「停在封面上一动不动」，看起来像一张静态图、也没有任何报错。要在 `onPrepared` 里
   `controller.startPlayback()`（`MovingPhotoViewController`），另外 `.onError` 要有降级文案 ——
   设备解码不了这段 MOV / HEVC 时同样不会抛异常，只会静静停住。
17. **`view/Thumb.ets` 中的 `Thumb` 是唯一直接调 `service/StillFrames` 的展示组件**：首帧是「逐文件、逐格子」的决定，
   放到 ViewModel 里预计算会把不可序列化的 `PixelMap` 塞进状态。别的展示组件仍然只吃模型字段。
   另外 `PixelMap` **不能用 `@Prop` 传**（对象类型会走深拷贝），句柄会被拷坏 ——
   `LivePhotoSlide` 因此由自己 `LivePhoto.load()`，而不是让预览页把 `MovingPhoto` 传下来。

18. **`@StorageProp` / `@StorageLink` 在 V2 里非法**（报 10905339
   `The '@StorageProp' decorator can only be used in a 'struct' decorated with '@Component'`）。
   全局安全区/键盘高度改成一个 `@ObservedV2` 单例：`theme/Metrics.ets` 的 `SCREEN_INSETS`
   （字段标 `@Trace`），`EntryAbility` 直接写、组件在 build 里读，**不需要层层透传** ——
   这正是当初改用全局态的理由，V2 用单例把它做干净了。迁移期曾让 AppStorage 与单例双写，
   现在 AppStorage 那半边已删（已无读者）。注意单例必须**在 `onWindowStageCreate` 里尽早写**，
   否则首帧拿到的是 0（V2 会在写入后自动重刷，所以只是首帧闪一下）。
19. **V2 的 `@Trace` 字段不能直接 `JSON.stringify`**（本轮最贵的一课）：
   观察代理把它们实现成**非普通可枚举属性**，序列化会写成 `__ob_id` / `__ob_name` / `__ob_size`，
   而读侧读的是 `id` / `name` / `size` —— **记录会在下次启动时静默变成空白**（名字空、大小 0），
   而且再写一次盘真值就没了。真机实测：6 条下载记录全空。
   落盘一律走 `StoreState.serialize()` 的**显式线格式**（一组无装饰器的 DTO 类，写出去的名字自己定）；
   单测 `serialize_then_parse_keeps_every_field` 断言线格式里不出现 `__ob_` 且字段往返一致。
   **不要**用 `UIUtils.getTarget()` 解代理：那是 `@kit.ArkUI` 的界面 API，持久化属于 service 层，
   分层规则不允许反向依赖界面。
20. **`@Watch` → `@Monitor`，而且 `@Monitor` 装饰的是「处理方法」不是成员**：
   `@Monitor('src') private onSourceChanged(monitor: IMonitor): void { … }`
   （`IMonitor` 是全局类型，不需要 import）。
21. **`@Link` 在 V2 里没有对应物**：改成 `@Param` + `@Event`，由持有状态的一方改自己再传下来。
   `ImageViewer` 的 `slides` / `index` 就是这样：Swiper 的 `onChange` 通过 `onIndexChange` 回写，
   预览页改自己的 `@Local`。
22. **`@Computed` 追踪得到嵌套 `@Trace`**（真机验证过）：`selectedTotal` 从 `item.selected` 派生、
   任务列表从 `item.status` 派生、图库统计从 `item.size` / `auxSize` 派生，嵌套字段一变就自动重算。
   于是 VM 里的手写 `recompute()` 全部删掉，`sync()` 只负责把商店的数组拉成本地镜像。


## 构建与测试

```bash
./scripts/build.sh assembleHap            # 主包（改 .ets 后至少跑这个）
./scripts/device.sh install|launch|shot|tap|swipe [目标]   # 默认真机；模拟器传 127.0.0.1:5555
```

**单测可以真的在设备上跑**（`assembleHap` 只编主包，不会编译 ohosTest，所以别以为改了纯函数就没法验证）：

```bash
DEVECO=/Applications/DevEco-Studio.app
export DEVECO_SDK_HOME="$DEVECO/Contents/sdk" JAVA_HOME="$DEVECO/Contents/jbr/Contents/Home" PATH="$JAVA_HOME/bin:$PATH"
node "$DEVECO/Contents/tools/hvigor/bin/hvigorw.js" assembleHap \
  -p module=entry@ohosTest -p product=default --no-daemon       # 编测试包（顺带会类型检查 src/main/ets）
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc -t 127.0.0.1:5555 shell "aa test -b com.example.imagedownloader -m entry_test \
  -s unittest OpenHarmonyTestRunner -s timeout 60000"
# 末行看：OHOS_REPORT_RESULT: stream=Tests run: N, Failure: 0, Error: 0, Pass: N
```

用例在 `entry/src/ohosTest/ets/test/DownloadStore.test.ets`，入口是 `List.test.ets`。
**动 `Naming` / `StoreState` / `SettingsOptions` 的归一逻辑后一定要跑一遍** —— 这些是纯函数，
搬动位置最容易悄悄改掉边界行为（`test/` 里的 describe 名就写着被测对象）。

### 真机验证基线（HUAWEI Mate 70 Pro / PLR-AL00 / API 26 / 1316×2832）

走 `DEVICE_TARGET=<设备>:<端口> ./scripts/device.sh <cmd>`；不设 `DEVICE_TARGET` 就落到模拟器
（`127.0.0.1:5555`）。**仓库里不写任何设备地址**。下面这份基线是在一台 HUAWEI Mate 70 Pro 上跑的：

- 主包与测试包都能用现有调试签名装上（两条 `system_basic` 权限的 ACL 已就位）；
- 单测 **78/78 通过**（迁移到 V2 后又跑了一遍，含新增的落盘往返用例；后来加「原图优先」的候选
  采集 / 择优 / 站点尺寸表时又加了一组用例，此数在模拟器 `127.0.0.1:5555` 上复测，真机未重跑）；
- **两个传感器特性在这台机器上都真的生效**：设置页「防窥保护」显示「已接入 · 检测到窥视时立即隐藏内容」，
  「智感握姿」显示「已接入 · 主操作跟随握持手」—— 也就是说 `dlpAntiPeep` 订阅与
  motion 握持手订阅都成功，模拟器上验不了这两条。**这两行现在都不弹 Toast**：握姿三条提示
  （已开启 / 已关闭 / 未生效）已改成常驻 aux，见 `SettingsScreen.gripHint()`。
- **智感握姿的三档已在真机上实测**（用户配合握持，`uitest dumpLayout` 逐帧判读）：

  | 握持 | 胶囊 | 镜像（`gripLeft()`） |
  |---|---|---|
  | 左手 | `握姿 · 左手` | ✅ 标题在右、`全选/反选/清空` 在左；下载条整体换边 |
  | 右手 | `握姿 · 右手` | ❌ 默认排布 |
  | 平放桌面（未握持） | **整颗消失**（设计上不显示「未握持 / 识别中」） | ❌ 默认排布 |

  判读靠**坐标**而不是肉眼：镜像时 `全选` 的 x 从 940 变到 52，标题 x 从 52 变到 792。
- 下载 → 相册投递会真的弹出系统「允许…保存 N 张图片?」，点「禁止」后设置页**不会**留下失败说明
  （`outcome.cancelled` 不算失败）；
- 大图预览、删除确认框、四个页签在 1316×2832 这个比例下都正常。
- **V2 迁移后又跑了一遍全量回归**：标题 `发现` 仍是 `[47,171][202,278]`（安全区改成单例、并撤掉
  AppStorage 双写之后依然逐像素一致）、四个页签与图库角标、设置页十行与两行 aux、下拉选深色并落盘、
  磁贴选中切换（计数 / 下载条 / 蒙层）、完整下载链路、`@Computed` 派生量（图库 `5 张图片 · 20.5 MB`、
  任务「已结束」6 条、选中计数跟着嵌套 `item.selected` 走）全部正常；单测 67/67（GUI 回归当次；
  后来补了候选用例，当前总数 78，见上）。

**还没在真机上验的**：`Delivery.stop()`（退出时取消待弹的系统框）要在 800ms 窗口内 force-stop，
时序不稳，只有代码走查；「双手握持」那一档（`握姿 · 双手`）没实测（与右手同属「不镜像」分支）。

## 签名 / 权限

**四条权限里两条需要证书 ACL，两条不需要。** 判据是 `PermissionDefinitions.json` 里的
`availableLevel`：高于普通应用（`system_basic` / `system_core`）的，声明完还得让证书
`allowed-acls` 带上它，否则 `hdc install` 直接失败（`code:9568289 … grant request permissions failed`），
表现是"改完装不上"，很容易误判成代码问题。

| 权限 | grantMode | availableLevel | 要不要 ACL |
|------|-----------|----------------|-----------|
| `ohos.permission.READ_PASTEBOARD` | `user_grant` | `system_basic` | **要**（首次点粘贴还会弹一次授权框）|
| `ohos.permission.DLP_GET_HIDE_STATUS` | `system_grant` | `system_basic` | **要**（**没有授权框**，最容易漏）|
| `ohos.permission.DETECT_GESTURE` | `system_grant` | `normal` | 不要 |
| `ohos.permission.FILE_ACCESS_PERSIST` | `system_grant` | `normal` | 不要（`fileShare.persistPermission` / `activatePermission` 用）|
| `ohos.permission.INTERNET` | `system_grant` | `normal` | 不要 |

`DLP_GET_HIDE_STATUS` 是防窥保护用的：`system_grant` 让人以为"装机即授予、不用管签名"，但
`availableLevel` 仍是 `system_basic`，漏了 ACL 一样装不上。实测现象：

```
msg:error: failed to install bundle. code:9568289 error: install failed due to grant request permissions failed.
PermissionName: ohos.permission.DLP_GET_HIDE_STATUS
```

补 ACL 的两条路（都已在本机验证过可行/不可行）：

1. DevEco Studio → Project Structure → Signing Configs → 重新自动签名；
2. 命令行 `devecocli signature generate --force`（`~/.cache/deveco/bin/devecocli`）——
   但它要求 `devecocli auth status` 已登录，未登录会直接拒绝。

查当前 profile 用：

```bash
openssl cms -inform DER -in ~/.ohos/config/<xxx>.p7b -verify -noverify | python3 -m json.tool
```

往 `requestPermissions` 里加权限前先查一下
`$DEVECO_SDK_HOME/default/openharmony/toolchains/lib/PermissionDefinitions.json` 里的
`grantMode` / `availableLevel`，别把 normal 权限当成需要 ACL 的来排查。

## Invariants (do NOT change)

- `module.json5`: `module.type` = `"entry"`, `module.mainElement` = `"EntryAbility"`
- `module.json5`: `abilities[0].skills` 保留 `entity.system.home` + `ohos.want.action.home`
- `EntryAbility.ets` 继承 `UIAbility`；`entry/build-profile.json5`: `apiType` = `"stageMode"`
