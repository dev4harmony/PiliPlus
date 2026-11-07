import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// 原生外观（深浅色模式 / 前景色 / 背景色）的唯一下发点，见
/// ohos/entry/src/main/ets/appearance/AppAppearance.ets。
abstract final class AppearanceSync {
  static bool _attached = false;

  /// 上一次成功下发的值，没变时不必反复过通道。
  static ({String colorMode, String foreground, String background})? _last;

  /// 挂监听并立刻下发一次。须在首帧后调用，此时主题才建好。
  static void attach() {
    if (_attached) return;
    _attached = true;
    // 应用内换深浅色 / 换主题色 / 纯黑主题都会走 rootController.update()。
    Get.rootController.addListener(_onThemeChanged);
    // 系统深浅色变化（ThemeMode.system 下真正切换主题）。
    WidgetsBinding.instance.addObserver(_brightnessObserver);
    republish(force: true);
  }

  /// 下发深浅色模式与主题色。[force] 为 false 时都没变即跳过。
  static void republish({bool force = false}) {
    if (!_attached) return;
    final theme = ThemeUtils.theme;
    final next = (
      // 用户选定的模式，原生据此调 context.setColorMode（未选过则传空串）。
      colorMode: ThemeUtils.themeModeMap[ThemeUtils.themeMode] ?? '',
      foreground: _hex(theme.colorScheme.primary),
      background: _hex(theme.scaffoldBackgroundColor),
    );
    if (!force && next == _last) return;
    _last = next;
    HarmonyChannel.setAppearance(
      colorMode: next.colorMode,
      foreground: next.foreground,
      background: next.background,
    );
  }

  static void _onThemeChanged() => republish();

  static final _BrightnessObserver _brightnessObserver = _BrightnessObserver();

  /// '#RRGGBB'，与 ArkTS 侧 AppAppearance.setAppearance 的入参格式一致。
  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

class _BrightnessObserver extends WidgetsBindingObserver {
  @override
  void didChangePlatformBrightness() => AppearanceSync.republish(force: true);
}
