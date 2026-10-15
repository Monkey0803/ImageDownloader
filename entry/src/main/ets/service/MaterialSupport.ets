import { uiMaterial } from '@kit.ArkUI';

/**
 * 沉浸光感材质的设备能力探测（**适配器**：把系统两套同名枚举翻译成界面上的说法）。
 *
 * `uiMaterial` 的 `MaterialLevel` 与 `hdsMaterial` 的同名枚举是一一对应的三档
 * （精致 / 均衡 / 轻盈 vs 精美 / 轻柔 / 流畅）。界面下拉里用的是后一套名字，
 * 用户选「自适应 = 跟随系统」时得能对上号，所以这里统一成下拉里的叫法。
 *
 * 两个方法都可能抛：没有对应 syscap 的设备上直接调会抛异常，所以都要 try 包住并给保守值
 * （不支持 / 自适应），不能让它冲崩页面。
 */
export class MaterialSupport {
  /** 本机是否支持沉浸式材质；不支持时界面应提示会回退为静态模糊。 */
  static immersiveSupported(): boolean {
    try {
      return uiMaterial.isImmersiveMaterialSupported();
    } catch (error) {
      return false;
    }
  }

  /** 本机算力落在哪一档，用「沉浸光感材质」下拉里的叫法说出来。 */
  static deviceLevelLabel(): string {
    try {
      const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      if (level === uiMaterial.MaterialLevel.EXQUISITE) {
        return '精美';
      }
      if (level === uiMaterial.MaterialLevel.GENTLE) {
        return '轻柔';
      }
      return '流畅';
    } catch (error) {
      return '自适应';
    }
  }
}
