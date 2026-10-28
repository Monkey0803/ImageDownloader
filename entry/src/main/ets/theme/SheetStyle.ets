import { uiMaterial } from '@kit.ArkUI';

/** 为应用内系统半模态面板创建同一档材质；每个宿主只创建一次。 */
export class SheetStyle {
  static material(): SystemUiMaterial {
    return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK });
  }

  /** 确认弹窗比半模态面板更需要遮蔽背景，使用系统推荐的超厚材质。 */
  static dialogMaterial(): SystemUiMaterial {
    return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK });
  }
}
