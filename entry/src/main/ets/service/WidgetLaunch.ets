import { Want } from '@kit.AbilityKit';

/** One-shot navigation request from the desktop widget to the existing Index page. */
export class WidgetLaunch {
  private static pendingTasks: boolean = false;
  private static pendingTargetId: string = '';
  private static pendingTargetKind: string = '';
  private static listener: (() => void) | undefined = undefined;

  static receive(want: Want): void {
    if (want.parameters?.['widgetPage'] !== 'tasks') { return; }
    WidgetLaunch.pendingTasks = true;
    const id: string = want.parameters?.['widgetTargetId'] as string ?? '';
    const kind: string = want.parameters?.['widgetTargetKind'] as string ?? '';
    WidgetLaunch.pendingTargetId = id;
    WidgetLaunch.pendingTargetKind = kind;
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

  static takeTargetId(): string {
    const id: string = WidgetLaunch.pendingTargetId;
    WidgetLaunch.pendingTargetId = '';
    return id;
  }

  static takeTargetKind(): string {
    const kind: string = WidgetLaunch.pendingTargetKind;
    WidgetLaunch.pendingTargetKind = '';
    return kind;
  }
}
