import { common } from "@kit.AbilityKit";
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

export default class EntryAbility extends FlutterAbility {
  harmonyChannel: HarmonyChannel = new HarmonyChannel();
  wasFloatingWindow: boolean = false;
  private flutterChannel: MethodChannel | null = null;
  private envChangeListener: number | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    flutterEngine.getPlugins()?.add(this.harmonyChannel);
    this.flutterChannel = this.harmonyChannel.getChannel();
    this.initFontWeightListener();
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
    super.onCreate(want, launchParam);
    // 默认不可接续，播放器持有视频时才由 Dart 侧置为 ACTIVE，
    // 避免无播放时对端出现接续入口、点击后提示接续失败
    this.context
      .setMissionContinueState(AbilityConstant.ContinueState.INACTIVE)
      .catch((err: BusinessError) => {
        console.error(`setMissionContinueState failed: ${err.code} ${err.message}`);
      });
    if (this.handleContinuation(want, launchParam)) {
      // 接续冷启动时系统在 onCreate 后触发 onWindowStageRestore 而非
      // onWindowStageCreate，必须调用 restoreWindowStage 才会加载窗口内容
      this.context.restoreWindowStage(new LocalStorage());
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    super.onNewWant(want, launchParam);
    // 热启动时窗口与 Flutter 引擎均已就绪，不走 restoreWindowStage，
    // 由 setPendingContinuation 推送通知 Dart 直接跳转
    this.handleContinuation(want, launchParam);
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
   */
  private handleContinuation(want: Want, launchParam: AbilityConstant.LaunchParam): boolean {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return false;
    }
    const data = want.parameters?.[CONTINUATION_KEY];
    if (typeof data === "string" && data.length > 0) {
      this.harmonyChannel.setPendingContinuation(data);
    }
    return true;
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
    w.on("windowStatusChange", (type) => {
      if (type == window.WindowStatusType.FLOATING && !this.wasFloatingWindow) {
        this.harmonyChannel.onFloatingWindowChange(true);
        this.wasFloatingWindow = true;
      } else if (this.wasFloatingWindow && type != window.WindowStatusType.FLOATING) {
        this.harmonyChannel.onFloatingWindowChange(false);
        this.wasFloatingWindow = false;
      }
    });
    await setTimeout(() => {
      let context = getContext() as common.UIAbilityContext;
      const documentViewPicker = new picker.DocumentViewPicker(context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      documentViewPicker
        .save(documentSaveOptions)
        .catch((err: BusinessError) => {
          console.error('测试：' +
            `Invoke documentViewPicker.save failed, code is ${err.code}, message is ${err.message}`,
          );
        });
      console.log('测试：' + '创建下载文件夹成功')
    }, 100)
  }

  onDestroy(): void {
    if (this.envChangeListener !== null) {
      this.context.getApplicationContext().off('environment', this.envChangeListener);
    }
    super.onDestroy();
  }
}
