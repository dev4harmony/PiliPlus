import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:auto_orientation/auto_orientation.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart'
    show SystemChrome, MethodChannel, SystemUiOverlay, DeviceOrientation;
import 'package:os_type/os_type.dart';

/// 鸿蒙侧系统栏显隐后，安全区变化传到 Flutter（MediaQuery padding）需要数帧。
/// 退出全屏时等待该时长再旋转/切回普通布局，避免普通页 AppBar 在旋转结束后
/// 才“长高”导致整体下移一跳。
const Duration kSystemBarSettleDelay = Duration(milliseconds: 120);

/// 竖屏全屏时的顶部避让高度：仅在全屏 + 竖屏 + 未移除安全边距时返回
/// [topInset]（进全屏前捕获的状态栏/挖孔高度），否则返回 null（不避让）。
/// 播控顶部组件与弹幕共用这一套判断，保证两处行为一致。
double? portraitFullscreenTopInset({
  required bool isFullScreen,
  required bool isPortrait,
  required bool removeSafeArea,
  required double? topInset,
}) {
  if (!isFullScreen || !isPortrait || removeSafeArea) return null;
  final inset = topInset ?? 0;
  return inset > 0 ? inset : null;
}

bool _isDesktopFullScreen = false;

@pragma('vm:notify-debugger-on-exception')
Future<void> enterDesktopFullScreen({bool inAppFullScreen = false}) async {
  if (!inAppFullScreen && !_isDesktopFullScreen) {
    _isDesktopFullScreen = true;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.EnterNativeFullscreen');
    } catch (_) {}
  }
}

@pragma('vm:notify-debugger-on-exception')
Future<void> exitDesktopFullScreen() async {
  if (_isDesktopFullScreen) {
    _isDesktopFullScreen = false;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.ExitNativeFullscreen');
    } catch (_) {}
  }
}

List<DeviceOrientation>? _lastOrientation;
Future<void>? _setPreferredOrientations(List<DeviceOrientation> orientations) {
  if (_lastOrientation == orientations) {
    return null;
  }
  _lastOrientation = orientations;
  return SystemChrome.setPreferredOrientations(orientations);
}

/// 鸿蒙：让系统在「左右两个横屏方向」之间按重力自动旋转，且不受控制中心旋转锁影响。
///
/// 上游是靠 native_device_orientation 的方向监听器判断当前朝向、再指定单一方向
/// （landscapeLeft / landscapeRight）；鸿蒙没有该插件实现，若沿用上游逻辑会因拿不到
/// 朝向而恒定锁死在一个方向。这里改用原生的 AUTO_ROTATION_LANDSCAPE 交给系统判断。
Future<void>? harmonyLandscapeAutoMode() {
  _invalidateOrientationCache();
  HarmonyChannel.autoRotateLandscape();
  return null;
}

/// 鸿蒙 gravity（强制重力转屏）模式：放开四个方向交给系统按重力旋转，
/// 且**忽略系统旋转锁定**。不用 AutoOrientation.fullAutoMode——那个在鸿蒙映射
/// 到 AUTO_ROTATION_RESTRICTED，受旋转开关控制；这里走原生 AUTO_ROTATION。
Future<void> harmonyFullAutoMode() {
  _invalidateOrientationCache();
  return HarmonyChannel.fullAutoRotate();
}

/// 页面级「跟随设备方向」：四个方向按重力旋转，但**受系统旋转锁定控制**——
/// 用户锁了旋转就保持当前方向不动。关闭横屏适配时的视频详情页用它，从而
/// 「系统锁定 → 停在竖屏」「系统未锁定 → 跟着设备转」两种预期各自成立。
///
/// 鸿蒙走 AUTO_ROTATION_RESTRICTED（auto_orientation 的 fullAutoMode，
/// 名字叫 full 其实是受开关控制的版本）。
Future<void>? deviceAutoMode() {
  if (OS.isHarmony) {
    _invalidateOrientationCache();
    return AutoOrientation.fullAutoMode();
  }
  return _setPreferredOrientations(
    const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
  );
}

/// 全屏用：锁定竖屏轴，轴内按重力 180° 翻转，且不受系统旋转锁定影响
/// （鸿蒙 AUTO_ROTATION_PORTRAIT）。其他平台没有等价语义，退化为固定竖屏。
Future<void>? portraitAxisMode() {
  if (OS.isHarmony) {
    _invalidateOrientationCache();
    return AutoOrientation.portraitAutoMode();
  }
  return portraitUpMode();
}

/// 全屏用（系统未锁定旋转时）：先转到视频所在的方向，转完继续跟随设备。
/// 既保证点全屏按钮会转屏，又保留「转回另一方向 → 自动退出全屏」的手感；
/// 锁死方向轴的 [portraitAxisMode] / [harmonyLandscapeAutoMode] 做不到后者。
Future<void>? userRotateMode({required bool landscape}) {
  if (!OS.isHarmony) return null;
  _invalidateOrientationCache();
  HarmonyChannel.userRotate(landscape: landscape);
  return null;
}

/// 上面两个走的都是原生 window.setPreferredOrientation / auto_orientation 插件，
/// 绕过了 SystemChrome，[_lastOrientation] 不会更新。必须显式作废缓存，否则退出全屏时
/// [_setPreferredOrientations] 会误判「方向没变」而跳过，把屏幕卡在横屏。
void _invalidateOrientationCache() => _lastOrientation = null;

Future<void>? portraitUpMode() {
  return _setPreferredOrientations(const [.portraitUp]);
}

Future<void>? portraitDownMode() {
  return _setPreferredOrientations(const [.portraitDown]);
}

Future<void>? landscapeLeftMode() {
  return _setPreferredOrientations(const [.landscapeLeft]);
}

Future<void>? landscapeRightMode() {
  return _setPreferredOrientations(const [.landscapeRight]);
}

/// 应用级「跟随系统」：开启横屏适配时的全局方向，方向由系统按设备朝向判定，
/// 受系统旋转锁定控制（锁定 → 系统决定锁成竖屏还是横屏；未锁定 → 跟随设备）。
Future<void>? fullMode() {
  final result = _setPreferredOrientations(
    const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
  );
  // 实测鸿蒙上全向旋转功能需调用此方法才能和安卓效果一致
  // 背后的鸿蒙代码参考文档
  // 自动旋转方向类型 AUTO_ROTATION_UNSPECIFIED
  // 跟随传感器自动旋转，受控制中心的旋转开关控制，且可旋转方向受系统判定
  // （如在某种设备，可以旋转到竖屏、横屏、反向横屏三个方向，无法旋转到反向竖屏）。
  if (OS.isHarmony) {
    AutoOrientation.setScreenOrientationUser();
  }
  return result;
}

bool _showSystemBar = true;
bool get showSystemBar_ => _showSystemBar;
Future<void>? hideSystemBar() {
  if (!_showSystemBar) {
    return null;
  }
  _showSystemBar = false;
  if (OS.isHarmony) {
    // 只切换系统栏显隐，不改窗口布局，避免 Flutter 视口尺寸变化导致画面跳动。
    return HarmonyChannel.setFullScreenBars(true);
  }
  return SystemChrome.setEnabledSystemUIMode(.immersiveSticky);
}

//退出全屏显示
Future<void>? showSystemBar(String reason) {
  if (_showSystemBar) {
    return null;
  }
  _showSystemBar = true;
  debugPrint('showSystemBar: $reason');
  if (OS.isHarmony) {
    return HarmonyChannel.setFullScreenBars(false);
  }
  return SystemChrome.setEnabledSystemUIMode(
    Platform.isAndroid && DeviceUtils.sdkInt < 29 ? .manual : .edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}

/// 供路由观察器在页面回到栈底时调用：若系统栏当前被隐藏则恢复。
/// 与原生顶栏的显隐同频，避免「顶栏已先出现、状态栏要等转场结束才恢复」
/// 导致页面布局在转场结束后下移（issue #151）。
void restoreSystemBarIfHidden() {
  if (!_showSystemBar) {
    showSystemBar('observer_sync');
  }
}

Future<void> toggleSystemBar() {
  _showSystemBar = !_showSystemBar;
  if (OS.isHarmony) {
    return HarmonyChannel.setFullScreenBars(!_showSystemBar);
  }
  return SystemChrome.setEnabledSystemUIMode(
    _showSystemBar ? .edgeToEdge : .immersiveSticky,
  );
}
