import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { SystemBarsController } from './SystemBars';

/// 自绘标题带高度（vp）。合法装饰高度为 [37,112]，取 40 与系统标题栏观感一致。
export const TITLE_BAR_HEIGHT: number = 40;

/// 本类只负责标题带何时出现 / 占多高 / 收不收，不持有任何颜色：底色由 Dart
/// 侧主题统一下发到 AppStorage `appBackgroundColor`（见
/// appearance/AppAppearance.ets）。

/// 装饰栏下发失败后的重试间隔（ms）。
const DECOR_RETRY_DELAY_MS: number = 150;

/// 窗口外观状态的唯一真源。UI（Index）与 Dart（经 WindowHost）都只读它。
export interface WindowChromeState {
  /// 自由窗口形态：2in1/PC、平板自由多窗或电脑模式。手机与平板普通模式为 false。
  isFreeWindowMode: boolean;
  status: window.WindowStatusType;
  maximized: boolean;
  contentFullScreen: boolean;
  /// 标题带是否需要渲染。自由窗口形态下恒为 true（全屏时要靠它留出顶部热区），
  /// 非自由窗口（手机等）为 false。
  titleBarVisible: boolean;
  /// 标题带自动收起：「内容全屏」且窗口占满显示器（最大化/全屏）时为 true。
  /// 此时标题带默认滑出窗口，只保留顶部热区，鼠标悬停时再临时放下。
  /// 窗口一旦被还原成浮动窗口，或没有全屏播放，标题带都保持常驻。
  titleBarAutoHide: boolean;
  /// 标题带当前是否被鼠标唤出（仅自动收起态有意义）。唤出期间会把标题带高度
  /// 并进顶部安全区，让播放器顶部那排按钮整体下移避让。
  titleBarRevealed: boolean;
  /// 标题带占用的顶部高度（vp），0 表示不占位（不渲染或自动收起时）。
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
  /// 系统栏是否已隐藏（Dart 侧 `SystemBars` 同步下来的状态）：标题带收起，见 [setBarsHidden]。
  private barsHidden: boolean = false;
  /// 已下发给 AppStorage 的 `titleBarCollapsed`（系统栏隐藏 与 全屏自动收起 的合并值）。
  /// null = 尚未下发过，下次 sync 强制写一次，避免热重启后停在旧状态。
  private lastCollapsed: boolean | null = null;
  /// 标题带当前是否被鼠标唤出（仅自动收起态有意义，见 [setTitleBarRevealed]）。
  private titleBarRevealed: boolean = false;

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
    // 幂等：热启动接续会再次走到窗口创建流程，若这里重复 on()，同一个窗口上
    // 会挂上 N 份监听，之后每次窗口状态变化都触发 N 次 sync + 下发。同一窗口
    // 已登记时直接返回；换窗口则先摘掉旧监听再重新登记。
    if (this.win === win) {
      return;
    }
    if (this.win !== null) {
      this.detach();
    }
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
    // 引擎 detach（热重启 / 插件卸载）后 Dart 侧的播放器状态已不存在，内容全屏
    // 必须复位，否则标题带永远停在自动收起、还原键也被藏掉。折叠状态一并置空，
    // 让下一次 sync 强制重写 AppStorage（避免新引擎继承上一次的折叠值）。
    this.contentFullScreen = false;
    this.lastCollapsed = null;
    this.titleBarRevealed = false;
  }

  /// 注入窗口级系统栏状态机（WindowState 持有）。本类只消费它的 apply 结果
  /// 来收起标题带；状态本身不在这里维护 —— 系统栏不是自由窗口标题栏的私产。
  bindSystemBars(controller: SystemBarsController): void {
    this.systemBars = controller;
  }

  onChange(listener: WindowChromeListener): void {
    this.listeners.push(listener);
  }

  /// 反注册监听。引擎 detach（热重启 / 插件卸载）后订阅方必须摘掉自己，
  /// 否则旧订阅会继续持有已失效的 channel，并被后续状态变化反复回调。
  offChange(listener: WindowChromeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  getState(): WindowChromeState {
    const status = this.readStatus();
    // 内容全屏期间个别版本在沉浸式全屏下不再上报自由窗口形态，这里兜一层：
    // 标题带必须继续存在，否则顶部热区没了，悬停也就唤不出标题带。
    const isFree = this.readFreeWindowMode() || this.contentFullScreen;
    // 自动收起要同时满足：内容全屏（播放器全屏）且窗口确实占满显示器。
    // 只要窗口被还原成浮动窗口（不管是点还原键、双击标题带还是系统操作），
    // 标题带就恢复常驻；单纯最大化窗口（没有全屏播放）也不会自动收起。
    const autoHide =
      isFree && this.contentFullScreen && this.isMaximizedStatus(status);
    // 自由窗口形态下始终渲染（自动收起时它只剩热区职责）；非自由窗口（手机）
    // 不渲染，也就没有热区，手机上的行为与改动前完全一致。
    const visible = isFree;
    return {
      isFreeWindowMode: isFree,
      status: status,
      maximized: this.isMaximizedStatus(status),
      contentFullScreen: this.contentFullScreen,
      titleBarVisible: visible,
      titleBarAutoHide: autoHide,
      titleBarRevealed: autoHide && this.titleBarRevealed,
      titleBarHeight: visible && !autoHide ? TITLE_BAR_HEIGHT : 0,
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
    // 折叠状态要先算：它由「系统栏隐藏」与「全屏自动收起」共同决定，且要在
    // 下面的去重之前落地（签名不变时也可能只翻转了其中一项）。
    this.applyCollapsed(state.titleBarAutoHide);
    const signature = `${state.isFreeWindowMode}|${state.status}|${state.titleBarVisible}|` +
      `${state.titleBarAutoHide}|${state.titleBarRevealed}|${state.contentFullScreen}`;
    if (signature === this.lastSignature) {
      return;
    }
    this.lastSignature = signature;
    AppStorage.setOrCreate('titleBarVisible', state.titleBarVisible);
    AppStorage.setOrCreate('titleBarHeight', state.titleBarHeight);
    AppStorage.setOrCreate('windowMaximized', state.maximized);
    AppStorage.setOrCreate('windowFreeMode', state.isFreeWindowMode);
    // 标题带据此区分「全屏自动收起」与「系统栏隐藏的图形收起」：前者只响应
    // 鼠标悬停，不响应触屏点击（见 WindowTitleBar）。
    AppStorage.setOrCreate('titleBarAutoHide', state.titleBarAutoHide);
    this.listeners.forEach((listener: WindowChromeListener) => {
      listener(state);
    });
  }

  /// 自绘标题带被鼠标唤出 / 收回（由 WindowTitleBar 上报）。
  ///
  /// 仅自动收起态有意义。唤出期间 [getState] 会把它并进顶部安全区（见
  /// WindowState.readSafeArea），让播放器顶部那排按钮整体下移，避免被标题带
  /// 盖住点不到；收回后恢复原位。
  setTitleBarRevealed(revealed: boolean): void {
    if (this.titleBarRevealed === revealed) {
      return;
    }
    this.titleBarRevealed = revealed;
    this.sync();
  }

  /// 下发标题带折叠状态：系统栏隐藏（沉浸页面）或窗口占满显示器（自动收起）。
  ///
  /// 两个来源合并成一个 AppStorage 值，[WindowTitleBar] 只认这一个，避免两处
  /// 各写各的互相覆盖。
  private applyCollapsed(autoHide: boolean): void {
    const collapsed = this.barsHidden || autoHide;
    if (this.lastCollapsed === collapsed) {
      return;
    }
    this.lastCollapsed = collapsed;
    AppStorage.setOrCreate('titleBarCollapsed', collapsed);
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
    // 此变化不在 sync() 的签名里，这里按最新窗口形态重算一次合并后的折叠状态。
    this.applyCollapsed(this.getState().titleBarAutoHide);
  }

  /// 最大化/还原。仅自由窗口形态下有意义。
  ///
  /// 进入用 EXIT_IMMERSIVE（铺满屏幕但保留 dock 与状态栏，窗口状态落在
  /// MAXIMIZE），还原用 recover()（回到 FLOATING 并恢复原尺寸位置）。
  /// 不用无参 maximize()：那会直接进入沉浸式全屏并隐藏 dock/状态栏，
  /// 最大化不该顺带改变系统栏形态。
  ///
  /// 这里只做**窗口**操作，不碰播放器全屏状态：全屏播放中把窗口还原成浮动
  /// 窗口时，视频继续铺满窗口、标题带恢复常驻（与系统/华为视频一致）。
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
    // 内容全屏期间用户手动改了窗口形态：把新形态记为「退出全屏时要还原到的
    // 状态」，否则退出全屏会把窗口弹回进入全屏前的旧形态，覆盖用户的操作。
    // 用切换前的状态推导（避免 await 后读取状态时机不稳）。
    if (this.contentFullScreen) {
      this.statusBeforeFullScreen = this.isMaximizedStatus(status)
        ? window.WindowStatusType.FLOATING
        : window.WindowStatusType.MAXIMIZE;
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
