import { motion } from '@kit.MultimodalAwarenessKit';

type HandHandler = (isLeft: boolean, fromOperating: boolean) => void;

/**
 * 智感握姿：握持手 + 操作手监听
 * （SystemCapability.MultimodalAwareness.Motion，握持手 API 20+、操作手 API 15+）。
 * 握持手反映真实握持变化；操作手在触屏时上报，响应更快，两者互补。
 * 不支持的设备（801 / canIUse false）静默降级为不订阅。
 */
export class MotionHand {
  private static instance: MotionHand | null = null;
  private readonly holdingHandCallback = (status: motion.HoldingHandStatus): void => {
    // NOT_HELD / BOTH_HANDS_HELD / UNKNOWN_STATUS：保持当前侧
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      this.handler?.(true, false);
    } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      this.handler?.(false, false);
    }
  };
  private readonly operatingHandCallback = (status: motion.OperatingHandStatus): void => {
    if (status === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
      this.handler?.(true, true);
    } else if (status === motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
      this.handler?.(false, true);
    }
  };
  private handler: HandHandler | null = null;
  private holdingSubscribed: boolean = false;
  private operatingSubscribed: boolean = false;

  static setMonitor(enable: boolean, onChange: HandHandler | null): void {
    if (MotionHand.instance === null) {
      MotionHand.instance = new MotionHand();
    }
    MotionHand.instance.setMonitorInner(enable, onChange);
  }

  private setMonitorInner(enable: boolean, onChange: HandHandler | null): void {
    this.handler = onChange;
    if (enable) {
      this.subscribeInner();
    } else {
      this.unsubscribeInner();
    }
  }

  private subscribeInner(): void {
    const supported = canIUse('SystemCapability.MultimodalAwareness.Motion');
    if (!this.holdingSubscribed && supported) {
      try {
        motion.on('holdingHandChanged', this.holdingHandCallback);
        this.holdingSubscribed = true;
      } catch (err) {
        console.warn(`MotionHand holdingHand on failed: ${err}`);
      }
    }
    if (!this.operatingSubscribed) {
      try {
        motion.on('operatingHandChanged', this.operatingHandCallback);
        this.operatingSubscribed = true;
      } catch (err) {
        // 801：设备不支持操作手感知，仅降级此通道
        console.warn(`MotionHand operatingHand on failed: ${err}`);
      }
    }
  }

  private unsubscribeInner(): void {
    if (this.holdingSubscribed) {
      try {
        motion.off('holdingHandChanged', this.holdingHandCallback);
      } catch (err) {
        console.warn(`MotionHand holdingHand off failed: ${err}`);
      }
      this.holdingSubscribed = false;
    }
    if (this.operatingSubscribed) {
      try {
        motion.off('operatingHandChanged', this.operatingHandCallback);
      } catch (err) {
        console.warn(`MotionHand operatingHand off failed: ${err}`);
      }
      this.operatingSubscribed = false;
    }
    this.handler = null;
  }
}
