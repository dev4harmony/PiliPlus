import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:os_type/os_type.dart';

/// 鸿蒙窗口方向策略（六种），对应 `window.Orientation` 的自动旋转族。
///
/// 方向的决策不在这里，见 `OrientationPolicy`：由「设备形态 + 页面类型 +
/// 是否全屏」唯一决定，本类只负责把策略下发给原生。
enum HarmonyOrientationPolicy {
  /// `AUTO_ROTATION_RESTRICTED`（8）：四方向跟随重力/智感，受控制中心的
  /// 旋转锁定开关控制。用于平板/2in1/横屏适配布局的折叠内屏，以及宽屏手机
  /// 等设备的非锁定页面（其非播放页不锁竖屏，仍可横屏）。
  followSystem('follow'),

  /// `PORTRAIT`（1）：固定正向竖屏，不跟随传感器，也不允许反向竖屏。
  ///
  /// 用于手机普通 UI（非播放页、竖屏视频）：这些界面不应在用户把手机倒过来
  /// （180°）时整个旋转到倒立。注意不要用 `AUTO_ROTATION_PORTRAIT`，后者
  /// 明确支持 portrait + reverse portrait，仍会跟着 180° 转。
  portraitFixed('portraitFixed'),

  /// `USER_ROTATION_PORTRAIT`（13）：先临时旋转到竖屏，之后跟随传感器
  /// （受控制中心旋转锁定控制，允许的方向由系统决定）。用于手机播放页的
  /// 横屏视频非全屏：进入播放页 / 退出全屏时把窗口转回竖屏，随后保持该策略，
  /// 等下一次传感器变化再跟随，避免设备仍横置时立即被自动旋转拉回横屏。
  ///
  /// 不能把播放页非全屏长期锁在 `portraitFixed`：窗口永远转不到横屏，
  /// 播放页非全屏下旋转手机就无法自动进入全屏了。
  userPortrait('userPortrait'),

  /// `AUTO_ROTATION_UNSPECIFIED`（12）：跟随传感器自动旋转，受控制中心旋转
  /// 锁定控制，**允许哪些方向由系统决定**（直板机不包含反向竖屏）。
  ///
  /// 用于锁关且进入全屏时窗口已是横屏的场景：允许横屏两方向与正向竖屏，
  /// 不会像 AUTO_ROTATION_RESTRICTED 那样转到 180° 反向竖屏而误退出全屏。
  systemDecided('systemDecided'),

  /// `AUTO_ROTATION_LANDSCAPE`（7）：仅横向两方向，不受旋转锁定控制。用于
  /// 手机竖屏播放形态设备、旋转锁定打开时的横屏视频全屏：180° 翻转跟手，
  /// 但窗口不会转竖屏退出（只能点按钮退出）。
  landscapeOnly('landscapeOnly'),

  /// `USER_ROTATION_LANDSCAPE`（14）：先临时旋转到横屏，之后跟随传感器
  /// （受控制中心旋转锁定控制，允许方向由系统决定）。用于手机从竖屏进入
  /// 横屏视频全屏：窗口转横后仍保持该策略，等下一次传感器变化再跟随；
  /// 直板机不允许反向竖屏，因此前摄朝下时仍保持横屏全屏。
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
