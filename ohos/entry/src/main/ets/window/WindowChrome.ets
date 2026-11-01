import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { SystemBarsController } from './SystemBars';

/// 自绘标题带高度（vp）。合法装饰高度为 [37,112]，取 40 与系统标题栏观感一致。
export const TITLE_BAR_HEIGHT: number = 40;

/// 标题带底色不再由原生固定：改由 Dart 侧主题同步下发
/// （`setTitleBarBackground` → AppStorage `titleBarBackground`），与 Flutter
/// 页面背景同色，深浅模式与纯黑主题都跟着 Dart 走。原生只留资源色兜底
/// （`app.color.title_bar_background`），供首帧 / 主题尚未同步时使用。
/// 三键与顶栏分类页签仍用 ColoringStrategy.INVERT（前景取背景反色），
/// 底色换色无需改动任何一处前景色。

/// 装饰栏下发失败后的重试间隔（ms）。
const DECOR_RETRY_DELAY_MS: number = 150;

/// 窗口外观状态的唯一真源。UI（Index）与 Dart（经 WindowHost）都只读它。
export interface WindowChromeState {
  /// 自由窗口形态：2in1/PC、平板自由多窗或电脑模式。手机与平板普通模式为 false。
  isFreeWindowMode: boolean;
  status: window.WindowStatusType;
  maximized: boolean;
  contentFullScreen: boolean;
  titleBarVisible: boolean;
  /// 标题带占用的顶部高度（vp），0 表示不占位。
  titleBarHeight: number;
}

export type WindowChromeListener = (state: WindowChromeState) => void;

/// 下发给 Dart 的窗口外观状态（channel 载荷），字段名与 Dart 侧一致。
export interface WindowChromePayload {
  isFreeWindowMode: boolean;
  maximized: boolean;
  contentFullScreen: boolean;
  titleBarVisible: boolean;
  titleBarHeight: number;
}

/// 自由窗口形态下的窗口外观控制器：装饰栏显隐、标题带状态、最大化/还原、内容全屏。
/// 状态变化统一经 [listeners] 广播，订阅方各自决定如何消费。
export class WindowChromeController {
  private win: window.Window | null = null;
  private contentFullScreen: boolean = false;
  private statusBeforeFullScreen: window.WindowStatusType | null = null;
  private listeners: WindowChromeListener[] = [];
  private lastSignature: string = '';
  /// null = 从未下发过，true/false = 最近一次下发的「自由窗口形态」取值。
  private decorAppliedForFree: boolean | null = null;
  /// 窗口内容是否已加载。装饰栏相关接口（setWindowDecorVisible /
  /// setWindowDecorHeight）官方要求「Stage 模型下需在 loadContent() 或
  /// setUIContent() 调用生效后使用」，早于此时机下发的调用不会生效，
  /// 而失败只会被 try/catch 吞成一条 warn —— 表现为系统三键始终不消失。
  /// 故 attach 阶段只登记窗口，真正下发推迟到 [onContentLoaded]。
  private contentLoaded: boolean = false;
  /// 装饰栏下发重试计数。形态切换（自由窗口 ↔ 全屏/最大化）瞬间系统可能
  /// 尚未就绪，setWindowTitleButtonVisible 会以 801 拒绝，稍后重试即可。
  private decorRetryTimer: number = -1;
  /// 标题带是否为深色内容，见 [setTitleBarDark]。
  private titleBarDark: boolean = false;
  /// 系统栏是否已隐藏（Dart 侧 `SystemBars` 同步下来的状态）：标题带收起，见 [setBarsHidden]。
  private barsHidden: boolean = false;
  /// 最近一次从 Dart 侧同步下来的标题带底色，空串表示尚未同步，见 [setTitleBarBackground]。
  private titleBarBackground: string = '';

  /// 系统栏状态机：窗口级状态在 [SystemBarsController]，本类只按它的 apply 结果
  /// 收起自绘标题带（`barsHidden`）。由 WindowState 注入，本类不拥有它。
  private systemBars: SystemBarsController | null = null;

  private statusCallback = (): void => {
    this.sync();
  };
  private freeCallback = (): void => {
    this.sync();
  };
  /// 登记主窗并开始监听状态变化。
  ///
  /// 注意此处**不**下发装饰栏：本方法运行在 onWindowStageCreate 内、loadContent
  /// 之前，官方要求这些接口在 loadContent 生效后调用，否则静默不生效。
  /// FlutterAbility 不会暴露 loadContent 回调，因此由 Index 页面
  /// aboutToAppear 回调 [onContentLoaded] 补上。
  attach(win: window.Window): void {
    this.win = win;
    try {
      if (deviceInfo.sdkApiVersion >= 20) {
        win.on('windowStatusDidChange', this.statusCallback);
      } else {
        win.on('windowStatusChange', this.statusCallback);
      }
    } catch (err) {
      const e = err as BusinessError;
      console.error('WindowChrome', `window status listener failed: ${e.code} ${e.message}`);
    }
    try {
      if (deviceInfo.sdkApiVersion >= 22) {
        win.on('freeWindowModeChange', this.freeCallback);
      }
    } catch (err) {
      const e = err as BusinessError;
      console.error('WindowChrome', `freeWindowMode listener failed: ${e.code} ${e.message}`);
    }
    this.sync();
  }

  /// 窗口内容已加载（由 Index 的 aboutToAppear 调用）：此为装饰栏接口的
  /// 最早生效时机，重算并强制下发一次。
  onContentLoaded(): void {
    if (this.contentLoaded) {
      return;
    }
    this.contentLoaded = true;
    this.decorAppliedForFree = null;
    this.lastSignature = '';
    this.sync();
    // 系统栏同样要等 loadContent 之后下发才稳妥（官方对窗口接口的时机要求），
    // 而 Dart 侧可能早在首帧前就同步过「需要隐藏」，交给窗口级状态机重放。
    this.systemBars?.onContentLoaded();
  }

  detach(): void {
    if (this.win === null) {
      return;
    }
    this.clearDecorRetry();
    try {
      if (deviceInfo.sdkApiVersion >= 20) {
        this.win.off('windowStatusDidChange', this.statusCallback);
      } else {
        this.win.off('windowStatusChange', this.statusCallback);
      }
      if (deviceInfo.sdkApiVersion >= 22) {
        this.win.off('freeWindowModeChange', this.freeCallback);
      }
    } catch (err) {
      console.error('WindowChrome', `detach failed: ${err}`);
    }
    this.win = null;
    this.contentLoaded = false;
    this.decorRetryTimer = -1;
    this.decorAppliedForFree = null;
    this.lastSignature = '';
  }

  /// 注入窗口级系统栏状态机（WindowState 持有）。本类只消费它的 apply 结果
  /// 来收起标题带；状态本身不在这里维护 —— 系统栏不是自由窗口标题栏的私产。
  bindSystemBars(controller: SystemBarsController): void {
    this.systemBars = controller;
  }

  onChange(listener: WindowChromeListener): void {
    this.listeners.push(listener);
  }

  getState(): WindowChromeState {
    const status = this.readStatus();
    const isFree = this.readFreeWindowMode();
    // 内容全屏与 FULL_SCREEN 下都不画标题带：前者是应用主动隐藏，后者是窗口铺满全屏。
    // 是否最大化只影响三键图标形态，不影响标题带显隐——最大化后仍然自绘。
    const visible = isFree && !this.contentFullScreen && status !== window.WindowStatusType.FULL_SCREEN;
    return {
      isFreeWindowMode: isFree,
      status: status,
      maximized: this.isMaximizedStatus(status),
      contentFullScreen: this.contentFullScreen,
      titleBarVisible: visible,
      titleBarHeight: visible ? TITLE_BAR_HEIGHT : 0,
    };
  }

  /// 是否处于「最大化」形态。FULL_SCREEN 必须一并算入：在自由窗口形态下，
  /// targetAPIVersion < 14 的应用最大化时 getWindowStatus() 返回的正是
  /// FULL_SCREEN（见 getWindowStatus 文档），只看 MAXIMIZE 会让三键图标
  /// 停在「最大化」态，点它反而又去 maximize。
  private isMaximizedStatus(status: window.WindowStatusType): boolean {
    return status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN;
  }

  /// 重算并下发。可重复调用，仅在状态真正变化时广播。
  sync(): void {
    if (this.win === null) {
      return;
    }
    const state = this.getState();
    this.applyDecor(state.isFreeWindowMode);
    const signature = `${state.isFreeWindowMode}|${state.status}|${state.titleBarVisible}|${state.contentFullScreen}`;
    if (signature === this.lastSignature) {
      return;
    }
    this.lastSignature = signature;
    AppStorage.setOrCreate('titleBarVisible', state.titleBarVisible);
    AppStorage.setOrCreate('titleBarHeight', state.titleBarHeight);
    AppStorage.setOrCreate('windowMaximized', state.maximized);
    AppStorage.setOrCreate('windowFreeMode', state.isFreeWindowMode);
    AppStorage.setOrCreate('titleBarDark', this.titleBarDark);
    this.listeners.forEach((listener: WindowChromeListener) => {
      listener(state);
    });
  }

  /// 自由窗口形态下隐藏系统装饰栏与系统三键，由自绘标题带接管；形态退出时交还系统。
  ///
  /// 顺序与官方 FAQ「自由窗口下如何自定义窗口标题栏」的示例一致：
  /// setWindowDecorVisible(false) → setWindowDecorHeight → setWindowTitleButtonVisible。
  /// 高度必须**先于**三键隐藏下发：setWindowDecorHeight 的作用范围是
  /// 「标题栏和三键区」，它是按自身参数重建三键区的，若放在隐藏之后调用，
  /// 已隐藏的三键会被重新带出来 —— 这正是电脑模式下系统三键不消失的成因。
  private applyDecor(isFree: boolean): void {
    if (!this.contentLoaded) {
      return;
    }
    if (this.decorAppliedForFree === isFree) {
      return;
    }
    const previous = this.decorAppliedForFree;
    this.decorAppliedForFree = isFree;
    if (isFree) {
      this.setDecorVisible(false);
      const heightOk = this.setDecorHeight(TITLE_BAR_HEIGHT);
      // 高度没下发成功，三键区几何仍是系统默认值，此时再隐藏三键会在
      // 顶部留下一条空白；交给 [scheduleDecorRetry] 稍后整套重下。
      if (heightOk) {
        this.setTitleButtonsVisible(false);
      } else {
        this.decorAppliedForFree = previous;
        this.scheduleDecorRetry();
      }
    } else if (previous === true) {
      this.setDecorVisible(true);
      this.setTitleButtonsVisible(true);
    }
  }

  /// 形态切换瞬间系统可能尚未就绪（setWindowTitleButtonVisible 返回 801、
  /// 装饰栏接口静默不生效），退避重试几次，避免一次失败就永久停在
  /// 「系统三键仍然可见」的状态。
  private scheduleDecorRetry(): void {
    if (this.decorRetryTimer >= 0) {
      return;
    }
    this.decorRetryTimer = setTimeout(() => {
      this.decorRetryTimer = -1;
      this.sync();
    }, DECOR_RETRY_DELAY_MS);
  }

  private clearDecorRetry(): void {
    if (this.decorRetryTimer >= 0) {
      clearTimeout(this.decorRetryTimer);
      this.decorRetryTimer = -1;
    }
  }

  private setDecorVisible(visible: boolean): void {
    try {
      this.win?.setWindowDecorVisible(visible);
    } catch (err) {
      const e = err as BusinessError;
      console.warn('WindowChrome', `setWindowDecorVisible(${visible}) skipped: ${e.code} ${e.message}`);
    }
  }

  private setDecorHeight(height: number): boolean {
    try {
      this.win?.setWindowDecorHeight(height);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      console.warn('WindowChrome', `setWindowDecorHeight(${height}) skipped: ${e.code} ${e.message}`);
      return false;
    }
  }

  /// 参数顺序为（最大化、最小化、关闭），与系统标题栏三键的排列顺序一致。
  private setTitleButtonsVisible(visible: boolean): void {
    try {
      this.win?.setWindowTitleButtonVisible(visible, visible, visible);
    } catch (err) {
      const e = err as BusinessError;
      console.warn('WindowChrome', `setWindowTitleButtonVisible(${visible}) skipped: ${e.code} ${e.message}`);
      this.scheduleDecorRetry();
    }
  }

  private readFreeWindowMode(): boolean {
    if (this.win === null || deviceInfo.sdkApiVersion < 22) {
      return false;
    }
    try {
      return this.win.isInFreeWindowMode();
    } catch (err) {
      return false;
    }
  }

  private readStatus(): window.WindowStatusType {
    if (this.win === null) {
      return window.WindowStatusType.UNDEFINED;
    }
    try {
      return this.win.getWindowStatus();
    } catch (err) {
      return window.WindowStatusType.UNDEFINED;
    }
  }

  /// 标题带是否为深色内容。自绘标题带已改为固定底色 + ColoringStrategy.INVERT
  /// 自动反色取色，不再需要外部按内容底色切换主题，此方法仅保留为兼容
  /// Dart 侧既有的 setDecorButtonDark 通道（同时把状态写入 AppStorage）。
  setTitleBarDark(dark: boolean): void {
    if (this.titleBarDark === dark) {
      return;
    }
    this.titleBarDark = dark;
    // 直接写 AppStorage 而不能依赖 sync()：sync 按签名去重，此变化不在签名里。
    AppStorage.setOrCreate('titleBarDark', dark);
  }

  /// 系统栏显隐（Dart 侧 `SystemBars` 同步下来的状态）：隐藏时标题带**收起**。
  ///
  /// 这里只写 AppStorage `titleBarCollapsed`，交给 UI 做图形位移；**不**改
  /// [getState] 里的 titleBarVisible / titleBarHeight。标题带高度是并进顶部
  /// 安全区下发给 Dart 的（getSafeArea），一旦归零，Dart 页面
  /// 顶部就会让出 40vp、滚动位置随之跳动 ——「仅收起，不影响其它内容布局」
  /// 要求收起只发生在绘制层，指针滑回原区域时再把画好的标题带临时放下来。
  setBarsHidden(hidden: boolean): void {
    if (this.barsHidden === hidden) {
      return;
    }
    this.barsHidden = hidden;
    // 同 setTitleBarDark：此变化不在 sync() 的签名里，必须直接写 AppStorage。
    AppStorage.setOrCreate('titleBarCollapsed', hidden);
  }

  /// 标题带底色，由 Dart 侧主题同步下发（`#RRGGBB` / `#AARRGGBB`），
  /// 使自绘标题带与 Flutter 页面背景同色。
  setTitleBarBackground(color: string): void {
    if (color.length === 0 || this.titleBarBackground === color) {
      return;
    }
    this.titleBarBackground = color;
    // 此变化同样不在 sync() 的签名里，直接写 AppStorage。
    AppStorage.setOrCreate('titleBarBackground', color);
  }

  /// 最大化/还原。仅自由窗口形态下有意义。
  ///
  /// 进入用 EXIT_IMMERSIVE（铺满屏幕但保留 dock 与状态栏，窗口状态落在
  /// MAXIMIZE），还原用 recover()（回到 FLOATING 并恢复原尺寸位置）。
  /// 不能用无参 maximize()：那会进入沉浸式全屏（状态 FULL_SCREEN），
  /// 而标题带在 FULL_SCREEN 下是隐藏的，用户就再也点不到还原按钮。
  async toggleMaximize(): Promise<void> {
    const status = this.readStatus();
    if (status === window.WindowStatusType.FLOATING) {
      try {
        await this.win?.maximize(window.MaximizePresentation.EXIT_IMMERSIVE);
      } catch (err) {
        const e = err as BusinessError;
        console.error('WindowChrome', `maximize failed: ${e.code} ${e.message}`);
      }
    } else if (this.isMaximizedStatus(status)) {
      // FULL_SCREEN 也当最大化处理：targetAPIVersion < 14 时最大化后的
      // 窗口状态就报 FULL_SCREEN，两者在自由窗口形态下语义等价。
      await this.recoverSafe();
    }
  }

  /// recover() 在已是浮动窗口时可能 resolve，也可能以 1300001 拒绝，两条路径都视为成功。
  private async recoverSafe(): Promise<void> {
    try {
      await this.win?.recover();
    } catch (err) {
      const e = err as BusinessError;
      if (e.code === 1300001 || e.code === 801) {
        return;
      }
      console.error('WindowChrome', `recover failed: ${e.code} ${e.message}`);
    }
  }

  minimize(): void {
    this.win?.minimize().catch((err: BusinessError) => {
      console.error('WindowChrome', `minimize failed: ${err.code} ${err.message}`);
    });
  }

  close(): void {
    const context = getContext() as common.UIAbilityContext;
    context.terminateSelf().catch((err: BusinessError) => {
      console.error('WindowChrome', `terminateSelf failed: ${err.code} ${err.message}`);
    });
  }

  /// 自绘标题带的拖拽：需在触摸 Down 之后的 Move 中调用才生效。
  startMoving(): void {
    if (this.win === null || !this.readFreeWindowMode()) {
      return;
    }
    this.win.startMoving().catch((err: BusinessError) => {
      console.error('WindowChrome', `startMoving failed: ${err.code} ${err.message}`);
    });
  }

  /// 内容全屏是否由本控制器接管（仅自由窗口形态）。同步返回，供必须同步
  /// 回复的原生通道调用方使用。
  canHandleContentFullScreen(): boolean {
    return this.contentFullScreen || this.readFreeWindowMode();
  }

  /// 播放器等内容全屏：铺满屏幕并禁止顶部热区唤出系统标题栏。
  ///
  /// 返回 false 表示当前不是自由窗口形态，本控制器不接管，调用方应回退到
  /// 其它全屏实现。判断放在原生侧，Dart 侧无需感知窗口形态。
  async enterContentFullScreen(): Promise<boolean> {
    if (!this.readFreeWindowMode()) {
      return false;
    }
    if (this.contentFullScreen) {
      return true;
    }
    const status = this.readStatus();
    this.statusBeforeFullScreen =
      status === window.WindowStatusType.MAXIMIZE ? window.WindowStatusType.MAXIMIZE : window.WindowStatusType.FLOATING;
    this.contentFullScreen = true;
    this.sync();
    try {
      await this.win?.maximize(window.MaximizePresentation.ENTER_IMMERSIVE_DISABLE_TITLE_AND_DOCK_HOVER);
    } catch (err) {
      const e = err as BusinessError;
      console.error('WindowChrome', `enter content fullscreen failed: ${e.code} ${e.message}`);
    }
    return true;
  }

  /// 退出内容全屏：全屏前为最大化则回最大化，否则回到全屏前的浮动尺寸与位置。
  ///
  /// 返回 false 表示本控制器未接管过全屏，调用方应回退到其它退出实现。
  async exitContentFullScreen(): Promise<boolean> {
    if (!this.contentFullScreen) {
      return false;
    }
    this.contentFullScreen = false;
    const previous = this.statusBeforeFullScreen;
    this.statusBeforeFullScreen = null;
    // ENTER_IMMERSIVE_DISABLE_TITLE_AND_DOCK_HOVER 会改掉 hover 策略，退出时复位。
    try {
      await this.win?.setTitleAndDockHoverShown(true, true);
    } catch (err) {
      const e = err as BusinessError;
      console.warn('WindowChrome', `reset hover shown failed: ${e.code} ${e.message}`);
    }
    if (previous === window.WindowStatusType.MAXIMIZE) {
      try {
        await this.win?.maximize(window.MaximizePresentation.EXIT_IMMERSIVE);
      } catch (err) {
        const e = err as BusinessError;
        console.error('WindowChrome', `restore maximize failed: ${e.code} ${e.message}`);
      }
    } else {
      await this.recoverSafe();
    }
    this.sync();
    return true;
  }
}

export const windowChrome: WindowChromeController = new WindowChromeController();
