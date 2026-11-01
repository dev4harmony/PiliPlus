import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// 把当前主题的背景色下发给原生自绘标题带。
///
/// 自由窗口形态下系统装饰栏被隐藏，窗口顶部改由 ArkTS 侧 WindowTitleBar
/// 自绘一条标题带；它取色于 AppStorage 'titleBarBackground'，只能由 Dart 侧
/// 下发，否则标题带与 Flutter 内容顶部会撞色（浅色主题下出现一条突兀的深条，
/// 反之亦然）。
///
/// 取的是 [ThemeUtils.theme] 的 scaffoldBackgroundColor：纯黑主题会被
/// ThemeUtils.darkenTheme 改写成纯黑，这里自动跟着变。
abstract final class TitleBarColor {
  static bool _attached = false;

  /// 上一次成功下发的颜色，避免主题没变时反复过通道。
  static String? _last;

  /// 挂上主题变化与系统深浅色变化的监听，并立刻下发一次。
  ///
  /// 必须在首帧后调用：首帧前 ThemeUtils.lightTheme/darkTheme 还没建好。
  static void attach() {
    if (_attached) return;
    _attached = true;
    // 应用内换主题 / 换主题色 / 开关纯黑主题都会走 Get 的 update()，最终通知
    // 到 rootController
    Get.rootController.addListener(_onThemeChanged);
    // 不配对 removeObserver：监听随整个 App 生命周期常驻，attach 有 _attached
    // 守卫只挂一次，不存在重复注册或泄漏。
    WidgetsBinding.instance.addObserver(_brightnessObserver);
    republish(force: true);
  }

  /// 下发当前主题背景色。[force] 为 false 时颜色未变即跳过。
  static void republish({bool force = false}) {
    if (!_attached) return;
    final hex = _hex(ThemeUtils.theme.scaffoldBackgroundColor);
    if (!force && hex == _last) return;
    _last = hex;
    HarmonyChannel.setTitleBarBackground(hex);
  }

  /// 主题变化回调（应用内切换深浅色、切换主题色、开关纯黑主题）。
  ///
  /// 这几条路径都是先刷新 [ThemeUtils] 的 lightTheme/darkTheme 再 update()
  /// （见 lib/utils/extension/get_ext.dart 的 updateMyAppTheme），故此处读到的
  /// 已经是新调色板，无需延后一帧。
  static void _onThemeChanged() => republish();

  /// 系统深浅色变化（ThemeMode.system 下真正切换主题）。
  static final _BrightnessObserver _brightnessObserver = _BrightnessObserver();

  /// '#RRGGBB'，与 ArkTS 侧 WindowChrome.setTitleBarBackground 的入参格式一致。
  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

class _BrightnessObserver extends WidgetsBindingObserver {
  @override
  void didChangePlatformBrightness() => TitleBarColor.republish(force: true);
}
