/**
 * 提示的显示时长；Index（四个页签）与 Viewer（大图预览）共用同一个节奏。
 */
const TOAST_MS: number = 2600;

/**
 * 「弹一句、过一会儿自己消失」的提示闩。
 *
 * 这段逻辑原来在 `pages/Index.ets` 和 `pages/Viewer.ets` 里各写了一份（一个 `notice`
 * 状态 + 一个定时器 + 销毁时 clear），连 2600 这个数字都是两处字面量。收在这里之后：
 *
 * - 页面只保留一个 `@State notice` 用来画，和一行 `bind()`；
 * - 定时器的生命周期只有一处实现，**销毁后自动拒绝新的提示** —— 预览页的
 *   分享 / 导出 / 存相册都是异步的，`.then` 回来时页面可能已经关了，那时再写 @State
 *   就是往已销毁的组件上打回调（原来靠页面自己记一个 destroyed 标志来挡）。
 *
 * 它不依赖任何组件类型：页面把「写进自己 @State」的动作 `bind` 进来即可。
 */
export class ToastLatch {
  private timer: number = -1;
  private released: boolean = false;
  private sink: (text: string) => void = (text: string): void => {
  };

  /** 绑定展示出口；页面在 `aboutToAppear` 里传 `(text) => { this.notice = text; }`。 */
  bind(sink: (text: string) => void): void {
    this.sink = sink;
  }

  /** 弹一条提示；空串表示不用吭声（文件操作的返回值就是给用户看的话）。 */
  show(text: string): void {
    if (this.released || text.length === 0) {
      return;
    }
    this.sink(text);
    this.clearTimer();
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.sink('');
    }, TOAST_MS);
  }

  /**
   * 页面销毁时调。
   *
   * 之后 `show()` 一律空操作：定时器不能留着，晚到的异步回调也不该再产生提示。
   */
  release(): void {
    this.released = true;
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }
}
