import 'dart:io';

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/widgets/back_detector.dart';
import 'package:PiliPlus/common/widgets/custom_toast.dart';
import 'package:PiliPlus/common/widgets/scale_app.dart';
import 'package:PiliPlus/common/widgets/scroll_behavior.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/theme/theme_color_type.dart';
import 'package:PiliPlus/router/app_pages.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/calc_window_position.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/json_file_handler.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:auto_orientation/auto_orientation.dart';
import 'package:catcher_2/catcher_2.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:os_type/os_type.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart' hide calcWindowPosition;

WebViewEnvironment? webViewEnvironment;

Future<void> _initDownPath() async {
  if (PlatformUtils.isDesktop) {
    final customDownPath = Pref.downloadPath;
    if (customDownPath != null && customDownPath.isNotEmpty) {
      try {
        final dir = Directory(customDownPath);
        if (!dir.existsSync()) {
          await dir.create(recursive: true);
        }
        downloadPath = customDownPath;
      } catch (e) {
        downloadPath = defDownloadPath;
        await GStorage.setting.delete(SettingBoxKey.downloadPath);
        if (kDebugMode) {
          debugPrint('download path error: $e');
        }
      }
    } else {
      downloadPath = defDownloadPath;
    }
  } else if (OS.isHarmony) {
    downloadPath = 'storage/Users/currentUser/Download/com.example.piliplus';
  } else if (Platform.isAndroid) {
    final externalStorageDirPath = (await getExternalStorageDirectory())?.path;
    downloadPath = externalStorageDirPath != null
        ? path.join(externalStorageDirPath, PathUtils.downloadDir)
        : defDownloadPath;
  } else {
    downloadPath = defDownloadPath;
  }
}

Future<void> _initTmpPath() async {
  tmpDirPath = (await getTemporaryDirectory()).path;
}

Future<void> _initAppPath() async {
  appSupportDirPath = (await getApplicationSupportDirectory()).path;
}

void main() async {
  ScaledWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (OS.isHarmony) await OS.initHarmonyDeviceType();
  await _initAppPath();
  try {
    await GStorage.init();
  } catch (e) {
    await Utils.copyText(e.toString());
    if (kDebugMode) debugPrint('GStorage init error: $e');
    exit(0);
  }
  ScaledWidgetsFlutterBinding.instance.scaleFactor = Pref.uiScale;
  await Future.wait([_initDownPath(), _initTmpPath()]);
  Get
    ..lazyPut(AccountService.new)
    ..lazyPut(DownloadService.new);

  // 配置网络请求
  HttpOverrides.global = _CustomHttpOverrides();

  CacheManager.autoClearCache();

  if (PlatformUtils.isMobile) {
    await Future.wait([
      SystemChrome.setPreferredOrientations(
        [
          DeviceOrientation.portraitUp,
          if (Pref.horizontalScreen) ...[
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        ],
      ),
    ]);
    // 鸿蒙embedder将 portraitUp+landscapeLeft+landscapeRight 组合映射为
    // window.Orientation.LOCKED(锁定启动时的方向),导致平板无法自动旋转,
    // 需再设为 AUTO_ROTATION_UNSPECIFIED 才能与安卓一致跟随传感器旋转
    if (OS.isHarmony && Pref.horizontalScreen) {
      await AutoOrientation.setScreenOrientationUser();
    }
  }

  if (PlatformUtils.isMobile || OS.isHarmony) {
    await setupServiceLocator();
  }

  if (Platform.isWindows) {
    if (await WebViewEnvironment.getAvailableVersion() != null) {
      webViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: path.join(
            appSupportDirPath,
            'flutter_inappwebview',
          ),
        ),
      );
    }
  }

  Request();
  Request.setCookie();
  RequestUtils.syncHistoryStatus();

  SmartDialog.config.toast = SmartConfigToast(
    displayType: SmartToastType.onlyRefresh,
  );

  if (PlatformUtils.isMobile) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    if (Platform.isAndroid) {
      FlutterDisplayMode.supported.then((mode) {
        final String? storageDisplay = GStorage.setting.get(
          SettingBoxKey.displayMode,
        );
        DisplayMode? displayMode;
        if (storageDisplay != null) {
          displayMode = mode.firstWhereOrNull(
            (e) => e.toString() == storageDisplay,
          );
        }
        FlutterDisplayMode.setPreferredMode(displayMode ?? DisplayMode.auto);
      });
    }
  } else if (PlatformUtils.isDesktop && !OS.isHarmony) {
    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      minimumSize: const Size(400, 720),
      skipTaskbar: false,
      titleBarStyle: Pref.showWindowTitleBar
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
      title: Constants.appName,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      final windowSize = Pref.windowSize;
      await windowManager.setBounds(
        await calcWindowPosition(windowSize) & windowSize,
      );
      if (Pref.isWindowMaximized) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  if (Pref.dynamicColor) {
    await MyApp.initPlatformState();
  }

  // TODO: 鸿蒙待适配 异常捕获
  if (Pref.enableLog && !OS.isHarmony) {
    // 异常捕获 logo记录
    final customParameters = {
      'BuildConfig':
          '\nBuild Time: ${DateFormatUtils.format(BuildConfig.buildTime, format: DateFormatUtils.longFormatDs)}\n'
          'Commit Hash: ${BuildConfig.commitHash}',
    };
    final fileHandler = await JsonFileHandler.init();
    final Catcher2Options debugConfig = Catcher2Options(
      SilentReportMode(),
      [
        ?fileHandler,
        ConsoleHandler(
          enableDeviceParameters: false,
          enableApplicationParameters: false,
          enableCustomParameters: true,
        ),
      ],
      customParameters: customParameters,
    );

    final Catcher2Options releaseConfig = Catcher2Options(
      SilentReportMode(),
      [
        ?fileHandler,
        ConsoleHandler(enableCustomParameters: true),
      ],
      customParameters: customParameters,
    );

    Catcher2(
      debugConfig: debugConfig,
      releaseConfig: releaseConfig,
      rootWidget: const MyApp(),
    );
  } else {
    runApp(const MyApp());
  }

  if (OS.isHarmony) {
    // 本次启动若由跨设备接续拉起，首帧后取回接续数据并跳转视频页；
    // 顺带注册 method channel handler，保证热启动接续推送可达
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HarmonyChannel.checkPendingContinuation();
      // 获取系统初始字重值
      HarmonyChannel.initSystemFontWeight();
    });
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static ColorScheme? _light, _dark;

  static ThemeData? darkThemeData;

  static void _onBack() {
    if (SmartDialog.checkExist()) {
      SmartDialog.dismiss();
      return;
    }

    final route = Get.routing.route;
    if (route is GetPageRoute) {
      if (route.popDisposition == .doNotPop) {
        route.onPopInvokedWithResult(false, null);
        return;
      }
    }

    final navigator = Get.key.currentState;
    if (navigator?.canPop() ?? false) {
      navigator!.pop();
    }
  }

  static (ThemeData, ThemeData) getAllTheme() {
    final dynamicColor = _light != null && _dark != null && Pref.dynamicColor;
    late final brandColor = colorThemeTypes[Pref.customColor].color;
    late final variant = Pref.schemeVariant;
    return (
      ThemeUtils.getThemeData(
        colorScheme: dynamicColor
            ? _light!
            : brandColor.asColorSchemeSeed(variant, Brightness.light),
        isDynamic: dynamicColor,
      ),
      ThemeUtils.getThemeData(
        isDark: true,
        colorScheme: dynamicColor
            ? _dark!
            : brandColor.asColorSchemeSeed(variant, Brightness.dark),
        isDynamic: dynamicColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (light, dark) = getAllTheme();
    return GetMaterialApp(
      title: Constants.appName,
      theme: light,
      darkTheme: dark,
      themeMode: Pref.themeMode,
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      locale: const Locale("zh", "CN"),
      fallbackLocale: const Locale("zh", "CN"),
      supportedLocales: const [Locale("zh", "CN"), Locale("en", "US")],
      initialRoute: '/',
      getPages: Routes.getPages,
      defaultTransition: Pref.pageTransition,
      builder: FlutterSmartDialog.init(
        toastBuilder: (msg) => CustomToast(msg: msg),
        loadingBuilder: (msg) => LoadingWidget(msg: msg),
        builder: _builder,
      ),
      navigatorObservers: [
        PageUtils.routeObserver,
        FlutterSmartDialog.observer,
      ],
      scrollBehavior: PlatformUtils.isDesktop
          ? const CustomScrollBehavior(desktopDragDevices)
          : null,
    );
  }

  static Widget _builder(BuildContext context, Widget? child) {
    // scaleFactor 变化不会改变根 View 的 MediaQuery 数据（physicalSize/dpr
    // 均来自引擎），本方法不会因此重建，下面的缩放校正会失效、页面布局与
    // 渲染画布脱节（如平板全景多窗内点全屏后内容只占 75%、右/下露白底）。
    // 必须显式监听缩放变化触发重建。
    return ListenableBuilder(
      listenable: ScaledWidgetsFlutterBinding.instance.scaleFactorNotifier,
      builder: (context, _) => _scaledBuilder(context, child),
    );
  }

  static Widget _scaledBuilder(BuildContext context, Widget? child) {
    // 鸿蒙小窗横屏临时缩小时需要获取真正的缩放比例
    final uiScale = ScaledWidgetsFlutterBinding.instance.scaleFactor;
    final mediaQuery = MediaQuery.of(context);
    final textScaler = TextScaler.linear(Pref.defaultTextScale);
    // 鸿蒙 embedding（FlutterPage/FlutterView）把 ArkUI PanGesture 默认的
    // 5(vp) 当 physicalTouchSlop 下发，框架除以 DPR 后竖向滚动的触发阈值
    // 只有 ~1.5 逻辑像素（Android 约为 8）。竖向手势几乎瞬间赢得竞技场，
    // 横向滑动（如简介/评论切换）无论怎么放宽都抢不到。此处恢复为
    // Android 水平，使横竖手势能按主导方向公平竞争。
    final gestureSettings = OS.isHarmony
        ? const DeviceGestureSettings(touchSlop: 8)
        : mediaQuery.gestureSettings;
    if (uiScale != 1.0) {
      child = MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: textScaler,
          size: mediaQuery.size / uiScale,
          padding: mediaQuery.padding / uiScale,
          viewInsets: mediaQuery.viewInsets / uiScale,
          viewPadding: mediaQuery.viewPadding / uiScale,
          devicePixelRatio: mediaQuery.devicePixelRatio * uiScale,
          gestureSettings: gestureSettings,
        ),
        child: child!,
      );
    } else {
      child = MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: textScaler,
          gestureSettings: gestureSettings,
        ),
        child: child!,
      );
    }
    if (PlatformUtils.isDesktop) {
      return BackDetector(
        onBack: _onBack,
        child: child,
      );
    }
    return child;
  }

  /// from [DynamicColorBuilderState.initPlatformState]
  static Future<bool> initPlatformState() async {
    if (_light != null || _dark != null) return true;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      final corePalette = await DynamicColorPlugin.getCorePalette();

      if (corePalette != null) {
        if (kDebugMode) {
          debugPrint('dynamic_color: Core palette detected.');
        }
        _light = corePalette.toColorScheme();
        _dark = corePalette.toColorScheme(brightness: Brightness.dark);
        return true;
      }
    } on PlatformException {
      if (kDebugMode) {
        debugPrint('dynamic_color: Failed to obtain core palette.');
      }
    }

    try {
      final Color? accentColor = await DynamicColorPlugin.getAccentColor();

      if (accentColor != null) {
        if (kDebugMode) {
          debugPrint('dynamic_color: Accent color detected.');
        }
        final variant = Pref.schemeVariant;
        _light = accentColor.asColorSchemeSeed(variant, Brightness.light);
        _dark = accentColor.asColorSchemeSeed(variant, Brightness.dark);
        return true;
      }
    } on PlatformException {
      if (kDebugMode) {
        debugPrint('dynamic_color: Failed to obtain accent color.');
      }
    }
    if (kDebugMode) {
      debugPrint('dynamic_color: Dynamic color not detected on this device.');
    }
    GStorage.setting.put(SettingBoxKey.dynamicColor, false);
    return false;
  }
}

class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // ..maxConnectionsPerHost = 32
    /// The default value is 15 seconds.
    //   ..idleTimeout = const Duration(seconds: 15);
    if (kDebugMode || Pref.badCertificateCallback) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }
}
