import 'dart:io' show Platform;

import 'package:PiliPlus/harmony_adapt/window/content_fullscreen.dart';
import 'package:PiliPlus/harmony_adapt/window/system_bars.dart';
import 'package:PiliPlus/harmony_adapt/window/window_facts.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiOverlay, MethodChannel, DeviceOrientation;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:os_type/os_type.dart';

/// 鸿蒙：窗口化（小窗/分屏/自由窗口）全屏且未移除播放页安全边距时，原生
/// 装饰（状态栏/挖孔/自绘标题带）合并出的顶部安全区（逻辑像素，已按
/// uiScale 换算）。
///
/// 原生侧已把自由窗口标题带并进顶部上报，[HarmonyChannel.rootTopInset] 即
/// 「播放器顶部必须让出的高度」。普通全屏页面自身已有黑边占位（上游行为），
/// 不在此重复让位。
///
/// [allowRevealedTitleBar] 供播控顶栏使用：自由窗口全屏下鼠标唤出自绘标题带时，
/// 原生会把标题带高度并进顶部安全区（见 ArkTS WindowState.readSafeArea），
/// 顶栏据此整体下移一条标题带的高度，避免被呼出的标题带盖住点不到。
/// 弹幕等其它消费方保持 false，避免唤出/收回时整片弹幕跳动。
double? harmonyDecorTopInset(
  BuildContext context, {
  required bool isFullScreen,
  required bool removeSafeArea,
  bool allowRevealedTitleBar = false,
}) {
  if (!OS.isHarmony || !isFullScreen || removeSafeArea) {
    return null;
  }
  final windowMode = WindowFacts.isWindowMode;
  final revealedTitleBar =
      allowRevealedTitleBar && WindowFacts.titleBarRevealed;
  if (!windowMode && !revealedTitleBar) {
    return null;
  }
  final inset = HarmonyChannel.rootTopInset(context);
  return inset > 0 ? inset : null;
}

bool _isDesktopFullScreen = false;

@pragma('vm:notify-debugger-on-exception')
Future<void> enterDesktopFullScreen({bool inAppFullScreen = false}) async {
  if (!inAppFullScreen && !_isDesktopFullScreen) {
    _isDesktopFullScreen = true;
    try {
      // 自由窗口形态交给原生（记状态、可还原），其余形态回退 media_kit 旧实现。
      if (await enterContentFullScreen()) return;
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
      if (await exitContentFullScreen()) return;
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

/// 方向策略在鸿蒙上统一由 `OrientationPolicy` 决策（形态 + 页面 + 全屏），
/// 这里不再直接下发方向，避免两处写策略互相覆盖。
Future<void>? portraitUpMode() {
  if (OS.isHarmony) return null;
  return _setPreferredOrientations(const [.portraitUp]);
}

Future<void>? portraitDownMode() {
  if (OS.isHarmony) return null;
  return _setPreferredOrientations(const [.portraitDown]);
}

Future<void>? landscapeLeftMode() {
  if (OS.isHarmony) return null;
  return _setPreferredOrientations(const [.landscapeLeft]);
}

Future<void>? landscapeRightMode() {
  if (OS.isHarmony) return null;
  return _setPreferredOrientations(const [.landscapeRight]);
}

Future<void>? fullMode() {
  if (OS.isHarmony) return null;
  return _setPreferredOrientations(
    const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
  );
}

bool _showSystemBar = true;
bool get showSystemBar_ => _showSystemBar;
Future<void>? hideSystemBar() {
  if (!_showSystemBar) {
    return null;
  }
  _showSystemBar = false;
  if (OS.isHarmony) return SystemBars.sync(hidden: true);
  return SystemChrome.setEnabledSystemUIMode(.immersiveSticky);
}

//退出全屏显示
Future<void>? showSystemBar() {
  if (_showSystemBar) {
    return null;
  }
  _showSystemBar = true;
  if (OS.isHarmony) return SystemBars.sync(hidden: false);
  return SystemChrome.setEnabledSystemUIMode(
    Platform.isAndroid && DeviceUtils.sdkInt < 29 ? .manual : .edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}