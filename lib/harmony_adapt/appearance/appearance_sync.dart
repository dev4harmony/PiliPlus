import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// 原生外观（前景色 / 背景色）的唯一下发点：跟随 Flutter 主题与系统深浅色变化，
/// 两色成对发给 ArkTS（见 ohos/entry/src/main/ets/appearance/AppAppearance.ets）。
abstract final class AppearanceSync {
  static bool _attached = false;

  /// 上一次成功下发的色值，主题没变时不必反复过通道。
  static ({String foreground, String background})? _last;

  /// 挂监听并立刻下发一次。须在首帧后调用，此时主题才建好。
  static void attach() {
    if (_attached) return;
    _attached = true;
    // 应用内换主题 / 换主题色 / 纯黑主题都会走 rootController.update() 通知到这里。
    Get.rootController.addListener(_onThemeChanged);
    // 监听随 App 生命周期常驻，不配对 removeObserver。
    WidgetsBinding.instance.addObserver(_brightnessObserver);
    republish(force: true);
  }

  /// 下发当前主题的前景/背景色。[force] 为 false 时两色都没变即跳过。
  static void republish({bool force = false}) {
    if (!_attached) return;
    final theme = ThemeUtils.theme;
    final next = (
      foreground: _hex(theme.colorScheme.primary),
      background: _hex(theme.scaffoldBackgroundColor),
    );
    if (!force && next == _last) return;
    _last = next;
    HarmonyChannel.setThemeColors(
      foreground: next.foreground,
      background: next.background,
    );
  }

  static void _onThemeChanged() => republish();

  static final _BrightnessObserver _brightnessObserver = _BrightnessObserver();

  /// '#RRGGBB'，与 ArkTS 侧 AppAppearance.setColors 的入参格式一致。
  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

class _BrightnessObserver extends WidgetsBindingObserver {
  @override
  void didChangePlatformBrightness() => AppearanceSync.republish(force: true);
}
