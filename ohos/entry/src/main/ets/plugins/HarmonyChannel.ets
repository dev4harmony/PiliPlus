import { common, wantAgent, WantAgent } from "@kit.AbilityKit";
import { BusinessError, deviceInfo } from "@kit.BasicServicesKit";
import { http } from "@kit.NetworkKit";
import { util } from "@kit.ArkTS";
import { fileIo } from "@kit.CoreFileKit";
import { formProvider } from "@kit.FormKit";
import AbilityConstant from "@ohos.app.ability.AbilityConstant";
import Want from "@ohos.app.ability.Want";
import ConfigurationConstant from "@ohos.app.ability.ConfigurationConstant";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import window from "@ohos.window";
import {
  Any,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodChannel,
  MethodResult,
} from "@ohos/flutter_ohos";

import display from "@ohos.display";

const colorModeMap: Record<string, ConfigurationConstant.ColorMode> = {
  "light": ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT,
  "dark": ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
  "system": ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET,
};

export default class HarmonyChannel implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private lastWindow: window.Window | null = null;
  private bgTaskPromise: Promise<void> = Promise.resolve();
  private isBackgroundTaskRunning: boolean = false;
  private bgTaskWanted: boolean = false;
  /// 当前底部页签是否为首页（由 Flutter 同步）。
  /// 用于 dialog 隐藏/显示顶栏时的多级分支判断。
  private topBarIsHome: boolean = false;
  /// 跨设备接续：对端 onCreate/onNewWant 收到的接续数据暂存于此，
  /// 由 Dart 侧就绪后主动拉取（getPendingContinuation），规避冷启动时
  /// Dart handler 尚未注册导致推送丢失的问题。
  private pendingContinuation: string | null = null;

  getUniqueClassName(): string {
    return "HarmonyChannel";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "harmonyChannel");
    this.channel.setMethodCallHandler(this);
    // // 监听画面方向
    // display.on('change', () => {
    //   // 获取当前旋转角度
    //   let rotation = display.getDefaultDisplaySync().rotation;
    //   this.channel!.invokeMethod('onRotationChange', { 'rotation': rotation })
    // })
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.stopSafeAreaListener();
    this.stopFreeWindowModeListener();
  }

  /**
   * 窗口是否处于「自由窗口模式」：2in1/PC、平板开启自由多窗、平板电脑模式
   * 下为 true；手机/平板普通模式下的系统小窗（悬浮窗）为 false。
   *
   * 这几种形态下窗口状态都是 FLOATING，只能靠它区分「普通桌面窗口」与
   * 「系统小窗」。不能用 deviceType 判断：平板（含带电脑模式的机型）上报的
   * 都是 tablet，且自由多窗可在运行中开关。
   */
  private freeWindowModeListening: boolean = false;
  private freeWindowModeCallback = (isFree: boolean): void => {
    const args: Record<string, boolean> = { 'isFreeWindowMode': isFree };
    this.channel?.invokeMethod("onFreeWindowModeChange", args);
  };

  private readFreeWindowMode(): boolean {
    try {
      return this.lastWindow?.isInFreeWindowMode() ?? false;
    } catch (err) {
      return false;
    }
  }

  private startFreeWindowModeListener(): void {
    if (this.freeWindowModeListening || !this.lastWindow) {
      return;
    }
    try {
      this.lastWindow.on('freeWindowModeChange', this.freeWindowModeCallback);
      this.freeWindowModeListening = true;
    } catch (err) {
      console.error("HarmonyChannel", `on freeWindowModeChange failed: ${err}`);
    }
  }

  private stopFreeWindowModeListener(): void {
    if (!this.freeWindowModeListening) {
      return;
    }
    this.freeWindowModeListening = false;
    try {
      this.lastWindow?.off('freeWindowModeChange', this.freeWindowModeCallback);
    } catch (err) {
      // 窗口已销毁
    }
  }

  /**
   * 安全区避让区（物理像素，窗口相对坐标）：TYPE_SYSTEM 与 TYPE_CUTOUT 逐边取
   * max，即官方「各类型避让区在同一方向上的最大值」。embedding 算 viewPadding
   * 只读 TYPE_SYSTEM，挖孔（横屏左右、竖屏隐藏状态栏后的顶部）避不开，故由这里
   * 上报、在 Dart 根 MediaQuery 里并进 padding（见 Dart 侧 [safeAreaInsets]）。
   * 自由窗口的三键带也含在 TYPE_SYSTEM 里，一并覆盖。
   */
  private safeAreaListening: boolean = false;
  // 合并并发安装（见 [startSafeAreaListener]）。
  private safeAreaStarting: Promise<void> | null = null;
  // 不做值去重：旋转时避让区四元组可能逐位不变（如竖横屏顶部高度相同），去重会
  // 吞掉这次方向变化。重复推送无害，Dart 侧 _updateSafeArea 自带判等。
  private safeAreaChangeCallback = (): void => {
    this.channel?.invokeMethod("onSafeAreaChange", this.readSafeArea());
  };

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
  private static trailingInset(
    rect: window.Rect,
    winSize: number,
    horizontal: boolean,
  ): number {
    if (horizontal) {
      return rect.width > 0 ? winSize - rect.left : 0;
    }
    return rect.height > 0 ? winSize - rect.top : 0;
  }

  private readSafeArea(): Record<string, number> {
    let sys: window.AvoidArea | undefined = undefined;
    let cut: window.AvoidArea | undefined = undefined;
    let winWidth = 0;
    let winHeight = 0;
    try {
      sys = this.lastWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      cut = this.lastWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const winRect = this.lastWindow?.getWindowProperties().windowRect;
      if (winRect) {
        winWidth = winRect.width;
        winHeight = winRect.height;
      }
    } catch (err) {
      console.error("HarmonyChannel", `readSafeArea failed: ${err}`);
    }
    // 逐边取 max（官方语义）。左右两边量法不同见 [leadingInset] / [trailingInset]。
    const res: Record<string, number> = {
      'left': Math.max(
        sys ? HarmonyChannel.leadingInset(sys.leftRect, true) : 0,
        cut ? HarmonyChannel.leadingInset(cut.leftRect, true) : 0),
      'top': Math.max(
        sys ? HarmonyChannel.leadingInset(sys.topRect, false) : 0,
        cut ? HarmonyChannel.leadingInset(cut.topRect, false) : 0),
      'right': Math.max(
        sys ? HarmonyChannel.trailingInset(sys.rightRect, winWidth, true) : 0,
        cut ? HarmonyChannel.trailingInset(cut.rightRect, winWidth, true) : 0),
      'bottom': Math.max(
        sys ? HarmonyChannel.trailingInset(sys.bottomRect, winHeight, false) : 0,
        cut ? HarmonyChannel.trailingInset(cut.bottomRect, winHeight, false) : 0),
    };
    return res;
  }

  private async startSafeAreaListener(): Promise<void> {
    // 不能提前置位 safeAreaListening 防重入：await 期间再进来会重复 on()，而
    // await 抛错时提前置位会让后续调用全部 return、监听器永不安装。故复用同一个
    // Promise 等待上次安装完成，只在真正 on() 成功后置位。
    if (this.safeAreaListening) {
      return;
    }
    if (this.safeAreaStarting != null) {
      return this.safeAreaStarting;
    }
    this.safeAreaStarting = this.doStartSafeAreaListener();
    try {
      await this.safeAreaStarting;
    } finally {
      this.safeAreaStarting = null;
    }
  }

  private async doStartSafeAreaListener(): Promise<void> {
    try {
      this.lastWindow ??= await window.getLastWindow(getContext());
    } catch (err) {
      // 拿不到窗口就保持未监听状态，下一次 getSafeArea 会重试。
      console.error("HarmonyChannel", `getLastWindow for safe area failed: ${err}`);
      return;
    }
    const w = this.lastWindow;
    try {
      w.on('avoidAreaChange', this.safeAreaChangeCallback);
      // 旋转/窗口尺寸变化后兜底重读一次：部分机型旋转时不会单独推送
      // TYPE_CUTOUT 的 avoidAreaChange。
      w.on('windowSizeChange', this.safeAreaChangeCallback);
      this.safeAreaListening = true;
    } catch (err) {
      console.error("HarmonyChannel", `safe area listener failed: ${err}`);
    }
  }

  private stopSafeAreaListener(): void {
    if (!this.safeAreaListening) {
      return;
    }
    this.safeAreaListening = false;
    try {
      this.lastWindow?.off('avoidAreaChange', this.safeAreaChangeCallback);
      this.lastWindow?.off('windowSizeChange', this.safeAreaChangeCallback);
    } catch (err) {
      console.error("HarmonyChannel", `safe area listener off failed: ${err}`);
    }
  }

  public getChannel(): MethodChannel | null {
    return this.channel;
  }


  /**
   * 全屏/退出全屏时只切换系统栏显隐，不改窗口布局（setWindowLayoutFullScreen 会改
   * surface 尺寸，导致 Flutter 视口变化、旋转进出全屏时画面跳动）。
   *
   * 状态栏显隐会改 TYPE_SYSTEM 的 topRect，但部分机型不推送 avoidAreaChange，
   * 故切换后主动重推一次。
   */
  async setFullScreenBars(fullscreen: boolean) {
    this.lastWindow ??= await window.getLastWindow(getContext());
    const w = this.lastWindow;
    await w.setSpecificSystemBarEnabled("status", !fullscreen, false);
    await w.setSpecificSystemBarEnabled("navigation", !fullscreen, false);
    await w.setSpecificSystemBarEnabled("navigationIndicator", !fullscreen, false);
    // 状态栏显隐会改 TYPE_SYSTEM.topRect，重推一次兜底。
    this.safeAreaChangeCallback();
  }

  async setWindowOrientation(orientation: number) {
    this.lastWindow ??= await window.getLastWindow(getContext());
    await this.lastWindow.setPreferredOrientation(orientation);
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case "getDisplayHdrFormats": {
        // 面板实际支持的 HDR 类型。取值见 @ohos.graphics.hdrCapability 的
        // HDRFormat：0=NONE 1=VIDEO_HLG 2=VIDEO_HDR10 3=VIDEO_HDR_VIVID。
        // Dart 侧据此决定 HDR 片源怎么输出：一个都不支持就按 SDR 输出；不支持
        // HDR Vivid 就只发 HDR10 静态元数据，不在这块屏上发 Vivid 信令。
        try {
          const d = display.getDefaultDisplaySync();
          const formats: number[] = (d.hdrFormats ?? []) as number[];
          console.info(`HarmonyChannel display hdrFormats: ${JSON.stringify(formats)}`);
          result.success(formats);
        } catch (err) {
          // 必须报错而不是回空数组：Dart 侧要用「查不到」和「查到了，不支持」
          // 区分开，空数组会被当成这块屏确实不支持 HDR，把功能整个关掉。
          console.error(`HarmonyChannel getDisplayHdrFormats failed: ${err}`);
          result.error("HDR_CAPABILITY_QUERY_FAILED", `${err}`, null);
        }
        break;
      }
      case "setFullScreenBars": {
        const fullscreen: boolean = call.argument("fullscreen") ?? false;
        await this.setFullScreenBars(fullscreen);
        result.success(true);
        break;
      }
      case "setWindowOrientation": {
        const orientation: number = call.argument("orientation") ?? 0;
        await this.setWindowOrientation(orientation);
        result.success(true);
        break;
      }
      case "setMiniWindowLandscape":
        const landscape: boolean = call.argument("landscape") ?? false;
        await this.setMiniWindowLandscape(landscape);
        result.success(true);
        break;
      case "setDecorButtonDark": {
        const dark: boolean = call.argument("dark") ?? false;
        await this.setDecorButtonDark(dark);
        result.success(true);
        break;
      }
      case "getWindowState": {
        // 启动时供 Dart 拉取窗口初始状态：是否自由多窗（FLOATING）、是否受限
        // 窗口模式（分屏/自由多窗）。见 Dart 侧 HarmonyChannel.initWindowState。
        this.lastWindow ??= await window.getLastWindow(getContext());
        let status: window.WindowStatusType = window.WindowStatusType.UNDEFINED;
        try {
          status = this.lastWindow.getWindowStatus();
        } catch (err) {
          console.error("HarmonyChannel", `getWindowStatus failed: ${err}`);
        }
        const isFloating = status == window.WindowStatusType.FLOATING;
        // ArkTS 不允许无类型对象字面量（arkts-no-untyped-obj-literals），
        // 显式声明为 Record 再填值
        const state: Record<string, boolean> = {
          'isFloatingWindow': isFloating,
          'isWindowMode': isFloating || status == window.WindowStatusType.SPLIT_SCREEN,
          'isFreeWindowMode': this.readFreeWindowMode(),
        };
        this.startFreeWindowModeListener();
        result.success(state);
        break;
      }
      case "getSafeArea": {
        // 启动时供 Dart 拉取安全区避让初值，并从此开始监听变化推送
        // onSafeAreaChange。见 [readSafeArea] 与 Dart 侧
        // HarmonyChannel.initWindowState。
        await this.startSafeAreaListener();
        result.success(this.readSafeArea());
        break;
      }
      case "setWindowDecorVisible": {
        const visible: boolean = call.argument("visible") ?? true;
        result.success(this.setWindowDecorVisible(visible));
        break;
      }
      case "getPendingContinuation": {
        const data = this.pendingContinuation;
        this.pendingContinuation = null;
        result.success(data);
        break;
      }
      case "setContinuationActive": {
        const active: boolean = call.argument("active") ?? false;
        this.setMissionContinueState(active);
        result.success(true);
        break;
      }
      case "setShellBars": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        const useNativeTabs: boolean = call.argument('useNativeTabs') ?? false;
        console.log(`is use native tabs: ${useNativeTabs}`);
        AppStorage.setOrCreate('useNativeTabs', useNativeTabs);
        result.success(true);
        break;
      }
      case "setNavBarConfig": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        // 底部 Navbar 页签（NavigationBarType 索引），与设置内 Navbar 编辑一致
        const tabs: number[] = call.argument('tabs') ?? [0, 1, 2];
        AppStorage.setOrCreate('navTabs', tabs);
        result.success(true);
        break;
      }
      case "setDynamicBadge": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        // 动态页签角标（mode 与 Flutter DynamicBadgeMode 一致：0=隐藏 1=红点 2=数字）
        const count: number = call.argument('count') ?? 0;
        const mode: number = call.argument('mode') ?? 0;
        AppStorage.setOrCreate('dynBadgeCount', count);
        AppStorage.setOrCreate('dynBadgeMode', mode);
        result.success(true);
        break;
      }
      case "startBackgroundTask": {
        this.startBackgroundTaskInner();
        result.success(true);
        break;
      }
      case "stopBackgroundTask": {
        this.stopBackgroundTaskInner();
        result.success(true);
        break;
      }
      case "setShellBarsHidden": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        const hidden: boolean = call.argument('hidden') ?? false;
        const force: boolean = call.argument('force') ?? false;
        AppStorage.setOrCreate('shellBarsHidden', hidden);
        // 沉浸光感顶栏与底栏共用此显隐信号：底栏直接隐藏，
        // 顶栏按「是否首页 + 窗口宽高比」在 ArkTS 侧多级分支。
        this.syncTopBarVisibility(hidden,force);
        result.success(true);
        break;
      }
      case "setTopBarIsHome": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        this.topBarIsHome = call.argument('isHome') ?? false;
        console.log(`is top bar home: ${this.topBarIsHome}`);
        result.success(true);
        break;
      }
      case "setShellBarsScrollHidden": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        const hidden: boolean = call.argument('hidden') ?? false;
        if (AppStorage.get('__scrollHidden') != hidden) {
          AppStorage.setOrCreate('__scrollHidden', hidden);
        }
        result.success(true);
        break;
      }
      case "changeTabIndex": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        const index: number = call.argument('index') ?? 0;
        this.changeTabIndex(index);
        result.success(true);
        break;
      }
      case "setTabMaterialLevel": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        // 与 Dart HdsMaterialLevel.value 一致：
        // 0=精美 EXQUISITE 1=轻柔 GENTLE 2=流畅 SMOOTH 10=系统自适应 ADAPTIVE
        const level: number = call.argument('level') ?? 10;
        AppStorage.setOrCreate('tabMaterialLevel', level);
        result.success(true);
        break;
      }
      case "setTabSelectedColor": {
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        const color: string = call.argument('color') ?? '#3367D6';
        const subColor: string = '#88'+color.substring(1);
        AppStorage.setOrCreate('tabSelectedColor', color);
        AppStorage.setOrCreate('tabSelectedSubColor', subColor);
        result.success(true);
        break;
      }
      case "setShellTopBar": {
        // API 23~25 由 HdsNavigation 承载，API 26+ 由 Navigation 承载（见 Index.ets）
        if (deviceInfo.sdkApiVersion < 23) {
          result.success(true);
          break;
        }
        const useNativeTopBar: boolean = call.argument('useNativeTopBar') ?? false;
        AppStorage.setOrCreate('useNativeTopBar', useNativeTopBar);
        result.success(true);
        break;
      }
      case "setHomeTopBarData": {
        const tabs: string[] = call.argument('tabs') ?? [];
        const hideTopBar: boolean = call.argument('hideTopBar') ?? false;
        const activeIndex: number = call.argument('activeIndex') ?? 0;
        AppStorage.setOrCreate('homeTabs', tabs);
        AppStorage.setOrCreate('homeHideTopBar', hideTopBar);
        AppStorage.setOrCreate('homeActiveTabIndex', activeIndex);
        result.success(true);
        break;
      }
      case "setHomeSearchText": {
        const text: string = call.argument('text') ?? '';
        AppStorage.setOrCreate('homeSearchText', text);
        result.success(true);
        break;
      }
      case "setHomeUnreadCount": {
        const count: string = call.argument('count') ?? '';
        AppStorage.setOrCreate('homeUnreadCount', count);
        result.success(true);
        break;
      }
      case "setHomeFaceUrl": {
        const url: string = call.argument('url') ?? '';
        AppStorage.setOrCreate('homeFaceUrl', url);
        result.success(true);
        break;
      }
      case "setHomeTabIndex": {
        const index: number = call.argument('index') ?? 0;
        AppStorage.setOrCreate('homeActiveTabIndex', index);
        result.success(true);
        break;
      }
      case "setTopBarCollapsed": {
        const collapsed: boolean = call.argument('collapsed') ?? false;
        AppStorage.setOrCreate('topBarCollapsed', collapsed);
        result.success(true);
        break;
      }
      case "setTopBarHidden": {
        const hidden: boolean = call.argument('hidden') ?? false;
        AppStorage.setOrCreate('topBarHidden', hidden);
        result.success(true);
        break;
      }
      case "setSystemColorMode": {
        const colorMode: string = call.argument('colorMode') ?? '';
        this.setColorMode(colorMode);
        result.success(true);
        break;
      }
      // case 'setWindowLayoutFullScreen': {
      //   this.lastWindow ??= await window.getLastWindow(getContext())
      //   this.lastWindow.setWindowLayoutFullScreen(call.argument('fullScreen'));
      //   result.success(true);
      //   break;
      // }
      case "addUpToDesktop": {
        await this.addUpToDesktop(call);
        result.success(true);
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }

  // 设置应用上下文的深浅色模式。
  private setColorMode(colorMode: string): void {
    try {
      const context = getContext() as common.ApplicationContext;
      context.setColorMode(colorModeMap[colorMode]);
      console.log('HarmonyChannel', `set color mode: ${colorMode}`);
    } catch (err) {
      console.error("HarmonyChannel", `get application context failed: ${err}`);
    }
  }

  /**
   * 添加UP主卡片到桌面：先下载头像转base64并保存待添加的UP数据
   * （onAddForm 时同步读取绑定卡片），再拉起系统卡片管理页让用户添加。
   */
  private async addUpToDesktop(call: MethodCall): Promise<void> {
    const mid = String(call.argument("mid") ?? "");
    const name = String(call.argument("name") ?? "");
    const avatar = String(call.argument("avatar") ?? "");
    const topPhoto = String(call.argument("topPhoto") ?? "");
    if (mid.length === 0) {
      return;
    }
    const avatarData = await this.downloadAvatarBase64(avatar);
    const topPhotoData = await this.downloadAvatarBase64(topPhoto);
    // 写沙箱文件（比 Preferences 可靠：onAddForm 同步读文件，无缓存/跨进程问题）
    try {
      const context = getContext() as common.Context;
      const file = fileIo.openSync(
        `${context.filesDir}/pending_up_card.json`,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
      );
      fileIo.writeSync(file.fd, JSON.stringify({
        mid: mid, name: name, avatar: avatarData, topPhoto: topPhotoData
      }));
      fileIo.closeSync(file);
    } catch (e) {
      console.error("HarmonyChannel", `save pending up failed: ${e}`);
    }
    try {
      const context = getContext() as common.UIAbilityContext;
      formProvider.openFormManager({
        bundleName: context.abilityInfo.bundleName,
        abilityName: "EntryFormAbility",
        parameters: {
          'ohos.extra.param.key.form_dimension': 1,
          'ohos.extra.param.key.form_name': 'up_card',
          'ohos.extra.param.key.module_name': 'entry',
        },
      });
    } catch (e) {
      console.error("HarmonyChannel", `openFormManager failed: ${e}`);
    }
  }

  /** 下载头像并以 base64 存储，供卡片/引导页直接显示 */
  private async downloadAvatarBase64(url: string): Promise<string> {
    if (url.length === 0) {
      return '';
    }
    let httpRequest: http.HttpRequest | null = null;
    try {
      httpRequest = http.createHttp();
      const resp = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 15000,
      });
      if (resp.responseCode !== 200) {
        return '';
      }
      const result = resp.result;
      let bytes: ArrayBuffer;
      if (result instanceof ArrayBuffer) {
        bytes = result;
      } else if (result instanceof Uint8Array) {
        bytes = result.buffer as ArrayBuffer;
      } else {
        return '';
      }
      if (bytes.byteLength === 0) {
        return '';
      }
      const mime = url.toLowerCase().includes('.webp') ? 'image/webp' : 'image/jpeg';
      const base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
      return `data:${mime};base64,${base64}`;
    } catch (e) {
      console.error("HarmonyChannel", `download avatar failed: ${e}`);
      return '';
    } finally {
      httpRequest?.destroy();
    }
  }

  private startBackgroundTaskInner(): void {
    this.enqueueBgTask(true);
  }

  private stopBackgroundTaskInner(): void {
    this.enqueueBgTask(false);
  }

  /**
   * Promise 链式队列：将所有 start/stop 请求排队执行，
   * 只根据最终期望状态 (bgTaskWanted) 决定实际操作，消除竞态条件。
   */
  private enqueueBgTask(wanted: boolean): void {
    this.bgTaskWanted = wanted;
    this.bgTaskPromise = this.bgTaskPromise.then(async (): Promise<void> => {
      if (this.bgTaskWanted) {
        // 期望启动；若实际未运行则执行启动
        if (this.isBackgroundTaskRunning) {
          return;
        }
        try {
          const context: common.UIAbilityContext = getContext() as common.UIAbilityContext;
          const wantAgentInfo: wantAgent.WantAgentInfo = {
            wants: [
              {
                bundleName: context.abilityInfo.bundleName,
                abilityName: context.abilityInfo.name,
              } as Want,
            ],
            actionType: wantAgent.OperationType.START_ABILITY,
            requestCode: 0,
            actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] as Array<wantAgent.WantAgentFlags>,
          };
          const wantAgentObj: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
          const list: Array<string> = ["dataTransfer"];
          await backgroundTaskManager.startBackgroundRunning(
            context, list, wantAgentObj,
          );
          this.isBackgroundTaskRunning = true;
          console.info("HarmonyChannel", "Background task started (dataTransfer)");
        } catch (error) {
          console.error("HarmonyChannel",
            `startBackgroundTask failed, code: ${(error as BusinessError).code}, msg: ${(error as
              BusinessError).message}`);
        }
      } else {
        // 期望停止；若实际在运行则执行停止
        if (!this.isBackgroundTaskRunning) {
          return;
        }
        try {
          await backgroundTaskManager.stopBackgroundRunning(getContext());
          this.isBackgroundTaskRunning = false;
          console.info("HarmonyChannel", "Background task stopped");
        } catch (error) {
          console.error("HarmonyChannel",
            `stopBackgroundTask failed, code: ${(error as BusinessError).code}, msg: ${(error as
              BusinessError).message}`);
        }
      }
    });
  }

  /**
   * 沉浸光感顶栏与底部导航栏共用 dialog 隐藏/显示信号时的多级分流。
   *
   * 宽高比 = 窗口宽 / 窗口高（Index.ets 已随窗口尺寸变化维护 winWidth/winHeight）：
   * - 当前不是首页：不处理（顶栏仅首页显示）
   * - 隐藏 + 宽高比 < 9/16（竖长屏）：不处理
   * - 隐藏 + 宽高比 9/16 ~ 1:1：改为「收起」顶栏
   * - 隐藏 + 宽高比 ≥ 1:1（正方/横屏）：隐藏顶栏
   * - 显示 + 宽高比 9/16 ~ 1:1：放下 + 显示顶栏
   * - 显示 + 宽高比 9/16 ~ 1:1 以外：仅显示顶栏
   */
  private syncTopBarVisibility(hidden: boolean, force: boolean): void {
    // 顶栏未启用或不处于首页时不处理
    if (AppStorage.get('useNativeTopBar') !== true || !this.topBarIsHome) {
      return;
    }
    const width = AppStorage.get('winWidth') as number ?? 0;
    const height = AppStorage.get('winHeight') as number ?? 0;
    if (width <= 0 || height <= 0) {
      return;
    } // 尚未拿到窗口尺寸
    const aspect = width / height;
    const portrait = aspect < 1.0;
    const tall = aspect < 9 / 16; // 竖长屏
    if (force) {
      AppStorage.setOrCreate('topBarHidden', hidden);
      return;
    }
    if (hidden) {
      if (tall) {
        return;
      } // 竖长屏不处理
      if (portrait) {
        AppStorage.setOrCreate('topBarCollapsed', true); // 9/16 ~ 1:1：收起
      } else {
        AppStorage.setOrCreate('topBarHidden', true); // ≥ 1:1：隐藏
      }
    } else {
      AppStorage.setOrCreate('topBarHidden', false);
    }
  }


  public changeTabIndex(index: number): void {
    const context = getContext() as common.UIAbilityContext;
    context.eventHub.emit('EVENT_CHANGE_TAB', index);
  }

  public onFloatingWindowChange(isFloatingWindow: boolean) {
    this.channel?.invokeMethod("onFloatingWindowChange", { isFloatingWindow: isFloatingWindow });
  }

  public onWindowModeChange(isWindowMode: boolean) {
    this.channel?.invokeMethod("onWindowModeChange", { isWindowMode: isWindowMode });
  }

  /**
   * 源端 onContinue 时向 Dart 拉取当前播放状态（JSON 字符串），
   * 无播放或超时返回 null。onContinue 有系统时限，超时兜底避免卡死接续流程。
   */
  public getContinuationState(): Promise<string | null> {
    if (this.channel == null) {
      return Promise.resolve(null);
    }
    return new Promise<string | null>((resolve) => {
      const timer = setTimeout(() => resolve(null), 1500);
      const callback: MethodResult = {
        success: (result: Any) => {
          clearTimeout(timer);
          resolve(typeof result === "string" ? result : null);
        },
        error: (_code: string, _msg: string, _details: Any) => {
          clearTimeout(timer);
          resolve(null);
        },
        notImplemented: () => {
          clearTimeout(timer);
          resolve(null);
        },
      };
      this.channel!.invokeMethod("getContinuationState", null, callback);
    });
  }

  /**
   * 对端收到接续数据：暂存，并按需通知 Dart。
   *
   * 仅热启动（notify=true）推送通知；冷启动不能推送：Dart 尚未注册 handler，
   * 推送会进引擎 channel buffer，在 Dart 注册 handler 的瞬间（首帧前）回放，
   * 此时 GetMaterialApp 尚未挂载，取走的数据无处跳转即被丢弃。冷启动由 Dart
   * 首帧后主动拉取暂存数据。
   */
  public setPendingContinuation(data: string, notify: boolean) {
    this.pendingContinuation = data;
    if (notify) {
      this.channel?.invokeMethod("onContinuationRestore", null);
    }
  }

  /**
   * 动态控制本应用在对端设备是否显示为“可接续”：仅播放器持有视频时激活，
   * 避免用户在无播放时发起接续而失败。
   */
  private setMissionContinueState(active: boolean) {
    const context = getContext() as common.UIAbilityContext;
    const state = active
      ? AbilityConstant.ContinueState.ACTIVE
      : AbilityConstant.ContinueState.INACTIVE;
    context.setMissionContinueState(state).catch((err: Object) => {
      console.error("HarmonyChannel", `setMissionContinueState failed: ${err}`);
    });
  }

  private async setMiniWindowLandscape(landscape: boolean) {
    this.lastWindow ??= await window.getLastWindow(getContext());
    if (landscape) {
      this.lastWindow.enableLandscapeMultiWindow();
    } else {
      this.lastWindow.disableLandscapeMultiWindow();
    }
  }

  /**
   * 控制系统装饰栏（应用图标 + 标题那条色条）显隐，直接调官方
   * window.setWindowDecorVisible。
   *
   * 不走 embedding 的 shouldHideWindowDecor 间接路径：那条路会把状态栏一并关
   * 掉，且把 viewPadding.top 钉成 getTitleButtonRect().height，绕过 TYPE_SYSTEM
   * 避让计算，使三键带避让无法并入统一安全区。
   *
   * API18 以下、或手机全屏下接口抛 1300004 时静默跳过，保持窗口原状。
   *
   * @returns 是否成功下发（false 表示当前设备/窗口形态不支持）
   */
  public setWindowDecorVisible(visible: boolean): boolean {
    if (deviceInfo.sdkApiVersion < 18) {
      return false;
    }
    try {
      this.lastWindow?.setWindowDecorVisible(visible);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      console.warn("HarmonyChannel",
        `setWindowDecorVisible(${visible}) skipped: ${e.code} ${e.message}`);
      return false;
    }
  }

  /**
   * 自由多窗装饰栏按钮颜色：dark=true 时按深色模式渲染（浅色按钮，适配
   * 深色内容顶部），false 恢复跟随系统颜色模式。仅装饰栏可见（自由窗口）
   * 时有视觉效果，其余窗口形态下为无害空操作。
   */
  private async setDecorButtonDark(dark: boolean) {
    this.lastWindow ??= await window.getLastWindow(getContext());
    try {
      this.lastWindow.setDecorButtonStyle({
        colorMode: dark
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET,
      });
    } catch (err) {
      console.error("HarmonyChannel", `setDecorButtonStyle failed: ${err}`);
    }
  }
}
