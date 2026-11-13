import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import display from '@ohos.display';

/**
 * 设备形态判定：当前是不是「细长竖屏」形态（普通直板机 / 大折叠外屏）。
 *
 * 这类形态下非播放页只允许竖屏；平板、2in1、阔直板、阔折叠（Pura X 内外屏）
 * 以及大折叠内屏都跟随系统。
 *
 * 不按型号判断，只看两件事：
 * 1. deviceType === 'phone'（折叠屏也报 phone，所以不能只用它）；
 * 2. 当前默认屏幕的长边/短边 ≥ 1.9：
 *    - 直板机 >19:9 ≥ 2.11，大折叠外屏约 20.9:9 ≈ 2.32
 *    - 平板 / Pura X 内屏 16:10 = 1.6，Pura X View 16:9.5 ≈ 1.684，
 *      Pura X 外屏 1:1，大折叠内屏 ≤ 1.3
 *    阈值取 1.9，两侧各留约 0.2 余量。
 *
 * 折叠/展开后默认屏幕会变，监听 foldStatusChange 重新判定（去抖 300ms，
 * 避开折叠动画中途的中间尺寸）。
 */
const PORTRAIT_FORM_RATIO: number = 1.9;
const FOLD_RECHECK_DELAY_MS: number = 300;

export type DeviceFormListener = (portraitForm: boolean) => void;

export class DeviceFormState {
  private portraitForm: boolean = false;
  private listener: DeviceFormListener | null = null;
  private foldListening: boolean = false;
  private recheckTimer: number = -1;

  private foldCallback = (): void => {
    if (this.recheckTimer !== -1) {
      clearTimeout(this.recheckTimer);
    }
    this.recheckTimer = setTimeout(() => {
      this.recheckTimer = -1;
      this.emit();
    }, FOLD_RECHECK_DELAY_MS);
  };

  /** 当前是否「细长竖屏」形态。 */
  isPortraitForm(): boolean {
    return this.portraitForm;
  }

  /** 读一次形态；任何异常都按「跟随系统」处理，不阻塞启动。 */
  read(): boolean {
    try {
      if (deviceInfo.deviceType !== 'phone') {
        return false;
      }
      const d = display.getDefaultDisplaySync();
      const longSide = Math.max(d.width, d.height);
      const shortSide = Math.min(d.width, d.height);
      if (shortSide <= 0) {
        return false;
      }
      return longSide / shortSide >= PORTRAIT_FORM_RATIO;
    } catch (err) {
      const e = err as BusinessError;
      console.warn('DeviceForm', `read failed: ${e.code} ${e.message}`);
      return false;
    }
  }

  /** 首次读取并开始监听折叠状态（幂等）。 */
  attach(listener: DeviceFormListener): void {
    this.listener = listener;
    this.portraitForm = this.read();
    if (this.foldListening) {
      return;
    }
    try {
      display.on('foldStatusChange', this.foldCallback);
      this.foldListening = true;
    } catch (err) {
      const e = err as BusinessError;
      console.warn('DeviceForm', `fold listener failed: ${e.code} ${e.message}`);
    }
  }

  detach(): void {
    this.listener = null;
    if (!this.foldListening) {
      return;
    }
    this.foldListening = false;
    if (this.recheckTimer !== -1) {
      clearTimeout(this.recheckTimer);
      this.recheckTimer = -1;
    }
    try {
      display.off('foldStatusChange', this.foldCallback);
    } catch (err) {
      // 注册时即失败
    }
  }

  private emit(): void {
    const next = this.read();
    if (next === this.portraitForm) {
      return;
    }
    this.portraitForm = next;
    const listener = this.listener;
    if (listener !== null) {
      listener(next);
    }
  }
}

export const deviceFormState: DeviceFormState = new DeviceFormState();
