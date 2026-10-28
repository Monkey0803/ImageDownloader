# 图库增强 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完整实现本地按需OCR内容搜索、视觉相似图识别、图片收藏/标签、裁剪/旋转/画笔与矩形标注的独立副本，并使用模拟器逐项验证。

**Architecture:** 以图片稳定ID为连接点，新增独立图库目录与逐资产索引，复用现有预览、筛选、OCR单引擎和文件操作。图像解码、方向归一、特征计算和导出由服务负责，VM只持有可序列化状态；编辑副本通过可回滚登记进入图库，和网络下载原件明确区分。四项功能共享目录、媒体身份和坐标契约，按以下任务顺序集成，不缩减交付范围。

**Tech Stack:** HarmonyOS Stage / API26、本机DevEco SDK、ArkTS V2、ImageKit、CoreVisionKit、CoreFileKit、ArkUI Canvas、Hypium、Node宿主测试；不新增云端识别、OpenCV或第三方编辑框架。

**Spec:** [已确认设计](../specs/2026-10-26-library-enhancements-design.md)、[独立验收判据](../specs/2026-10-26-library-enhancements-test-oracles.md)。用户于2026-10-26确认设计与本计划，并选择当前会话连续实现。

## Global Constraints

- 完整覆盖OCR、相似图、收藏标签、轻量编辑和模拟器验证五项目标。
- “既有交互继续成立：点击缩略图预览，选择按钮独立；预览默认显示控件、点图隐藏；预览范围沿用当前筛选结果；已下载原图优先。”
- “现有未提交改动保留，不执行Git提交。”不自动暂存、提交、推送或建立另一份缺失当前未跟踪代码的工作树。每任务用限定文件diff和源码摘要形成检查点，代替技能默认的自动提交步骤。
- `pages → view → viewmodel → service → model`；VM不持有UIContext/PixelMap，不用UI API解观察代理。V2字段逐个标记，DTO显式序列化。
- 新ArkTS不写any/unknown/as断言、动态对象属性、解构、模板字符串或匿名内联对象类型；测试脚本的Node代码不受ArkTS语法规则限制。
- 不自动识别或上传图片；搜索只读已有索引；分析由用户明确触发，能取消并拒绝旧结果。
- “保存时按选定裁剪区域的原始像素尺寸解码并应用旋转和标注，不用屏幕截图充当输出，不静默降分辨率。”
- 动图编辑/索引明确使用首帧，实况照片使用静态封面；输出独立静态PNG，不覆盖原件。
- 构建、宿主测试、原生测试、真实模拟器交互分别提供证据。系统能力声明、假OCR结果和绿色构建不替代实际OCR识别。
- 原计划只定向操作模拟器；用户随后明确告知真机已连接，并授权补验。真机测试前刷新独立基线，仅清理本轮内容；始终不重启共享HDC。
- 已知仓库守卫遗留：桌面卡片V1组件及旧TODO中的设备地址。记录基线并报告，不把旧问题混入本轮修改，也不宣称全仓检查全绿。

## Review Focus

1. 改名/同ID文件替换/实况封面更新：收藏标签保留，旧文字与特征不能错误复用（Task 2、4、5、12）。
2. 取消、删除及修改标签与分析结果同时发生：不复活已删除记录，不覆盖新标签，不提交旧任务（Task 2、5、7、12）。
3. 透明像素、红蓝通道、EXIF镜像方向：预览与原尺寸导出一致，不出现黑底、红蓝互换或二次旋转（Task 4、8、9、13）。
4. 状态写入失败、文件转正后进程中断、重复点保存：原件不变，不显示假成功，不留下重复记录或误清理有效副本（Task 10、11、12）。
5. 裁剪/旋转/标注的操作顺序与视口改变：标注绑定原图位置，框和画笔在横竖屏及撤销后仍与输出吻合（Task 8、9、11、13）。

---

## 执行方法与检查点

推荐Native：当前会话按任务顺序实现，每任务完成独立测试和限定文件审阅，最后一次独立整体验证。原因：任务共享`LibraryCatalog`、图片身份和编辑坐标契约，频繁换实现上下文会增加接口对齐成本。也可选择子代理逐任务实现/逐任务复核；这不改变任务或验收范围。

模拟器始终由一个验证代理独占。开发者不同时注入触摸或重启调试服务。现有准备目录是`/tmp/image-library-enhancements-20261026/`；执行期继续使用该目录保存源码清单、固定包、日志和数据备份，报告写入`docs/image-library-enhancements-acceptance.md`。

每任务结束：检查该任务拥有文件的diff、运行对应测试、`git diff --check`，更新本文checkbox。没有Git提交步骤；用户另行要求提交时，遵守仓库的拉取、限定暂存和精确提交信息确认流程。

## 文件结构与统一契约

### 新文件

| 文件 | 单一职责 |
| --- | --- |
| `model/LibraryAsset.ets` | 目录、源版本、索引、搜索条目和分析进度模型/显式DTO |
| `model/ImageEditDocument.ets` | 原图坐标下的裁剪、旋转、标注与编辑文档 |
| `util/LibraryText.ets` | 关键词/标签归一、文字片段和命中判定 |
| `util/PerceptualHash.ets` | 低频/梯度特征、颜色与透明度约束、确定性分组 |
| `util/ImageEditGeometry.ets` | 原图/旋转后/视口坐标映射、裁剪约束 |
| `util/EditRasterizer.ets` | BGRA小块画笔与矩形栅格化，不调用系统API |
| `service/LibraryCatalog.ets` | 目录与逐图片索引的原子持久化、版本/身份校验和订阅 |
| `service/LibraryImageReader.ets` | 有效静态源解析、EXIF方向归一、区域/小图读取和句柄生命周期 |
| `service/LibraryAnalysis.ets` | 按需OCR与视觉分析调度、进度、取消、索引发布 |
| `service/EditExport.ets` | 原尺寸区域解码、旋转、分块标注、PNG写入与验证 |
| `service/EditJournal.ets` | 编辑pending操作日志及中断恢复 |
| `viewmodel/ImageEditorViewModel.ets` | 草稿、工具、撤销/保存状态和页面事件 |
| `view/LibraryFindPanel.ets` | 搜索范围、索引状态、收藏/标签筛选及分析入口 |
| `view/LibrarySimilarPanel.ets` | 候选组缩略图与组内预览入口 |
| `view/ImageTagDialog.ets` | 单图/批量标签编辑 |
| `view/ImageEditorCanvas.ets` | 有界预览、裁剪触点和临时标注，提交原图坐标事件 |
| `pages/ImageEditor.ets` | 独立编辑路由与页面装配 |
| `scripts/lib/arkts-test-loader.cjs` | 独立宿主测试的ArkTS载入器，沿用现有transpile方式 |
| `scripts/test-library-enhancements.cjs` | 本轮纯逻辑、持久化故障及编排测试 |
| `entry/src/ohosTest/ets/test/LibraryCatalog.test.ets` | 目录DTO、查询及原生持久化用例 |
| `entry/src/ohosTest/ets/test/LibraryVision.test.ets` | 原生OCR、方向/像素读取和感知特征用例 |
| `entry/src/ohosTest/ets/test/ImageEdit.test.ets` | 编辑几何、输出像素、原图哈希与回滚用例 |

上表省略的生产路径统一以`entry/src/main/ets/`为根；测试文件路径已写全。修改现有文件：`model/Models.ets`、`model/PreviewAsset.ets`、`service/StoreState.ets`、`service/DownloadStore.ets`、`service/ImageTools.ets`、`service/LibraryQuery.ets`、`service/UiPort.ets`、`viewmodel/LibraryViewModel.ets`、`viewmodel/TasksViewModel.ets`、`view/screens/LibraryScreen.ets`、`view/Cards.ets`、`view/PreviewTools.ets`、`view/DiscoverPreview.ets`、`pages/Index.ets`、`pages/Viewer.ets`、`entryability/EntryAbility.ets`和`resources/base/profile/main_pages.json`。原生用例注册到现有`List.test.ets`，不替换已有测试入口。新增测试必须使用相应class构造实例，不能通过as断言绕过ArkTS检查。

### 数据契约（Task 1定义，后续统一使用）

以下为计划中的真实类型定义；实现时按职责拆到上述两个model文件。服务引用这些类型，不重新发明相似名字。

```typescript
export class AssetStamp {
  id: string = '';
  path: string = '';
  sourceKind: string = 'image';
  bytes: number = 0;
  modified: number = 0;
  orientation: number = 1;
}
export class LibraryMeta {
  id: string = '';
  favorite: boolean = false;
  tags: string[] = [];
}
export class VisualFeature {
  version: number = 1;
  lowBits: string = '';
  edgeBits: string = '';
  red: number = 0;
  green: number = 0;
  blue: number = 0;
  alpha: number = 0;
  width: number = 0;
  height: number = 0;
}
export class LibraryIndex {
  version: number = 1;
  id: string = '';
  stamp: AssetStamp = new AssetStamp();
  ocrVersion: number = 1;
  ocrStatus: string = 'unindexed';
  text: string = '';
  ocrError: string = '';
  feature: VisualFeature | undefined = undefined;
}
export class LibrarySearchEntry {
  id: string = '';
  favorite: boolean = false;
  tags: string[] = [];
  text: string = '';
  ocrStatus: string = 'unindexed';
}
export class LibrarySearchOptions {
  scope: string = 'all';
  query: string = '';
  source: string = '';
  format: string = '';
  order: string = 'newest';
  favoritesOnly: boolean = false;
  tag: string = '';
}
export class AnalysisProgress {
  kind: string = 'ocr';
  done: number = 0;
  total: number = 0;
  success: number = 0;
  empty: number = 0;
  failed: number = 0;
  message: string = '';
}
export class SimilarGroup {
  representativeId: string = '';
  ids: string[] = [];
}
export class EditPoint {
  x: number = 0;
  y: number = 0;
}
export class EditRect {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
}
export class EditStroke {
  kind: string = 'pen';
  color: string = '#FF0000';
  width: number = 4;
  points: EditPoint[] = [];
}
export class EditDocument {
  sourceWidth: number = 0;
  sourceHeight: number = 0;
  crop: EditRect = new EditRect();
  turns: number = 0;
  strokes: EditStroke[] = [];
}
export class EditResult {
  path: string = '';
  width: number = 0;
  height: number = 0;
  bytes: number = 0;
}
```

带可选feature的索引DTO读写显式处理undefined，不依赖JSON自动恢复class；向量字段逐个还原为真实模型。目录/索引DTO保持普通类；VM的可变展示字段使用`@Trace`。文件来源在现有`DownloadItem`增加`@Trace origin: string = 'download'`及`@Trace originalId: string = ''`。

### 统一执行与断言命令

```bash
node scripts/test-library-enhancements.cjs
node scripts/test-workflows.cjs
bash scripts/build.sh assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug
bash scripts/build.sh assembleHap --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug
git diff --check
```

宿主测试用`node:test`；新runner开头可解析`--filter=<关键字>`，仅注册匹配测试，用于下面的红/绿循环。实际实现为包装`node:test`的`caseTest(name, fn)`，匹配使用`name.includes(filter)`，没有filter时全部注册。原生用例用Hypium并注册到`List.test.ets`。不把框架测试总数写死为原有92；每次保留实际输出和新增用例名。

---

## Task 1: 图片来源、目录模型与旧状态迁移

**Files:** 新建`model/LibraryAsset.ets`、`model/ImageEditDocument.ets`、宿主runner和loader；修改`model/Models.ets`、`service/StoreState.ets`；扩展`DownloadStore.test.ets`的序列化断言；任务来源过滤在Task 10独立完成。

**Interfaces:** Produces上面的类型、`DownloadItem.origin/originalId`及对应`DownloadWire`字段。`StoreState.normalized`缺失/未知origin归为download，只有显式edited才按副本处理。Consuming现有`SavedState`与显式DTO规则。

- [x] Step 1：在新runner使用真实`StoreState`注册失败用例；`caseTest`、`ets`和fixture构造helper使用文末实际代码；loader使用现有脚本中的TypeScript路径、装饰器替身和模块缓存，`@kit`逐项mock，不运行其他测试文件副作用。

```javascript
caseTest('origin survives state migration', () => {
  const { DownloadItem, SavedState } = load(ets('model/Models'));
  const { StoreState } = load(ets('service/StoreState'));
  const item = new DownloadItem();
  item.id = 'edited-1'; item.origin = 'edited'; item.originalId = 'original-1';
  const state = new SavedState(); state.downloads = [item];
  const raw = StoreState.serialize(state);
  const restored = StoreState.normalized(StoreState.parse(raw));
  assert.equal(restored.downloads[0].origin, 'edited');
  assert.equal(restored.downloads[0].originalId, 'original-1');
  assert.ok(!raw.includes('__ob_'));
  assert.equal(StoreState.normalized(StoreState.parse('{"downloads":[{"id":"old"}]}')).downloads[0].origin, 'download');
});
```

- [x] Step 2：运行`node scripts/test-library-enhancements.cjs --filter=origin`，确认在尚无新字段/线格式时失败。
- [x] Step 3：实现类型；在serialize和normalized都显式映射。禁止直接stringify观察模型。

```typescript
out.origin = item.origin === 'edited' ? 'edited' : 'download';
out.originalId = item.originalId;
```

归一化对`originalId`使用现有`orString`，不能凭空继承原URL；旧状态默认值保留。runner定义`ets(name)`为`path.join(source, name + '.ets')`；`load=loader(nativeMocks)`按当前测试需要创建，不共享跨场景native状态。

- [x] Step 4：运行origin过滤用例、现有`test-workflows.cjs`和主包构建，检查旧下载与新副本都能往返且无代理字段。
- [x] Step 5：限定审阅Models/StoreState及新测试文件，保存检查点摘要，不提交。

## Task 2: 原子目录与逐图片索引

**Files:** 新建`service/LibraryCatalog.ets`；扩展`LibraryCatalog.test.ets`及宿主runner。

**Interfaces:**
- `LibraryCatalog.initialize(filesDir: string): Promise<void>`；导出单例`LIBRARY_CATALOG`，重复初始化复用同一Promise。
- `getMeta(id: string): LibraryMeta`、`getIndex(id: string): LibraryIndex | undefined`返回副本；`entries(items: DownloadItem[]): LibrarySearchEntry[]`只读取已加载内存，不在搜索build中逐文件读盘。
- `setFavorite(ids: string[], value: boolean): Promise<void>`、`changeTags(ids: string[], add: string[], remove: string[]): Promise<void>`、`putIndex(index: LibraryIndex): Promise<boolean>`、`clearText(ids: string[]): Promise<void>`、`reconcile(items: DownloadItem[]): Promise<void>`、`relocate(id: string, from: string, to: string): Promise<void>`。
- `subscribe(listener: () => void): void`、`unsubscribe(listener: () => void): void`；通知在持久化确认后发布。`putIndex`校验活动ID与源版本，失效结果返回false。
- 文件：`filesDir/library-catalog.json`保存meta；`filesDir/library-index/`保存索引分片。初始化失败保留原文件，操作返回可展示错误。

- [x] Step 1：宿主测试定义`memoryFs()`模拟文件、fd、rename和故障点，再定义`catalogHarness()`返回新Catalog实例、文件表和`failNextRename()`。native mock提供`openSync/readTextSync/writeSync/closeSync/statSync/renameSync/unlinkSync/mkdirSync/listFileSync`，`writeSync`按实际字节数返回。注入失败只影响下一次操作，不能让测试永远卡在mock里。

```javascript
caseTest('catalog failed rename preserves prior favorite', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a']);
  await h.catalog.setFavorite(['a'], true);
  h.failNextRename();
  await assert.rejects(h.catalog.setFavorite(['a'], false));
  const restored = h.reload();
  await restored.initialize('/files');
  assert.equal(restored.getMeta('a').favorite, true);
});
```

`catalogHarness`保存`files: Map<string,Buffer>`与fd/cursor表，failNextRename是一次性布尔故障；`h.reload()`使用同一文件表及新的loader/Catalog实例；`h.seedAssets(ids: string[])`构造真实completed DownloadItem、提供实际mock文件/stat并调用reconcile。增加损坏分片不影响其他条目、短写失败、未知schema、OCR与标签并发、删除后旧结果拒绝、改名仍保留文字/标签、同ID实际像素替换失效、首帧/封面版本分别校验。

- [x] Step 2：运行`--filter=catalog`确认缺少服务时失败。
- [x] Step 3：实现显式DTO序列化和单写入队列，写新payload必须从当前meta/index合并，不能用分析启动时的旧meta覆盖。

```typescript
const file: fs.File = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
try {
  const bytes: ArrayBuffer = new util.TextEncoder().encodeInto(payload).buffer;
  if (fs.writeSync(file.fd, bytes) !== bytes.byteLength) { throw new Error('目录写入不完整'); }
} finally { fs.closeSync(file); }
fs.renameSync(temp, target);
```

`util`来自`@kit.ArkTS`。提交磁盘替换成功后才替换内存状态；失败删除本次temp、保留原文件并抛错。安全分片名由稳定ID编码/摘要生成，拒绝越界路径；reconcile只清理本目录下已知格式的失效ID分片。启动读取索引异步分批，索引尚未读完时通知VM展示加载状态，不能把缺失内存当无文字。

- [x] Step 4：运行catalog用例和主包构建；在原生目录测试用临时专用目录完成保存/重读/删除，finally只清理该目录。
- [x] Step 5：审阅并确认目录数据没有混入`download-state.json`。

## Task 3: 收藏、标签、组合搜索与界面

**Files:** 新建`util/LibraryText.ets`、`view/LibraryFindPanel.ets`、`view/ImageTagDialog.ets`；修改`LibraryQuery.ets`、`LibraryViewModel.ets`、`LibraryScreen.ets`、`Cards.ets`、`PreviewTools.ets`、`PreviewAsset.ets`、`DiscoverPreview.ets`、`Viewer.ets`、`Index.ets`、`EntryAbility.ets`。

**Interfaces:**
- `LibraryText.normalize(value: string): string`、`textKey(value: string): string`、`tags(values: string[]): string[]`、`snippet(text: string, query: string, limit: number = 96): string`。
- `LibraryQuery.search(items: DownloadItem[], entries: LibrarySearchEntry[], options: LibrarySearchOptions): DownloadItem[]`；原`images`签名保留给既有调用和测试。
- VM新增`searchScope/favoritesOnly/tagFilter/catalogReady`与`toggleFavorite(id)`、`changeSelectedTags(add, remove)`、`clearFilters()`、`entry(id)`。异步错误走`UiPort.say`。
- `PreviewAsset.libraryId: string`只填真实有效图库记录ID；发现页临时uid不能直接用于目录。`LibraryCatalog.assetForPreview(url, kind)`可作为同服务静态resolver，按既有最新有效原件顺序解析。

- [x] Step 1：增加查询测试，包括组合AND条件、scope隔离、原排序不变，以及`ALPHA`不在文件名时仍命中已有文字。

```javascript
caseTest('search combines OCR favorite and tag without changing order', () => {
  const a = completed('a', 'receipt-a.png'), b = completed('b', 'receipt-b.png');
  const entries = [searchEntry('a', true, ['工作'], 'INVOICEALPHA'), searchEntry('b', false, ['工作'], 'INVOICEBETA')];
  const options = new LibrarySearchOptions();
  options.scope = 'text'; options.query = 'alpha'; options.favoritesOnly = true; options.tag = '工作';
  assert.deepEqual(LibraryQuery.search([a, b], entries, options).map(x => x.id), ['a']);
});
```

`completed(id,name)`在runner构造真实DownloadItem并设置completed、batchId空、finishedAt；`searchEntry`构造上文LibrarySearchEntry并复制入参。增加标签去重/空白、仅收藏、来源/格式、空查询、Unicode标签、OCR换行词与命中片段位置、加载中与无匹配区分；修改文字条件不应偷偷清空其他筛选。

- [x] Step 2：运行`--filter=search`与标签用例，确认失败。
- [x] Step 3：实现纯查询；按id建立Map查找entry，避免每张图扫描整个目录。匹配scope为name/text/tags/all，大小写归一后逐关键词匹配；所有开启的筛选合取，最后调用原排序。

```typescript
const needle: string = value.trim().toLowerCase().replace(/\s+/g, ' ');
```

OCR文字匹配还使用textKey去除识别空白，确保“开发\n计划”可被“开发计划”找到。snippet保存规范化索引到原字符串的偏移映射，换行/大小写归一后仍截取真正命中位置；关键词中的括号、点等按普通文字匹配，不拼接未转义的正则。标签保留原展示文字，比较键使用normalize；空标签忽略，重复不新增。UI增加范围选择、收藏/标签筛选、单图工具面板与选择模式批量操作；网格文件信息显示星形状态、标签和命中片段，预览底部不加一排操作。未下载图片说明下载后整理。所有按钮采用现有Glyph系统符号与至少40vp触点。

- [x] Step 4：在EntryAbility初始化目录，在Index装配VM并订阅；异步初始化完成前显示读取状态，页面销毁注销同一监听。验证改名后仍收藏/有标签、重启可恢复，旧来源筛选和两/三列密度布局不退化。
- [x] Step 5：运行本任务用例、旧LibraryQuery原生用例、主包构建；审阅真实ID解析没有把网页uid落盘。

## Task 4: 统一静态源读取、方向与OCR引擎队列

**Files:** 新建`service/LibraryImageReader.ets`；修改`service/ImageTools.ets`；扩展`LibraryVision.test.ets`与宿主原生mock。

**Interfaces:**
- `LibraryImageReader.stamp(item: DownloadItem): Promise<AssetStamp>`选普通path、动图首帧或实况stillPath，校验可读性与源版本。
- `LibraryImageReader.info(stamp: AssetStamp): Promise<PreviewSize>`返回方向归一后的尺寸；`rgba(frame: image.PixelMap): Promise<Uint8Array>`仅用于小图特征，输出明确为非预乘RGBA，依据实际像素格式/alpha类型转换。
- `LibraryImageReader.decode(stamp: AssetStamp, region: EditRect, size: PreviewSize, editable: boolean): Promise<image.PixelMap>`；调用者负责release，服务内部ImageSource在finally释放。
- `ImageTools.withTextEngine<T>(operation: () => Promise<T>): Promise<T>`沿用现有同一个recognition队列，统一init/release；`ImageTools.textLines(frame: image.PixelMap): Promise<RecognizedLine[]>`只在该锁内调用。
- `RecognizedLine`在`LibraryAsset.ets`定义text、x、y、width、height；从SDK`result.blocks[].lines[].value/cornerPoints`转换。

- [x] Step 1：扩展既有OCR生命周期mock，增加单图识别与批量索引同时发起时只存在一个引擎；初始化false、recognize异常、取消都释放。原生测试增加EXIF 1–8的非对称四角图与透明红蓝图，先记录ImageSource和PixelMap实际方向/通道行为。

```javascript
caseTest('OCR index and preview share a single native engine', async () => {
  const h = visionHarness();
  await Promise.all([h.tools.text('/a.png'), h.tools.withTextEngine(() => h.tools.textLines(h.frame))]);
  assert.equal(h.maxActiveEngines(), 1);
  assert.equal(h.events.filter(x => x === 'init').length, h.events.filter(x => x === 'release').length);
});
```

`visionHarness()`用延迟可控的init/recognize/release mock跟踪active计数，帧/源release计数和解码选项；每实例新的loader。不能在mock中直接返回已排好坐标而跳过实际转换函数。

- [x] Step 2：运行vision宿主用例，原生先做SDK语义探针；有方向差异先修统一reader，不让三个功能各自补旋转。
- [x] Step 3：reader显式建立编码坐标到显示坐标的EXIF变换，region反变换至编码区域，解码后只应用一次方向；归一尺寸从实际解码约定得到。使用SDK确有的选项：

```typescript
const frame: image.PixelMap = await source.createPixelMap({ index: 0, editable: editable,
  desiredRegion: nativeRegion, desiredSize: nativeSize,
  desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
  cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST });
```

`nativeRegion/nativeSize`由reader内部的反变换产生，不直接把已旋转坐标传给解码器。rgba使用`readPixelsToBuffer`并验证实际格式及预乘状态，半透明红蓝夹具证明返回的是非预乘RGBA，不能直接把预乘字节当普通颜色；区域读写的PositionArea在本机SDK明确为BGRA，后续标注不得按RGBA解释。

- [x] Step 4：原来的`ImageTools.text(path)`改用withTextEngine组织，保留原有单图行为和现有宿主用例；textLines不二次排队导致死锁。检查所有错误路径finally释放。
- [x] Step 5：运行新旧OCR宿主用例、主包和测试包构建，确认方向/通道原生用例通过再提供reader给后续任务。

## Task 5: 分块OCR索引、覆盖状态与内容检索

**Files:** 新建`service/LibraryAnalysis.ets`；扩展`LibraryText.ets`、`LibraryAsset.ets`、`LibraryViewModel.ets`、`LibraryFindPanel.ets`、`PreviewTools.ets`和测试。

**Interfaces:**
- `AnalysisToken`定义generation/cancelled和`cancel(): void`，每次用户启动新实例，定义在LibraryAsset中，后续任务统一导入：

```typescript
export class AnalysisToken {
  generation: number = 0;
  cancelled: boolean = false;
  cancel(): void { this.cancelled = true; this.generation++; }
}
```
- `LibraryAnalysis.ocr(items: DownloadItem[], force: boolean, token: AnalysisToken, progress: (value: AnalysisProgress) => void): Promise<void>`。
- `LibraryText.tiles(width: number, height: number): EditRect[]`和`mergeLines(lines: RecognizedLine[]): string`；tile两轴最大2048原始像素、重叠128，末块覆盖到边；每次只解码/识别一块。
- VM提供`startOcr(scope: string, force: boolean)`、`cancelAnalysis()`、`retryFailedOcr()`、`clearTextIndex()`；scope是selected/current/all且默认current。当前结果在启动时快照，不能因已识别结果改变搜索范围而使任务不断变动。

- [x] Step 1：测试长图tiles完全覆盖上/中/下、接缝同一行只合并一次、相同词在不同位置不能被全局Set误删，及取消/改图/删除/改标签交错。

```javascript
caseTest('OCR cancellation cannot overwrite new tags or resurrect a deleted asset', async () => {
  const h = analysisHarness();
  const running = h.startOcr(['a']);
  await h.waitUntilRecognizing();
  await h.catalog.changeTags(['a'], ['新标签'], []);
  h.removeAsset('a'); h.token.cancel(); h.finishRecognition('OLDTEXT');
  await running;
  assert.equal(h.catalog.getIndex('a'), undefined);
  assert.equal(h.visibleIds().includes('a'), false);
});
```

`analysisHarness()`由Task 2 catalogHarness和Task 4 visionHarness组合；暴露固定DownloadItem集合、可完成的识别Promise、AnalysisToken及当前目录查询。`removeAsset`先更新活动ID再reconcile；`visibleIds`返回该集合，不能根据测试预期硬编码。

- [x] Step 2：运行`--filter=OCR`确认失败。
- [x] Step 3：在withTextEngine中串行处理tiles，块坐标映射回原图，重复判定同时要求归一文本相同和空间框显著重叠。拼接按上到下、同一行左到右；保留不同位置的重复词。每块完成检查token和实际源版本，finally释放帧；每个资产结束立即putIndex，取消保留先前已确认条目。

```typescript
if (token.cancelled || !LibraryAnalysis.sameStamp(before, after)) { return; }
index.text = LibraryText.mergeLines(lines);
index.ocrStatus = index.text.length > 0 ? 'ready' : 'empty';
await LIBRARY_CATALOG.putIndex(index);
```

`sameStamp(a: AssetStamp,b: AssetStamp): boolean`在LibraryAnalysis定义，对id/sourceKind/bytes/modified/orientation以及已知relocate后的path比较；校验失败不能只写一个新的stamp继续提交旧文本。空结果、失败和未处理状态分开。

- [x] Step 4：UI展示数量、覆盖状态、当前进度、取消/继续/重试/重建/清空文字；操作前确认scope数量。单图识别同样保存到真实libraryId的索引，网页临时预览仍只展示识别结果。
- [x] Step 5：运行OCR与search测试、主包构建；真实模拟器原生OCR验收留Task 13，当前不能标成功识别。

## Task 6: 视觉特征与相似分组纯算法

**Files:** 新建`util/PerceptualHash.ets`；扩展`LibraryAsset.ets`、宿主与`LibraryVision.test.ets`。

**Interfaces:** `PerceptualHash.feature(rgba: Uint8Array, width: number, height: number): VisualFeature`、`distance(a: string,b: string): number`、`matches(a: VisualFeature,b: VisualFeature): boolean`、`groups(ids: string[], features: Map<string,VisualFeature>): SimilarGroup[]`。

输入严格为32×32非预乘RGBA样本，feature.width/height随后填方向归一的原尺寸。透明颜色先合成白色计算低频/梯度，同时保留实际alpha均值。低频为32×32灰度DCT的8×8区域，去DC，以非DC均值形成64位；梯度由9×8灰度采样的水平差生成64位。不引入OpenCV、不复制其源码。

- [x] Step 1：写实际像素数组测试，覆盖缩放/压缩样例、颜色、透明、线稿、参数畸形和非传递分组。

```javascript
caseTest('similar feature rejects different flat colors', () => {
  const red = PerceptualHash.feature(solidRgba(255, 0, 0, 255), 32, 32);
  const blue = PerceptualHash.feature(solidRgba(0, 0, 255, 255), 32, 32);
  red.width = blue.width = 800; red.height = blue.height = 600;
  assert.equal(PerceptualHash.matches(red, blue), false);
});
```

`solidRgba`真实填充32×32×4字节。`distance`测试空串/长度错误应拒绝，不能把坏特征当距离0。非传递组使用人工64位特征A/B/C满足AB与BC近、AC远，断言组代表与每个成员都匹配。

- [x] Step 2：运行`--filter=similar`确认失败。
- [x] Step 3：实现DCT/梯度和确定性代表图分组，初始门槛为lowBits≤8、edgeBits≤10、宽高比相对差≤5%、三通道平均差各≤20、alpha均值差≤16（均为0–255量纲）；所有特征先检验版本与长度；不合法特征返回不匹配，distance对非64位输入返回大于64的哨兵值或明确抛错，不能默认为0。

```typescript
let distance: number = 0;
for (let index: number = 0; index < 64; index++) {
  if (a.charAt(index) !== b.charAt(index)) { distance++; }
}
return distance;
```

组代表使用稳定ID顺序，后续成员必须与代表匹配；不得用连通分量把间接相似自动合并。低频/梯度计算的灰度权重固定为0.299/0.587/0.114；均值特征保留统一0–255量纲，matches按上述像素量纲比较。算法变动提升version。

- [x] Step 4：用自制独立正负样本校准，记录输入SHA与距离，不能凭fixture文件名识别；出现误组先修算法或阈值并保留反例测试。
- [x] Step 5：运行算法测试和主包构建，确认完全重复字节检查代码仍独立存在。

## Task 7: 相似分析任务、缓存与结果界面

**Files:** 扩展`LibraryAnalysis.ets`、`LibraryViewModel.ets`；新建`view/LibrarySimilarPanel.ets`；修改`LibraryScreen.ets`及测试。

**Interfaces:** `LibraryAnalysis.similar(items: DownloadItem[], token: AnalysisToken, progress: (value: AnalysisProgress)=>void): Promise<SimilarGroup[]>`；VM提供`startSimilar(scope)`、`openSimilarGroup(group)`，后者用`UiPort.openViewer(first,true,group.ids)`复用预览及双图对比。

- [x] Step 1：通过analysisHarness测试复用有效特征不再解码、已变更文件重算、取消分组不回写旧结果、清除OCR文字仍保留有效视觉特征。

```javascript
caseTest('similar scan reuses features but recomputes changed file', async () => {
  const h = analysisHarness();
  await h.runSimilar(['a', 'b']);
  const first = h.decodeCount();
  await h.runSimilar(['a', 'b']);
  assert.equal(h.decodeCount(), first);
  h.changeFile('b');
  await h.runSimilar(['a', 'b']);
  assert.equal(h.decodeCount(), first + 1);
});
```

`runSimilar`调用真实LibraryAnalysis.similar；`changeFile`更新mock实际文件stat/像素版本，不能只改期望计数。

- [x] Step 2：运行similar分析用例确认失败。
- [x] Step 3：使用统一reader解码32×32、经reader.rgba读取真实非预乘RGBA数组、释放frame，创建feature并填原始方向尺寸。资产级缓存后才分组；每128次比较yield一次timer并检查token，避免阻塞UI。动态媒体标明首帧/封面，缺失封面计为失败而不是解码livp包。

```typescript
await new Promise<void>((resolve): void => { setTimeout(resolve, 0); });
if (token.cancelled) { return []; }
```

- [x] Step 4：候选组显示代表图、成员名/尺寸、查看本组；仅用户点击后打开，不自动删文件。保留同URL、同文件名与内容一致三项旧结果。
- [x] Step 5：运行分析/分组测试与主包构建，审阅当前筛选快照、取消和数据变化后的失效逻辑。

## Task 8: 编辑文档、裁剪旋转、历史与坐标变换

**Files:** 新建`util/ImageEditGeometry.ets`；扩展`model/ImageEditDocument.ets`；添加宿主与`ImageEdit.test.ets`。

**Interfaces:**
- `ImageEditGeometry.create(width,height): EditDocument`、`copy(doc): EditDocument`、`outputSize(doc): PreviewSize`。
- `toOutput(point: EditPoint,doc: EditDocument): EditPoint`、`toSource(point: EditPoint,doc: EditDocument): EditPoint`；点表示像素中心，连续UI点在最终采样时取整。
- `constrainCrop(rect: EditRect,width:number,height:number): EditRect`、`aspectCrop(doc:EditDocument,ratio:number): EditRect`；ratio=0表示原始比例，其他使用1或4/3。
- `EditHistory`在ImageEditDocument定义`reset(doc)`、`commit(doc)`、`undo(): EditDocument | undefined`、`canUndo(): boolean`，保存独立快照。

- [x] Step 1：用独立oracle写精确测试，不能仅验证forward/inverse彼此抵消。

```javascript
caseTest('edit crop then clockwise turn follows pixel oracle', () => {
  const doc = ImageEditGeometry.create(800, 600);
  doc.crop.x = 100; doc.crop.y = 50; doc.crop.width = 400; doc.crop.height = 300; doc.turns = 1;
  assert.deepEqual(ImageEditGeometry.outputSize(doc), { width: 300, height: 400 });
  assert.deepEqual(ImageEditGeometry.toOutput({x: 200, y: 150}, doc), {x: 199, y: 100});
  assert.deepEqual(ImageEditGeometry.toSource({x: 259, y: 40}, doc), {x: 140, y: 90});
});
```

增加0/1/2/3转、反向拖动、越界、零尺寸、不合法数值、裁剪后再次旋转、撤销文档与stroke.points不共享可变引用、横屏视口只改view映射不改原图文档。

- [x] Step 2：运行`--filter=edit geometry`确认失败。
- [x] Step 3：实现裁剪绑定原图坐标、turns归一0–3、标注点和宽度使用原图像素；CW一次的核心映射为：

```typescript
const localX: number = point.x - doc.crop.x;
const localY: number = point.y - doc.crop.y;
return { x: doc.crop.height - 1 - localY, y: localX };
```

完整分支覆盖0/90/180/270，所有裁剪必须有至少1×1有效像素；预览的fit/letterbox另用显式view矩形处理，不能把留白区当图像。历史至少保留最近100个已提交操作，绘制中临时Move不逐点推入撤销栈。

- [x] Step 4：运行精确oracle与原生纯几何用例、主包构建；确认恢复全图不丢已有标注的原图坐标。
- [x] Step 5：审阅所有UI回调只传原图几何，后续renderer/exporter共用此契约。

## Task 9: 原始像素导出与有界标注写入

**Files:** 新建`util/EditRasterizer.ets`、`service/EditExport.ets`；扩展`ImageEdit.test.ets`、宿主测试。

**Interfaces:**
- `EditRasterizer.paintBgra(buffer: Uint8Array, tile: EditRect, doc: EditDocument, premultiplied: boolean): void`；buffer是已旋转输出空间中该tile的BGRA像素，alpha语义显式传入。
- `EditExport.render(stamp: AssetStamp, doc: EditDocument, pendingPath: string, token: AnalysisToken): Promise<EditResult>`；不登记图库，不覆盖文件；失败删除本次pending，释放frame/packer/source。

- [x] Step 1：宿主验证笔线/矩形只改覆盖区域、透明/半透明未覆盖像素不变、半透明笔迹边缘正确混合、红蓝不交换；原生用精确编辑图验证尺寸与角颜色。

```javascript
caseTest('edit BGRA paint changes red source to blue only on stroke', () => {
  const doc = oracleDocument();
  doc.strokes = [oracleBlueStroke()];
  const tile = { x: 198, y: 99, width: 3, height: 3 };
  const pixels = new Uint8Array(36);
  for (let i = 0; i < 36; i += 4) { pixels[i + 2] = 255; pixels[i + 3] = 255; }
  EditRasterizer.paintBgra(pixels, tile, doc, true);
  assert.deepEqual([...pixels.slice(16, 20)], [255, 0, 0, 255]);
});
```

`oracleDocument`严格构造Task 8的800×600裁剪/旋转文档；`oracleBlueStroke`为原图(200,150)处宽3、蓝色单点，两个helper放在runner中且供相应用例调用。

- [x] Step 2：运行`--filter=edit BGRA`确认失败。
- [x] Step 3：render使用reader读取精确crop原尺寸、editable=true；应用用户turns；遍历与标注相交的最多256×256输出tile，readPixels/paintBgra/writePixels，额外buffer每块最多256KiB。不能把整幅图读回第二份JS缓冲，也不能用预览Canvas导出代替原尺寸。

```typescript
const area: image.PositionArea = { pixels: buffer, offset: 0,
  stride: tile.width * 4,
  region: { x: tile.x, y: tile.y, size: { width: tile.width, height: tile.height } } };
await frame.readPixels(area);
EditRasterizer.paintBgra(new Uint8Array(buffer), tile, doc, premultiplied);
await frame.writePixels(area);
```

premultiplied由Task 4已验证的原生区域缓冲语义和PixelMap alpha类型确定，每次导出读取一次元信息。BGRA图层颜色按SDK契约写入；混合在预乘色域完成，再按目标alpha语义写回；只对真正被笔迹覆盖的像素计算，未覆盖像素逐字节不动，避免整块反复预乘/反预乘损伤半透明底图。矩形只画边不填内；画笔段按点到线段距离和半径覆盖，不只连接稀疏点导致断笔。只处理与标注包围盒相交的tile。

- [x] Step 4：packToFile PNG，关闭后重新getImageInfo核对预期尺寸与正字节数；失败返回可展示错误，原件SHA不变，内存不足不静默缩图。token取消须在每块之间与编码后检查。
- [x] Step 5：运行像素纯测试和模拟器原生ImageEdit用例：四角颜色、alpha=0点、蓝色点、黑框边与红色内部；附原图前后SHA。

## Task 10: 副本登记与中断恢复

**Files:** 新建`service/EditJournal.ets`；修改`DownloadStore.ets`、`TasksViewModel.ets`、Catalog整合、`TasksViewModel.test.ets`和相关原生/宿主测试。

**Interfaces:**
- `EditJournal.prepare(filesDir:string,id:string,originalId:string): Promise<EditTicket>`、`finalize(ticket:EditTicket,result:EditResult): Promise<void>`、`finish(ticket): Promise<void>`、`rollback(ticket): Promise<void>`、`recover(filesDir:string,items:DownloadItem[]):Promise<void>`。
- `EditTicket`在ImageEditDocument定义id/originalId/pendingPath/finalPath/journalPath；所有路径必须属于专用`filesDir/edits`并有本功能生成的受控前缀。
- `DownloadStore.registerEdited(sourceId:string,ticket:EditTicket,result:EditResult): Promise<DownloadItem>`；登记origin=edited、originalId=sourceId、url空、kind=image、animated=false、status=completed、batchId/taskId空。

- [x] Step 1：registrationHarness使用真实DownloadStore登记函数和memoryFs，注入save短写/rename失败；同时测试转正后崩溃与登记后崩溃的恢复。

```javascript
caseTest('edited registration failure rolls back only its new file', async () => {
  const h = registrationHarness();
  const originalHash = h.hash('/files/images/original.png');
  const ticket = await h.prepareCopy('a');
  h.failStateWrite();
  await assert.rejects(h.registerCopy('a', ticket));
  assert.equal(h.hash('/files/images/original.png'), originalHash);
  assert.equal(h.items().filter(x => x.origin === 'edited').length, 0);
  assert.equal(h.exists(ticket.finalPath), false);
});
```

`registrationHarness`组合catalogHarness文件表与现有DownloadStore native mocks，`hash`用Node SHA-256读取mock实体字节，不能只比较名称；`prepareCopy/registerCopy`分别调用上述真实API。增加重复登记同ticket幂等、源已删、无关文件不删除、已登记副本journal残留只删journal、原URL优先仍返回原件、任务页排除副本。

- [x] Step 2：运行`--filter=edited registration`及recovery用例确认失败。
- [x] Step 3：prepare先写小日志，render输出pending，finalize校验路径和文件再转正；register同步持久化成功后才emit成功。不能仅调用会吞错的notify后就宣称成功：使用显式保存结果或检查saveProblem，在失败时撤回本次记录并rollback。

```typescript
item.origin = 'edited'; item.originalId = sourceId; item.url = '';
item.path = ticket.finalPath; item.kind = 'image'; item.animated = false;
item.status = 'completed'; item.size = result.bytes;
```

名称通过Naming.clean/uniqueName生成带编辑后缀的PNG；sourcePage继承，标签在独立目录中复制，favorite默认false，索引空。跨文件提交成功后清journal；启动recover只根据受控日志与当前记录判断，不扫描删除整个images目录。

- [x] Step 4：TasksViewModel只把origin不是edited的记录纳入任务列表/清理入口；图库及占用仍包括副本。检查WidgetSnapshot活动计数无需把completed副本计为任务。原件删除与副本删除互不级联。
- [x] Step 5：运行身份迁移、LocalPreview、TasksViewModel、WidgetSnapshot相关用例及主包构建，审阅所有删除路径。

## Task 11: 编辑页、画布操作与草稿状态

**Files:** 新建`ImageEditorViewModel.ets`、`ImageEditorCanvas.ets`、`pages/ImageEditor.ets`；修改`UiPort.ets`、`PreviewTools.ets`、`Viewer.ets`、`DiscoverPreview.ets`、`Index.ets`、`main_pages.json`。

**Interfaces:**
- VM：`load(itemId:string):Promise<void>`、`setCrop(rect)`、`setAspect(ratio)`、`rotate()`、`addStroke(stroke)`、`undo()`、`clearStrokes()`、`restoreCrop()`、`save():Promise<void>`、`cancel():void`、`hasChanges:boolean`。
- 画布入参stamp/document/tool/color/width，事件`onCrop(rect:EditRect)`、`onStroke(stroke:EditStroke)`；原图坐标传给VM，PixelMap和临时Move点留在组件内。
- `ImageEditorPort`定义在`model/ImageEditDocument.ets`，VM通过`attach(port: ImageEditorPort): void`接入，页面先attach后load；不在构造字段初始化时取UIContext。

```typescript
export interface ImageEditorPort {
  source(id: string): Promise<AssetStamp>;
  info(stamp: AssetStamp): Promise<PreviewSize>;
  exportAndRegister(id: string, doc: EditDocument, token: AnalysisToken): Promise<DownloadItem>;
  showError(message: string): void;
  finish(newId: string): void;
}
```

`AssetStamp/AnalysisToken`从LibraryAsset导入，PreviewSize从现有PreviewGeometry导入，DownloadItem从Models导入。Runtime port在页面装配实现该接口，核心VM不依赖UI层。

- 路由params仅真实itemId。`UiPort.openImageEditor(id:string):void`由Index注入；Viewer工具可使用当前UIContext路由，不在VM使用全局router或断言。

- [x] Step 1：editorHarness注入真实VM及可控reader/export/register，测试重复点保存只登记一次、取消不登记、失败保留草稿、无更改退出不提示、修改后退出继续编辑/放弃。（核心保存测试及模拟器退出确认通过）

```javascript
caseTest('editor saves once and keeps draft after export failure', async () => {
  const h = editorHarness();
  await h.vm.load('a'); h.vm.rotate();
  h.failNextExport();
  await h.vm.save();
  assert.equal(h.vm.hasChanges, true);
  assert.equal(h.registerCount(), 0);
  await Promise.all([h.vm.save(), h.vm.save()]);
  assert.equal(h.registerCount(), 1);
});
```

`editorHarness`先通过attach注入上面定义的`ImageEditorPort`接口；生产port装配Task 4/9/10真实函数，测试port记录调用并控制失败，无UIContext/PixelMap穿过该接口。

- [x] Step 2：运行`--filter=editor saves`确认失败。
- [x] Step 3：VM修改采用新文档快照，保存期间禁用重复提交；renderer解码底图≤300万像素，缩放至画布实际大小。手势命中四角/范围移动/画笔/矩形分别处理；逆变换跳过图像留白区，绘制结束一次性提交stroke。

```typescript
if (this.saving) { return; }
this.saving = true;
try {
  const copy: DownloadItem = await this.port.exportAndRegister(this.itemId, this.document, this.token);
  this.port.finish(copy.id);
} catch (error) {
  this.port.showError('保存失败，编辑内容已保留，请重试');
} finally { this.saving = false; }
```

`ImageEditorPort.exportAndRegister`返回新DownloadItem；成功后port.finish(newId)使图库刷新并可预览副本。错误保留document，不向UI事件泄漏未处理Promise；未attach时load明确报未就绪而非访问undefined。

- [ ] Step 4：工具面板显示静图“编辑副本”、动图“编辑首帧副本”、实况“编辑封面副本”；无有效本地原件显示下载后编辑原因。裁剪自由/原比例/1:1/4:3、90°旋转、红蓝黑画笔/矩形、宽度、撤销、清空和保存都能在竖/横屏操作。（静图、GIF/WebP、四角/1:1/旋转/蓝笔/黑框、竖横屏实测；缺有效 Live Photo 夹具，未全覆盖）
- [x] Step 5：新增路由`pages/ImageEditor`；系统返回与顶部返回使用同一草稿退出逻辑。构建并准备模拟器手势验收，不能只截图看到按钮就计为通过。

## Task 12: 生命周期、删除和并发回归

**Files:** 修改`EntryAbility.ets`、`Index.ets`、`LibraryViewModel.ets`、Catalog/Analysis、DownloadStore与编辑页；扩展宿主/原生测试。

**Interfaces:** VM统一`cancelAnalysis()`递增token；Catalog.reconcile始终接收当前有效记录快照；应用后台/离开图库/进入编辑停止接纳旧分析。恢复由用户继续，不在启动时自动OCR。

- [x] Step 1：添加交错测试：标签修改与OCR返回、原图改名/删除与相似结果返回、暂停中原图替换、编辑保存中源文件删除、清空图库但不删除已导出副本。

```javascript
caseTest('background cancellation ignores late analysis while keeping confirmed entries', async () => {
  const h = analysisHarness();
  await h.indexFirstAsset('a');
  const running = h.startOcr(['b']); await h.waitUntilRecognizing();
  h.background(); h.finishRecognition('LATE'); await running;
  assert.equal(h.catalog.getIndex('a').ocrStatus, 'ready');
  assert.equal(h.catalog.getIndex('b'), undefined);
});
```

`indexFirstAsset`通过真实ocr任务建立第一条，`background`触发生产相同VM取消方法；不能仅让mock返回cancelled而跳过代次检查。

- [x] Step 2：运行对应过滤用例确认失败，再连接现有生命周期入口；不更改旧预览前后台恢复、GIF手动暂停和原URL优先规则。
- [x] Step 3：删除/clearAll使目录与结果即时排除相应ID，磁盘清理失败可重试，启动再对照实际记录；rename使用relocate保留同一源身份。副本与原件保持独立，编辑pending恢复在主状态载入后执行。

```typescript
this.analysisToken?.cancel();
this.analysisGeneration++;
this.analyzing = false;
```

- [x] Step 4：运行全部本轮宿主测试和原有test-workflows，构建主包/测试包并跑StoreState原生往返及旧图库任务用例。（宿主 81/81、既有流程 92/92、原生 143/143）
- [x] Step 5：审阅注册/注销监听是同一函数引用，所有晚到native帧finally释放，不把产品状态、识别文本或用户路径打印到常规日志。

## Task 13: 固定夹具、原生测试与模拟器全流程

**Files:** 创建`entry/src/ohosTest/resources/rawfile/library-enhancements/`内受控测试图及manifest、`scripts/make-library-fixtures.cjs`；扩展三个新原生测试并注册`List.test.ets`；创建`docs/image-library-enhancements-acceptance.md`。测试夹具放ohosTest，不进生产资源。

**Interfaces:** manifest记录caseId/name/尺寸/SHA/预期短语或采样像素。生成器使用现有本机可用运行时和图像工具；先确认依赖，不能未经确认安装大型系统组件。原生runner只读取本轮测试目录，输出caseId/结果，不输出真实用户OCR文本。

- [x] Step 1：按独立oracle生成中英截图、长图、空白、相似正负样本、透明图、编辑四角图、EXIF1–8样例；校验manifest与实际文件摘要、尺寸一致。
- [x] Step 2：构建并运行全部宿主测试，主包与测试包构建；复制为不可变包并记录SHA。测试入口使用项目确有的`OpenHarmonyTestRunner.ets`与既有List注册。

```bash
node scripts/test-library-enhancements.cjs > /tmp/image-library-enhancements-20261026/host-tests.log 2>&1
node scripts/test-workflows.cjs > /tmp/image-library-enhancements-20261026/regression-tests.log 2>&1
bash scripts/build.sh assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug > /tmp/image-library-enhancements-20261026/main-build.log 2>&1
bash scripts/build.sh assembleHap --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug > /tmp/image-library-enhancements-20261026/test-build.log 2>&1
cp entry/build/default/outputs/default/entry-default-signed.hap /tmp/image-library-enhancements-20261026/library-main.hap
cp entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap /tmp/image-library-enhancements-20261026/library-test.hap
shasum -a 256 /tmp/image-library-enhancements-20261026/library-main.hap /tmp/image-library-enhancements-20261026/library-test.hap
```

- [x] Step 3：验证代理重新读取模拟器目标、模块、现有JSON、文件清单及设置并备份；准备记录21/3/13/1只作旧参考，不能覆盖后续新增用户数据。只对明确模拟器目标安装固定包，记录安装返回与启动PID。

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t 127.0.0.1:5555 install -r /tmp/image-library-enhancements-20261026/library-main.hap
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t 127.0.0.1:5555 install -r /tmp/image-library-enhancements-20261026/library-test.hap
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t 127.0.0.1:5555 shell "aa test -b com.example.imagedownloader -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000"
```

此命令只在确认目标仍是模拟器后执行；若OCR原生套件确需更长时间，以实测单例时长设置明确timeout并记录原因，不把观察超时当测试终止后重新启动第二份。

- [x] Step 4：实际操作OCR建立/取消/重试、三个长图短语检索、收藏/标签组合/批量/改名/重启、相似组预览与双图对比、编辑四角拖动/范围移动/比例/旋转/画笔/矩形/撤销/清空/放弃/保存；竖屏、横屏及长文件名均检查布局和触点。模拟器覆盖非 OCR 成功路径，真机补齐短图与长图顶中尾的实际系统识别和搜索；分设备证据见验收报告。
- [x] Step 5：取回本轮输出副本，独立解码核对尺寸、四角/alpha/蓝点/黑框像素；比较原图前后SHA。保存副本后验证图库立即显示、重启仍在、普通文件操作可用且原URL仍取原件；见模拟器最终设备报告。
- [x] Step 6：真机实际系统OCR结果包含预期中英文短语，短图4项正确、长图顶中尾6项均包含；空白图独立标记无文字，未预填索引。真机服务、识别结果、查询与重启证据见真机报告。模拟器原 init 失败仍保留为设备限制；长图中段存在近似重复误识别。
- [ ] Step 7：性能记录说明场景与采样时机，检查长图索引/保存后资源释放，避免把PixelMap输出预算写成进程峰值保证。只在明确发现问题时扩大验证，不重复无关全量操作。（本轮真机没有采集峰值/PSS，不能声称通过定量性能验收；功能交互与结果已独立验证。）
- [x] Step 8：报告每项为通过/部分验证/未覆盖，写明实际包版本、测试总数、失败/修复和结果；未完成项继续保留在目标中。

## Task 14: 最终复核、恢复与交付

**Files:** 限定复核本轮新增/修改文件；更新`README.md`和`AGENT.md`相关结构说明，完成验收报告与本文checkbox。

**Interfaces:** Native执行选项要求一次新的独立整体代码复核；子代理选项要求逐任务复核加最终整体复核。验证代理继续独占模拟器，不与复核者并行触摸。

- [x] Step 1：独立复核覆盖持久化、来源身份、取消/并发、EXIF/alpha/BGRA、编辑几何/输出和路径清理；逐项处理发现并针对修复重跑相关测试。不得因为已有构建绿色忽略代码发现。
- [x] Step 2：与设计逐项对照：四项功能、全部子能力和设备证据分别列入验收矩阵；模拟器缺失的系统OCR成功路径已由真机实际识别和搜索补齐。Live Photo 封面入口、独立副本与重启已补验；长图识别准确性边界已记录。
- [x] Step 3：验证代理停止本轮任务，清理本轮fixture下载、编辑副本、索引、标签/收藏变更、历史、pending文件、截图/临时转发和本轮服务。按操作前新基线恢复原记录、原文件与设置；原先存在的测试模块不得当作本轮新模块盲目卸载。
- [x] Step 4：最终固定主包保留在模拟器，确认正常启动；对照原数据、目录与文件摘要，报告模块处理情况和任何无法完全恢复的项目，不使用模糊“已全部清理”。
- [x] Step 5：记录构建包SHA与最后一次必要构建/测试证据；`git diff --check`通过；Git保持未暂存未提交。真机安装包SHA和保留数据安装回执已记录。
- [x] Step 6：四项功能已有宿主测试、模拟器交互和真机OCR成功路径的对应证据；交付时分别说明模拟器系统服务缺失、真机长图一次近似重复识别和未测性能峰值，不将设备证据混同。

## 宿主测试基础代码

下列代码放入`test-library-enhancements.cjs`，并从新loader模块导入`loader`。它定义上述示例用到的通用fixture helper；任务特有的catalog/vision/analysis/registration/editor harness按各任务的明确真实服务与native mock契约实现，不使用真实用户数据。

```javascript
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loader } = require('./lib/arkts-test-loader.cjs');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'entry/src/main/ets');
const ets = name => path.join(source, name + '.ets');
const filterArg = process.argv.find(value => value.startsWith('--filter='));
const filter = filterArg ? filterArg.slice('--filter='.length) : '';
const caseTest = (name, run) => { if (!filter || name.includes(filter)) test(name, run); };
const load = loader();
const { DownloadItem } = load(ets('model/Models'));
const { LibrarySearchOptions, LibrarySearchEntry } = load(ets('model/LibraryAsset'));
const { LibraryQuery } = load(ets('service/LibraryQuery'));
const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
const { PerceptualHash } = load(ets('util/PerceptualHash'));
const { EditRasterizer } = load(ets('util/EditRasterizer'));
function completed(id, name) {
  const item = new DownloadItem();
  item.id = id; item.name = name; item.path = '/files/images/' + name;
  item.status = 'completed'; item.finishedAt = 100; item.batchId = '';
  return item;
}
function searchEntry(id, favorite, tags, text) {
  const entry = new LibrarySearchEntry();
  entry.id = id; entry.favorite = favorite; entry.tags = tags.slice();
  entry.text = text; entry.ocrStatus = 'ready';
  return entry;
}
function solidRgba(red, green, blue, alpha) {
  const pixels = new Uint8Array(32 * 32 * 4);
  for (let offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = red; pixels[offset + 1] = green;
    pixels[offset + 2] = blue; pixels[offset + 3] = alpha;
  }
  return pixels;
}
function oracleDocument() {
  const doc = ImageEditGeometry.create(800, 600);
  doc.crop.x = 100; doc.crop.y = 50; doc.crop.width = 400; doc.crop.height = 300;
  doc.turns = 1;
  return doc;
}
function oracleBlueStroke() {
  const { EditStroke, EditPoint } = load(ets('model/ImageEditDocument'));
  const stroke = new EditStroke(); stroke.kind = 'pen'; stroke.color = '#0000FF'; stroke.width = 3;
  const point = new EditPoint(); point.x = 200; point.y = 150; stroke.points = [point];
  return stroke;
}
```

按任务逐步加入相应require/load，不能在Task 1就载入还未创建的Task 8/9模块；测试注册失败应由缺少当前任务能力产生，不能被无关未来模块导入打断。原生测试同样使用真实class实例，并以当前套件已有Hypium模式组织。

## 计划自审

- 范围映射：OCR=Tasks 2/4/5/13；相似图=2/4/6/7/13；收藏标签=2/3/12/13；编辑=1/4/8/9/10/11/12/13；模拟器与恢复=13/14。
- 明确处理：索引加载未完成、标签/分析并发、首帧/封面身份、EXIF镜像方向、无文字/失败/取消、格式和来源组合、原图不变、BGRA通道、原尺寸输出、重复保存、状态写入失败、崩溃pending恢复、原/副本独立删除。
- 无自动提交；生产代码、测试夹具和模拟器操作均尚未开始。
- 待用户审阅本计划并选择执行方式后，按对应技能执行；现有设计确认不冒充尚未审阅的实现计划确认。
