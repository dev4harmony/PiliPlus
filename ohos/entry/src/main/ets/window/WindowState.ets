import { BusinessError } from "@kit.BasicServicesKit";
import window from "@ohos.window";
import { TITLE_BAR_HEIGHT, WindowChromeController, WindowChromeState } from "./WindowChrome";
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
  /// 标题带是否被鼠标唤出（仅自动收起态为 true）。Dart 侧据此让播放器顶部
  /// 按钮整体下移，避免被呼出的标题带盖住。
  titleBarRevealed: boolean;
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
  /// 登记到 WindowChrome 的订阅。detach 时用它反注册，避免重复 attach 时
  /// 在 chrome 上堆积多份（每次都会触发一遍快照 + 安全区重算与推送）。
  private chromeListener: ((s: WindowChromeState) => void) | null = null;

  attach(win: window.Window, chrome: WindowChromeController): void {
    if (this.win === win && this.chrome === chrome && this.chromeListener !== null) {
      // 幂等：热启动接续会再走一遍窗口创建流程，重复登记只会让推送翻倍。
      this.emitSnapshot();
      this.emitSafeArea();
      return;
    }
    // 避让区监听可能已经由 Dart 侧 getSafeArea 抢先装在同一个窗口上（插件
    // attach 早于窗口创建，Dart 首帧也可能早于 onWindowStageCreate）。下面
    // 的窗口级清理会把监听摘掉，必须在末尾按原状态重新装上，否则旋转后再
    // 也没有 avoidAreaChange 推送。
    const wasListening = this.safeAreaListening;
    this.detachWindow();
    this.win = win;
    this.chrome = chrome;
    const listener = (s: WindowChromeState): void => {
      this.emitSnapshot();
      // 标题带占位等价于一条顶部安全区，状态一变必须重推安全区，
      // 否则 Dart 侧留白与原生实际占位错位。
      this.emitSafeArea();
    };
    this.chromeListener = listener;
    chrome.onChange(listener);
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
    if (wasListening) {
      // 换窗口后重新挂避让监听（旧窗口的监听已在 detachWindow 里摘掉）。
      this.startSafeAreaListener();
    }
    // attach 时的首次 sync 发生在订阅之前，这里补推一次初值。
    this.emitSnapshot();
    this.emitSafeArea();
  }

  /**
   * 只清理**窗口作用域**的资源：避让监听、系统栏状态机、chrome 订阅。
   *
   * 与 [detach] 的区别：不清 [snapshotListener] / [safeAreaListener]——那两个
   * 是插件挂上来的引擎级推送回调，只在 onDestroy 时才解除。attach 复用它，
   * 避免重挂窗口时把推送通道一并拔掉（表现为初值正常、之后再也不更新）。
   */
  private detachWindow(): void {
    this.stopSafeAreaListener();
    this.systemBars?.detach();
    this.systemBars = null;
    if (this.chrome !== null && this.chromeListener !== null) {
      this.chrome.offChange(this.chromeListener);
    }
    this.chromeListener = null;
    this.chrome = null;
    this.win = null;
    this.lastSnapshotSignature = "";
  }

  detach(): void {
    this.detachWindow();
    this.snapshotListener = null;
    this.safeAreaListener = null;
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

  /// 应用窗口方向策略（五种，由 Dart 侧按「设备形态 + 页面类型 + 视频方向 +
  /// 是否全屏」决定）：
  /// - `portraitOnly`：AUTO_ROTATION_PORTRAIT —— 仅竖向，不受旋转锁定控制，
  ///   用于细长竖屏形态设备的非播放页 / 竖屏视频（含全屏）。
  /// - `userPortrait`：USER_ROTATION_PORTRAIT —— 临时旋转到竖屏，之后跟随
  ///   传感器（受旋转锁定控制）。用于细长竖屏形态设备「横屏视频、非全屏」的
  ///   播放页：进入播放页 / 退出全屏时先把窗口转回竖屏，避免横置手机直接
  ///   横屏全屏、或退出全屏后又被「窗口横屏自动进全屏」拉回。
  /// - `userLandscape`：USER_ROTATION_LANDSCAPE —— 临时旋转到横屏，之后跟随
  ///   传感器（受旋转锁定控制）：锁关时转竖屏会跟回竖屏（用于自动退出全屏），
  ///   锁开时保持横屏。用于细长竖屏形态设备的横屏视频全屏。
  /// - `landscapeOnly`：AUTO_ROTATION_LANDSCAPE —— 仅横向两方向、不受旋转
  ///   锁定控制，用于旋转锁定打开时的横屏视频全屏（180° 翻转可用，但窗口
  ///   不会转竖屏退出，只能点按钮）。
  /// - `follow`：AUTO_ROTATION_RESTRICTED —— 四方向跟随重力/智感，受旋转锁定
  ///   控制，用于平板/2in1/阔折叠等跟随系统的形态，以及全屏中窗口已是横屏
  ///   的状态（不再重复请求旋转）。
  ///
  /// 应用不再下发固定方向（PORTRAIT/LANDSCAPE），也不读取系统旋转锁。
  async setWindowOrientation(policy: string): Promise<void> {
    this.win ??= await window.getLastWindow(getContext());
    let orientation: window.Orientation;
    switch (policy) {
      case 'portraitOnly':
        orientation = window.Orientation.AUTO_ROTATION_PORTRAIT;
        break;
      case 'userPortrait':
        orientation = window.Orientation.USER_ROTATION_PORTRAIT;
        break;
      case 'userLandscape':
        orientation = window.Orientation.USER_ROTATION_LANDSCAPE;
        break;
      case 'landscapeOnly':
        orientation = window.Orientation.AUTO_ROTATION_LANDSCAPE;
        break;
      default:
        orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
        break;
    }
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
      'titleBarRevealed': chrome?.titleBarRevealed ?? false,
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
    // 只在标题带真正占位时并入（titleBarHeight > 0）：全屏自动收起时高度为 0，
    // 内容要能铺满窗口，唤出的标题带浮在内容之上、不推挤布局。
    //
    // 例外是「标题带被鼠标唤出」：此时也要把标题带高度并进安全区，让播放器
    // 顶部那排按钮整体下移，避免呼出的标题带把它们盖住、点不到。
    let titleInset = 0;
    const chrome = this.chrome?.getState();
    if (chrome !== undefined) {
      if (chrome.titleBarHeight > 0) {
        titleInset = this.vp2px(chrome.titleBarHeight);
      } else if (chrome.titleBarRevealed) {
        titleInset = this.vp2px(TITLE_BAR_HEIGHT);
      }
    }
    // 先只算系统避让带（四边），它们构成「已经让位过」的区域，
    // 后面判断挖孔是否落在其中。
    const sysLeft = sys !== undefined ? WindowState.leadingInset(sys.leftRect, true) : 0;
    const sysTop = sys !== undefined ? WindowState.leadingInset(sys.topRect, false) : 0;
    const sysRight = sys !== undefined
      ? WindowState.trailingInset(sys.rightRect, winWidth, true) : 0;
    const sysBottom = sys !== undefined
      ? WindowState.trailingInset(sys.bottomRect, winHeight, false) : 0;
    let top = Math.max(sysTop, titleInset);
    let left = sysLeft;
    let right = sysRight;
    let bottom = sysBottom;

    // CUTOUT 逐边并入。
    //
    // 关键：OpenHarmony 的 TYPE_CUTOUT 只把挖孔矩形写进**一条边**（见
    // window_window_manager 的 avoid_area_controller.cpp，GetAvoidPosType 用两条
    // 对角线把挖孔中心归类到 top/left/right/bottom 之一）。所以角落挖孔会被
    // 归到 LEFT 或 TOP 而不是"两边都有"，若直接按该边并入，落在状态栏里的
    // 角落挖孔就会凭空多出「挖孔宽/高」的侧边距——它其实已被状态栏那条带盖住。
    //
    // 因此逐边判断：该边的挖孔矩形若整段落在任一已避让带内，就不计这一边。
    const cutLeftRect = cut?.leftRect;
    const cutTopRect = cut?.topRect;
    const cutRightRect = cut?.rightRect;
    const cutBottomRect = cut?.bottomRect;
    let cutoutCovered = false;
    if (cut !== undefined) {
      cutoutCovered = WindowState.cutoutInsideBands(cut, winWidth, winHeight,
        left, top, right, bottom);
    }
    if (!cutoutCovered) {
      // 顶部：挖孔整段落在左右系统带里时不重复让位。
      if (cutTopRect !== undefined && cutTopRect.height > 0 &&
        !WindowState.rectInsideSideBands(cutTopRect, winWidth, left, right)) {
        top = Math.max(top, WindowState.leadingInset(cutTopRect, false));
      }
      // 左/右：挖孔整段落在顶部（含标题带）或底部带里时不重复让位。
      if (cutLeftRect !== undefined && cutLeftRect.width > 0 &&
        !WindowState.rectInsideVerticalBands(cutLeftRect, winHeight, top, bottom)) {
        left = Math.max(left, WindowState.leadingInset(cutLeftRect, true));
      }
      if (cutRightRect !== undefined && cutRightRect.width > 0 &&
        !WindowState.rectInsideVerticalBands(cutRightRect, winHeight, top, bottom)) {
        right = Math.max(right, WindowState.trailingInset(cutRightRect, winWidth, true));
      }
      if (cutBottomRect !== undefined && cutBottomRect.height > 0 &&
        !WindowState.rectInsideSideBands(cutBottomRect, winWidth, left, right)) {
        bottom = Math.max(bottom, WindowState.trailingInset(cutBottomRect, winHeight, false));
      }
    }
    const insets: SafeAreaInsets = {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    };
    return insets;
  }

  /**
   * 挖孔避让区是否**整体**已被系统避让带覆盖（此时并入它没有任何新增让位）。
   *
   * 只检出非空的那条矩形（OpenHarmony 只填一条边），再看它是否整段落在
   * 顶部 / 底部 / 左侧 / 右侧任一条带内。
   */
  private static cutoutInsideBands(cut: window.AvoidArea, winWidth: number, winHeight: number,
    left: number, top: number, right: number, bottom: number): boolean {
    const rect = WindowState.nonEmptyRect(cut);
    if (rect === undefined) {
      return true;
    }
    return WindowState.rectInsideVerticalBands(rect, winHeight, top, bottom) ||
      WindowState.rectInsideSideBands(rect, winWidth, left, right);
  }

  /// 取避让区里第一条非空矩形（OpenHarmony 的 CUTOUT 只填一条边）。
  private static nonEmptyRect(cut: window.AvoidArea | undefined): window.Rect | undefined {
    if (cut === undefined) {
      return undefined;
    }
    const rects: window.Rect[] = [cut.leftRect, cut.topRect, cut.rightRect, cut.bottomRect];
    for (const rect of rects) {
      if (rect !== undefined && (rect.width > 0 || rect.height > 0)) {
        return rect;
      }
    }
    return undefined;
  }

  /**
   * 矩形是否被顶部带 [0, top] 或底部带 [winHeight - bottom, winHeight] 吃掉。
   *
   * 两种情形算吃掉：
   * 1. **整段包含**：矩形整个落在带内（状态栏比挖孔高时最常见）；
   * 2. **角落锚定**：矩形近侧边贴在带内（`rect.top <= top`），说明它是顶角/底角
   *    的挖孔——平台按对角线把它归到了 LEFT/RIGHT，但它其实是"角上的孔"，
   *    顶部避让带已经把那个角让出来了。若不这么判，横屏角落挖孔会凭空多出
   *    一整个挖孔宽度的左边距（真实坐标只被顶部带挡住）。
   *
   * 代价：一个从角上起始、却向下伸得远比状态栏高的挖孔，会被少让一点侧边
   * 距离。真机上挖孔直径远小于状态栏高度，不构成实际问题。
   */
  private static rectInsideVerticalBands(rect: window.Rect, winHeight: number,
    top: number, bottom: number): boolean {
    if (rect.height <= 0) {
      return false;
    }
    if (top > 0 && rect.top >= 0 && rect.top + rect.height <= top) {
      return true;
    }
    if (top > 0 && rect.top >= 0 && rect.top <= top) {
      // 角落锚定：孔的近侧边已经在顶部带里。
      return true;
    }
    if (bottom > 0 && rect.top + rect.height <= winHeight && rect.top >= winHeight - bottom) {
      return true;
    }
    if (bottom > 0 && rect.top + rect.height <= winHeight &&
      rect.top + rect.height >= winHeight - bottom) {
      // 底角锚定：孔的远侧边已经在底部带里。
      return true;
    }
    return false;
  }

  /** 矩形是否整段落在左侧带 [0, left] 或右侧带 [winWidth - right, winWidth] 内。 */
  private static rectInsideSideBands(rect: window.Rect, winWidth: number,
    left: number, right: number): boolean {
    if (rect.width <= 0) {
      return false;
    }
    if (left > 0 && rect.left >= 0 && rect.left + rect.width <= left) {
      return true;
    }
    if (right > 0 && rect.left + rect.width <= winWidth && rect.left >= winWidth - right) {
      return true;
    }
    return false;
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
      `${snapshot.contentFullScreen}|${snapshot.titleBarVisible}|${snapshot.titleBarRevealed}|` +
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
      // 画中画进入/退出等
      w.on('windowStatusChange', this.safeAreaChangeCallback);
    } catch (err) {
      console.error("WindowState", `safe area listener failed: ${err}`);
      // 任一失败就保持未监听，下次拉取时重装，避免半装状态
      try {
        w.off('avoidAreaChange', this.safeAreaChangeCallback);
        w.off('windowSizeChange', this.safeAreaChangeCallback);
        w.off('windowStatusChange', this.safeAreaChangeCallback);
      } catch (offErr) {
        console.error("WindowState", `safe area listener rollback failed: ${offErr}`);
      }
      return;
    }
    this.safeAreaListening = true;
  }

  private safeAreaChangeCallback = (): void => {
    this.emitSafeArea();
    // 状态栏/画中画切换中系统可能更新避让区不及时，需要幂等延时重读
    if (this.safeAreaDelayedTimer !== -1) {
      clearTimeout(this.safeAreaDelayedTimer);
    }
    this.safeAreaDelayedTimer = setTimeout(() => {
      this.safeAreaDelayedTimer = -1;
      this.emitSafeArea();
    }, 32);
  };
  private safeAreaDelayedTimer: number = -1;

  private stopSafeAreaListener(): void {
    if (!this.safeAreaListening) {
      return;
    }
    this.safeAreaListening = false;
    try {
      this.win?.off('avoidAreaChange', this.safeAreaChangeCallback);
      this.win?.off('windowSizeChange', this.safeAreaChangeCallback);
      this.win?.off('windowStatusChange', this.safeAreaChangeCallback);
      if (this.safeAreaDelayedTimer !== -1) {
        clearTimeout(this.safeAreaDelayedTimer);
        this.safeAreaDelayedTimer = -1;
      }
    } catch (err) {
      console.error("WindowState", `safe area listener off failed: ${err}`);
    }
  }
}

export const windowState = new WindowState();
