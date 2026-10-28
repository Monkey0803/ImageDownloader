import { TransparentGlass } from './TransparentGlass';

/** 为应用内系统半模态面板创建同一档材质；每个宿主只创建一次。 */
export class SheetStyle {
  static material(): SystemUiMaterial | undefined {
    return TransparentGlass.material();
  }

  /** 确认弹窗复用固定半透明赋色，避免系统深色调色使玻璃发灰。 */
  static dialogMaterial(): SystemUiMaterial | undefined {
    return TransparentGlass.material();
  }

  static background(): ResourceColor | undefined {
    return TransparentGlass.background();
  }
}
