import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import display from '@ohos.display';
import window from '@ohos.window';

/**
 * 鸿蒙设备形态判定：一次读出两个值。
 *
 * 1. `portraitForm`：是否「细长竖屏」形态（直板机 / 大折叠外屏），供方向策略用。
 *    设备类型为 phone 且当前屏幕长边/短边 ≥ 1.9。
 *
 * 2. `horizontalLayout`：横屏适配自动值，仅决定布局（全页面统一），鸿蒙上不再
 *    由用户设置：
 *    - 平板 / 2in1 → 开启；
 *    - 手机类：直板机（含 Pura X View、阔直板）→ 关闭；
 *      折叠设备看 `getFoldDisplayMode()`：
 *      - 外屏（SUB，含 Pocket 圆形小外屏、Pura X/Pura X Max 外屏）→ 关闭；
 *      - 未知（UNKNOWN）→ 关闭（保守，等事件纠正）；
 *      - 内屏（MAIN）/ 双屏协同（COORDINATION）→ 当前屏幕长边/短边 < 1.5 才开启。
 *        即只有书本式大折叠、三折叠、阔折叠（Pura X Max 1.414）的内屏开启；
 *        小折叠内屏（Pura X 16:10 = 1.6，Pocket ≈2.35）关闭。
 *
 * 触发重判有四路保障：
 * 1. `foldDisplayModeChange`：内容完成内/外屏切换——**立即**刷新横屏适配值，
 *    让随后由窗口尺寸变化触发的 rebuild 直接读到新值；
 * 2. `foldStatusChange`：去抖 300ms 后稳定读（方向策略用）；
 * 3. 主窗口 `windowSizeChange`（仅折叠设备）：作为折展完成的兜底触发；
 * 4. 应用回前台（EntryAbility.onForeground）：后台折展可能收不到事件，补判。
 *
 * 稳定读：连续两次采样一致才采纳，避免读到折展动画的中间尺寸。
 */
const PORTRAIT_FORM_RATIO: number = 1.9;
const HORIZONTAL_LAYOUT_RATIO: number = 1.5;
/** 折叠/窗口尺寸变化后的首次重判延迟（避开折展动画）。 */
const RECHECK_DELAY_MS: number = 300;
/** 稳定读的两次采样间隔。 */
const STABLE_SAMPLE_DELAY_MS: number = 200;
/** 稳定读最多尝试次数：连续两次读数一致才采纳。 */
const STABLE_MAX_ATTEMPTS: number = 3;

export interface DeviceFormSnapshot {
  /** 细长竖屏形态（方向策略用）。 */
  portraitForm: boolean;
  /** 横屏适配自动值（布局用，全页面统一）。 */
  horizontalLayout: boolean;
}

export type DeviceFormListener = (snapshot: DeviceFormSnapshot) => void;

export class DeviceFormState {
  private snapshot: DeviceFormSnapshot = {
    portraitForm: false,
    horizontalLayout: false,
  };
  private listener: DeviceFormListener | null = null;
  private foldListening: boolean = false;
  private modeListening: boolean = false;
  private sizeListening: boolean = false;
  private win: window.Window | null = null;
  private recheckTimer: number = -1;
  /** 代际：detach 后让挂起的去抖/稳定读回调作废。 */
  private generation: number = 0;

  private foldCallback = (): void => {
    this.requestRecheck();
  };

  private foldModeCallback = (): void => {
    // 内容完成内/外屏切换：立即更新横屏适配自动值（稳定读只做兜底），
    // 保证随后由窗口尺寸变化触发的 rebuild 能读到新布局形态。
    this.refreshLayoutNow();
    this.requestRecheck();
  };

  /** 折叠/展开会改窗口尺寸：把它当作「屏幕切换基本完成」的信号再补判一次。 */
  private sizeCallback = (): void => {
    this.requestRecheck();
  };

  isPortraitForm(): boolean {
    return this.snapshot.portraitForm;
  }

  isHorizontalLayout(): boolean {
    return this.snapshot.horizontalLayout;
  }

  currentSnapshot(): DeviceFormSnapshot {
    return {
      portraitForm: this.snapshot.portraitForm,
      horizontalLayout: this.snapshot.horizontalLayout,
    };
  }

  /** 细长竖屏形态判定；失败返回 null（区别于「判定为非竖屏形态」）。 */
  private readPortraitFormOrNull(): boolean | null {
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
      console.warn('DeviceForm', `read portraitForm failed: ${e.code} ${e.message}`);
      return null;
    }
  }

  /** 横屏适配自动值；失败返回 null。 */
  private readHorizontalLayoutOrNull(): boolean | null {
    try {
      const type = deviceInfo.deviceType;
      if (type === 'tablet' || type === '2in1') {
        return true;
      }
      if (type !== 'phone') {
        return false;
      }
      // 直板机（含 Pura X View、阔直板）一律关闭。
      if (!display.isFoldable()) {
        return false;
      }
      const mode = display.getFoldDisplayMode();
      if (mode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_SUB ||
        mode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN) {
        // 外屏（大/小外屏）一律关闭；未知状态保守关闭，等 foldDisplayModeChange 纠正。
        return false;
      }
      // 内屏（MAIN）或双屏协同（COORDINATION）：当前屏幕够宽才算平板布局。
      const d = display.getDefaultDisplaySync();
      const longSide = Math.max(d.width, d.height);
      const shortSide = Math.min(d.width, d.height);
      if (shortSide <= 0) {
        return false;
      }
      return longSide / shortSide < HORIZONTAL_LAYOUT_RATIO;
    } catch (err) {
      const e = err as BusinessError;
      console.warn('DeviceForm', `read horizontalLayout failed: ${e.code} ${e.message}`);
      return null;
    }
  }

  private readSnapshotOrNull(): DeviceFormSnapshot | null {
    const portraitForm = this.readPortraitFormOrNull();
    if (portraitForm === null) {
      return null;
    }
    const horizontalLayout = this.readHorizontalLayoutOrNull();
    if (horizontalLayout === null) {
      return null;
    }
    return { portraitForm: portraitForm, horizontalLayout: horizontalLayout };
  }

  /** 首次读取并开始监听折叠状态（幂等）。 */
  attach(listener: DeviceFormListener): void {
    this.listener = listener;
    const initial = this.readSnapshotOrNull();
    if (initial !== null) {
      this.snapshot = initial;
    }
    if (this.foldListening) {
      return;
    }
    try {
      display.on('foldStatusChange', this.foldCallback);
      this.foldListening = true;
    } catch (err) {
      const e = err as BusinessError;
      console.warn('DeviceForm', `foldStatus listener failed: ${e.code} ${e.message}`);
    }
    try {
      display.on('foldDisplayModeChange', this.foldModeCallback);
      this.modeListening = true;
    } catch (err) {
      const e = err as BusinessError;
      console.warn('DeviceForm', `foldDisplayMode listener failed: ${e.code} ${e.message}`);
    }
    this.attachSizeListener();
  }

  /** 监听主窗口尺寸变化（仅折叠设备）：作为折叠/展开完成的兜底触发。 */
  private async attachSizeListener(): Promise<void> {
    if (this.sizeListening) {
      return;
    }
    try {
      if (!display.isFoldable()) {
        return;
      }
    } catch (err) {
      return;
    }
    try {
      this.win ??= await window.getLastWindow(getContext());
      const w = this.win;
      if (w === null) {
        return;
      }
      w.on('windowSizeChange', this.sizeCallback);
      this.sizeListening = true;
    } catch (err) {
      const e = err as BusinessError;
      console.warn('DeviceForm', `windowSizeChange listener failed: ${e.code} ${e.message}`);
    }
  }

  detach(): void {
    this.listener = null;
    this.generation += 1;
    this.cancelRecheck();
    if (this.foldListening) {
      this.foldListening = false;
      try {
        display.off('foldStatusChange', this.foldCallback);
      } catch (err) {
        // 注册时即失败
      }
    }
    if (this.modeListening) {
      this.modeListening = false;
      try {
        display.off('foldDisplayModeChange', this.foldModeCallback);
      } catch (err) {
        // 注册时即失败
      }
    }
    if (this.sizeListening) {
      this.sizeListening = false;
      try {
        this.win?.off('windowSizeChange', this.sizeCallback);
      } catch (err) {
        // 窗口已销毁
      }
    }
    this.win = null;
  }

  /**
   * 立即重判，应用回前台时调用：后台折展可能收不到事件，不补判会继续用
   * 旧形态的方向策略与布局。
   */
  refreshNow(): void {
    this.cancelRecheck();
    if (!this.sizeListening) {
      this.attachSizeListener();
    }
    const snapshot = this.readSnapshotOrNull();
    if (snapshot !== null) {
      this.adopt(snapshot);
    }
  }

  /** 立即刷新横屏适配值（foldDisplayModeChange 触发，不等稳定读）。 */
  private refreshLayoutNow(): void {
    const horizontalLayout = this.readHorizontalLayoutOrNull();
    if (horizontalLayout === null ||
      horizontalLayout === this.snapshot.horizontalLayout) {
      return;
    }
    this.adopt({
      portraitForm: this.snapshot.portraitForm,
      horizontalLayout: horizontalLayout,
    });
  }

  /** 去抖后做稳定读重判（foldStatusChange / windowSizeChange 触发）。 */
  private requestRecheck(): void {
    this.cancelRecheck();
    const gen = this.generation;
    this.recheckTimer = setTimeout(() => {
      this.recheckTimer = -1;
      if (gen !== this.generation) {
        return;
      }
      this.readStable(gen, 0);
    }, RECHECK_DELAY_MS);
  }

  /**
   * 稳定读：折展动画过程中默认屏幕尺寸可能还在变，连续两次采样一致才采纳；
   * 始终不一致时在最大次数后采纳最后一次，避免永远不更新。读取失败的采样
   * 不采纳，全部失败时保持旧形态。
   */
  private readStable(gen: number, attempt: number): void {
    const first = this.readSnapshotOrNull();
    setTimeout(() => {
      if (gen !== this.generation) {
        return;
      }
      const second = this.readSnapshotOrNull();
      if (second === null) {
        if (attempt + 1 < STABLE_MAX_ATTEMPTS) {
          this.readStable(gen, attempt + 1);
        }
        return;
      }
      const stable = first !== null &&
        first.portraitForm === second.portraitForm &&
        first.horizontalLayout === second.horizontalLayout;
      if (stable || attempt + 1 >= STABLE_MAX_ATTEMPTS) {
        this.adopt(second);
        return;
      }
      this.readStable(gen, attempt + 1);
    }, STABLE_SAMPLE_DELAY_MS);
  }

  private adopt(next: DeviceFormSnapshot): void {
    if (next.portraitForm === this.snapshot.portraitForm &&
      next.horizontalLayout === this.snapshot.horizontalLayout) {
      return;
    }
    this.snapshot = next;
    console.info('DeviceForm', `form changed: ${JSON.stringify(next)}`);
    const listener = this.listener;
    if (listener !== null) {
      listener({
        portraitForm: next.portraitForm,
        horizontalLayout: next.horizontalLayout,
      });
    }
  }

  private cancelRecheck(): void {
    if (this.recheckTimer !== -1) {
      clearTimeout(this.recheckTimer);
      this.recheckTimer = -1;
    }
  }
}

export const deviceFormState: DeviceFormState = new DeviceFormState();
