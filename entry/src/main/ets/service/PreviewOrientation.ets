import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/** Allow rotation only while inspecting images, respecting the user's rotation lock. */
export class PreviewOrientation {
  private static pending: Promise<void> = Promise.resolve();
  private target: window.Window | undefined = undefined;
  private previous: window.Orientation = window.Orientation.UNSPECIFIED;

  enter(context: common.UIAbilityContext): void {
    PreviewOrientation.pending = PreviewOrientation.pending.then(async (): Promise<void> => {
      if (this.target !== undefined) { return; }
      const target: window.Window = await window.getLastWindow(context);
      this.previous = target.getPreferredOrientation();
      this.target = target;
      await target.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED);
    }).catch((): void => {});
  }

  leave(): void {
    PreviewOrientation.pending = PreviewOrientation.pending.then(async (): Promise<void> => {
      const target: window.Window | undefined = this.target;
      this.target = undefined;
      if (target !== undefined) { await target.setPreferredOrientation(this.previous); }
    }).catch((): void => {});
  }
}
