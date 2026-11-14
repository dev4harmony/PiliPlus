import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:os_type/os_type.dart';

/// 鸿蒙窗口方向策略（三种），对应 `window.Orientation` 的自动旋转族。
///
/// 方向的决策不在这里，见 `OrientationPolicy`：由「设备形态 + 页面类型 +
/// 是否全屏」唯一决定，本类只负责把策略下发给原生。
enum HarmonyOrientationPolicy {
  /// `AUTO_ROTATION_RESTRICTED`（8）：四方向跟随重力/智感，受控制中心的
  /// 旋转锁定开关控制。用于平板/2in1/阔折叠等跟随系统的形态，以及横屏
  /// 视频全屏中「窗口已经横屏」的状态。
  followSystem('follow'),

  /// `USER_ROTATION_PORTRAIT`（13）：**临时**旋转到竖屏，之后跟随传感器
  /// （受控制中心旋转锁定控制）。用于细长竖屏形态设备上「横屏视频、非全屏」
  /// 的播放页：进入播放页 / 退出全屏时向系统发一次「临时转回竖屏」，让页面
  /// 落到竖屏非全屏；之后用户转动设备时再跟随。
  userPortrait('userPortrait'),

  /// `AUTO_ROTATION_PORTRAIT`（6）：仅竖向，不受旋转锁定控制。用于细长竖屏
  /// 形态设备（直板机 / 大折叠外屏）的非播放页。
  portraitOnly('portraitOnly'),

  /// `AUTO_ROTATION_LANDSCAPE`（7）：仅横向，不受旋转锁定控制。用于需要
  /// 「不管怎么拿都保持横屏」的场景（当前没有状态使用）。
  landscapeOnly('landscapeOnly'),

  /// `USER_ROTATION_LANDSCAPE`（14）：**临时**旋转到横屏，之后跟随传感器
  /// （受控制中心旋转锁定控制）。用于细长竖屏形态设备的横屏视频全屏：
  /// - 旋转锁关闭：转到竖屏时窗口跟着转回竖屏 → 触发自动退出全屏；
  /// - 旋转锁打开：不再跟随传感器，保持横屏，只能点按钮退出。
  userLandscape('userLandscape');

  const HarmonyOrientationPolicy(this.value);

  final String value;
}

abstract final class HarmonyOrientation {
  static Future<void> apply(HarmonyOrientationPolicy policy) async {
    if (!OS.isHarmony) return;
    try {
      await HarmonyChannel.setWindowOrientation(policy.value);
    } catch (_) {}
  }
}
