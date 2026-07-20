import { common } from "@kit.AbilityKit";
import AbilityConstant from "@ohos.app.ability.AbilityConstant";
import ConfigurationConstant from "@ohos.app.ability.ConfigurationConstant";
import window from "@ohos.window";
import {
  Any,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodChannel,
  MethodResult,
} from "@ohos/flutter_ohos";

// import display from "@ohos.display";

export default class HarmonyChannel implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private lastWindow: window.Window | null = null;

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
  }

  public getChannel(): MethodChannel | null {
    return this.channel;
  }

  async csy(call: MethodCall) {
    this.lastWindow ??= await window.getLastWindow(getContext());
    return this.lastWindow.setSpecificSystemBarEnabled("status", call.argument("value"), true);
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case "csy":
        result.success(await this.csy(call));
        break;
      case "setMiniWindowLandscape":
        const landscape: boolean = call.argument("landscape") ?? false;
        await this.setMiniWindowLandscape(landscape);
        result.success(true);
        break;
      case "autoRotateLandscape":
        await this.autoRotateLandscape();
        result.success(true);
        break;
      case "setDecorButtonDark": {
        const dark: boolean = call.argument("dark") ?? false;
        await this.setDecorButtonDark(dark);
        result.success(true);
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
      case "getSystemFontWeightScale": {
        result.success(true);
        break;
      }
      // case 'setWindowLayoutFullScreen': {
      //   this.lastWindow ??= await window.getLastWindow(getContext())
      //   this.lastWindow.setWindowLayoutFullScreen(call.argument('fullScreen'));
      //   result.success(true);
      //   break;
      // }
      default:
        result.notImplemented();
        break;
    }
  }

  public onFloatingWindowChange(isFloatingWindow: boolean) {
    this.channel?.invokeMethod("onFloatingWindowChange", { isFloatingWindow: isFloatingWindow });
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
   * 对端收到接续数据：暂存并通知 Dart。冷启动时 Dart 尚未就绪，
   * 通知会丢失，但 Dart 首帧后会主动拉取暂存数据。
   */
  public setPendingContinuation(data: string) {
    this.pendingContinuation = data;
    this.channel?.invokeMethod("onContinuationRestore", null);
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

  async autoRotateLandscape() {
    this.lastWindow ??= await window.getLastWindow(getContext());
    this.lastWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE)
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
