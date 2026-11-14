import { common, ConfigurationConstant, wantConstant } from "@kit.AbilityKit";
import { formProvider } from "@kit.FormKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { fileIo, fileUri, picker } from "@kit.CoreFileKit";
import AbilityConstant from "@ohos.app.ability.AbilityConstant";
import type Want from "@ohos.app.ability.Want";
import window from "@ohos.window";
import { FlutterAbility, FlutterEngine, MethodChannel } from "@ohos/flutter_ohos";
import { GeneratedPluginRegistrant } from "../plugins/GeneratedPluginRegistrant";
import HarmonyChannel from "../plugins/HarmonyChannel";
import { windowChrome } from "../window/WindowChrome";
import { deviceFormState } from "../window/DeviceForm";
import { windowState } from "../window/WindowState";

/// 跨设备接续数据在 want.parameters 中的键
const CONTINUATION_KEY = "pili_continuation";

/// 桌面快捷方式跳转类型在 want.parameters 中的键，具体见shortcuts_config
const SHORTCUT_KEY = "pili_shortcut";

/// UP主卡片点击跳转：pili_up_card=1 且带 mid
const UP_CARD_KEY = "pili_up_card";

/// 快捷方式映射
const SHORTCUT_URI_MAP: Record<string, string> = {
  "search": "bilibili://search",
  "offline": "bilibili://download",
  "history": "bilibili://history",
  "favorite": "bilibili://main/favorite",
};

/// 底栏相关事件，与 Index.ets 保持一致
const EVENT_TAB_SWITCH = 'EVENT_TAB_SWITCH';

/// 底栏由隐藏翻回显示：Flutter 据此幂等对齐页签，与 Index.ets 保持一致
const EVENT_SHELL_BARS_SHOWN = 'EVENT_SHELL_BARS_SHOWN';

/// 顶栏相关事件，与 Index.ets 保持一致
const EVENT_TOP_SEARCH = 'EVENT_TOP_SEARCH';
const EVENT_TOP_MSG = 'EVENT_TOP_MSG';
const EVENT_TOP_MINE = 'EVENT_TOP_MINE';
const EVENT_HOME_TAB_CHANGE = 'EVENT_HOME_TAB_CHANGE';

export default class EntryAbility extends FlutterAbility {
  harmonyChannel: HarmonyChannel = new HarmonyChannel();
  wasFloatingWindow: boolean = false;
  wasWindowMode: boolean = false;
  private flutterChannel: MethodChannel | null = null;
  private envChangeListener: number | null = null;
  private window: window.Window | null = null;
  /// 窗口是否已初始化（onWindowStageCreate 已跑过）。接续热启动会在
  /// onNewWant 之后再次触发 onWindowStageRestore，必须靠它拦住重复初始化，
  /// 见 [onWindowStageRestore]。窗口销毁时复位。
  private windowStageReady: boolean = false;
  /// windowStatusChange 的具名回调，销毁时要 off 掉，否则同一窗口上会随
  /// 窗口重建堆积多份监听（重复推送窗口模式/自由窗口事件）。
  private windowStatusCallback = (type: window.WindowStatusType): void => {
    // 窗口状态变化后重算外观状态（自由窗口/最大化/内容全屏 → 自绘标题带显隐）
    windowChrome.sync();
    windowState.refreshStatus();
    if (type == window.WindowStatusType.FLOATING && !this.wasFloatingWindow) {
      this.harmonyChannel.onFloatingWindowChange(true);
      this.wasFloatingWindow = true;
    } else if (this.wasFloatingWindow && type != window.WindowStatusType.FLOATING) {
      this.harmonyChannel.onFloatingWindowChange(false);
      this.wasFloatingWindow = false;
    }
    // 应用窗口是否处于受限窗口模式（分屏/自由多窗/悬浮窗等非全屏窗口）。
    // 此模式下窗口宽高比不代表设备方向，且窗口无法旋转到全屏横屏
    // 此处用于修复全屏时视频与页面没变
    const isWindowMode =
      type == window.WindowStatusType.SPLIT_SCREEN ||
      type == window.WindowStatusType.FLOATING;
    if (isWindowMode != this.wasWindowMode) {
      this.wasWindowMode = isWindowMode;
      this.harmonyChannel.onWindowModeChange(isWindowMode);
    }
  };

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    flutterEngine.getPlugins()?.add(this.harmonyChannel);
    this.flutterChannel = this.harmonyChannel.getChannel();
    this.initShellEventListeners();
  }

  /// 监听 Index.ets eventHub 的底栏切换事件，转发给 Flutter
  private initShellEventListeners(): void {
    this.context.eventHub.on(EVENT_TAB_SWITCH, (index: number) => {
      this.flutterChannel?.invokeMethod('showTab', { index: index });
    });
    // 底栏由隐藏翻回显示 → 让 Flutter 幂等对齐一次页签（首页/动态/我的）。
    // 与 EVENT_TAB_SWITCH 分开：那是「用户点了底栏」（会触发刷新/回顶部），
    // 这里只是显隐恢复后的静默对齐，见 Dart 侧 ShellTabSync。
    // typeIndex 为 NavigationBarType 序号（自定义排序下与位置序号不同）。
    this.context.eventHub.on(EVENT_SHELL_BARS_SHOWN, (index: number, typeIndex: number) => {
      this.flutterChannel?.invokeMethod('onShellBarsShown', {
        'index': index,
        'type': typeIndex,
      });
    });
    // 顶栏搜索框点击 → Flutter 打开搜索页
    this.context.eventHub.on(EVENT_TOP_SEARCH, () => {
      this.flutterChannel?.invokeMethod('onTopSearchTap', null);
    });
    // 顶栏私信点击 → Flutter 打开私信页
    this.context.eventHub.on(EVENT_TOP_MSG, () => {
      this.flutterChannel?.invokeMethod('onTopMsgTap', null);
    });
    // 顶栏头像点击 → Flutter 跳个人页
    this.context.eventHub.on(EVENT_TOP_MINE, () => {
      this.flutterChannel?.invokeMethod('onTopMineTap', null);
    });
    // 分类栏切换 → Flutter 切换首页 TabController
    this.context.eventHub.on(EVENT_HOME_TAB_CHANGE, (index: number) => {
      this.flutterChannel?.invokeMethod('onHomeTabChange', { index: index });
    });
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    AppStorage.setOrCreate('shellBarsHidden', false);
    AppStorage.setOrCreate('__scrollHidden', false);

    // 快捷方式拉起（冷启动）
    this.injectShortcutUri(want);
    super.onCreate(want, launchParam);
    // 默认不可接续，播放器持有视频时才由 Dart 侧置为 ACTIVE，
    // 避免无播放时对端出现接续入口、点击后提示接续失败
    this.context
      .setMissionContinueState(AbilityConstant.ContinueState.INACTIVE)
      .catch((err: BusinessError) => {
        console.error(`setMissionContinueState failed: ${err.code} ${err.message}`);
      });
    if (this.handleContinuation(want, launchParam, false)) {
      // 接续冷启动时系统在 onCreate 后触发 onWindowStageRestore 而非
      // onWindowStageCreate，必须调用 restoreWindowStage 才会加载窗口内容
      this.context.restoreWindowStage(new LocalStorage());
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    // 快捷方式拉起（热启动）
    this.injectShortcutUri(want);
    super.onNewWant(want, launchParam);
    // 热启动时窗口与 Flutter 引擎均已就绪，不走 restoreWindowStage，
    // 由 setPendingContinuation 推送通知 Dart 直接跳转
    this.handleContinuation(want, launchParam, true);
  }

  /**
   * 接续时的窗口恢复回调。系统在 onCreate（冷启动）**或** onNewWant（热启动）
   * 之后触发本回调而不是 onWindowStageCreate，两种情形都必须能正常加载窗口。
   *
   * 但窗口只允许初始化一次：热启动时窗口与 Flutter 引擎早已就绪，若在这里
   * 再走一遍 onWindowStageCreate，FlutterAbility 会重新 createView()（新
   * FlutterView id）+ 再次 loadContent()，得到两个 FlutterView 挂同一个
   * engine、ability↔view 映射失配；PC 自由窗口下还会重复下发同步窗口装饰
   * 接口（PostSyncTask 阻塞 ArkUI 线程），表现为接续后整机卡死。
   * 故已初始化过就只补齐窗口外观状态，不再重建。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    if (this.windowStageReady) {
      console.info('EntryAbility', 'onWindowStageRestore: window stage already initialized, skip re-create');
      windowChrome.sync();
      windowState.refreshStatus();
      return;
    }
    this.onWindowStageCreate(windowStage);
  }

  /**
   * 对端（接收方）：由接续拉起/唤醒时，从 want 中取出源端保存的播放状态，
   * 暂存后由 Dart 侧拉取并跳转视频页。返回是否为接续启动。
   *
   * notify 仅热启动（onNewWant）为 true：此时 Dart 已挂载，可直接推送让其
   * 立即跳转。冷启动（onCreate）必须为 false——推送会被引擎的 channel
   * buffer 缓存，并在 Dart 注册 handler 的瞬间（首帧、GetMaterialApp 挂载前）
   * 回放，导致数据被提前取走而无处跳转；冷启动统一由 Dart 首帧后主动拉取。
   */
  private handleContinuation(want: Want, launchParam: AbilityConstant.LaunchParam,
    notify: boolean): boolean {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return false;
    }
    const data = want.parameters?.[CONTINUATION_KEY];
    if (typeof data === "string" && data.length > 0) {
      this.harmonyChannel.setPendingContinuation(data, notify);
    }
    return true;
  }

  //快捷方式拉起：转译want.parameters为url schemes塞给want.uri，供flutter侧的app_links读取
  private injectShortcutUri(want: Want): void {
    const type = want.parameters?.[SHORTCUT_KEY];
    if (typeof type === "string" && type.length > 0) {
      const uri = SHORTCUT_URI_MAP[type];
      if (uri !== undefined) {
        want.uri = uri;
      }
    }
    // UP主卡片点击跳转：优先进入投稿视频 bilibili://video/{bvid}，否则进入UP空间 bilibili://space/{mid}
    if (want.parameters?.[UP_CARD_KEY] === "1") {
      const bvid = want.parameters?.["bvid"];
      if (typeof bvid === "string" && bvid.length > 0) {
        want.uri = `bilibili://video/${bvid}`;
      } else {
        const mid = want.parameters?.["mid"];
        if (typeof mid === "string" && mid.length > 0) {
          want.uri = `bilibili://space/${mid}`;
          // 点击卡片时同步一次数据：触发所有 up_card 卡片的 onUpdateForm 刷新
          try {
            formProvider.reloadForms(this.context as common.UIAbilityContext, "entry", "EntryFormAbility", "up_card")
              .then((num: number): void => {
                console.info(`EntryAbility: reload up_card forms success: ${num}`);
              })
              .catch((err: BusinessError): void => {
                console.error(`EntryAbility: reload up_card forms failed: ${err.code} ${err.message}`);
              });
          } catch (e) {
            console.error(`EntryAbility: reloadForms error: ${e}`);
          }
        }
      }
    }
  }

  /**
   * 源端（发起方）：系统发起接续时收集当前播放状态写入 wantParam。
   * 无正在播放的视频时拒绝本次接续。
   */
  async onContinue(wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    const state = await this.harmonyChannel.getContinuationState();
    if (state == null) {
      return AbilityConstant.OnContinueResult.REJECT;
    }
    wantParam[CONTINUATION_KEY] = state;
    // 不迁移页面栈：默认 true 会让系统接管页面栈恢复，但本应用用 Flutter
    // 自绘路由，ArkUI 侧只有 Index 一个页面，系统恢复页面栈会与
    // restoreWindowStage / 自绘标题带重建冲突。跳转完全由 Dart 侧按
    // CONTINUATION_KEY 里的播放状态完成。
    wantParam[wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY] = false;
    return AbilityConstant.OnContinueResult.AGREE;
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // 幂等：接续热启动会在 onNewWant 之后再次触发 onWindowStageRestore，
    // 而该回调会走到这里。窗口与引擎此时已就绪，再初始化一次会重建
    // FlutterView、重复 loadContent、重复挂窗口监听，PC 自由窗口下还会
    // 重复下发同步窗口装饰接口，直接把主线程卡死在 appfreeze。
    if (this.windowStageReady) {
      console.info('EntryAbility', 'onWindowStageCreate: already initialized, skip');
      return;
    }
    this.windowStageReady = true;
    super.onWindowStageCreate(windowStage);
    let w = windowStage.getMainWindowSync();
    // 窗口尺寸记忆：交系统托管，冷启动时按上次关闭的主窗尺寸/状态恢复。
    windowStage.setWindowRectAutoSave(true).catch((err: BusinessError) => {
      console.error(`setWindowRectAutoSave failed: ${err.code} ${err.message}`);
    });
    // 窗口沉浸：布局延伸到状态栏区域，配合 ArkTS 顶部沉浸栏
    // （Index.ets 顶栏自绘 + statusBarHeight 避让）实现“顶部沉浸光感”。
    // 与「仅隐藏安全区、保留状态栏图标」的关键：setWindowLayoutFullScreen
    // 让 surface 布局扩展到状态栏（隐藏安全区），同时状态栏背景设为
    // 透明，使下方 ArkTS 顶栏光感罩透出、且系统状态栏图标仍保留可见。
    // 注意：不能用 SystemChrome 隐藏整个状态栏，否则连同图标一起消失。
    w.setWindowLayoutFullScreen(true).catch((err: BusinessError) => {
      console.error(`setWindowLayoutFullScreen failed: ${err.code} ${err.message}`);
    });
    w.setWindowSystemBarProperties({
      statusBarColor: '#00000000'
    }).catch((err: BusinessError) => {
      console.error(`setWindowSystemBarProperties failed: ${err.code} ${err.message}`);
    });
    // 装饰栏/标题带/最大化状态由 WindowChrome 统一维护，这里只做挂载；
    // 窗口状态（分屏/小窗）与安全区由 WindowState 订阅并推送给 Flutter。
    // 装饰栏的真正下发时机是内容加载完成（Index.aboutToAppear 调
    // windowChrome.onContentLoaded），此前接口调用不生效。
    windowChrome.attach(w);
    windowState.attach(w, windowChrome);
    // 首帧前先按设备形态定基调：细长竖屏形态（直板机 / 大折叠外屏）先竖屏，
    // 其余（平板 / 2in1 / 阔折叠 / 折叠内屏）跟随系统。之后 Dart 侧按
    // 「形态 + 页面类型 + 是否全屏」继续收口。
    windowState.setWindowOrientation(
      deviceFormState.isPortraitForm() ? 'portraitOnly' : 'follow'
    ).catch((err: BusinessError) => {
      console.error(`set initial orientation failed: ${err.code} ${err.message}`);
    });
    this.window = w;
    w.on("windowStatusChange", this.windowStatusCallback);
    // 应用启动时可能已处于分屏/多窗状态（如从分屏入口拉起），补发初始窗口模式
    try {
      const initStatus = w.getWindowStatus();
      if (initStatus == window.WindowStatusType.SPLIT_SCREEN ||
        initStatus == window.WindowStatusType.FLOATING) {
        this.wasWindowMode = true;
        this.harmonyChannel.onWindowModeChange(true);
      }
    } catch (err) {
      console.error('EntryAbility', `read initial window status failed: ${err}`);
    }
    setTimeout(() => {
      let context = getContext() as common.UIAbilityContext;
      const documentViewPicker = new picker.DocumentViewPicker(context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      documentViewPicker
        .save(documentSaveOptions)
        .catch((err: BusinessError) => {
          console.error('EntryAbility',
            `Invoke documentViewPicker.save failed, code is ${err.code}, message is ${err.message}`);
        });
    }, 100)
  }

  /**
   * 窗口舞台销毁（窗口被真正重建而非复用）时复位初始化标记，让下一次
   * onWindowStageCreate 能正常重建；顺带把窗口级监听摘干净。
   */
  onWindowStageDestroy(): void {
    this.windowStageReady = false;
    if (this.window !== null) {
      try {
        this.window.off("windowStatusChange", this.windowStatusCallback);
      } catch (err) {
        console.error('EntryAbility', `off windowStatusChange failed: ${err}`);
      }
      this.window = null;
    }
    windowChrome.detach();
    windowState.detach();
    super.onWindowStageDestroy();
  }

  onDestroy(): void {
    if (this.envChangeListener !== null) {
      this.context.getApplicationContext().off('environment', this.envChangeListener);
    }
    if (this.window !== null) {
      try {
        this.window.off("windowStatusChange", this.windowStatusCallback);
      } catch (err) {
        console.error('EntryAbility', `off windowStatusChange failed: ${err}`);
      }
    }
    this.windowStageReady = false;
    this.window = null;
    windowChrome.detach();
    windowState.detach();
    super.onDestroy();
  }
}
