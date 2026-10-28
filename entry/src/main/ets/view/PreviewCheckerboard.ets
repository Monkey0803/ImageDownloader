/** Phase-aware tiles let viewport crops replace transparent pixels without double compositing. */
@ComponentV2
export struct PreviewCheckerboard {
  @Param cellSize: number = 12;
  @Param phaseX: number = 0;
  @Param phaseY: number = 0;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(false));

  @Monitor('cellSize', 'phaseX', 'phaseY')
  private onPatternChanged(monitor: IMonitor): void { this.paint(); }

  private paint(): void {
    const width: number = this.context.width;
    const height: number = this.context.height;
    const cell: number = Math.max(1, this.cellSize);
    this.context.fillStyle = '#D8D8D8';
    this.context.fillRect(0, 0, width, height);
    this.context.fillStyle = '#A8A8A8';
    const startX: number = -this.phaseX % cell;
    const startY: number = -this.phaseY % cell;
    const column: number = Math.floor(this.phaseX / cell);
    const row: number = Math.floor(this.phaseY / cell);
    for (let y: number = 0; startY + y * cell < height; y++) {
      for (let x: number = 0; startX + x * cell < width; x++) {
        if ((row + y + column + x) % 2 === 0) {
          this.context.fillRect(startX + x * cell, startY + y * cell, cell, cell);
        }
      }
    }
  }

  build() {
    Canvas(this.context).onReady((): void => { this.paint(); })
      .onSizeChange((): void => { this.paint(); }).hitTestBehavior(HitTestMode.None)
  }
}
