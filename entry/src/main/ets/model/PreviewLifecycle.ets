/** Ability foreground is independent of router visibility. */
@ObservedV2
export class PreviewLifecycle {
  @Trace foreground: boolean = true;
  private listeners: Set<(foreground: boolean) => void> = new Set();

  subscribe(listener: (foreground: boolean) => void): void { this.listeners.add(listener); }
  unsubscribe(listener: (foreground: boolean) => void): void { this.listeners.delete(listener); }

  setForeground(value: boolean): void {
    if (this.foreground === value) { return; }
    this.foreground = value;
    for (const listener of this.listeners) { listener(value); }
  }
}
export const PREVIEW_LIFECYCLE: PreviewLifecycle = new PreviewLifecycle();
