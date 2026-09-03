import 'dart:math';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 原生顶栏启用时，首页各 Tab 列表顶部注入的可滚动留白。
///
/// 以 Sliver 形式放在 CustomScrollView 顶部：初始时留出空白不与 ArkTS 顶栏
/// 重叠；用户上滑时空白随列表一起卷走，内容自然滑入 ArkTS 顶栏下方形成
/// 沉浸重合，而非固定遮罩。
///
/// 高度随顶栏显隐联动，并按分类标签数量区分
/// 收起信号来自 HomeController.topBarCollapsed（由滚动偏移同步），
/// 与 ArkTS 顶栏的收起状态保持同时变化。
class NativeTopSpacer extends StatelessWidget {
  const NativeTopSpacer({super.key});

  /// 多个分类标签时：顶栏展开/收起对应的留白高度
  static const double expandedHeight = 137;
  static const double collapsedHeight = 82;

  /// 仅一个分类标签时：顶栏展开/收起对应的留白高度。
  static const double singleExpandedHeight = 107;
  static const double singleCollapsedHeight = 52;

  /// ArkTS 顶栏自身的高度，含状态栏，用于启用原生顶栏时调整刷新指示器高度
  static const double barExpandedHeight = 172;
  static const double barCollapsedHeight = 107;

  /// 留白高度的过渡节奏，须与 Index.ets 的 TOP_BAR_MOTION_DURATION /
  /// TOP_BAR_MOTION_CURVE 一一对应：两侧不同步时，列表内容与 ArkTS 顶栏
  /// 会以两种节奏收缩，重合处出现相对滑动。
  static const Duration _motionDuration = Duration(milliseconds: 300);
  static const Cubic _motionCurve = Cubic(0.2, 0, 0, 1);

  /// 原生顶栏当前是否真正生效（响应式读取，供 Obx 依赖）。
  /// 仅鸿蒙的 _initHdsBar 会置位 nativeTopBarActive，无需再判平台；
  /// 横屏/侧栏布局下 ArkTS 顶栏已被隐藏，此处同样返回 false。
  static bool get _active =>
      Get.find<MainController>().nativeTopBarActive.value;

  static HomeController? get _homeController {
    try {
      return Get.find<HomeController>();
    } catch (_) {
      return null;
    }
  }

  /// 顶栏是否处于收起态（收起时 ArkTS 顶栏只剩小搜索按钮）
  static bool get _collapsed => _homeController?.topBarCollapsed.value ?? false;

  /// 首页其他非滚动容器（如分区左侧标签栏）的静态留白高度。
  /// 禁用原生顶栏时返回 0。
  /// 按分类标签数量区分：
  /// - 仅一个分类：展开 55vp / 收起 0vp
  /// - 多个分类：展开 85vp / 收起 30vp
  static double staticHeight(BuildContext context) {
    if (!_active) return 0;
    final collapsed = _collapsed;
    final single = (_homeController?.tabs.length ?? 0) <= 1;
    if (single) {
      return collapsed ? singleCollapsedHeight : singleExpandedHeight;
    }
    return collapsed ? collapsedHeight : expandedHeight;
  }

  /// 下拉刷新指示器的顶部偏移（RefreshIndicator.edgeOffset）。
  ///
  /// 列表本身是全屏沉浸的，转圈默认贴着列表顶边（= 状态栏下沿）出现，
  /// 会被 ArkTS 顶栏整个盖住。此处把它下移到顶栏底边，转圈仍按
  /// displacement 落在「可视顶边下方」，与非沉浸页面观感一致。
  ///
  /// 主内容区顶部已由 Scaffold 的 AppBar(toolbarHeight: 0) 吃掉状态栏高度，
  /// 故只需避让顶栏在状态栏以下的部分。Scaffold body 内 MediaQuery 的
  /// padding/viewPadding 顶部均已被移除，这里直接从 View 读物理值换算。
  static double refreshEdgeOffset(BuildContext context) {
    if (!_active) return 0;
    final barHeight = _collapsed ? barCollapsedHeight : barExpandedHeight;
    final view = View.of(context);
    final statusBarHeight = view.viewPadding.top / view.devicePixelRatio;
    return max(0.0, barHeight - statusBarHeight);
  }

  @override
  Widget build(BuildContext context) {
    // 各 Tab 页处于 keepAlive 状态，不随 HomePage 重建，需用 Obx
    // 确保 useNativeTopBar 异步就绪/顶栏收起状态变化后高度自动更新。
    return SliverToBoxAdapter(
      child: Obx(
        () => AnimatedContainer(
          duration: _motionDuration,
          curve: _motionCurve,
          height: staticHeight(context),
        ),
      ),
    );
  }
}

/// 首页各 Tab 列表的下拉刷新包装：原生顶栏启用时把转圈下移到顶栏下方，
/// 避免刷新指示器被 ArkTS 顶栏遮挡；未启用（含横屏/侧栏布局）时
/// edgeOffset 为 0，与普通 refreshIndicator 完全一致。
///
/// 用 Obx 包裹以跟随 nativeTopBarActive 异步就绪 / topBarCollapsed 变化；
/// child 由外层 build 构造并被闭包捕获，Obx 重建时是同一个 widget 实例，
/// 列表子树不会跟着重建。
class NativeTopRefreshIndicator extends StatelessWidget {
  const NativeTopRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => refreshIndicator(
        edgeOffset: NativeTopSpacer.refreshEdgeOffset(context),
        onRefresh: onRefresh,
        child: child,
      ),
    );
  }
}
