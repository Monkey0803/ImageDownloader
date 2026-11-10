import { uiMaterial } from '@kit.ArkUI';
import { MaterialSupport } from '../service/MaterialSupport';
import { Palette } from './Tokens';
import { TransparentGlass } from './TransparentGlass';

/** 弹层使用比标题栏更厚的材质，面板上的文字保持可读。 */
export class SheetStyle {
  private static overlay: uiMaterial.Material | undefined = undefined;
  private static usable: boolean | undefined = undefined;

  private static materialUsable(): boolean {
    if (SheetStyle.usable !== undefined) { return SheetStyle.usable; }
    if (!MaterialSupport.immersiveSupported()) {
      SheetStyle.usable = false;
      return false;
    }
    try {
      SheetStyle.usable = uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE;
    } catch (error) {
      console.error('sheet material state unavailable: ' + String(error));
      SheetStyle.usable = false;
    }
    return SheetStyle.usable;
  }

  static material(enabled: boolean = true): SystemUiMaterial | undefined {
    if (!SheetStyle.materialUsable()) { return undefined; }
    try {
      if (!enabled) { return uiMaterial.Material.empty; }
      if (SheetStyle.overlay === undefined) {
        SheetStyle.overlay = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK,
          interactive: true,
          lightEffect: { color: undefined }
        });
      }
      return SheetStyle.overlay;
    } catch (error) {
      console.error('sheet material unavailable: ' + String(error));
      return undefined;
    }
  }

  /** 材质生效时显式让出背板，失败时回退实色。 */
  static sheetBackground(material: SystemUiMaterial | undefined, enabled: boolean,
    opaque: boolean): ResourceColor | undefined {
    if (enabled && material !== undefined) { return Color.Transparent; }
    if (opaque || enabled) { return Palette.card; }
    return undefined;
  }

  /** 确认弹窗复用固定半透明赋色，避免系统深色调色使玻璃发灰。 */
  static dialogMaterial(): SystemUiMaterial | undefined {
    return TransparentGlass.material();
  }

  static background(): ResourceColor | undefined {
    return TransparentGlass.background();
  }
}
