import 'dart:io' show Platform;

import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:flutter/services.dart'
    show SystemChrome, MethodChannel, SystemUiOverlay, DeviceOrientation;
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;
import 'package:os_type/os_type.dart';

/// 竖屏全屏时的顶部避让高度：仅在全屏 + 竖屏 + 未移除安全边距时返回
/// [topInset]（页面传入的状态栏/挖孔高度，如直播页的 viewPadding.top），
/// 否则返回 null（不避让）。播控顶部组件与弹幕共用这一套判断，保证两处
/// 行为一致。页面自身已在播放器上方留出安全区（如视频页的黑边）时应传 null。
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

/// 鸿蒙自由多窗/悬浮窗内播控顶栏的额外避让高度。
///
/// 这类窗口的系统装饰栏已被隐藏以实现顶部沉浸（见
/// HarmonyChannel._syncWindowDecor），但最小化/最大化/关闭三键仍由系统悬浮
/// 绘制在窗口右上角，embedding 把该区域高度钉进 viewPadding.top。全屏时页面
/// 不再为播放器留顶部黑边，播控顶栏若不自己避开这一带，右上角那两排图标
/// （空降助手/弹幕/画中画/点赞/投币/收藏…）就压在三键下面，点不到。
///
/// 只认自由窗口（[HarmonyChannel.isMiniWindow]）：分屏等其它受限窗口没有这排
/// 按钮，viewPadding.top 只是引擎照搬的设备状态栏高度，避让了反而会平白多出
/// 一条空白。返回 null 表示不需要额外避让。
double? harmonyDecorTopInset(BuildContext context) {
  if (!OS.isHarmony || !HarmonyChannel.isMiniWindow) return null;
  final top = MediaQuery.viewPaddingOf(context).top;
  return top > 0 ? top : null;
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

Future<void>? fullMode() {
  return _setPreferredOrientations(
    const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
  );
}

/// 鸿蒙强制窗口转回竖屏（修mate80 横屏无法退出全屏bug）
Future<void>? harmonyForcePortrait() {
  if (!OS.isHarmony) return null;
  _lastOrientation = null;
  return HarmonyChannel.setWindowOrientation(1);
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
Future<void>? showSystemBar() {
  if (_showSystemBar) {
    return null;
  }
  _showSystemBar = true;
  if (OS.isHarmony) {
    return HarmonyChannel.setFullScreenBars(false);
  }
  return SystemChrome.setEnabledSystemUIMode(
    Platform.isAndroid && DeviceUtils.sdkInt < 29 ? .manual : .edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}