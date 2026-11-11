import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { Palette } from '../theme/Tokens';

/** One place for HDS and component material capability, policy and cached recipes. */
export class MaterialController {
  private static hdsTypes: hdsMaterial.MaterialType[] | undefined = undefined;
  private static glassAvailable: boolean | undefined = undefined;
  private static appState: uiMaterial.MaterialState | undefined = undefined;
  private static level: uiMaterial.MaterialLevel | undefined = undefined;
  private static glass: uiMaterial.Material | undefined = undefined;
  private static segment: uiMaterial.Material | undefined = undefined;
  private static overlay: uiMaterial.Material | undefined = undefined;
  private static dialog: uiMaterial.Material | undefined = undefined;

  static supportedTypes(): hdsMaterial.MaterialType[] {
    if (MaterialController.hdsTypes !== undefined) { return MaterialController.hdsTypes; }
    try { MaterialController.hdsTypes = hdsMaterial.getSystemMaterialTypes(); }
    catch (error) { MaterialController.hdsTypes = []; }
    return MaterialController.hdsTypes;
  }

  static immersiveSupported(): boolean {
    return MaterialController.supportedTypes().includes(hdsMaterial.MaterialType.IMMERSIVE);
  }

  static glassSupported(): boolean {
    if (MaterialController.glassAvailable !== undefined) { return MaterialController.glassAvailable; }
    try { MaterialController.glassAvailable = uiMaterial.isImmersiveMaterialSupported(); }
    catch (error) { MaterialController.glassAvailable = false; }
    return MaterialController.glassAvailable;
  }

  static materialState(): uiMaterial.MaterialState {
    if (MaterialController.appState !== undefined) { return MaterialController.appState; }
    try { MaterialController.appState = uiMaterial.getMaterialInfo().state; }
    catch (error) { MaterialController.appState = uiMaterial.MaterialState.DEFAULT; }
    return MaterialController.appState;
  }

  static appMaterialOn(): boolean {
    return MaterialController.materialState() !== uiMaterial.MaterialState.DISABLE;
  }

  static globalLevel(): uiMaterial.MaterialLevel {
    if (MaterialController.level !== undefined) { return MaterialController.level; }
    MaterialController.level = uiMaterial.MaterialLevel.SMOOTH;
    if (MaterialController.glassSupported()) {
      try { MaterialController.level = uiMaterial.getGlobalMaterialLevel(); }
      catch (error) { MaterialController.level = uiMaterial.MaterialLevel.SMOOTH; }
    }
    return MaterialController.level;
  }

  static uiActive(enabled: boolean): boolean {
    return enabled && MaterialController.glassSupported() && MaterialController.appMaterialOn();
  }

  static hdsParams(typeId: string, enabled: boolean): SystemMaterialParams {
    const types: hdsMaterial.MaterialType[] = MaterialController.supportedTypes();
    let type: hdsMaterial.MaterialType = typeId === 'immersive'
      ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE;
    if (!types.includes(type)) {
      type = types.includes(hdsMaterial.MaterialType.IMMERSIVE)
        ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.NONE;
    }
    if (!enabled || typeId === 'none' || !MaterialController.appMaterialOn()) {
      type = hdsMaterial.MaterialType.NONE;
    }
    return { materialType: type, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE };
  }

  private static usableMaterial(enabled: boolean): uiMaterial.Material | undefined {
    if (!MaterialController.glassSupported() || !MaterialController.appMaterialOn()) { return undefined; }
    return enabled ? undefined : uiMaterial.Material.empty;
  }

  static glassMaterial(enabled: boolean): uiMaterial.Material | undefined {
    const fallback: uiMaterial.Material | undefined = MaterialController.usableMaterial(enabled);
    if (!enabled || !MaterialController.uiActive(enabled)) { return fallback; }
    if (MaterialController.glass === undefined) {
      try {
        MaterialController.glass = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN, colorInvert: true, applyShadow: true
        });
      } catch (error) { return undefined; }
    }
    return MaterialController.glass;
  }

  static segmentMaterial(enabled: boolean): uiMaterial.Material | undefined {
    const fallback: uiMaterial.Material | undefined = MaterialController.usableMaterial(enabled);
    if (!enabled || !MaterialController.uiActive(enabled)) { return fallback; }
    if (MaterialController.segment === undefined) {
      try {
        MaterialController.segment = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN, colorInvert: true, interactive: true,
          lightEffect: { color: Palette.brand }
        });
      } catch (error) { return undefined; }
    }
    return MaterialController.segment;
  }

  static overlayMaterial(enabled: boolean): uiMaterial.Material | undefined {
    const fallback: uiMaterial.Material | undefined = MaterialController.usableMaterial(enabled);
    if (!enabled || !MaterialController.uiActive(enabled)) { return fallback; }
    if (MaterialController.overlay === undefined) {
      try {
        MaterialController.overlay = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK,
          interactive: true, lightEffect: { color: undefined }
        });
      } catch (error) { return undefined; }
    }
    return MaterialController.overlay;
  }

  static dialogMaterial(enabled: boolean): uiMaterial.Material | undefined {
    const fallback: uiMaterial.Material | undefined = MaterialController.usableMaterial(enabled);
    if (!enabled || !MaterialController.uiActive(enabled)) { return fallback; }
    if (MaterialController.dialog === undefined) {
      try {
        MaterialController.dialog = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR, applyShadow: true,
          lightEffect: { color: Palette.brand }
        });
      } catch (error) { return undefined; }
    }
    return MaterialController.dialog;
  }
}
