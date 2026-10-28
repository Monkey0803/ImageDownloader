import { uiMaterial } from '@kit.ArkUI';
import { MaterialSupport } from '../service/MaterialSupport';
import { Palette } from './Tokens';

// API 26 / Stage：固定赋色不参与深浅色调色。原生材质句柄只创建一次，不放入 UI 状态。
const GLASS_MATERIAL: uiMaterial.ImmersiveMaterial | undefined = MaterialSupport.immersiveSupported()
  ? new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.REGULAR,
    materialColor: '#33FFFFFF',
    colorInvert: true,
    applyShadow: true
  }) : undefined;

/** 仅供系统标题栏、底部 Tabs 和系统弹层使用；内容区不挂载通用 systemMaterial。 */
export class TransparentGlass {
  static material(enabled: boolean = true): uiMaterial.ImmersiveMaterial | undefined {
    return enabled ? GLASS_MATERIAL : undefined;
  }

  /** 有材质时不再叠 backgroundColor；无材质时提供不透明底色。 */
  static background(enabled: boolean = true): ResourceColor | undefined {
    return TransparentGlass.material(enabled) === undefined ? Palette.card : undefined;
  }

  static foreground(enabled: boolean = true): ResourceColor {
    return TransparentGlass.material(enabled) === undefined ? Palette.fontPrimary : $r('sys.color.font_primary');
  }

  static secondary(enabled: boolean = true): ResourceColor {
    return TransparentGlass.material(enabled) === undefined ? Palette.fontSecondary : $r('sys.color.font_secondary');
  }
}
