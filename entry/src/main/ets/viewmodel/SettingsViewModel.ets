import { DownloadStore } from '../service/DownloadStore';
import { FolderChoice, pickFolder } from '../service/FileActions';
import { MaterialSupport } from '../service/MaterialSupport';
import { ThemeController } from '../service/ThemeController';
import { UiPort } from '../service/UiPort';
import { formatBytes } from '../theme/Tokens';
import {
  ChoiceOption, DOWNLOAD_LOCATIONS, EDIT_QUALITIES, EditQualityHints, LocationHints,
  MATERIAL_TYPES, PICTURE_QUALITIES, QualityHints, THEME_CHOICES
} from '../model/SettingsOptions';

/**
 * 设置页的 ViewModel。
 *
 * 设置页里的几行「语义档位」：主题、材质类型、材质等级、下载图片质量、编辑副本科质、
 * 下载位置、沉浸光感开关。它们在 Index 里各配了一组 getter（下标 / 当前名 / 说明文字）加一个 pick 方法，
 * 一共三十来个成员。这里把它们归成一个 ViewModel，并把「档位表」交给 model/SettingsOptions
 * 的 `ChoiceSet` —— 组件只问「现在显示哪一项、这一行该写什么」。
 *
 * 两个有副作用的选择（主题、自定义目录）也在这里：
 * - 主题落盘后立刻 `ThemeController.apply`；
 * - 选「自定义目录」要先拉起系统目录选择器，选到了才真正落档，取消则**什么都不改**。
 */
@ObservedV2
export class SettingsViewModel {
  private ui: UiPort = new UiPort();

  @Trace themeMode: string = 'system';
  @Trace materialType: string = 'adaptive';
  @Trace lightEffect: boolean = true;
  /** 预览是否按 HDR 解码/显示；与 DownloadStore.hdrEnabled 同步。 */
  @Trace hdrEnabled: boolean = true;
  @Trace wifiOnly: boolean = false;
  /** 下载位置；与 DownloadStore.downloadLocation 同步。 */
  @Trace downloadLocation: string = 'app';
  /** 扫描取图策略（「下载图片质量」那一行）；与 DownloadStore.pictureQuality 同步。 */
  @Trace pictureQuality: string = 'original';
  /** 编辑副本科质（「编辑副本科质」那一行）；与 DownloadStore.editQuality 同步。 */
  @Trace editQuality: string = 'high';
  /** 自定义目录的显示名，写在下拉行下面的说明里。 */
  @Trace customDirName: string = '';
  /** 上次投递到相册 / 自定义目录失败的原因；非空时顶掉下载位置那行的说明文字。 */
  @Trace destinationProblem: string = '';
  /** 下载位置下拉的强制重建号；用户选了「自定义目录」又取消时 +1，见 chooseCustomDir。 */
  @Trace locationRevision: number = 0;
  /** 应用内已占用字节数与它的可读形式；「数据」那一节的 meta 用。 */
  @Trace usedBytes: number = 0;
  @Trace usedLabel: string = '';
  /** 状态写盘失败的原因；非空时顶掉「数据」那一节的占用说明。 */
  @Trace saveProblem: string = '';

  attach(ui: UiPort): void {
    this.ui = ui;
  }

  /** 把落盘的设置拉回界面。 */
  sync(): void {
    this.themeMode = DownloadStore.themeMode;
    this.materialType = DownloadStore.materialType;
    this.lightEffect = DownloadStore.lightEffect;
    this.hdrEnabled = DownloadStore.hdrEnabled;
    this.wifiOnly = DownloadStore.wifiOnly;
    this.downloadLocation = DownloadStore.downloadLocation;
    this.pictureQuality = DownloadStore.pictureQuality;
    this.editQuality = DownloadStore.editQuality;
    this.customDirName = DownloadStore.customDirName;
    this.destinationProblem = DownloadStore.destinationProblem;
    this.saveProblem = DownloadStore.saveProblem;
    // 占用是「设置页要显示的一个数」，不是每次 build 都去问一遍文件系统的动作。
    this.usedBytes = DownloadStore.usedBytes();
    this.usedLabel = this.usedBytes > 0 ? '占用 ' + formatBytes(this.usedBytes) : '';
  }

  // ------------------------------------------------------------------ 数据

  setWifiOnly(value: boolean): void {
    DownloadStore.setWifiOnly(value);
  }

  /** 清掉打包中断后残留在暂存目录的图片，并把释放的空间说给用户听。 */
  cleanTemp(): void {
    const freed: number = DownloadStore.cleanStaging();
    this.ui.say('暂存目录已清理 · 释放 ' + formatBytes(freed));
  }

  confirmClearAll(): void {
    this.ui.confirm('清空下载记录', '将删除原始下载图片、压缩包与下载记录。编辑副本及已导出的文件不受影响。', '删除',
      (): void => {
        this.ui.say(DownloadStore.clearAll() ? '已清空下载记录，编辑副本已保留' :
          '部分文件未能删除，记录已保留，可重试清理');
      });
  }

  // ------------------------------------------------------------------ 外观 / 材质

  /** 切换主题：下标对应 THEME_CHOICES，落盘后立刻重新应用系统深浅色。 */
  pickTheme(index: number): void {
    if (index < 0 || index >= THEME_CHOICES.size()) {
      return;
    }
    DownloadStore.setThemeMode(THEME_CHOICES.at(index).id);
    this.sync();
    this.applyTheme();
  }

  /** 把当前主题刷到应用级；启动时也要调一次，恢复上次的选择。 */
  applyTheme(): void {
    ThemeController.apply(this.ui.context(), DownloadStore.themeMode);
  }

  setLightEffect(value: boolean): void {
    DownloadStore.setLightEffect(value);
    this.sync();
  }

  /** HDR 显示开关；只影响之后打开的预览，已打开的画面保持当前解码结果。 */
  setHdrEnabled(value: boolean): void {
    DownloadStore.setHdrEnabled(value);
    this.sync();
  }

  /**
   * 切换材质类型。
   *
   * 文档里 ADAPTIVE 默认就按沉浸式材质生效，所以选它和选沉浸式一样受设备能力限制；
   * 这里只在用户明确选「沉浸式」而本机不支持时提示一次，不替用户改写选择。
   */
  pickMaterialType(index: number): void {
    if (index < 0 || index >= MATERIAL_TYPES.size()) {
      return;
    }
    const type: ChoiceOption = MATERIAL_TYPES.at(index);
    DownloadStore.setMaterialType(type.id);
    this.sync();
    if (type.id === 'immersive' && !MaterialSupport.immersiveSupported()) {
      this.ui.say('本机不支持沉浸式材质，将回退为普通样式');
    }
  }

  /** API 26 材质等级为设备只读能力，不能用用户偏好覆盖。 */
  deviceMaterialLevel(): string {
    return MaterialSupport.immersiveSupported() ? MaterialSupport.deviceLevelLabel() : '不支持';
  }

  /** 「材质类型」下拉的当前下标。 */
  materialTypeIndex(): number {
    return MATERIAL_TYPES.index(this.materialType);
  }

  // ------------------------------------------------------------------ 下载图片质量

  qualityIndex(): number {
    return PICTURE_QUALITIES.index(this.pictureQuality);
  }

  qualityLabel(): string {
    return PICTURE_QUALITIES.label(this.pictureQuality);
  }

  qualityHint(): string {
    return QualityHints.text(this.pictureQuality);
  }

  /**
   * 切换取图策略。
   *
   * 档位只在**扫描的那一刻**被读；而右上角刷新是按 URL 合并进 pictures 的（已扫到的旧条目
   * 不会被清掉），所以文案必须说清生效时机：重新打开网页才会得到一份干净的列表。
   */
  pickPictureQuality(index: number): void {
    if (index < 0 || index >= PICTURE_QUALITIES.size()) {
      return;
    }
    const quality: ChoiceOption = PICTURE_QUALITIES.at(index);
    DownloadStore.setPictureQuality(quality.id);
    this.sync();
    this.ui.say('图片质量已改为「' + quality.label + '」，重新打开网页后生效');
  }

  // ------------------------------------------------------------------ 编辑副本科质

  editQualityIndex(): number {
    return EDIT_QUALITIES.index(this.editQuality);
  }

  editQualityLabel(): string {
    return EDIT_QUALITIES.label(this.editQuality);
  }

  editQualityHint(): string {
    return EditQualityHints.text(this.editQuality);
  }

  /** 只影响之后保存的编辑副本；已保存的副本不会重编码。 */
  pickEditQuality(index: number): void {
    if (index < 0 || index >= EDIT_QUALITIES.size()) {
      return;
    }
    const quality: ChoiceOption = EDIT_QUALITIES.at(index);
    DownloadStore.setEditQuality(quality.id);
    this.sync();
    this.ui.say('编辑副本科质已改为「' + quality.label + '」，之后保存的副本生效');
  }

  // ------------------------------------------------------------------ 下载位置

  locationIndex(): number {
    return DOWNLOAD_LOCATIONS.index(this.downloadLocation);
  }

  locationLabel(): string {
    return DOWNLOAD_LOCATIONS.label(this.downloadLocation);
  }

  /** 下载位置那行的说明文字；投递失败的原因优先顶掉正常说明。 */
  locationHint(): string {
    return LocationHints.text(this.downloadLocation, this.customDirName, this.destinationProblem);
  }

  /**
   * 切换下载位置。
   *
   * 「自定义目录」不是选完就完事：得先让用户挑到目录、并且把这次授权持久化，
   * 才能真正落成 custom 档（没目录时 store 会把它归一回应用文件，见 normalizeLocation）。
   * 用户取消选择器时**什么都不改**：档位、目录、说明文字都保持原样。
   */
  pickDownloadLocation(index: number): void {
    if (index < 0 || index >= DOWNLOAD_LOCATIONS.size()) {
      return;
    }
    const location: ChoiceOption = DOWNLOAD_LOCATIONS.at(index);
    if (location.id !== 'custom') {
      DownloadStore.setDownloadLocation(location.id);
      this.sync();
      this.ui.say(location.id === 'gallery' ? '图片将自动存入系统相册' : '已改回应用文件');
      return;
    }
    if (!canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')) {
      // 选择器拉不起来，这次选择同样没被接受：把胶囊刷回已提交的档位（同 chooseCustomDir 的取消分支）。
      this.locationRevision += 1;
      this.sync();
      this.ui.say('本机不支持选择目录，仍保存在' + this.locationLabel());
      return;
    }
    this.chooseCustomDir();
  }

  private async chooseCustomDir(): Promise<void> {
    const choice: FolderChoice = await pickFolder(this.ui.context());
    if (!choice.ok) {
      // 用户取消了选择器：档位、目录、说明文字都不动。
      // 但原生 Select 已经被点成「自定义目录」了，得让控件重建一次才刷得回已提交的值
      // （否则胶囊长期显示「自定义目录」，而实际下载位置还是上一次选的），见 SettingSelect.revision。
      this.locationRevision += 1;
      this.sync();
      if (choice.message.length > 0) {
        this.ui.say(choice.message);
      }
      return;
    }
    DownloadStore.setCustomDir(choice.uri, choice.name);
    this.sync();
    this.ui.say(choice.message.length > 0 ? choice.message : '下载位置已改为「' + choice.name + '」');
  }
}
