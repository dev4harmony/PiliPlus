import { BusinessError } from "@kit.BasicServicesKit";
import window from "@ohos.window";
import { WindowChromeController, WindowChromeState } from "./WindowChrome";
import { SystemBarsController } from "./SystemBars";

/**
 * 窗口快照：Dart 侧据此维护窗口形态（自由窗口 / 小窗 / 受限窗口）、
 * 自绘标题带显隐与全屏状态。字段与 Dart 侧 WindowFacts 一一对应。
 */
export interface WindowSnapshot {
  isFreeWindowMode: boolean;
  maximized: boolean;
  contentFullScreen: boolean;
  titleBarVisible: boolean;
  titleBarHeight: number;
  isMiniWindow: boolean;
  isWindowMode: boolean;
}

/** 安全区避让区（物理像素，窗口相对坐标）。 */
export interface SafeAreaInsets {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export type WindowSnapshotListener = (snapshot: WindowSnapshot) => void;
export type SafeAreaListener = (insets: SafeAreaInsets) => void;

/**
 * 窗口级状态中心：窗口句柄、系统栏状态机、安全区读取与推送都在这里。
 *
 * Dart 侧通过 MethodChannel 'harmonyChannel' 主动拉取（getWindowSnapshot /
 * getSafeArea），之后靠 onWindowSnapshot / onSafeAreaChange 两条反向推送接收变化；
 * 本类不持有任何 Flutter 侧的业务判断。
 */
export class WindowState {
  private win: window.Window | null = null;
  private chrome: WindowChromeController | null = null;
  private systemBars: SystemBarsController | null = null;

  private snapshotListener: WindowSnapshotListener | null = null;
  private safeAreaListener: SafeAreaListener | null = null;

  private safeAreaListening: boolean = false;
  private safeAreaStarting: Promise<void> | null = null;
  private lastSnapshotSignature: string = "";

  attach(win: window.Window, chrome: WindowChromeController): void {
    this.win = win;
    this.chrome = chrome;
    chrome.onChange((s: WindowChromeState) => {
      this.emitSnapshot();
      // 标题带占位等价于一条顶部安全区，状态一变必须重推安全区，
      // 否则 Dart 侧留白与原生实际占位错位。
      this.emitSafeArea();
    });
    // 系统栏状态机独立于标题带：apply 完成同时通知标题带收起与安全区重推。
    if (this.systemBars === null) {
      const bars = new SystemBarsController();
      bars.onApplied((hidden: boolean) => {
        chrome.setBarsHidden(hidden);
        // 系统栏显隐会改 TYPE_SYSTEM 的 topRect，必须重推一次安全区。
        this.emitSafeArea();
      });
      bars.attach(win);
      chrome.bindSystemBars(bars);
      this.systemBars = bars;
    }
    // attach 时的首次 sync 发生在订阅之前，这里补推一次初值。
    this.emitSnapshot();
    this.emitSafeArea();
  }

  detach(): void {
    this.stopSafeAreaListener();
    this.systemBars?.detach();
    this.systemBars = null;
    this.chrome = null;
    this.win = null;
    this.snapshotListener = null;
    this.safeAreaListener = null;
    this.lastSnapshotSignature = "";
  }

  /** 登记窗口快照推送回调（传 null 解除）；登记即补推一次当前值。 */
  setSnapshotListener(listener: WindowSnapshotListener | null): void {
    this.snapshotListener = listener;
    if (listener !== null) {
      this.lastSnapshotSignature = "";
      this.emitSnapshot();
    }
  }

  /** 登记安全区推送回调（传 null 解除）；登记即补推一次当前值。 */
  setSafeAreaListener(listener: SafeAreaListener | null): void {
    this.safeAreaListener = listener;
    if (listener !== null) {
      this.emitSafeArea();
    }
  }

  /** 主动重推一次安全区（系统栏切换等会改 TYPE_SYSTEM 的时机）。 */
  notifySafeArea(): void {
    this.emitSafeArea();
  }

  /** 窗口状态（FLOATING / SPLIT_SCREEN / MAXIMIZE …）变化后由 EntryAbility 调用。 */
  refreshStatus(): void {
    this.emitSnapshot();
    this.emitSafeArea();
  }

  async syncSystemBars(hidden: boolean, revision: number, epoch: number): Promise<void> {
    if (this.systemBars !== null) {
      await this.systemBars.sync(hidden, revision, epoch);
      return;
    }
    // 兜底：控制器尚未绑定（窗口创建早期）时按命令直接执行。Dart 侧下一次
    // 同步会带更高 revision，晚到的旧命令不会覆盖它。
    this.win ??= await window.getLastWindow(getContext());
    await this.win.setSpecificSystemBarEnabled("status", !hidden, false);
    await this.win.setSpecificSystemBarEnabled("navigation", !hidden, false);
    await this.win.setSpecificSystemBarEnabled("navigationIndicator", !hidden, false);
  }

  async setWindowOrientation(orientation: number): Promise<void> {
    this.win ??= await window.getLastWindow(getContext());
    await this.win.setPreferredOrientation(orientation);
  }

  async setMiniWindowLandscape(landscape: boolean): Promise<void> {
    this.win ??= await window.getLastWindow(getContext());
    if (landscape) {
      await this.win.enableLandscapeMultiWindow();
    } else {
      await this.win.disableLandscapeMultiWindow();
    }
  }

  /** 无 WindowChrome 的降级路径：自由窗口形态下装饰栏策略由 WindowChrome 独占。 */
  setDecorVisible(visible: boolean): boolean {
    try {
      this.win?.setWindowDecorVisible(visible);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      console.warn("WindowState", `setWindowDecorVisible(${visible}) skipped: ${e.code} ${e.message}`);
      return false;
    }
  }

  readSnapshot(): WindowSnapshot {
    const chrome = this.chrome?.getState();
    const status = this.readStatus();
    const snapshot: WindowSnapshot = {
      'isFreeWindowMode': chrome?.isFreeWindowMode ?? false,
      'maximized': chrome?.maximized ?? false,
      'contentFullScreen': chrome?.contentFullScreen ?? false,
      'titleBarVisible': chrome?.titleBarVisible ?? false,
      'titleBarHeight': chrome?.titleBarHeight ?? 0,
      'isMiniWindow': status === window.WindowStatusType.FLOATING,
      'isWindowMode': status === window.WindowStatusType.FLOATING ||
        status === window.WindowStatusType.SPLIT_SCREEN,
    };
    return snapshot;
  }

  readSafeArea(): SafeAreaInsets {
    let sys: window.AvoidArea | undefined = undefined;
    let cut: window.AvoidArea | undefined = undefined;
    let winWidth = 0;
    let winHeight = 0;
    try {
      sys = this.win?.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      cut = this.win?.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const winRect = this.win?.getWindowProperties().windowRect;
      if (winRect) {
        winWidth = winRect.width;
        winHeight = winRect.height;
      }
    } catch (err) {
      console.error("WindowState", `readSafeArea failed: ${err}`);
    }
    // 自绘标题带占据窗口顶部，等价于一条顶部安全区：并进来后 Dart 侧无需感知标题带。
    let titleInset = 0;
    const chrome = this.chrome?.getState();
    if (chrome !== undefined && chrome.titleBarVisible) {
      titleInset = this.vp2px(chrome.titleBarHeight);
    }
    const top = Math.max(
      Math.max(
        sys ? WindowState.leadingInset(sys.topRect, false) : 0,
        cut ? WindowState.leadingInset(cut.topRect, false) : 0),
      titleInset);
    // 角落挖孔去重：顶部已经避让到的挖孔，不在侧边重复避让。
    const leftCutCovered = WindowState.cutoutCoveredByTop(cut?.leftRect, top);
    const rightCutCovered = WindowState.cutoutCoveredByTop(cut?.rightRect, top);
    const insets: SafeAreaInsets = {
      'left': Math.max(
        sys ? WindowState.leadingInset(sys.leftRect, true) : 0,
        cut && !leftCutCovered ? WindowState.leadingInset(cut.leftRect, true) : 0),
      'top': top,
      'right': Math.max(
        sys ? WindowState.trailingInset(sys.rightRect, winWidth, true) : 0,
        cut && !rightCutCovered ? WindowState.trailingInset(cut.rightRect, winWidth, true) : 0),
      'bottom': Math.max(
        sys ? WindowState.trailingInset(sys.bottomRect, winHeight, false) : 0,
        cut ? WindowState.trailingInset(cut.bottomRect, winHeight, false) : 0),
    };
    return insets;
  }

  /**
   * 左/上边的安全距离，0 宽/高视为无障碍。
   *
   * 避让区矩形贴窗口左/上缘（left=0 / top=0），故取「近侧坐标 + 尺寸」；竖屏
   * 挖孔不贴屏幕顶边，只取 height 会少让出 top 这段。
   */
  private static leadingInset(rect: window.Rect, horizontal: boolean): number {
    if (horizontal) {
      return rect.width > 0 ? rect.left + rect.width : 0;
    }
    return rect.height > 0 ? rect.top + rect.height : 0;
  }

  /**
   * 右/下边的安全距离，0 宽/高视为无障碍。
   *
   * 从窗口远侧缘量起：横屏右旋时挖孔落在右边，rightRect 为
   * {left: W - d, width: d}，用 [leadingInset] 的 left + width 会算出整窗宽度。
   */
  private static trailingInset(rect: window.Rect, winSize: number, horizontal: boolean): number {
    if (horizontal) {
      return rect.width > 0 ? winSize - rect.left : 0;
    }
    return rect.height > 0 ? winSize - rect.top : 0;
  }

  /** 该侧 cutout 矩形是否已经被顶部避让带整块盖住（平板前摄常在角落）。 */
  private static cutoutCoveredByTop(rect: window.Rect | undefined, topInset: number): boolean {
    if (topInset <= 0 || rect === undefined || rect.height <= 0) {
      return false;
    }
    return rect.top >= 0 && rect.top + rect.height <= topInset;
  }

  /** vp → 物理像素。避让区接口一律返回像素，标题带高度是 vp，并入前需换算。 */
  private vp2px(value: number): number {
    try {
      return this.win?.getUIContext().vp2px(value) ?? value;
    } catch (err) {
      return value;
    }
  }

  private readStatus(): window.WindowStatusType {
    try {
      return this.win?.getWindowStatus() ?? window.WindowStatusType.UNDEFINED;
    } catch (err) {
      return window.WindowStatusType.UNDEFINED;
    }
  }

  private emitSnapshot(): void {
    const listener = this.snapshotListener;
    if (listener === null) {
      return;
    }
    const snapshot = this.readSnapshot();
    const signature = `${snapshot.isFreeWindowMode}|${snapshot.maximized}|` +
      `${snapshot.contentFullScreen}|${snapshot.titleBarVisible}|` +
      `${snapshot.titleBarHeight}|${snapshot.isMiniWindow}|${snapshot.isWindowMode}`;
    if (signature === this.lastSnapshotSignature) {
      return;
    }
    this.lastSnapshotSignature = signature;
    listener(snapshot);
  }

  /**
   * 不做值去重：旋转时避让区四元组可能逐位不变（如竖横屏顶部高度相同），
   * 去重会吞掉这次方向变化。重复推送无害，Dart 侧自带判等。
   */
  private emitSafeArea(): void {
    const listener = this.safeAreaListener;
    if (listener === null) {
      return;
    }
    listener(this.readSafeArea());
  }

  startSafeAreaListener(): Promise<void> {
    // 不能提前置位 safeAreaListening 防重入：await 期间再进来会重复 on()，而
    // await 抛错时提前置位会让后续调用全部 return、监听器永不安装。故复用同一个
    // Promise 等待上次安装完成，只在真正 on() 成功后置位。
    if (this.safeAreaListening) {
      return Promise.resolve();
    }
    if (this.safeAreaStarting != null) {
      return this.safeAreaStarting;
    }
    const starting = this.doStartSafeAreaListener();
    this.safeAreaStarting = starting;
    return starting.finally(() => {
      this.safeAreaStarting = null;
    });
  }

  private async doStartSafeAreaListener(): Promise<void> {
    try {
      this.win ??= await window.getLastWindow(getContext());
    } catch (err) {
      // 拿不到窗口就保持未监听状态，下一次拉取安全区会重试。
      console.error("WindowState", `getLastWindow for safe area failed: ${err}`);
      return;
    }
    const w = this.win;
    try {
      w.on('avoidAreaChange', this.safeAreaChangeCallback);
      // 旋转/窗口尺寸变化后兜底重读一次：部分机型旋转时不会单独推送
      // TYPE_CUTOUT 的 avoidAreaChange。
      w.on('windowSizeChange', this.safeAreaChangeCallback);
    } catch (err) {
      console.error("WindowState", `safe area listener failed: ${err}`);
      // 任一失败就保持未监听，下次拉取时重装，避免半装状态
      try {
        w.off('avoidAreaChange', this.safeAreaChangeCallback);
        w.off('windowSizeChange', this.safeAreaChangeCallback);
      } catch (offErr) {
        console.error("WindowState", `safe area listener rollback failed: ${offErr}`);
      }
      return;
    }
    this.safeAreaListening = true;
  }

  private safeAreaChangeCallback = (): void => {
    this.emitSafeArea();
  };

  private stopSafeAreaListener(): void {
    if (!this.safeAreaListening) {
      return;
    }
    this.safeAreaListening = false;
    try {
      this.win?.off('avoidAreaChange', this.safeAreaChangeCallback);
      this.win?.off('windowSizeChange', this.safeAreaChangeCallback);
    } catch (err) {
      console.error("WindowState", `safe area listener off failed: ${err}`);
    }
  }
}

export const windowState = new WindowState();
