import { common, ConfigurationConstant } from "@kit.AbilityKit";
import { formProvider } from "@kit.FormKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { fileIo, fileUri, picker } from "@kit.CoreFileKit";
import AbilityConstant from "@ohos.app.ability.AbilityConstant";
import type Want from "@ohos.app.ability.Want";
import window from "@ohos.window";
import { FlutterAbility, FlutterEngine, MethodChannel } from "@ohos/flutter_ohos";
import { GeneratedPluginRegistrant } from "../plugins/GeneratedPluginRegistrant";
import HarmonyChannel from "../plugins/HarmonyChannel";

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

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    flutterEngine.getPlugins()?.add(this.harmonyChannel);
    this.flutterChannel = this.harmonyChannel.getChannel();
    this.initFontWeightListener();
    this.initShellEventListeners();
  }

  /// 监听 Index.ets eventHub 的底栏切换事件，转发给 Flutter
  private initShellEventListeners(): void {
    this.context.eventHub.on(EVENT_TAB_SWITCH, (index: number) => {
      this.flutterChannel?.invokeMethod('showTab', { index: index });
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

  private initFontWeightListener(): void {
    // 监听系统字重变化
    this.envChangeListener = this.context.getApplicationContext().on('environment', {
      onConfigurationUpdated: (config) => {
        const fontWeightScale = config.fontWeightScale;
        console.info(`EntryAbility: fontWeightScale changed to ${fontWeightScale}`);
        this.flutterChannel?.invokeMethod("onFontWeightScaleChange", { fontWeightScale: fontWeightScale });
      },
      onMemoryLevel: () => {
      }
    });

    // 获取初始系统字重值
    const initialFontWeightScale = this.context.config.fontWeightScale;
    console.info(`EntryAbility: initial fontWeightScale is ${initialFontWeightScale}`);
    this.flutterChannel?.invokeMethod("onFontWeightScaleChange", { fontWeightScale: initialFontWeightScale });
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
   * 接续冷启动的窗口恢复回调。FlutterAbility 未实现此回调（不使用
   * ArkUI 页面栈），按正常创建流程初始化 Flutter 视图并加载页面。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
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
    return AbilityConstant.OnContinueResult.AGREE;
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    super.onWindowStageCreate(windowStage);
    let w = windowStage.getMainWindowSync();
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
    this.hideWindowDecorIfFloating(w);
    w.on("windowStatusChange", (type) => {
      // 原生先行隐藏，避免 Dart 侧（首帧前）下发前装饰栏先露一下
      this.hideWindowDecorIfFloating(w, type);
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
    });
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
   * 自由多窗（FLOATING）/ 最大化（MAXIMIZE，2in1）下提前隐藏系统装饰栏。
   *
   * 真正的策略由 Dart 侧 HarmonyChannel._syncWindowDecor 通过 embedding 的
   * SystemChrome 通道维护（只保留 'navigation' → embedding 自己会
   * setWindowDecorVisible(false) 并把 viewPadding.top 钉成三键高度）；这里
   * 只是在窗口创建 / 进入自由窗口的第一时间先隐藏一次，否则 Dart 首帧前
   * 装饰栏会先出现再收回。非自由窗口不调用：手机全屏下该接口会抛 1300004。
   */
  private hideWindowDecorIfFloating(w: window.Window, status?: window.WindowStatusType): void {
    if (status === undefined) {
      try {
        status = w.getWindowStatus();
      } catch (err) {
        return;
      }
    }
    if (status != window.WindowStatusType.FLOATING && status != window.WindowStatusType.MAXIMIZE) {
      return;
    }
    try {
      w.setWindowDecorVisible(false);
    } catch (err) {
      const e = err as BusinessError;
      console.warn('EntryAbility', `setWindowDecorVisible(false) skipped: ${e.code} ${e.message}`);
    }
  }

  onDestroy(): void {
    if (this.envChangeListener !== null) {
      this.context.getApplicationContext().off('environment', this.envChangeListener);
    }
    super.onDestroy();
  }
}
