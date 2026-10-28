/**
 * 设置页里所有「语义 id + 界面名」的选项表。
 *
 * 原先这些表和查表函数（choiceOf / choiceIndex / choiceLabels）都长在 Index 组件里，
 * 主题、材质类型、材质等级、下载位置、下载图片质量五行各查一遍，页面一改就要动组件。
 * 现在收敛成一张 **ChoiceSet**（表 + 默认项 + 三种查询），组件只拿到「当前该显示哪一项」。
 *
 * 这是**享元**意义的共享：五张表在模块加载时各建一次，界面只读，不复制。
 */

/** 一个选项：`id` 是落盘的语义值，`label` 是界面上给用户看的名字。 */
export interface ChoiceOption {
  id: string;
  label: string;
}

/**
 * 选项表：一组 `ChoiceOption` 加一个默认项 id。
 *
 * 三件事在这里一次做完，调用方不必知道表长什么样：
 * - `option(id)`：id → 选项；状态文件里是旧值 / 脏值时退回默认项，永不返回 undefined；
 * - `index(id)`：id → 下标，直接交给 ArkUI `Select` 的 `selected`；
 * - `selectOptions()`：表 → `Select` 要的 `{ value }` 列表（**适配器**，把领域选项适配成控件入参）。
 */
export class ChoiceSet {
  private items: ChoiceOption[] = [];
  private fallbackId: string = '';
  /**
   * `selectOptions()` 的缓存。
   *
   * 这个返回值每次 build 都会被读一次（五个下拉各一次），而它只取决于构造时固定的表，
   * 所以算一次就够；顺便让子组件拿到的是**同一个数组引用**，不至于每帧都注入一个新数组。
   */
  private cachedSelect: SelectOption[] = [];

  constructor(items: ChoiceOption[], fallbackId: string) {
    this.items = items;
    this.fallbackId = fallbackId;
  }

  size(): number {
    return this.items.length;
  }

  /** 下标对应的选项；越界时退回默认项，调用方不用自己判越界。 */
  at(index: number): ChoiceOption {
    if (index < 0 || index >= this.items.length) {
      return this.option(this.fallbackId);
    }
    return this.items[index];
  }

  option(id: string): ChoiceOption {
    for (const item of this.items) {
      if (item.id === id) {
        return item;
      }
    }
    for (const item of this.items) {
      if (item.id === this.fallbackId) {
        return item;
      }
    }
    return this.items[0];
  }

  index(id: string): number {
    const target: ChoiceOption = this.option(id);
    for (let i: number = 0; i < this.items.length; i++) {
      if (this.items[i] === target) {
        return i;
      }
    }
    return 0;
  }

  label(id: string): string {
    return this.option(id).label;
  }

  /** 这个 id 是不是表里认识的一档（用来区分「用户选的」和「旧版本 / 脏值」）。 */
  has(id: string): boolean {
    for (const item of this.items) {
      if (item.id === id) {
        return true;
      }
    }
    return false;
  }

  /**
   * 认不出的值退回默认档的 id。
   *
   * 存盘文件可能是旧版本写的、也可能被人改过；**判据只有这张表**，所以「哪些档位合法」
   * 永远只有一个答案（原来这段逻辑散在 `DownloadStore.normalizeQuality` 里）。
   */
  normalize(id: string): string {
    return this.has(id) ? id : this.fallbackId;
  }

  selectOptions(): SelectOption[] {
    if (this.cachedSelect.length === 0) {
      const options: SelectOption[] = [];
      for (const item of this.items) {
        const option: SelectOption = { value: item.label };
        options.push(option);
      }
      this.cachedSelect = options;
    }
    return this.cachedSelect;
  }
}

/** 主题：跟随系统 / 浅色 / 深色，第一项就是默认项。 */
const THEME_ITEMS: ChoiceOption[] = [
  { id: 'system', label: '跟随系统' },
  { id: 'light', label: '浅色' },
  { id: 'dark', label: '深色' }
];
export const THEME_CHOICES: ChoiceSet = new ChoiceSet(THEME_ITEMS, 'system');

/**
 * 材质类型，取值对应 hdsMaterial.MaterialType
 * （NONE=0 无材质效果 / ADAPTIVE=100 自适应 / IMMERSIVE=101 沉浸式），
 * 见 ui-design-hdsmaterial#materialtype。
 *
 * 文档说 ADAPTIVE 默认就按沉浸式材质生效，所以默认档位仍是 ADAPTIVE；
 * 「无材质效果」放最后，它是关掉材质，不是一档效果。
 */
const MATERIAL_TYPE_ITEMS: ChoiceOption[] = [
  { id: 'adaptive', label: '自适应' },
  { id: 'immersive', label: '沉浸式' },
  { id: 'none', label: '无材质效果' }
];
export const MATERIAL_TYPES: ChoiceSet = new ChoiceSet(MATERIAL_TYPE_ITEMS, 'adaptive');

/**
 * 沉浸光感材质等级，取值对应 hdsMaterial.MaterialLevel
 * （EXQUISITE=0 精美 / GENTLE=1 轻柔 / SMOOTH=2 流畅 / ADAPTIVE=10 自适应）。
 * 顺序与系统设置里的下拉一致：三个手动档位在前，跟随系统的「自适应」在后。
 */
const MATERIAL_LEVEL_ITEMS: ChoiceOption[] = [
  { id: 'exquisite', label: '精美' },
  { id: 'gentle', label: '轻柔' },
  { id: 'smooth', label: '流畅' },
  { id: 'adaptive', label: '自适应' }
];
export const MATERIAL_LEVELS: ChoiceSet = new ChoiceSet(MATERIAL_LEVEL_ITEMS, 'adaptive');

/**
 * 下载位置三档，与 DownloadStore.downloadLocation 的语义 id 一一对应。
 *
 * 「应用文件」是默认档：图片落 `filesDir/images`、压缩包落 `filesDir/archives`。
 * 另两档都是**额外的第二落点**，应用内的那份副本永远保留（图库 / 预览 / 改名 / 导出都指着它）。
 */
const DOWNLOAD_LOCATION_ITEMS: ChoiceOption[] = [
  { id: 'app', label: '应用文件' },
  { id: 'gallery', label: '系统相册' },
  { id: 'custom', label: '自定义目录' }
];
export const DOWNLOAD_LOCATIONS: ChoiceSet = new ChoiceSet(DOWNLOAD_LOCATION_ITEMS, 'app');

/**
 * 「下载图片质量」三档，与 DownloadStore.pictureQuality 的语义 id 一一对应。
 *
 * 这一行管的其实是**扫描时每个 img 取哪个地址**，不涉及本地重编码：
 * 「原图优先」先把页面里所有更大的候选地址（data-*、srcset、外层链接、站点尺寸阶梯）收集起来，
 * 再用一次 HTTP 头请求按文件字节数挑最大的那张，所以扫描会多花几秒；
 * 「网页显示图」只取浏览器真正渲染出来的那张；「全部」是旧行为——每个候选地址各收一张。
 * 三档对应的取值算法在 service/PageScanner.ets 的 SourceOrderStrategy 里，
 * 候选收集与仲裁分别在 service/ImageCandidates.ets 和 service/SizeArbiter.ets。
 */
const PICTURE_QUALITY_ITEMS: ChoiceOption[] = [
  { id: 'original', label: '原图优先' },
  { id: 'display', label: '网页显示图' },
  { id: 'all', label: '全部' }
];
export const PICTURE_QUALITIES: ChoiceSet = new ChoiceSet(PICTURE_QUALITY_ITEMS, 'original');

/**
 * 「编辑副本科质」三档，与 `DownloadStore.editQuality` 的语义 id 一一对应。
 *
 * 编辑导出原先无条件写无损 PNG：PNG 的 quality 参数不生效，一张 227 KB 的有损原图
 * 重新编码后会膨胀到 1.6 MB。这里把「格式 + JPEG 质量」收成用户可选的档位：
 * - `high` 不透明源按 JPEG 质量 90 编码（默认，体积约为无损 PNG 的 1/5）；
 * - `compact` 不透明源按 JPEG 质量 80 编码（体积最小）；
 * - `lossless` 保持旧行为，始终 PNG。
 *
 * 带透明通道的源在任何档位下都强制 PNG —— JPEG 不支持 alpha，强行编码会把透明区域
 * 变成黑色；透明度未知时 EditExport 会先做一次有界像素扫描再决定。
 * 判据与编码策略见 service/EditExport.ets。
 */
const EDIT_QUALITY_ITEMS: ChoiceOption[] = [
  { id: 'high', label: '高质量 JPEG' },
  { id: 'compact', label: '体积优先 JPEG' },
  { id: 'lossless', label: '无损 PNG' }
];
export const EDIT_QUALITIES: ChoiceSet = new ChoiceSet(EDIT_QUALITY_ITEMS, 'high');

/** 「编辑副本科质」那一行的说明文字；透明回退是硬规则，所以每档都写一句。 */
export class EditQualityHints {
  static text(id: string): string {
    if (id === 'lossless') {
      return '保留全部像素与透明通道，文件最大';
    }
    if (id === 'compact') {
      return 'JPEG 质量 80，文件最小；细看可能有损失。含透明通道的图片始终存为 PNG';
    }
    return 'JPEG 质量 90，照片观感接近原图，体积约为无损 PNG 的 1/5。含透明通道的图片始终存为 PNG';
  }
}

/**
 * 「下载图片质量」那一行的说明文字。
 *
 * 三档各是一句用户看得懂的话；没有失败态要顶掉说明，所以只按档位给一句（**策略**：
 * 一句话对应一个档位，档位变了文案跟着变，调用方不必写 if 链）。
 */
export class QualityHints {
  static text(id: string): string {
    if (id === 'original') {
      return '优先取网页里的大图地址，缩略图不再重复出现（会多花几秒核对）';
    }
    if (id === 'display') {
      return '只取浏览器当前显示的那张图';
    }
    return '每个候选地址各收一张，缩略图与大图会同时出现';
  }
}

/**
 * 「下载位置」那一行的说明文字。
 *
 * 与图片质量不同，这一行有失败态：投递失败的原因（problem）优先顶掉正常说明 ——
 * 只在设置页说一句，用户才有地方查「为什么相册 / 目录里没有」。
 */
export class LocationHints {
  static text(id: string, customDirName: string, problem: string): string {
    if (problem.length > 0) {
      return problem;
    }
    if (id === 'gallery') {
      return '图片下载完成后存入相册（系统会弹一次确认），压缩包仍留应用文件';
    }
    if (id === 'custom') {
      return customDirName.length > 0
        ? '图片与压缩包再存一份到「' + customDirName + '」，应用内保留一份'
        : '选一个目录，图片与压缩包再存一份到那里，应用内保留一份';
    }
    return '应用文件 · 图片与压缩包分开存放';
  }
}

/**
 * 把任意来源（存盘文件、界面回调）的**取图策略**归一到 `PICTURE_QUALITIES` 认识的档位。
 *
 * 判据就是那张表：认不出的一律退回**表里的默认档**（现在是「原图优先」）——
 * 默认档意味着「用户没表达过意见时该给什么」，比留一个写死的旧档位更不容易和设置页对不上：
 * 默认档改了，脏值和旧存档跟着一起改，不会出现「设置页第一项是 A、脏值却退回 B」的错位。
 */
export function normalizeQuality(value: string): string {
  return PICTURE_QUALITIES.normalize(value);
}

/** 与 `normalizeQuality` 同一条规则：认不出的值退回表里的默认档（高质量 JPEG）。 */
export function normalizeEditQuality(value: string): string {
  return EDIT_QUALITIES.normalize(value);
}

/**
 * 把任意来源的**下载位置**归一到三档之一。
 *
 * 这里不能只查表：`custom` 还依赖「有没有记住目录 URI」—— 选了自定义目录却没记住 URI 时
 * 必须退回「应用文件」，否则之后每次下载都会往空 URI 上拷、每次都失败。
 */
export function normalizeLocation(value: string, uri: string): string {
  if (value === 'gallery') {
    return 'gallery';
  }
  if (value === 'custom' && uri.length > 0) {
    return 'custom';
  }
  return 'app';
}
