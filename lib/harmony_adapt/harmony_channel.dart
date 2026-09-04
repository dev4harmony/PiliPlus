import 'dart:math' show max;

import 'package:PiliPlus/common/widgets/scale_app.dart';
import 'package:PiliPlus/harmony_adapt/continuation.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:os_type/os_type.dart';

abstract class HarmonyChannel {
  static double? _systemFontWeightScale;

  static double? get systemFontWeightScale => _systemFontWeightScale;

  static final MethodChannel _channel = const MethodChannel('harmonyChannel')
    ..setMethodCallHandler(handler);

  static Future<dynamic> handler(MethodCall call) async {
    switch (call.method) {
      case 'onFloatingWindowChange':
        onLandscapeOrMiniWindowChange(null, call.arguments['isFloatingWindow']);
        break;
      case 'onWindowModeChange':
        _windowMode = call.arguments['isWindowMode'] as bool? ?? false;
        break;
      case 'onCutoutAvoidAreaChange':
        _updateCutout(call.arguments);
        break;
      case 'onFontWeightScaleChange':
        final fontWeightScale = (call.arguments['fontWeightScale'] as num?)?.toDouble();
        _systemFontWeightScale = fontWeightScale;
        if (Pref.appFontWeight == -1) {
          Get.updateMyAppTheme();
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
    bool hidden, 
    {bool retry = false, bool force = false,}
  ) async {
    if (!OS.isHarmony) return;
    _hiddenByPage = hidden;
    final int total = retry ? 8 : 1;
    for (int i = 0; i < total; i++) {
      try {
        _channel.invokeMethod('setShellBarsHidden', {'hidden': hidden,'force': force});
        return;
      } catch (_) {
        if (i == total - 1) return;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  /// 同步主题色到 ArkTS HdsTabs 底栏
  static Future<void> setTabSelectedColor(String hexColor) =>
      _invoke('setTabSelectedColor', {'color': hexColor});

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
      await _channel.invokeMethod(
          'setWindowOrientation', {'orientation': orientation});
    } catch (_) {}
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

  /// 获取系统当前字重设置（仅 Harmony 平台）
  static Future<void> initSystemFontWeight() =>
      _invoke('getSystemFontWeightScale');

  /// 将应用内设定的主题颜色传递给原生层，用于原生层的深浅色模式感知
  static Future<void> setSystemColorMode(String colorMode) =>
      _invoke('setSystemColorMode', {'colorMode': colorMode});

  /// 横屏小窗的缩放比例固定值
  static const _miniWindowLandscapeScale = 0.75;
  static bool _landscape = false;
  static bool _miniWindow = false;

  /// 当前是否处于系统自由小窗（悬浮窗/全景多窗）。小窗内窗口宽高比不代表
  /// 设备方向，基于方向的自动全屏等逻辑应据此跳过。
  static bool get isMiniWindow => _miniWindow;

  /// 是否处于「横屏小窗」：系统小窗内把横屏视频切到了全屏，此时调用过原生
  /// enableLandscapeMultiWindow。实测仅此状态下进画中画会黑屏（小窗内不全屏
  /// 进画中画画面正常），故用它而不是 [isMiniWindow] 作为拦截条件。
  static bool get isMiniWindowLandscape => _miniWindow && _landscape;

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
    if (miniWindowChanged) _syncWindowDecor();
    if (_miniWindow && _landscape) {
      _setMiniWindowLandscape(true);
      ScaledWidgetsFlutterBinding.instance.scaleFactor =
          _miniWindowLandscapeScale;
    } else {
      ScaledWidgetsFlutterBinding.instance.scaleFactor = Pref.uiScale;
      _setMiniWindowLandscape(false);
    }
  }

  static void _setMiniWindowLandscape(bool landscape) {
    _channel.invokeMethod('setMiniWindowLandscape', {'landscape': landscape});
  }

  /// 启动时（runApp 之前）拉取窗口初始状态（是否自由多窗 / 受限窗口模式），
  /// 并据此一次性下发系统栏模式（代替 main.dart 里的 edgeToEdge）。
  ///
  /// 原生只在 windowStatusChange 时推送 onFloatingWindowChange，应用直接在
  /// 自由多窗里启动时收不到；且 Dart 侧 handler 注册前的通道消息最多缓存
  /// 一条，靠原生「补发」不可靠，这里改为主动拉取。放在首帧之前、且不先发
  /// edgeToEdge，是为了避免装饰栏「先出现再收回」的闪动；原生侧
  /// EntryAbility 在窗口创建时已先隐藏一次，这里只是让 embedding 的状态与之
  /// 一致（并把 viewPadding.top 钉成三键高度）。
  static Future<void> initWindowState() async {
    if (!OS.isHarmony) return;
    try {
      final state = await _channel.invokeMethod<Map>('getWindowState');
      if (state != null) {
        _windowMode = state['isWindowMode'] as bool? ?? _windowMode;
        await onLandscapeOrMiniWindowChange(
          null,
          state['isFloatingWindow'] as bool?,
        );
      }
    } catch (_) {}
    try {
      _updateCutout(await _channel.invokeMethod<Map>('getCutoutAvoidArea'));
    } catch (_) {}
    _syncWindowDecor();
  }

  /// 摄像头挖孔（TYPE_CUTOUT）避让区，**物理像素**，窗口相对坐标，随旋转
  /// 变化；由原生 getCutoutAvoidArea / onCutoutAvoidAreaChange 维护。
  ///
  /// 鸿蒙 embedding 算 viewPadding 只读 TYPE_SYSTEM（状态栏/导航栏），不读
  /// 挖孔：横屏时 viewPadding.left/right 恒为 0、竖屏隐藏状态栏后
  /// viewPadding.top 归 0，ViewSafeArea/SafeArea 都避不开挖孔。Android
  /// embedding 会把 cutout 并进 viewPadding，上上游代码按该语义写，故在
  /// main.dart 的根 MediaQuery 里把这里的值按边取 max 合并进
  /// padding/viewPadding，让下游无需感知平台差异。
  ///
  /// 仅手机上报：平板/2in1 的摄像头在边框上，避让只会平白让出一条空带，
  /// 原生侧直接不报（见 ETS HarmonyChannel.cutoutEnabled），此处恒为 zero。
  static final ValueNotifier<EdgeInsets> cutoutInsets = ValueNotifier(
    EdgeInsets.zero,
  );

  static void _updateCutout(dynamic args) {
    if (args is! Map) return;
    double side(String key) => (args[key] as num?)?.toDouble() ?? 0;
    final insets = EdgeInsets.fromLTRB(
      side('left'),
      side('top'),
      side('right'),
      side('bottom'),
    );
    if (insets != cutoutInsets.value) {
      cutoutInsets.value = insets;
    }
  }

  /// 把 [cutoutInsets]（物理像素）换算为逻辑像素后与 [padding] 按边取 max。
  /// [devicePixelRatio] 须是引擎上报的原始 DPR（uiScale 缩放前）。
  static EdgeInsets mergeCutout(EdgeInsets padding, double devicePixelRatio) {
    final cutout = cutoutInsets.value;
    if (cutout == EdgeInsets.zero) return padding;
    final c = cutout / devicePixelRatio;
    return EdgeInsets.fromLTRB(
      max(padding.left, c.left),
      max(padding.top, c.top),
      max(padding.right, c.right),
      max(padding.bottom, c.bottom),
    );
  }

  /// 已下发给 embedding 的装饰栏策略：true = 隐藏（自由多窗沉浸），
  /// false = 显示，null = 尚未下发。
  static bool? _decorHidden;

  /// 自由多窗（平板全景多窗 / 2in1）下隐藏系统装饰栏，让窗口顶部随内容沉浸。
  ///
  /// 系统装饰栏是一条带应用图标 + 标题的独立色条（浅/深色各一套灰），与
  /// colorScheme.surface 永远对不上色；只调 setDecorButtonStyle 改按钮颜色
  /// 是不够的，栏本身得隐藏。
  ///
  /// 不能直接调 window.setWindowDecorVisible(false)：鸿蒙 embedding 的
  /// PlatformPlugin.updateSystemUiOverlays 在每次 SystemChrome 设置系统栏、
  /// 以及 app 回前台 restoreSystemUiOverlays 时，都会按自己的
  /// showBarOrNavigation 重写装饰栏可见性——edgeToEdge（['status',
  /// 'navigation']）→ 显示装饰栏并把 paddingTop 钉 0，直接调的隐藏会被覆盖。
  /// embedding 约定的隐藏方式是只保留 'navigation'，即
  /// setEnabledSystemUIOverlays([SystemUiOverlay.bottom])：它会
  /// setWindowDecorVisible(false) 并把 viewPadding.top 钉成右上角三键区域
  /// 高度（getTitleButtonRect），SimpleScaffold 的状态栏占位、首页零高
  /// AppBar、视频页顶部黑条都据此避让，内容不会压到按钮下面。三键仍由系统
  /// 悬浮绘制，颜色跟随应用颜色模式，视频/直播页顶部为黑时由
  /// [setDecorDark] 切浅色。
  ///
  /// 自由窗口内没有状态栏，去掉 'status' 无副作用；回到全屏窗口时必须恢复
  /// edgeToEdge，否则状态栏会被隐藏。代价：没有标题栏后不能再拖标题栏移动
  /// 窗口（边缘缩放、三键不受影响）。
  static void _syncWindowDecor() {
    if (!OS.isHarmony) return;
    final hide = _miniWindow;
    if (_decorHidden == hide) return;
    _decorHidden = hide;
    if (hide) {
      // SystemChrome.setEnabledSystemUIOverlays 在 Dart 侧已被移除，但鸿蒙
      // embedding 的 PlatformChannel 仍处理这条消息，参数为
      // SystemUiOverlay 的枚举名列表。
      SystemChannels.platform.invokeMethod<void>(
        'SystemChrome.setEnabledSystemUIOverlays',
        const ['SystemUiOverlay.bottom'],
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  /// 自由多窗装饰栏按钮（全屏/最小化/关闭）的颜色跟随「按钮下方那条顶栏
  /// 的实际底色」而非系统颜色模式：浅色模式下深色按钮叠在播放页黑色顶部上
  /// 视觉不可见。顶部为深色内容的页面（视频/直播播放页）在可见期间持有此
  /// 状态，使按钮切为浅色风格；无人持有时恢复跟随系统。用持有者集合而非
  /// 开关，规避路由切换（如视频页跳视频页）中生命周期回调顺序的不确定性。
  ///
  /// 注意「播放页 == 顶部是黑的」并不恒成立：视频页竖屏滚动时顶栏会由黑
  /// 渐变到 colorScheme.surface（浅色模式下即白色），此时必须放开持有让
  /// 按钮变回深色，否则白底浅按钮不可辨认。故持有方应随顶栏底色变化调用
  /// [setDecorDark] 更新，而不是进页面时一次性持有到底。
  static final Set<Object> _darkDecorOwners = <Object>{};

  /// 按 [dark] 更新 [owner] 的持有状态：顶栏底色为深色时持有（按钮浅色），
  /// 变浅时释放（按钮跟随系统颜色模式）。重复调用同一状态是无害空操作。
  static void setDecorDark(Object owner, bool dark) {
    if (dark) {
      holdDecorDark(owner);
    } else {
      releaseDecorDark(owner);
    }
  }

  static void holdDecorDark(Object owner) {
    if (!OS.isHarmony) return;
    final wasEmpty = _darkDecorOwners.isEmpty;
    _darkDecorOwners.add(owner);
    if (wasEmpty) {
      _setDecorButtonDark(true);
    }
  }

  static void releaseDecorDark(Object owner) {
    if (!OS.isHarmony) return;
    if (_darkDecorOwners.remove(owner) && _darkDecorOwners.isEmpty) {
      _setDecorButtonDark(false);
    }
  }

  static void _setDecorButtonDark(bool dark) {
    _channel.invokeMethod('setDecorButtonDark', {'dark': dark});
  }
}
