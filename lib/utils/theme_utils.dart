import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoThemeData;
import 'package:flutter/foundation.dart' show PlatformDispatcher;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:os_type/os_type.dart';

abstract final class ThemeUtils {
  static late ThemeData lightTheme;

  static late ThemeData darkTheme;

  static final Rx<ThemeMode> _themeMode = Pref.themeMode.obs;

  /// 手动将当前主题模式通知给原生层（应用内切换主题模式的开关处调用）
  static void syncColorModeToNative() {
    if (!OS.isHarmony) return;
    HarmonyChannel.setSystemColorMode(themeModeMap[_themeMode.value] ?? '');
  }

  static ThemeMode get themeMode => _themeMode.value;

  static set themeMode(ThemeMode value) => _themeMode.value = value;

  static Rx<ThemeMode> get themeModeRx => _themeMode;

  static Map<ThemeMode, String> themeModeMap = {
    ThemeMode.light: "light",
    ThemeMode.dark: "dark",
    ThemeMode.system: "system",
  };

  static ThemeData get theme {
    if (themeMode == .dark ||
        (themeMode == .system &&
            PlatformDispatcher.instance.platformBrightness == .dark)) {
      return darkTheme;
    }
    return lightTheme;
  }

  static bool get isDarkMode => theme.isDark;

  static String themeUrl(bool isDark) =>
      'native.theme=${isDark ? 2 : 1}&night=${isDark ? 1 : 0}';

  static ThemeData getThemeData({
    required ColorScheme colorScheme,
    required bool isDynamic,
    bool isDark = false,
  }) {
    final appFontWeight = Pref.appFontWeight.clamp(
      -1,
      FontWeight.values.length - 1,
    );

    FontWeight? fontWeight;
    if (appFontWeight == -1) {
      // 跟随系统设置
      double systemScale;
      if (OS.isHarmony && HarmonyChannel.systemFontWeightScale != null) {
        final raw = HarmonyChannel.systemFontWeightScale!;
        // 如果取到的值无效（NaN、Infinity），回退到默认值 1
        if (raw.isNaN || raw.isInfinite) {
          systemScale = 1.0;
        } else {
          systemScale = raw;
        }
      } else {
        // 完全取不到值时，使用默认值 1
        systemScale = 1.0;
      }

      // 按区间直接映射到 FontWeight，超出范围的值自动取下限(w100)或上限(w900)
      if (systemScale <= 0.75) {
        fontWeight = FontWeight.w100;
      } else if (systemScale <= 0.8) {
        fontWeight = FontWeight.w200;
      } else if (systemScale <= 0.9) {
        fontWeight = FontWeight.w300;
      } else if (systemScale <= 1.1) {
        fontWeight = FontWeight.w400;
      } else if (systemScale <= 1.2) {
        fontWeight = FontWeight.w500;
      } else if (systemScale <= 1.3) {
        fontWeight = FontWeight.w600;
      } else if (systemScale <= 1.45) {
        fontWeight = FontWeight.w700;
      } else {
        fontWeight = FontWeight.w800;
      }
    } else {
      fontWeight = FontWeight.values[appFontWeight];
    }

    // 上游 4ca037345 起支持用户自选字体族，db77169b4 起改为 FontUtils.fontFamily
    //（含自定义导入字体）。鸿蒙没有枚举系统字体的通道，用户不导入字体时它为
    // null，回落到鸿蒙一贯的 HarmonyOS Sans；在本仓库的安卓 / Windows / Linux
    // 构建上则由用户的选择覆盖。
    late final fontFamily =
        FontUtils.fontFamily ?? "HarmonyOS Sans";
    late final textStyle = TextStyle(
      fontWeight: fontWeight,
      fontFamily: fontFamily,
    );
    ThemeData theme = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      textTheme: TextTheme(
        displayLarge: textStyle,
        displayMedium: textStyle,
        displaySmall: textStyle,
        headlineLarge: textStyle,
        headlineMedium: textStyle,
        headlineSmall: textStyle,
        titleLarge: textStyle,
        titleMedium: textStyle,
        titleSmall: textStyle,
        bodyLarge: textStyle,
        bodyMedium: textStyle,
        bodySmall: textStyle,
        labelLarge: textStyle,
        labelMedium: textStyle,
        labelSmall: textStyle,
      ),
      tabBarTheme: TabBarThemeData(labelStyle: textStyle),
      appBarTheme: AppBarTheme(
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
          color: colorScheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        surfaceTintColor: isDark ? colorScheme.surfaceContainerHighest : null,
      ),
      snackBarTheme: SnackBarThemeData(
        elevation: 20,
        actionTextColor: colorScheme.primary,
        closeIconColor: colorScheme.secondary,
        backgroundColor: colorScheme.secondaryContainer,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: fontWeight,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        surfaceTintColor: isDark ? colorScheme.surfaceContainerHighest : null,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        surfaceTintColor: isDark ? colorScheme.onSurfaceVariant : null,
      ),
      progressIndicatorTheme: isDark
          ? ProgressIndicatorThemeData(
              // ignore: deprecated_member_use
              year2023: false,
              refreshBackgroundColor: colorScheme.onInverseSurface,
            )
          // ignore: deprecated_member_use
          : const ProgressIndicatorThemeData(year2023: false),
      dialogTheme: DialogThemeData(
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
          color: colorScheme.onSurface,
        ),
        backgroundColor: colorScheme.surface,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: Style.bottomSheetRadius,
        ),
      ),
      // ignore: deprecated_member_use
      sliderTheme: const SliderThemeData(year2023: false),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(
          fontSize: 14,
          color: Colors.white,
          fontFamily: fontFamily,
          fontWeight: fontWeight,
        ),
        decoration: const BoxDecoration(
          color: Color(0xE6616161), // Colors.grey[700]!.withValues(alpha: 0.9)
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        selectionHandleColor: colorScheme.primary,
      ),
      switchTheme: const SwitchThemeData(
        padding: .zero,
        materialTapTargetSize: .shrinkWrap,
        thumbIcon: WidgetStateProperty<Icon?>.fromMap(
          <WidgetStatesConstraint, Icon?>{
            WidgetState.selected: Icon(Icons.done),
            WidgetState.any: null,
          },
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      listTileTheme: const ListTileThemeData(controlAffinity: .leading),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(
          shadowColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
    if (isDark && Pref.isPureBlackTheme) {
      return darkenTheme(theme);
    }
    return theme;
  }

  static ThemeData darkenTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final color = colorScheme.surfaceContainerHighest.darken(0.7);
    return theme.copyWith(
      canvasColor: Colors.black,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      cardTheme: theme.cardTheme.copyWith(
        color: colorScheme.surfaceContainer.darken(0.75),
      ),
      dialogTheme: theme.dialogTheme.copyWith(backgroundColor: color),
      bottomSheetTheme: theme.bottomSheetTheme.copyWith(
        backgroundColor: color,
      ),
      bottomNavigationBarTheme: theme.bottomNavigationBarTheme.copyWith(
        backgroundColor: color,
      ),
      navigationBarTheme: theme.navigationBarTheme.copyWith(
        backgroundColor: color,
      ),
      navigationRailTheme: theme.navigationRailTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      popupMenuTheme: theme.popupMenuTheme.copyWith(color: color),
      colorScheme: colorScheme.copyWith(
        primary: colorScheme.primary.darken(0.1),
        onPrimary: colorScheme.onPrimary.darken(0.1),
        primaryContainer: colorScheme.primaryContainer.darken(0.1),
        onPrimaryContainer: colorScheme.onPrimaryContainer.darken(0.1),
        inversePrimary: colorScheme.inversePrimary.darken(0.1),
        secondary: colorScheme.secondary.darken(0.05),
        onSecondary: colorScheme.onSecondary.darken(0.05),
        secondaryContainer: colorScheme.secondaryContainer.darken(0.05),
        onSecondaryContainer: colorScheme.onSecondaryContainer.darken(0.05),
        error: colorScheme.error.darken(0.05),
        surface: Colors.black,
        onSurface: colorScheme.onSurface.darken(0.15),
        surfaceTint: colorScheme.surfaceTint.darken(),
        inverseSurface: colorScheme.inverseSurface.darken(),
        onInverseSurface: colorScheme.onInverseSurface.darken(),
        surfaceContainer: colorScheme.surfaceContainer.darken(),
        surfaceContainerHigh: colorScheme.surfaceContainerHigh.darken(),
        surfaceContainerHighest: colorScheme.surfaceContainerHighest.darken(
          0.4,
        ),
      ),
    );
  }
}
