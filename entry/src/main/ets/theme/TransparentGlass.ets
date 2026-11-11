import { uiMaterial } from '@kit.ArkUI';
import { DownloadStore } from '../service/DownloadStore';
import { MaterialController } from '../service/MaterialController';
import { Palette } from './Tokens';

/** 仅供系统标题栏、底部 Tabs 和系统弹层使用；内容区不挂载通用 systemMaterial。 */
export class TransparentGlass {
  private static enabled(enabled: boolean): boolean {
    return enabled && DownloadStore.lightEffect && DownloadStore.materialType !== 'none';
  }

  static material(enabled: boolean = true): uiMaterial.Material | undefined {
    return MaterialController.glassMaterial(TransparentGlass.enabled(enabled));
  }

  /** 有材质时不再叠 backgroundColor；无材质时提供不透明底色。 */
  static background(enabled: boolean = true): ResourceColor | undefined {
    return MaterialController.uiActive(TransparentGlass.enabled(enabled)) ? undefined : Palette.card;
  }

  static foreground(enabled: boolean = true): ResourceColor {
    return MaterialController.uiActive(TransparentGlass.enabled(enabled))
      ? $r('sys.color.font_primary') : Palette.fontPrimary;
  }

  static secondary(enabled: boolean = true): ResourceColor {
    return MaterialController.uiActive(TransparentGlass.enabled(enabled))
      ? $r('sys.color.font_secondary') : Palette.fontSecondary;
  }
}
