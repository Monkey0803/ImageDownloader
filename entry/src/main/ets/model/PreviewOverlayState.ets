/** Shared with the host page so system Back closes the foremost panel first. */
@ObservedV2
export class PreviewOverlayState {
  @Trace tools: boolean = false;
  @Trace comparison: boolean = false;
  @Trace navigation: boolean = false;

  dismissTop(): boolean {
    if (this.comparison) { this.comparison = false; return true; }
    if (this.tools) { this.tools = false; return true; }
    if (this.navigation) { this.navigation = false; return true; }
    return false;
  }

  reset(): void { this.tools = false; this.comparison = false; this.navigation = false; }
}
