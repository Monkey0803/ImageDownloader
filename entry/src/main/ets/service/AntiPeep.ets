import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/*
 * AntiPeep.ets — 防窥保护（dlpAntiPeep）。
 *
 * 系统能力来自 Device Security Kit 的 dlpAntiPeep 模块：系统用前置摄像头判断屏幕前
 * 是否有机主以外的人在看，把结果以 DlpAntiPeepStatus 回调给应用，应用自己决定怎么遮盖。
 * 开发文档：https://developer.huawei.com/consumer/cn/doc/doccenter-advanced-features/bpta-antipeep-protection
 *
 * 五个必须记住的点：
 * 1. 调任何 dlpAntiPeep 接口之前必须先 canIUse('SystemCapability.Security.DlpAntiPeep')：
 *    在不支持该 syscap 的设备（比如模拟器）上直接调用会抛异常把应用冲崩，不是返回失败。
 * 2. 三层 gating，缺一不可：应用开关打开 → 系统「设置 > 隐私和安全」里的防窥保护开关
 *    也打开（isDlpAntiPeepSwitchOn）→ 才订阅。系统开关没开时订阅拿不到有效状态。
 * 3. 全部接口都要 ohos.permission.DLP_GET_HIDE_STATUS。它是 system_grant，不会弹授权框，
 *    但 availableLevel 是 system_basic，调试证书的 allowed-acls 里必须带上，否则装不上。
 * 4. 订阅只在开关打开时存在，关掉就 off；页面销毁也必须 off，否则回调会打到已销毁的组件上。
 * 5. 识别不是确定性的：暗光/强光/逆光、角度过大都会降低成功率，人像海报也可能误报。
 *    所以 `peeking` 只是一次"可能有人在看"的判断，界面必须允许用户一键点掉（acknowledge）。
 */

/** 系统回调把结果写进类状态；用模块级函数而不是类属性箭头函数，避免静态成员里的 this。 */
function onAntiPeepStatus(status: dlpAntiPeep.DlpAntiPeepStatus): void {
  const was: boolean = AntiPeep.peeking;
  AntiPeep.peeking = status === dlpAntiPeep.DlpAntiPeepStatus.HIDE;
  // 系统 live view 每次窥视只发一次：重复发会被系统以 1020600005（已发布）拒掉。
  if (AntiPeep.peeking && !was) {
    AntiPeep.publishLiveView();
  }
  AntiPeep.notify();
}

export class AntiPeep {
  /** 系统当前是否报告"有人在看"。 */
  static peeking: boolean = false;
  /** False when the platform has no DlpAntiPeep syscap — the device cannot do this at all. */
  static supported: boolean = true;
  static subscribed: boolean = false;
  /** 系统「设置 > 隐私和安全」里的防窥保护开关。 */
  static systemSwitchOn: boolean = false;
  /** Empty while everything is fine; otherwise the reason shown in 设置. */
  static problem: string = '';
  /** 系统提醒发不出去时置位，界面用一次 Toast 兜底。 */
  static liveViewFailed: boolean = false;
  /** The page registers here to re-render when the peeping status changes. */
  static listener: (() => void) | undefined = undefined;
  /** 让关闭开关或页面销毁后尚未返回的系统探测失效。 */
  private static openRevision: number = 0;

  static attach(listener: () => void): void {
    AntiPeep.listener = listener;
  }

  static detach(): void {
    AntiPeep.listener = undefined;
  }

  static notify(): void {
    if (AntiPeep.listener !== undefined) {
      AntiPeep.listener();
    }
  }

  /**
   * 设置页那个开关的开关。
   *
   * 不带 context 时绝不做任何交互（启动恢复订阅走的就是这条路）；带上 context 才会在
   * 系统开关没开时拉起 requestAntiPeepOptions 弹窗。返回订阅是否真的生效。
   */
  static async setEnabled(enabled: boolean, context?: common.UIAbilityContext): Promise<boolean> {
    if (!enabled) {
      AntiPeep.stop();
      return false;
    }
    const revision: number = ++AntiPeep.openRevision;
    return await AntiPeep.doOpen(context, revision);
  }

  /** 取消订阅并清掉窥视状态：关开关和页面销毁都走这里。 */
  static stop(): void {
    AntiPeep.openRevision++;
    if (AntiPeep.subscribed) {
      try {
        // @SuppressWarnings syscap
        dlpAntiPeep.off('dlpAntiPeep');
      } catch (err) {
        // 已经取消或系统侧收回订阅：本地状态照常清理。
      }
    }
    AntiPeep.subscribed = false;
    AntiPeep.peeking = false;
    AntiPeep.liveViewFailed = false;
    AntiPeep.notify();
  }

  /**
   * 「轻点任意位置继续」的落点。
   *
   * passDlpAntiPeepInfo() 把隐藏状态钉成固定值：用户明确表示可以看了，就不用一直盖着，
   * 等下次解锁后系统感知重新生效。本地状态要一起清，别等回调。
   */
  static acknowledge(): void {
    if (AntiPeep.supported) {
      try {
        // @SuppressWarnings syscap
        dlpAntiPeep.passDlpAntiPeepInfo();
      } catch (err) {
        // 钉不住也要照常放行：遮罩是本地状态说了算。
      }
    }
    AntiPeep.peeking = false;
    AntiPeep.notify();
  }

  /**
   * 文档给的顺序：查能力 → 查系统开关 → 订阅 → 取初始状态。每个 await 之后核对请求版本。
   *
   * 不加"同一时刻只跑一遍"的合并：那样界面主动开开关的那一遍（带 context、能拉系统弹窗）
   * 会搭上启动探测那一遍（没 context）的便车，系统弹窗永远弹不出来——真机实测踩过。
   * 启动恢复与用户点击可能同时探测；只允许最后一次开启继续订阅。关闭或页面销毁也会
   * 使尚未返回的探测失效，避免关掉开关后又挂上回调。
   */
  private static async doOpen(context: common.UIAbilityContext | undefined, revision: number): Promise<boolean> {
    try {
      // 设备级不支持是终态，探到一次就别再举手。少了这道短路，后面任何一遍探测都会把
      // 「设备不支持防窥保护」覆盖成「请在系统设置中开启防窥保护」，用户就去找一个
      // 根本不存在的能力了（模拟器上实测踩过）。
      if (!AntiPeep.supported) {
        AntiPeep.problem = '设备不支持防窥保护';
        return false;
      }
      if (!canIUse('SystemCapability.Security.DlpAntiPeep')) {
        AntiPeep.supported = false;
        AntiPeep.problem = '设备不支持防窥保护';
        return false;
      }
      AntiPeep.supported = true;
      const initialSwitchOn: boolean = await AntiPeep.readSystemSwitch();
      if (revision !== AntiPeep.openRevision) { return false; }
      AntiPeep.systemSwitchOn = initialSwitchOn;
      // readSystemSwitch 探到 801（设备没这个能力）时会把 supported 翻下去：这是终态，
      // 不能再用「系统开关没开」糊过去——用户会照着去找一个根本不存在的能力。
      if (!AntiPeep.supported) {
        AntiPeep.problem = '设备不支持防窥保护';
        return false;
      }
      // 本次探测里最具体的原因；空串表示只探到"系统开关没开"。
      let reason: string = '';
      if (!AntiPeep.systemSwitchOn && context !== undefined) {
        // API 23 起可以直接把用户送到系统开关上，不用他自己翻设置。
        reason = await AntiPeep.askSystemSwitch(context);
        if (revision !== AntiPeep.openRevision) { return false; }
        const confirmedSwitchOn: boolean = await AntiPeep.readSystemSwitch();
        if (revision !== AntiPeep.openRevision) { return false; }
        AntiPeep.systemSwitchOn = confirmedSwitchOn;
      }
      if (!AntiPeep.systemSwitchOn) {
        AntiPeep.problem = reason.length > 0 ? reason : '请在系统设置中开启防窥保护';
        return false;
      }
      if (AntiPeep.subscribed) {
        return true;
      }
      // @SuppressWarnings syscap
      dlpAntiPeep.on('dlpAntiPeep', onAntiPeepStatus);
      AntiPeep.subscribed = true;
      AntiPeep.problem = '';
      // 进页面时可能已经在被窥视：on 只管之后的变化，初值必须同步取一次。
      AntiPeep.peeking = dlpAntiPeep.getDlpAntiPeepInfo() === dlpAntiPeep.DlpAntiPeepStatus.HIDE;
      return true;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      // 错误码留在日志里：界面只给用户看得懂的说法，不暴露 201/1020600004 这类系统码。
      console.error('dlpAntiPeep open failed: ' + error.code.toString());
      AntiPeep.subscribed = false;
      // 801 是设备没这个能力（终态）；1020600004 是系统里没录人脸，防窥判断没法工作。
      // 两者都表现为"开不了"，但说法不同，而且都不能被后面那一遍探测覆盖成通用文案。
      if (error.code === 801) {
        AntiPeep.supported = false;
        AntiPeep.problem = '设备不支持防窥保护';
      } else {
        AntiPeep.problem = error.code === 1020600004 ? '请先在系统里录入人脸' : '防窥保护暂时不可用';
      }
      return false;
    } finally {
      AntiPeep.notify();
    }
  }

  /**
   * 拉起系统弹窗，把用户送到「设置 > 隐私和安全」的防窥保护开关上。
   *
   * 返回值是这次失败的具体原因（给界面的 `problem` 用），空串表示"没拿到更具体的信息，
   * 就按系统开关没开讲"。
   */
  private static async askSystemSwitch(context: common.UIAbilityContext): Promise<string> {
    try {
      const result: dlpAntiPeep.AntiPeepOptionsResult = await dlpAntiPeep.requestAntiPeepOptions(context);
      // SUCCESS / ALREADY_ON 都表示弹窗走通了，开关状态以复查为准，这里不返回原因。
      if (result === dlpAntiPeep.AntiPeepOptionsResult.FAIL) {
        return '请在系统设置中开启防窥保护';
      }
      return '';
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('requestAntiPeepOptions failed: ' + error.code.toString());
      if (error.code === 801) {
        AntiPeep.supported = false;
        return '设备不支持防窥保护';
      }
      return error.code === 1020600004 ? '请先在系统里录入人脸' : '请在系统设置中开启防窥保护';
    }
  }

  private static async readSystemSwitch(): Promise<boolean> {
    try {
      // @SuppressWarnings syscap
      return await dlpAntiPeep.isDlpAntiPeepSwitchOn();
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('isDlpAntiPeepSwitchOn failed: ' + error.code.toString());
      // 801 = 设备没这个能力。真机日志证实：模拟器上 canIUse 照样返回 true，真正把我们挡住的是
      // 这里，所以这条路径必须把 supported 翻下去，否则界面会误报成「系统开关没开」。
      if (error.code === 801) {
        AntiPeep.supported = false;
      }
      return false;
    }
  }

  /**
   * 系统级提醒（live view）。
   *
   * 发不出去不算故障：遮罩由应用自己画，提醒只是让用户知道"为什么被盖住了"。
   * 1020600002 系统开关关了、1020600003 应用不在前台、1020600005 已经发过、
   * 1020600006 这次没判出风险，都属于"这次不用提醒"，不是错误。
   *
   * 公开是因为调用点在模块级的 onAntiPeepStatus 里（同 GripSensor：回调函数写在类外，
   * 免得静态成员里出现 this），不是给界面用的接口。
   */
  static publishLiveView(): void {
    AntiPeep.liveViewFailed = false;
    try {
      // @SuppressWarnings syscap
      dlpAntiPeep.publishAntiPeepInformation().catch((err: BusinessError): void => {
        console.error('publishAntiPeepInformation failed: ' + err.code.toString());
        AntiPeep.liveViewFailed = true;
        AntiPeep.notify();
      });
    } catch (err) {
      AntiPeep.liveViewFailed = true;
    }
  }
}
