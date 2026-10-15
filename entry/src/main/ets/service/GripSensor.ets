import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';

/*
 * GripSensor.ets — 智感握姿（握持手感知）。
 *
 * 系统能力来自 Multimodal Awareness Kit 的 motion 模块：应用订阅
 * `holdingHandChanged` 后，系统把「当前是左手还是右手握着设备」回调过来。
 * 开发文档：https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/motion-guidelines
 *
 * 三个必须记住的点：
 * 1. 只有部分机型支持。设备不支持时订阅直接抛 801（功能不支持），所以这里把
 *    `supported` 记下来交给界面提示，而不是把异常抛给调用方。
 * 2. 需要 `ohos.permission.DETECT_GESTURE`（normal + system_grant，装机即授予，
 *    不需要运行时弹窗），已声明在 module.json5。
 * 3. 识别有条件：需亮屏解锁、五指自然握持并让掌心接触设备、保护壳不超过 3mm；
 *    未握持的识别依赖设备静止。所以 `hand` 在拿到首个结果前是 'unknown'，
 *    界面按「识别中」显示，不做任何假设。
 */

/** 系统回调把结果写进类状态；用模块级函数而不是类属性箭头函数，避免静态成员里的 this。 */
function onHoldingHand(status: motion.HoldingHandStatus): void {
  GripSensor.hand = GripSensor.handOf(status);
  GripSensor.notify();
}

export class GripSensor {
  /** 'left' | 'right' | 'both' | 'none' | 'unknown' */
  static hand: string = 'unknown';
  /** False once the platform answers 801 — the device has no 智感握姿. */
  static supported: boolean = true;
  static subscribed: boolean = false;
  /** Empty while everything is fine; otherwise the reason shown in 设置. */
  static problem: string = '';
  /** The page registers here to re-render when the holding hand changes. */
  static listener: (() => void) | undefined = undefined;

  static attach(listener: () => void): void {
    GripSensor.listener = listener;
  }

  /**
   * 摘掉刷新回调，只摘监听**不动订阅**：订阅跟着持久化的开关走是刻意的
   * （见 setEnabled / DownloadStore.initialize），页面销毁时不该顺手把它关掉。
   */
  static detach(): void {
    GripSensor.listener = undefined;
  }

  static notify(): void {
    if (GripSensor.listener !== undefined) {
      GripSensor.listener();
    }
  }

  /** The platform enum, narrowed to the four values this app reasons about. */
  static handOf(status: motion.HoldingHandStatus): string {
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      return 'left';
    }
    if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      return 'right';
    }
    if (status === motion.HoldingHandStatus.BOTH_HANDS_HELD) {
      return 'both';
    }
    if (status === motion.HoldingHandStatus.NOT_HELD) {
      return 'none';
    }
    return 'unknown';
  }

  /** Follow the 设置 switch. Safe to call with the current value. */
  static setEnabled(enabled: boolean): void {
    if (enabled) {
      GripSensor.subscribe();
    } else {
      GripSensor.unsubscribe();
    }
  }

  static subscribe(): void {
    if (GripSensor.subscribed) {
      return;
    }
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      GripSensor.supported = false;
      GripSensor.problem = '设备不支持智感握姿';
      GripSensor.notify();
      return;
    }
    try {
      // @SuppressWarnings syscap
      motion.on('holdingHandChanged', onHoldingHand);
      GripSensor.subscribed = true;
      GripSensor.supported = true;
      GripSensor.problem = '';
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      // 错误码留在日志里：界面只给用户看得懂的说法，不暴露 801 这类系统码。
      console.error('holdingHandChanged failed: ' + error.code.toString());
      GripSensor.subscribed = false;
      // 801 有两种可能：设备本身没有这个能力，或者设备支持但用户在
      // 「设置 > 系统」里把「智感握姿」关掉了。文档给的现象都是 801，
      // 无法在应用侧区分，所以提示里两种都提，不把话说死。
      GripSensor.supported = error.code !== 801;
      GripSensor.problem = error.code === 801
        ? '设备不支持，或系统「智感握姿」未开启'
        : '握姿识别暂时不可用';
    }
    GripSensor.notify();
  }

  static unsubscribe(): void {
    if (!GripSensor.subscribed) {
      return;
    }
    try {
      // @SuppressWarnings syscap
      motion.off('holdingHandChanged');
    } catch (err) {
      // 已经取消或系统侧收回订阅：本地状态照常清理。
    }
    GripSensor.subscribed = false;
    GripSensor.hand = 'unknown';
    GripSensor.notify();
  }
}
