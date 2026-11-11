import { MaterialController } from '../service/MaterialController';
import { DownloadStore } from '../service/DownloadStore';
import { Palette } from './Tokens';
import { TransparentGlass } from './TransparentGlass';

/** 弹层使用比标题栏更厚的材质，面板上的文字保持可读。 */
export class SheetStyle {
  static material(enabled: boolean = true): SystemUiMaterial | undefined {
    return MaterialController.overlayMaterial(enabled);
  }

  /** 材质生效时显式让出背板，失败时回退实色。 */
  static sheetBackground(material: SystemUiMaterial | undefined, enabled: boolean,
    opaque: boolean): ResourceColor | undefined {
    if (enabled && material !== undefined) { return Color.Transparent; }
    if (opaque || enabled) { return Palette.card; }
    return undefined;
  }

  /** 确认弹窗使用较薄的系统材质。 */
  static dialogMaterial(): SystemUiMaterial | undefined {
    return MaterialController.dialogMaterial(DownloadStore.lightEffect && DownloadStore.materialType !== 'none');
  }

  static background(): ResourceColor | undefined {
    return TransparentGlass.background();
  }
}
