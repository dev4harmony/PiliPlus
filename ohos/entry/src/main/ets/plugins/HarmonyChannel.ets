import { common, wantAgent, WantAgent } from "@kit.AbilityKit";
import { BusinessError, deviceInfo } from "@kit.BasicServicesKit";
import { http } from "@kit.NetworkKit";
import { util } from "@kit.ArkTS";
import { fileIo } from "@kit.CoreFileKit";
import { formProvider } from "@kit.FormKit";
import AbilityConstant from "@ohos.app.ability.AbilityConstant";
import Want from "@ohos.app.ability.Want";
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
import settings from "@ohos.settings";
import { appAppearance } from "../appearance/AppAppearance";
import { deviceFormState } from "../window/DeviceForm";
import { windowChrome } from "../window/WindowChrome";
import { SafeAreaInsets, WindowSnapshot, windowState } from "../window/WindowState";

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
  /**
   * 兼容旧通道 setFullScreenBars 用的序号与「会话 epoch」。
   *
   * 新链路（Dart SystemBars.sync）自带 revision/epoch；旧链路没有，这里补上，
   * 两者都汇入 WindowState 的同一个状态机，晚到的旧命令不会覆盖新状态。
   */
  private barsRevision: number = 0;
  private barsEpoch: number = Date.now() & 0x7fffffff;

  private nextBarsRevision(): number {
    this.barsRevision += 1;
    return this.barsRevision;
  }

  getUniqueClassName(): string {
    return "HarmonyChannel";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "harmonyChannel");
    this.channel.setMethodCallHandler(this);
    // 窗口级状态中心 → Flutter 的反向推送。窗口快照（自由窗口/小窗/受限窗口、
    // 自绘标题带显隐）与安全区避让区都从 windowState 出来，推送名与 Dart 侧
    // HarmonyChannel 的 handler 一一对应。
    windowState.setSnapshotListener((snapshot: WindowSnapshot): void => {
      this.channel?.invokeMethod("onWindowSnapshot", snapshot);
    });
    windowState.setSafeAreaListener((insets: SafeAreaInsets): void => {
      this.channel?.invokeMethod("onSafeAreaChange", insets);
    });
    // 设备形态（细长竖屏 / 跟随系统）变化：折叠、展开后重新判定并推给 Dart，
    // 由 Dart 按「形态 + 页面类型 + 是否全屏」重算方向策略。
    deviceFormState.attach((portraitForm: boolean): void => {
      this.channel?.invokeMethod("onDeviceFormChange", {
        'portraitForm': portraitForm,
      });
    });
    // // 监听画面方向
    // display.on('change', () => {
    //   // 获取当前旋转角度
    //   let rotation = display.getDefaultDisplaySync().rotation;
    //   this.channel!.invokeMethod('onRotationChange', { 'rotation': rotation })
    // })
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    windowState.setSnapshotListener(null);
    windowState.setSafeAreaListener(null);
    deviceFormState.detach();
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
    // 走窗口级系统栏状态机：串行 apply、失败重试、旋转后按最新意图重放，
    // 避免旋转与全屏切换并发时状态栏显隐被后到的一次吃掉（见 SystemBars）。
    await windowState.syncSystemBars(fullscreen, this.nextBarsRevision(), this.barsEpoch);
    // 状态栏显隐会改 TYPE_SYSTEM.topRect，重推一次兜底。
    windowState.notifySafeArea();
  }

  async setWindowOrientation(policy: string) {
    await windowState.setWindowOrientation(policy);
  }

  /// 系统「自动旋转」开关是否开启（即旋转锁定是否关闭）。读取失败按开启处理。
  ///
  /// 仅用于横屏视频全屏时选择方向策略：锁关用 USER_ROTATION_LANDSCAPE
  /// （临时转横后四方向跟随，转竖屏可自动退全屏），锁开用
  /// AUTO_ROTATION_LANDSCAPE（仅横向两方向、不受锁控制，可 180° 翻转）。
  private readAutoRotateEnabled(): boolean {
    try {
      const value: string = settings.getValueSync(
        getContext(),
        settings.general.ACCELEROMETER_ROTATION_STATUS,
        '1',
      );
      return value === '1';
    } catch (err) {
      console.warn('HarmonyChannel', `read ACCELEROMETER_ROTATION_STATUS failed: ${err}`);
      return true;
    }
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
      case "getAppCloneIndex": {
        // 应用分身索引：0 = 主应用，1~5 = 分身应用（见 ApplicationInfo.appIndex）。
        // 供 Dart 侧判断「当前是否主应用」——分身与主应用共用包名和公共下载目录，
        // 只有主应用才该把下载落到 storage/Users/currentUser/Download/<bundle>。
        let appCloneIndex: number = 0;
        try {
          const appContext = (getContext() as common.UIAbilityContext)
            .getApplicationContext();
          appCloneIndex = appContext.getCurrentAppCloneIndex();
        } catch (err) {
          console.error("HarmonyChannel", `getCurrentAppCloneIndex failed: ${err}`);
        }
        result.success(appCloneIndex);
        break;
      }
      case "setFullScreenBars": {
        const fullscreen: boolean = call.argument("fullscreen") ?? false;
        await this.setFullScreenBars(fullscreen);
        result.success(true);
        break;
      }
      case "setWindowOrientation": {
        const policy: string = call.argument("policy") ?? 'follow';
        await this.setWindowOrientation(policy);
        result.success(true);
        break;
      }
      case "getDeviceForm": {
        // 启动时给 Dart 一个初值：是否「细长竖屏」形态（直板机 / 大折叠外屏）。
        const form: Record<string, boolean> = {
          'portraitForm': deviceFormState.isPortraitForm(),
        };
        result.success(form);
        break;
      }
      case "getAutoRotateEnabled": {
        // 旋转锁定是否关闭（系统「自动旋转」开关），供横屏视频全屏选策略。
        const state: Record<string, boolean> = {
          'enabled': this.readAutoRotateEnabled(),
        };
        result.success(state);
        break;
      }
      case "setMiniWindowLandscape":
        const landscape: boolean = call.argument("landscape") ?? false;
        await this.setMiniWindowLandscape(landscape);
        result.success(true);
        break;
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
        // onSafeAreaChange。见 WindowState.readSafeArea 与 Dart 侧
        // HarmonyChannel.initWindowState。
        await windowState.startSafeAreaListener();
        result.success(windowState.readSafeArea());
        break;
      }
      case "getWindowSnapshot": {
        // 与 getWindowState 同源，但多了自绘标题带与全屏信息（WindowState）。
        result.success(windowState.readSnapshot());
        break;
      }
      case "setSystemBarsHidden": {
        // 幂等下发：hidden + 单调递增 revision + 会话 epoch。旋转后由原生按
        // 最新意图重放，Dart 侧无需在旋转回调里补发。
        const hidden: boolean = call.argument("hidden") ?? false;
        const revision: number = call.argument("revision") ?? 0;
        const epoch: number = call.argument("epoch") ?? 0;
        await windowState.syncSystemBars(hidden, revision, epoch);
        result.success(true);
        break;
      }
      case "enterContentFullScreen": {
        result.success(await windowChrome.enterContentFullScreen());
        break;
      }
      case "exitContentFullScreen": {
        result.success(await windowChrome.exitContentFullScreen());
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
      case "setAppearance": {
        // 深浅色模式 + 前景色 + 背景色一并下发，见 appearance/AppAppearance.ets。
        const colorMode: string = call.argument('colorMode') ?? '';
        const foreground: string = call.argument('foreground') ?? '';
        const background: string = call.argument('background') ?? '';
        appAppearance.setAppearance(colorMode, foreground, background);
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
    await windowState.setMiniWindowLandscape(landscape);
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
    // 自由窗口形态下装饰栏（含系统三键）由 WindowChrome 独占：那里会先隐藏
    // 系统标题栏、再把高度设为自绘标题带高度并把三键隐藏，页面顶部由自绘
    // 标题带接管。此时 Dart 侧不要从外面把装饰栏重新打开，否则会把自绘
    // 标题带顶掉。Dart 侧 [WindowBridge] 已按同样条件跳过下发。
    if (windowChrome.getState().isFreeWindowMode) {
      return false;
    }
    return windowState.setDecorVisible(visible);
  }
}
