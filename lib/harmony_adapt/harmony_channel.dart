import 'dart:math' show max;

import 'package:PiliPlus/common/widgets/scale_app.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/harmony_adapt/window/window_facts.dart';
import 'package:PiliPlus/harmony_adapt/continuation.dart';
import 'package:PiliPlus/harmony_adapt/shell_tab_sync.dart';
import 'package:PiliPlus/models/common/harmony/hds_material_level.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:os_type/os_type.dart';

abstract class HarmonyChannel {
  /// @ohos.graphics.hdrCapability 的 HDRFormat 中 HDR Vivid 的取值。
  static const int _hdrFormatVivid = 3;

  /// 面板实际支持的 HDR 类型，启动时查一次。
  ///
  /// null 表示**还没查到**（没查过 / 查询失败），与「查到了，一个都不支持」
  /// （空集）是两回事：前者不能拿来关掉 HDR，否则查询一旦失败，HDR 就会在一台
  /// 完全正常的设备上被静默禁用；后者才是这块屏确实不支持。
  static Set<int>? _displayHdrFormats;

  /// 面板是否**明确**不支持任何 HDR 格式。只有问出过结果才敢下这个结论，
  /// 见 [_displayHdrFormats] 对 null 的说明。
  static bool get displayHasNoHdr => _displayHdrFormats?.isEmpty ?? false;

  /// 面板**没有明确表示**不支持 HDR Vivid（未知按支持）。
  ///
  /// HDR Vivid 是鸿蒙唯一带动态元数据的类型，HDR Vivid、杜比视界、HDR10+
  /// 都靠它上报。与 [displayHasNoHdr] 同一个口径——查询失败不该把它们静默
  /// 降级成只有静态元数据的 HDR10。
  static bool get displayMaySupportHdrVivid =>
      _displayHdrFormats?.contains(_hdrFormatVivid) ?? true;

  /// 查询面板的 HDR 能力。只在鸿蒙上有意义。
  ///
  /// 失败时能力保持未知，不能记成空集，见 [_displayHdrFormats]。
  static Future<void> loadDisplayHdrFormats() async {
    if (!OS.isHarmony) return;
    try {
      final list = await _channel.invokeMethod<List<Object?>>(
        'getDisplayHdrFormats',
      );
      _displayHdrFormats = <int>{
        for (final e in list ?? const <Object?>[])
          if (e is int) e,
      };
    } catch (e) {
      // 含 MissingPluginException：原生侧没有这个 method 的旧版本。
      // 不写 _displayHdrFormats，能力保持「未知」。
      if (kDebugMode) {
        debugPrint('[HDRCAP] query failed, capability stays unknown: $e');
      }
    }
  }

  /// 应用分身索引：0 = 主应用，1~5 = 分身应用
  static int _appCloneIndex = 0;

  /// 当前是否运行在分身应用里。主应用为 false
  static bool get isAppClone => _appCloneIndex > 0;

  /// 当前是否运行在主应用里
  static bool get isMainApp => _appCloneIndex == 0;

  /// 查询当前是否为主应用。
  static Future<void> loadAppCloneIndex() async {
    if (!OS.isHarmony) return;
    try {
      final index = await _channel.invokeMethod<int>('getAppCloneIndex');
      _appCloneIndex = index ?? 0;
    } catch (e) {
      // 含 MissingPluginException：原生侧没有这个 method 的旧版本。
      // 不写非 0 值，按主应用处理，避免把下载目录误降到应用私有目录。
      _appCloneIndex = 0;
      if (kDebugMode) {
        debugPrint('[APPCLONE] query failed, treat as main app: $e');
      }
    }
  }

  static final MethodChannel _channel = const MethodChannel('harmonyChannel')
    ..setMethodCallHandler(handler);

  static Future<dynamic> handler(MethodCall call) async {
    switch (call.method) {
      case 'onFloatingWindowChange':
        onLandscapeOrMiniWindowChange(null, call.arguments['isFloatingWindow']);
        break;
      case 'onFreeWindowModeChange':
        _onFreeWindowModeChange(
          call.arguments['isFreeWindowMode'] as bool? ?? false,
        );
        break;
      case 'onWindowModeChange':
        _windowMode = WindowFacts.isWindowMode =
            call.arguments['isWindowMode'] as bool? ?? false;
        break;
      case 'onSafeAreaChange':
        _updateSafeArea(call.arguments);
        break;
      // 原生窗口快照（自由多窗/小窗/分屏/标题带状态的整体推送，
      // 见 ArkTS WindowState.emitSnapshot）
      case 'onWindowSnapshot':
        if (call.arguments is Map) {
          applyWindowSnapshot(
            (call.arguments as Map).cast<Object?, Object?>(),
          );
        }
        break;
      // 源端 onContinue 拉取当前播放状态
      case 'getContinuationState':
        return HarmonyContinuation.currentState();
      // 对端应用已在运行时被接续唤醒
      case 'onContinuationRestore':
        checkPendingContinuation();
        break;
      // 原生底栏切换页签（index 为 Navbar 排序后的页签序号，与设置内
      // Navbar 编辑保持一致；数量与顺序由 setNavBarConfig 同步）
      case 'showTab':
        _onShellTabSwitch?.call(call.arguments['index'] as int? ?? 0);
        break;
      // 原生 HDS 底栏「隐藏 → 显示」时上报（ArkTS Index.ets 在 shellBarsHidden
      // 由 true 翻回 false 的那一帧发一次，带上当前页签的类型序号）。此时按原生
      // 当前页签幂等对齐 Flutter：一致则什么都不做，见 [ShellTabSync.align]。
      case 'onShellBarsShown':
        {
          final args = call.arguments;
          final type = args is Map ? args['type'] : null;
          ShellTabSync.align(
            type is int ? type : -1,
            dispatch: _onShellTabSwitch,
          );
          break;
        }
      // ArkTS 顶栏搜索框点击 → Flutter 跳转搜索页
      case 'onTopSearchTap':
        _onTopSearchTap?.call();
        break;
      // ArkTS 顶栏私信点击 → Flutter 跳转私信页
      case 'onTopMsgTap':
        _onTopMsgTap?.call();
        break;
      // ArkTS 顶栏头像点击 → Flutter 跳个人页
      case 'onTopMineTap':
        _onTopMineTap?.call();
        break;
      // ArkTS 分类栏切换 → Flutter 切换首页 TabController
      case 'onHomeTabChange':
        _onHomeTabChange?.call(call.arguments['index'] as int? ?? 0);
        break;
      // 原生握持手/操作手变化 → FAB 左右换边（智感握姿）
      case 'onHoldingHandChange':
        FabSideController.instance.syncFromNative(
          isLeft: call.arguments['isLeft'] as bool? ?? false,
          fromOperatingHand: call.arguments['fromOperating'] as bool? ?? false,
        );
        break;
      default:
        break;
    }
  }

  /// 顶栏搜索点击回调：由 HomePage 注册
  static void Function()? _onTopSearchTap;
  static set onTopSearchTap(void Function()? callback) =>
      _onTopSearchTap = callback;

  /// 顶栏私信点击回调
  static void Function()? _onTopMsgTap;
  static set onTopMsgTap(void Function()? callback) => _onTopMsgTap = callback;

  /// 顶栏头像点击回调
  static void Function()? _onTopMineTap;
  static set onTopMineTap(void Function()? callback) =>
      _onTopMineTap = callback;

  /// 分类切换回调：由 HomeController 注册
  static void Function(int index)? _onHomeTabChange;
  static set onHomeTabChange(void Function(int)? callback) =>
      _onHomeTabChange = callback;

  /// Shell 页签切换回调：由 MainController 注册
  static void Function(int index)? _onShellTabSwitch;

  static set onShellTabSwitch(void Function(int)? callback) =>
      _onShellTabSwitch = callback;

  /// 向原生发送壳配置的公共辅助：非鸿蒙直接跳过，静默失败。
  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!OS.isHarmony) return;
    try {
      await _channel.invokeMethod(method, args);
    } on PlatformException catch (_) {}
  }

  /// 开关鸿蒙智感握姿的原生握持手订阅
  static Future<void> setHoldingHandMonitor(bool enable) =>
      _invoke('setHoldingHandMonitor', {'enable': enable});

  /// 向原生发送 shell 配置（Flutter 侧计算后通知 ArkTS）
  static Future<void> setShellBars({required bool useNativeTabs}) =>
      _invoke('setShellBars', {'useNativeTabs': useNativeTabs});

  /// 同步 Navbar 页签（数量与顺序，与设置内「Navbar 编辑」一致）到 ArkTS HdsTabs
  static Future<void> setNavBarConfig(List<NavigationBarType> bars) =>
      _invoke('setNavBarConfig', {'tabs': bars.map((e) => e.index).toList()});

  /// 同步动态页签角标（数量与模式，与 Flutter Badge 一致）到 ArkTS HdsTabs
  static Future<void> setDynamicBadge({
    required int count,
    required int mode,
  }) => _invoke('setDynamicBadge', {'count': count, 'mode': mode});

  /// HDS 底栏当前是否为显示状态
  static bool _hiddenByPage = false;
  static bool get hdsBarVisible => !_hiddenByPage;

  /// 控制原生 HDS 底栏/顶栏的显隐（弹窗、全屏页等场景）
  static Future<void> setShellBarsHidden(
    bool hidden, {
    bool retry = false,
    bool force = false,
  }) async {
    if (!OS.isHarmony) return;
    _hiddenByPage = hidden;
    final int total = retry ? 8 : 1;
    for (int i = 0; i < total; i++) {
      try {
        _channel.invokeMethod('setShellBarsHidden', {
          'hidden': hidden,
          'force': force,
        });
        return;
      } catch (_) {
        if (i == total - 1) return;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  /// 同步沉浸光感底栏材质等级到 ArkTS HdsTabs（hdsMaterial.MaterialLevel）
  static Future<void> setTabMaterialLevel(HdsMaterialLevel level) =>
      _invoke('setTabMaterialLevel', {'level': level.value});

  /// 下发原生外观：[colorMode] 为 light / dark / system，[foreground] 供原生
  /// 顶栏与 HDS 底栏选中态，[background] 供自绘标题带与顶栏底板（均 '#RRGGBB'）。
  /// 三者必须同一条消息，否则原生会出现模式已换、颜色还是旧主题的中间帧。
  static Future<void> setAppearance({
    required String colorMode,
    required String foreground,
    required String background,
  }) => _invoke('setAppearance', {
    'colorMode': colorMode,
    'foreground': foreground,
    'background': background,
  });

  /// 向原生发送顶栏配置（Flutter 侧计算后通知 ArkTS）
  static Future<void> setShellTopBar({required bool useNativeTopBar}) =>
      _invoke('setShellTopBar', {'useNativeTopBar': useNativeTopBar});

  /// 批量同步首页顶部数据到 ArkTS 原生顶栏
  static Future<void> setHomeTopBarData({
    required List<String> tabs,
    required bool hideTopBar,
    required int activeIndex,
  }) => _invoke('setHomeTopBarData', {
    'tabs': tabs,
    'hideTopBar': hideTopBar,
    'activeIndex': activeIndex,
  });

  /// 同步搜索默认词到 ArkTS Search 组件
  static Future<void> setHomeSearchText(String text) =>
      _invoke('setHomeSearchText', {'text': text});

  /// 同步私信未读数到 ArkTS 红点
  static Future<void> setHomeUnreadCount(String count) =>
      _invoke('setHomeUnreadCount', {'count': count});

  /// 同步头像到 ArkTS
  static Future<void> setHomeFaceUrl(String url) =>
      _invoke('setHomeFaceUrl', {'url': url});

  /// Flutter 切分类时同步高亮到 ArkTS Tabs
  static Future<void> setHomeTabIndex(int index) =>
      _invoke('setHomeTabIndex', {'index': index});

  /// 下滑收起/展开顶部大搜索栏
  static Future<void> setTopBarCollapsed(bool collapsed) =>
      _invoke('setTopBarCollapsed', {'collapsed': collapsed});

  /// 同步当前底部页签是否为首页到 ArkTS（顶栏 dialog 分流判断用）
  static Future<void> setTopBarIsHome(bool isHome) =>
      _invoke('setTopBarIsHome', {'isHome': isHome});

  /// 顶栏隐藏状态合并：路由/横屏 or 非首页页签
  static bool _topBarHiddenByRoute = false;
  static bool _topBarHiddenByTab = false;

  /// 路由/横屏切换时整体隐藏顶栏（与底栏联动）
  static Future<void> setTopBarHidden(bool hidden) async {
    if (!OS.isHarmony) return;
    _topBarHiddenByRoute = hidden;
    try {
      _channel.invokeMethod('setTopBarHidden', {
        'hidden': _topBarHiddenByRoute || _topBarHiddenByTab,
      });
    } on PlatformException catch (_) {}
  }

  /// 非首页页签（动态/我的）时隐藏顶栏（仅首页显示）
  static Future<void> setTopBarTabHidden(bool hidden) async {
    if (!OS.isHarmony) return;
    _topBarHiddenByTab = hidden;
    try {
      _channel.invokeMethod('setTopBarHidden', {
        'hidden': _topBarHiddenByRoute || _topBarHiddenByTab,
      });
    } on PlatformException catch (_) {}
  }

  /// 同步 Flutter 页签切换到 ArkTS HdsTabs
  static Future<void> changeTabIndex(int index) =>
      _invoke('changeTabIndex', {'index': index});

  /// 控制原生 HDS 底栏的滚动显隐（带动画）
  static Future<void> setShellBarsScrollHidden(bool hidden) =>
      _invoke('setShellBarsScrollHidden', {'hidden': hidden});

  /// 启动长时任务，用于下载
  static Future<void> startBackgroundTask() => _invoke('startBackgroundTask');

  /// 停止长时任务
  static Future<void> stopBackgroundTask() => _invoke('stopBackgroundTask');

  /// 取走 ETS 侧暂存的接续数据并跳转视频页。冷启动在首帧后调用，
  /// 热启动由 onContinuationRestore 推送触发；数据取走即清除，不会重复跳转。
  static Future<void> checkPendingContinuation() async {
    // 路由未就绪（首帧前）时不消费，否则数据取走即丢；留给首帧后的主动拉取
    if (Get.key.currentState == null) {
      return;
    }
    try {
      final data = await _channel.invokeMethod<String>(
        'getPendingContinuation',
      );
      HarmonyContinuation.restore(data);
    } on PlatformException catch (_) {}
  }

  /// “可接续”状态按持有者管理：视频播放器/直播间/音频页/专栏页在存续期间
  /// 持有，任一持有者存在时系统显示接续入口，全部释放后置为不可接续。
  /// 列表保持持有顺序（最新在尾部），接续时从最近的持有者生成快照。
  static final List<Object> _continuationOwners = [];

  static List<Object> get continuationOwners => _continuationOwners;

  static void holdContinuation(Object owner) {
    if (!OS.isHarmony) return;
    final wasEmpty = _continuationOwners.isEmpty;
    _continuationOwners
      ..remove(owner)
      ..add(owner);
    if (wasEmpty) {
      _setContinuationActive(true);
    }
  }

  static void releaseContinuation(Object owner) {
    if (!OS.isHarmony) return;
    if (_continuationOwners.remove(owner) && _continuationOwners.isEmpty) {
      _setContinuationActive(false);
    }
  }

  static void _setContinuationActive(bool active) {
    _channel.invokeMethod('setContinuationActive', {'active': active});
  }

  /// 测试用，ai生成信息请忽略这部分更改
  static Future csy(value) {
    return _channel.invokeMethod('csy', {'value': value});
  }

  /// 全屏/退出全屏时仅切换系统栏（状态栏+导航栏）显隐，不改窗口布局，
  /// 避免 setWindowLayoutFullScreen 改变 surface 尺寸导致画面跳动。
  static Future<void> setFullScreenBars(bool fullscreen) =>
      _invoke('setFullScreenBars', {'fullscreen': fullscreen});

  /// 鸿蒙部分机型（Mate80）开启系统旋转锁定后无法强制窗口转回竖屏，这里走原生接口。
  static Future<void> setWindowOrientation(int orientation) async {
    if (!OS.isHarmony) return;
    try {
      await _channel.invokeMethod('setWindowOrientation', {
        'orientation': orientation,
      });
    } catch (_) {}
  }

  /// 通用窗口方法发送器：非鸿蒙直接返回 null，原生异常（含旧版本没有该
  /// method 的 [MissingPluginException]）一律静默降级，窗口能力缺失不应让
  /// 调用方崩溃。
  ///
  /// 与 [_invoke] 的区别：这里需要把原生返回值取回来（窗口快照、进入/退出
  /// 内容全屏是否成功等），且参数名/返回类型由 ArkTS 侧契约决定。
  static Future<T?> invokeWindowMethod<T>(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!OS.isHarmony) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  /// 拉取一次原生窗口快照。
  ///
  /// 返回的键与 ArkTS 侧 WindowSnapshot 一致：isFreeWindowMode、maximized、
  /// contentFullScreen、titleBarVisible、titleBarHeight、isMiniWindow、
  /// isWindowMode。原生不再持有 landscape，方向由播放器回传。
  static Future<Map<Object?, Object?>?> getWindowSnapshot() =>
      invokeWindowMethod<Map<Object?, Object?>>('getWindowSnapshot');

  /// 系统栏（状态栏 + 导航栏）显隐同步。
  ///
  /// [revision] 单调递增、[epoch] 标识本次会话：原生据此丢弃乱序落地或跨会话
  /// 残留的旧消息（快速进出全屏时异步调用可能乱序）。
  static Future<void> setSystemBarsHidden({
    required bool hidden,
    required int revision,
    required int epoch,
  }) async {
    await invokeWindowMethod<void>('setSystemBarsHidden', {
      'hidden': hidden,
      'revision': revision,
      'epoch': epoch,
    });
  }

  /// 进入「内容全屏」：窗口仍占满屏，只隐藏系统栏与原生自绘标题带。
  ///
  /// 返回 true 表示原生窗口层已接管，调用方不必再走 media_kit 旧通道。
  static Future<bool> enterContentFullScreen() async =>
      await invokeWindowMethod<bool>('enterContentFullScreen') ?? false;

  /// 退出「内容全屏」，返回值语义同 [enterContentFullScreen]。
  static Future<bool> exitContentFullScreen() async =>
      await invokeWindowMethod<bool>('exitContentFullScreen') ?? false;

  /// 小窗横屏缩放开关：true 时开 enableLandscapeMultiWindow（小窗内全屏横屏），
  /// false 时关掉。
  static Future<void> setMiniWindowLandscape(bool landscape) async {
    await invokeWindowMethod<void>('setMiniWindowLandscape', {
      'landscape': landscape,
    });
  }

  /// 系统装饰栏（带应用图标 + 标题的窗口顶栏）显隐。自由窗口形态下原生由
  /// WindowChrome 独占，Dart 侧调用会被原生忽略。
  static Future<void> setWindowDecorVisible({required bool visible}) async {
    await invokeWindowMethod<void>('setWindowDecorVisible', {
      'visible': visible,
    });
  }

  /// 主动刷新一次安全区避让区（物理像素）。原生 getSafeArea 同时会订阅窗口
  /// 安全区变化，之后由 onSafeAreaChange 推送。
  static Future<void> refreshSafeArea() async {
    final area = await invokeWindowMethod<Map<Object?, Object?>>('getSafeArea');
    _updateSafeArea(area);
  }

  /// 添加UP主卡片到桌面（仅 Harmony）：原生保存UP数据并拉起添加引导页
  static Future<void> addUpToDesktop({
    required String mid,
    required String name,
    required String avatar,
    String topPhoto = '',
  }) {
    if (!OS.isHarmony) return Future.value();
    return _channel.invokeMethod('addUpToDesktop', {
      'mid': mid,
      'name': name,
      'avatar': avatar,
      'topPhoto': topPhoto,
    });
  }

  /// 横屏小窗的缩放比例固定值
  static const _miniWindowLandscapeScale = 0.75;

  /// 播放器是否已把当前视频切到全屏横屏。由播放器经
  /// [onLandscapeOrMiniWindowChange] 回传，原生侧不持有。
  static bool _landscape = false;

  /// 当前是否处于系统小窗/受限窗口。与 [WindowFacts.isMiniWindow] 同源，
  /// 保留本地副本是为了兼容老的原生推送路径（onFloatingWindowChange）。
  static bool _miniWindow = false;

  /// 当前是否处于系统自由小窗（悬浮窗/全景多窗）。小窗内窗口宽高比不代表
  /// 设备方向，基于方向的自动全屏等逻辑应据此跳过。
  static bool get isMiniWindow => _miniWindow;

  /// 是否处于「横屏小窗」：系统小窗内把横屏视频切到了全屏，此时调用过原生
  /// enableLandscapeMultiWindow。实测仅此状态下进画中画会黑屏（小窗内不全屏
  /// 进画中画画面正常），故用它而不是 [isMiniWindow] 作为拦截条件。
  static bool get isMiniWindowLandscape =>
      _miniWindow && _landscape && !_freeWindowMode;

  /// 窗口是否处于系统「自由窗口模式」（2in1/PC、平板自由多窗、平板电脑
  /// 模式）。此时窗口同样恒为 FLOATING、[_miniWindow] 为 true，但那是普通
  /// 桌面窗口而非系统小窗：窗口内全屏不会变成「横屏小窗」，不能套用 0.75
  /// 缩放与 enableLandscapeMultiWindow，否则每次进出全屏界面整体缩放一次，
  /// 观感即 DPI 突变。由原生 isInFreeWindowMode / freeWindowModeChange 维护，
  /// 不按 deviceType 判断（平板及带电脑模式的机型均上报 tablet）。
  static bool _freeWindowMode = false;

  static void _onFreeWindowModeChange(bool freeWindowMode) {
    WindowFacts.isFreeWindowMode = freeWindowMode;
    if (_freeWindowMode == freeWindowMode) return;
    _freeWindowMode = freeWindowMode;
    _applyMiniWindowLandscape();
  }

  static bool _windowMode = false;

  /// 应用窗口是否处于受限窗口模式（分屏/自由多窗/悬浮窗等非全屏窗口）。
  /// 此模式下窗口宽高比不代表设备方向，且窗口无法旋转到全屏横屏
  /// 仍应按 isFullScreen 渲染全屏布局，
  /// 此处用于修复全屏时视频与页面没变
  static bool get isWindowMode => _windowMode;

  /// 当方向或小窗变化
  static Future<void> onLandscapeOrMiniWindowChange(
    bool? landscape,
    bool? miniWindow,
  ) async {
    landscape ??= _landscape;
    miniWindow ??= _miniWindow;
    if (_landscape == landscape && _miniWindow == miniWindow) return;
    final miniWindowChanged = _miniWindow != miniWindow;
    _landscape = landscape;
    _miniWindow = miniWindow;
    WindowFacts.landscape = landscape;
    WindowFacts.isMiniWindow = miniWindow;
    if (miniWindowChanged) _syncWindowDecor();
    _applyMiniWindowLandscape();
  }

  /// 应用原生窗口快照：先落 [WindowFacts]（真源），再让本地副本与之一致，
  /// 最后只有「横屏小窗」这一组合状态发生翻转时才真正调整缩放与装饰栏——
  /// 原生在小窗内每次状态变化都会推快照，避免重复下发缩放造成视觉抖动。
  static void _applyWindowSnapshot(Map<Object?, Object?> snapshot) {
    final wasMiniWindow = _miniWindow;
    final wasMiniWindowLandscape = isMiniWindowLandscape;
    WindowFacts.applySnapshot(snapshot);
    _miniWindow = WindowFacts.isMiniWindow;
    _freeWindowMode = WindowFacts.isFreeWindowMode;
    _windowMode = WindowFacts.isWindowMode;
    // landscape 不在原生快照内，仍由播放器回传；这里只把本地镜像同步回去，
    // 避免原生推快照把 WindowFacts.landscape 冲成默认值。
    WindowFacts.landscape = _landscape;
    // 装饰栏看的是「是否小窗」本身（与方向无关），小窗进出就要重算；缩放看
    // 的才是「横屏小窗」这一组合，避免每次推快照都重设 scaleFactor 抖动。
    if (wasMiniWindow != _miniWindow) _syncWindowDecor();
    if (wasMiniWindowLandscape == isMiniWindowLandscape) return;
    _applyMiniWindowLandscape();
    _syncWindowDecor();
  }

  static void _applyMiniWindowLandscape() {
    final target = isMiniWindowLandscape;
    ScaledWidgetsFlutterBinding.instance.scaleFactor = target
        ? _miniWindowLandscapeScale
        : Pref.uiScale;
    setMiniWindowLandscape(target);
  }

  /// 依据 [WindowFacts] 重算「横屏小窗」缩放与 enableLandscapeMultiWindow。
  ///
  /// 窗口事实变化后由 lib/harmony_adapt/window/window_bridge.dart 调用；缩放始终只
  /// 在这一处落地，避免出现两个各自维护 scaleFactor 的入口。
  static void syncMiniWindowLandscape() => _applyMiniWindowLandscape();

  /// 依据 [WindowFacts] 重下发装饰栏显隐策略（自由窗口形态下装饰栏由原生
  /// 独占，本方法不产生下发）。
  static void syncWindowDecor() => _syncWindowDecor();

  /// 应用一份原生窗口快照：更新 [WindowFacts] 与本类镜像状态，并在「横屏
  /// 小窗」翻转时重算缩放与装饰栏。原生推送 onWindowSnapshot 时调用。
  static void applyWindowSnapshot(Map<Object?, Object?> snapshot) =>
      _applyWindowSnapshot(snapshot);

  /// 启动时（runApp 之前）主动拉取窗口初始状态：是否自由多窗 / 受限窗口模式
  /// （据此下发系统栏模式）、安全区避让区初值（见 [safeAreaInsets]）、装饰栏
  /// 策略（见 [_syncWindowDecor]）。
  ///
  /// 主动拉取的必要性：原生只在 windowStatusChange 时推送
  /// onFloatingWindowChange，应用直接在自由多窗里启动时收不到；且 Dart 侧
  /// handler 注册前的通道消息最多缓存一条，靠原生「补发」不可靠。放在首帧之前
  /// 是为了避免装饰栏「先出现再收回」的闪动（原生侧 EntryAbility 在窗口创建时
  /// 已先隐藏一次）。
  static Future<void> initWindowState() async {
    if (!OS.isHarmony) return;
    try {
      final state = await _channel.invokeMethod<Map>('getWindowState');
      if (state != null) {
        _windowMode = WindowFacts.isWindowMode =
            state['isWindowMode'] as bool? ?? _windowMode;
        _freeWindowMode = WindowFacts.isFreeWindowMode =
            state['isFreeWindowMode'] as bool? ?? false;
        await onLandscapeOrMiniWindowChange(
          null,
          state['isFloatingWindow'] as bool?,
        );
      }
    } catch (_) {}
    await refreshSafeArea();
    _syncWindowDecor();
  }

  /// 拉取一次原生窗口快照并应用。启动时由 lib/harmony_adapt/window/window_bridge.dart
  /// 调用；原生侧尚无 getWindowSnapshot 的旧版本返回 null，此时保留旧状态。
  static Future<void> refreshWindowSnapshot() async {
    final snapshot = await getWindowSnapshot();
    if (snapshot != null) applyWindowSnapshot(snapshot);
  }

  /// 窗口安全区避让区，**物理像素**，窗口相对坐标，随旋转/窗口形态变化；
  /// 四边为 max(TYPE_SYSTEM, TYPE_CUTOUT)。由原生 getSafeArea /
  /// onSafeAreaChange 上报，在 main.dart 根 MediaQuery 里并入
  /// padding/viewPadding，供 ViewSafeArea/SafeArea 直接使用。
  ///
  /// 独立上报的原因：embedding 算 viewPadding 只读 TYPE_SYSTEM，不读挖孔，
  /// 横屏时 left/right 恒为 0、竖屏隐藏状态栏后 top 归 0。自由窗口的三键带
  /// 也含在 TYPE_SYSTEM 内，一并覆盖。
  static final ValueNotifier<EdgeInsets> safeAreaInsets = ValueNotifier(
    EdgeInsets.zero,
  );

  static void _updateSafeArea(dynamic args) {
    if (args is! Map) return;
    double side(String key) => (args[key] as num?)?.toDouble() ?? 0;
    final insets = EdgeInsets.fromLTRB(
      side('left'),
      side('top'),
      side('right'),
      side('bottom'),
    );
    if (insets != safeAreaInsets.value) {
      safeAreaInsets.value = insets;
    }
  }

  /// 根视图的顶部避让（逻辑像素，已按 uiScale 换算），等价于根 MediaQuery 的
  /// viewPadding.top。
  ///
  /// 给 Scaffold body 内部用：Scaffold 有 appBar 时对 body 做 removePadding，
  /// 会把 viewPadding.top 连同 padding.top 一起减掉，body 里读 MediaQuery
  /// 顶部恒为 0，只能回到 View 取原始值，再合并原生上报的部分。
  static double rootTopInset(BuildContext context) {
    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    final top = mergeSafeArea(
      EdgeInsets.only(top: view.viewPadding.top / dpr),
      dpr,
    ).top;
    return top / ScaledWidgetsFlutterBinding.instance.scaleFactor;
  }

  /// 把 [safeAreaInsets]（物理像素）换算为逻辑像素后与 [padding] 按边取 max。
  /// [devicePixelRatio] 须是引擎上报的原始 DPR（uiScale 缩放前）。
  static EdgeInsets mergeSafeArea(EdgeInsets padding, double devicePixelRatio) {
    final area = safeAreaInsets.value;
    if (area == EdgeInsets.zero) return padding;
    final a = area / devicePixelRatio;
    return EdgeInsets.fromLTRB(
      max(padding.left, a.left),
      max(padding.top, a.top),
      max(padding.right, a.right),
      max(padding.bottom, a.bottom),
    );
  }

  /// 已下发给原生的装饰栏策略：true = 隐藏（自由多窗沉浸），
  /// false = 显示，null = 尚未下发。
  static bool? _decorHidden;

  /// 自由多窗（平板全景多窗 / 2in1）下隐藏系统装饰栏，让窗口顶部随内容沉浸。
  ///
  /// 系统装饰栏是一条带应用图标 + 标题的独立色条，与 colorScheme.surface 对不
  /// 上色，只能整条隐藏（只改按钮颜色不够）。走原生 [setWindowDecorVisible]，
  /// 不用 embedding 的 shouldHideWindowDecor 间接路径，原因见该方法注释。
  ///
  /// 自由窗口内没有状态栏，故隐藏装饰栏不会误伤。代价：没有标题栏后不能再拖
  /// 标题栏移动窗口（边缘缩放、三键不受影响）。
  ///
  /// 自由窗口形态下装饰栏显隐由原生 WindowChrome 独占（系统装饰栏被隐藏、改
  /// 由 ArkTS 自绘标题带），Dart 侧不得下发，否则会把自绘标题带顶掉。这里只
  /// 处理平板系统小窗等非自由窗口。
  static void _syncWindowDecor() {
    if (!OS.isHarmony) return;
    if (_freeWindowMode) {
      _decorHidden = null;
      return;
    }
    final hide = _miniWindow;
    if (_decorHidden == hide) return;
    _decorHidden = hide;
    setWindowDecorVisible(visible: !hide);
  }
}
