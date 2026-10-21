import { Want } from '@kit.AbilityKit';

/** One-shot navigation request from the desktop widget to the existing Index page. */
export class WidgetLaunch {
  private static pendingTasks: boolean = false;
  private static listener: (() => void) | undefined = undefined;

  static receive(want: Want): void {
    if (want.parameters?.['widgetPage'] !== 'tasks') { return; }
    WidgetLaunch.pendingTasks = true;
    WidgetLaunch.listener?.();
  }

  static subscribe(listener: () => void): void {
    WidgetLaunch.listener = listener;
  }

  static unsubscribe(listener: () => void): void {
    if (WidgetLaunch.listener === listener) { WidgetLaunch.listener = undefined; }
  }

  static takeTasks(): boolean {
    const pending: boolean = WidgetLaunch.pendingTasks;
    WidgetLaunch.pendingTasks = false;
    return pending;
  }
}
