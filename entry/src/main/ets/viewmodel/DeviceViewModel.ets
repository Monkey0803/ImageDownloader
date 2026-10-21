import { DownloadStore } from '../service/DownloadStore';
import { GripSensor } from '../service/GripSensor';
import { AntiPeep } from '../service/AntiPeep';
import { UiPort } from '../service/UiPort';

/**
 * 设备特性（智感握姿 + 防窥保护）的 ViewModel。
 *
 * 这两件事原本以十几个 `@State` 的形式长在 Index 里，夹在下载队列和页面几何之间 ——
 * 但它们其实是**同一类东西**：都由系统传感器驱动、都有「开关 / 支持 / 当前状态 / 未生效原因」
 * 四件套、都要在页面销毁时摘回调。收在一个 ViewModel 里之后：
 *
 * - 发现页只读 `gripLeft()` / `gripChipVisible()` 决定镜像与胶囊；
 * - 设置页只读 `antiPeepReady()` 决定说明文字；
 * - 「开关数据怎么落盘、订阅什么时候挂」全在这一层，界面不再直接碰系统 kit
 *   （AGENT.md 坑 5：任何 `dlpAntiPeep` 调用都必须过 syscap 守卫，守卫就在 AntiPeep 里）。
 */
@ObservedV2
export class DeviceViewModel {
  /** UI 出口，页面在 `attach` 时注入；默认是安全空实现。 */
  private ui: UiPort = new UiPort();

  /** 智感握姿开关；与 DownloadStore.gripEnabled 同步。 */
  @Trace grip: boolean = false;
  /** 系统识别出的握持手：'left' | 'right' | 'both' | 'none' | 'unknown'。 */
  @Trace gripHand: string = 'unknown';
  /** 本机是否支持智感握姿；订阅返回 801 时为 false。 */
  @Trace gripSupported: boolean = true;
  /** 智感握姿「开着但没生效」的原因，写在设置行里（不再靠 Toast）。 */
  @Trace gripProblem: string = '';

  /** 防窥保护开关；与 DownloadStore.antiPeepEnabled 同步。 */
  @Trace antiPeep: boolean = false;
  /** 系统当前是否报告有人窥视；true 时整屏内容被遮罩。 */
  @Trace peeking: boolean = false;
  /** 本机是否支持防窥保护；没有 DlpAntiPeep syscap 时为 false。 */
  @Trace antiPeepSupported: boolean = true;
  /** 防窥保护「开着但没生效」的原因，写在设置行里。 */
  @Trace antiPeepProblem: string = '';
  /** 忽略较早一次开关操作迟到的订阅结果与提示。 */
  private antiPeepPickRevision: number = 0;

  attach(ui: UiPort): void {
    this.ui = ui;
  }

  /**
   * 挂听两个传感器。
   *
   * **必须在 `DownloadStore.initialize()` 之前调**：initialize 会按持久化的开关恢复订阅，
   * 订阅结果要能刷到界面（先挂听再初始化，第一次回调才不会丢）。
   */
  start(): void {
    GripSensor.attach((): void => {
      this.gripHand = GripSensor.hand;
      this.gripSupported = GripSensor.supported;
      this.gripProblem = GripSensor.problem;
    });
    AntiPeep.attach((): void => {
      this.peeking = AntiPeep.peeking;
      this.antiPeepSupported = AntiPeep.supported;
      this.antiPeepProblem = AntiPeep.problem;
      // 系统 live view 发不出去时，遮罩上没有任何解释，用一次 Toast 补上。
      if (AntiPeep.peeking && AntiPeep.liveViewFailed) {
        this.ui.say('检测到他人注视屏幕，已隐藏内容');
      }
    });
  }

  /**
   * 页面销毁时把挂出去的东西都摘掉。
   *
   * 防窥：文档要求必须 `off('dlpAntiPeep')`，否则回调会打到已销毁的组件上；
   * 先 detach 再 stop（`stop()` 结尾会 `notify()`，那时监听者已经摘掉了）。
   * 握姿：同样要摘回调 —— 订阅本身留着（跟着持久化开关走，见 `GripSensor.detach`）。
   */
  stop(): void {
    AntiPeep.detach();
    AntiPeep.stop();
    GripSensor.detach();
  }

  /** 把落盘的开关与传感器的当前状态拉回界面。 */
  sync(): void {
    this.grip = DownloadStore.gripEnabled;
    this.gripHand = GripSensor.hand;
    this.gripSupported = GripSensor.supported;
    this.gripProblem = GripSensor.problem;
    this.antiPeep = DownloadStore.antiPeepEnabled;
    this.peeking = AntiPeep.peeking;
    this.antiPeepSupported = AntiPeep.supported;
    this.antiPeepProblem = AntiPeep.problem;
  }

  /** 握持手的可读名称；拿到首个识别结果前显示「识别中」。 */
  handName(): string {
    if (this.gripHand === 'left') {
      return '左手';
    }
    if (this.gripHand === 'right') {
      return '右手';
    }
    if (this.gripHand === 'both') {
      return '双手';
    }
    if (this.gripHand === 'none') {
      return '未握持';
    }
    return '识别中';
  }

  /**
   * 主操作是否跟随左手。
   *
   * 智感握姿只镜像「左手握持」这一种情况：右手握持就是界面本来的排布，
   * 未知 / 未握持 / 双手都保持原样，避免界面在识别抖动时来回翻。
   */
  gripLeft(): boolean {
    return this.grip && this.gripHand === 'left';
  }

  /**
   * 发现页的握姿提示只在真的认出一只手时出现。
   *
   * 「未握持」「识别中」都属于没什么可说的状态：手机平放在桌上时它就是「未握持」，
   * 这颗胶囊会一直挂在页签栏上方当常驻噪音。原型里这枚胶囊也只写左手 / 右手。
   */
  gripChipVisible(): boolean {
    return this.grip && this.gripSupported
      && (this.gripHand === 'left' || this.gripHand === 'right' || this.gripHand === 'both');
  }

  /** 订阅真的挂上了才算「已接入」；只是开关打开不算。 */
  antiPeepReady(): boolean {
    return this.antiPeepSupported && AntiPeep.subscribed;
  }

  /**
   * 智感握姿开关。
   *
   * **刻意不弹任何提示**：
   * - 「已开启 / 已关闭」本来就是开关自身的状态，再 Toast 一遍纯属噪音；
   * - 「未生效：<原因>」改写在设置页那一行的说明里（见 `gripHint()`）—— 那是一条常驻信息，
   *   用户想查的时候看得见，也不用为了一次勾选被打断。
   *
   * 开关本身照旧保存用户的选择（能不能用由设备决定，不替用户改写）；实时握持状态看发现页的握姿胶囊。
   */
  pickGrip(value: boolean): void {
    DownloadStore.setGripEnabled(value);
    this.sync();
  }

  /**
   * 防窥保护开关。
   *
   * 订阅由这里驱动，不走 DownloadStore 的 setter：拉订阅需要 UIAbilityContext 才能在
   * 系统开关没开时拉起 requestAntiPeepOptions 弹窗。**一次点击只调一次 setEnabled**——
   * 早先「先无 context 探一次、再带 context 调一次」的写法里，第一次会占住服务的在飞行
   * 状态，第二次直接搭便车复用它的结果，弹窗永远弹不出来（真机实测踩到）。
   */
  async pickAntiPeep(value: boolean): Promise<void> {
    const revision: number = ++this.antiPeepPickRevision;
    DownloadStore.setAntiPeepEnabled(value);
    this.sync();
    if (!value) {
      AntiPeep.setEnabled(false);
      this.ui.say('防窥保护已关闭');
      return;
    }
    const ready: boolean = await AntiPeep.setEnabled(true, this.ui.context());
    if (revision !== this.antiPeepPickRevision || !DownloadStore.antiPeepEnabled) { return; }
    this.sync();
    const reason: string = AntiPeep.problem.length > 0 ? AntiPeep.problem : '设备不支持防窥保护';
    this.ui.say(ready ? '防窥保护已开启' : '防窥保护未生效：' + reason);
  }
}
