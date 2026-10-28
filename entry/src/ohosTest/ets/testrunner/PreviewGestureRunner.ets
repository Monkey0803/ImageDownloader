import { TestRunner } from '@kit.TestKit';

// UiTest must load after the framework registers AbilityDelegator. Importing it
// while the runner module is evaluated leaves the native Driver disconnected.
export default class PreviewGestureRunner implements TestRunner {
  private stopService: () => void = (): void => {};

  onPrepare(): void {}

  onStop(): void { this.stopService(); }

  async onRun(): Promise<void> {
    const module = await import('./PreviewGestureService');
    const service = new module.PreviewGestureService();
    this.stopService = (): void => { service.stop(); };
    await service.run();
  }
}
