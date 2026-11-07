import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';

/// 进入「内容全屏」：窗口仍占满整个屏幕，只隐藏系统栏与自绘标题带。
///
/// 返回 true 表示原生窗口层已接管，调用方不必再走 media_kit 旧通道。
Future<bool> enterContentFullScreen() =>
    HarmonyChannel.enterContentFullScreen();

/// 退出「内容全屏」。返回值语义同 [enterContentFullScreen]。
Future<bool> exitContentFullScreen() => HarmonyChannel.exitContentFullScreen();

/// 强制窗口朝向（1 = 竖屏、0 = 横屏，对应原生 Orientation 常量）。
///
/// 部分机型（Mate80）开启系统旋转锁定后无法用 SystemChrome 强制转回竖屏，
/// 只能走原生接口。
Future<void> setWindowOrientation(int orientation) =>
    HarmonyChannel.setWindowOrientation(orientation);
