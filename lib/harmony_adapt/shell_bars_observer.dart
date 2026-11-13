import 'package:PiliPlus/common/widgets/image_viewer/hero_dialog_route.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/harmony_adapt/orientation/orientation_policy.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:material_ui/material_ui.dart';

/// 监听全局路由变化，自动控制 ArkTS HDS 底栏的显隐。
/// 路由栈深度 > 1 时（有页面覆盖在主页之上）隐藏底栏，回到栈底时恢复。
class ShellBarsObserver extends NavigatorObserver {
  final Set<Route<dynamic>> _activeRoutes = {};
  bool _orientationHidden = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _activeRoutes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _activeRoutes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _activeRoutes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _activeRoutes.remove(oldRoute);
    if (newRoute != null) _activeRoutes.add(newRoute);
    _sync();
  }

  /// 由 MainApp.didChangeDependencies 调用：非竖屏底栏布局（横屏侧栏）时隐藏底栏。
  /// 子页面覆盖期间也照常记录，避免返回主页后用的是过期方向。
  void onOrientationChanged(bool useBottomNav) {
    _orientationHidden = !useBottomNav;
    _sync();
  }

  void _sync() {
    // 底栏隐藏条件：页面覆盖（无弹层）或弹层覆盖（PopupRoute 计入）或横屏。
    // 底栏 + 顶栏宽高比分流共用此信号：dialog/bottomSheet/popupmenu 弹出时
    // 也触发，顶栏按「首页 + 宽高比」由 ArkTS syncTopBarVisibility 收起/隐藏。
    final hasOverlay = _activeRoutes.length > 1 || _orientationHidden;
    HarmonyChannel.setShellBarsHidden(hasOverlay, force:true);
    // 顶栏「强制隐藏」仅针对页面覆盖（PageRoute：如视频页/设置页）与横屏；
    // 弹层（PopupRoute：dialog/bottomSheet/popupmenu）不计入，避免顶栏被
    // 直接隐藏而绕过宽高比分流。
    final hasPageOverlay = _activeRoutes.whereType<PageRoute>().length > 1;
    HarmonyChannel.setTopBarHidden(hasPageOverlay || _orientationHidden);
    // 系统状态栏跟随「最上层页面是否仍是沉浸播放页」，与原生顶栏同频：
    // - 最上层是视频/直播播放页（/videoV、/liveRoom）：保持沉浸，不干预
    // - 最上层是普通整页（含播放页 → UP 主主页 → 再进播放页 → 返回等嵌套
    //   场景）：立即恢复状态栏，避免新页面继承播放页的沉浸状态
    // - 图片查看器（HeroDialogRoute）自带状态栏逻辑，跳过
    final pageRoutes = _activeRoutes.whereType<PageRoute>().toList();
    final topPage = pageRoutes.isEmpty ? null : pageRoutes.last;
    final topIsPlayer = topPage != null &&
        (topPage.settings.name == '/videoV' ||
            topPage.settings.name == '/liveRoom');
    // 方向策略的「页面类型」输入：播放页跟随系统/全屏横屏，其余页面在细长
    // 竖屏形态下锁竖屏（见 OrientationPolicy）。
    OrientationPolicy.setPlayerPage(topIsPlayer);
    // 这里不能带上 _orientationHidden：它表示「横屏（侧栏布局）下原生 HDS 栏不
    // 显示」，与系统状态栏无关。带上它会让横屏退出播放页时本处不恢复状态栏，
    // 最终由 PlPlayerController.dispose() 里 removeSafeArea 的兜底恢复——那是
    // 异步 dispose，落在退场动画之后，表现为状态栏「突然跳出」。竖屏走本处，
    // 在 didPop 时同步恢复，所以只有横屏能看到这个跳变。
    if ((topPage == null || !topIsPlayer) && topPage is! HeroDialogRoute) {
      showSystemBar();
    }
  }
}
