import 'dart:math';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/home/widgets/home_top_bar.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 原生顶栏启用时，首页各 Tab 列表顶部注入的可滚动留白。
///
/// 以 Sliver 形式放在 CustomScrollView 顶部：初始时留出空白不与原生顶栏
/// （ArkTS 的搜索行 + Flutter 悬浮的分类栏，见 HomeTopBar）重叠；用户上滑时
/// 空白随列表一起卷走，内容自然滑入顶栏下方形成沉浸重合，而非固定遮罩。
///
/// 高度随顶栏显隐联动，并按分类标签数量区分：
/// - 多个分类：让出搜索行 + 分类栏（HomeTopBar.height）
/// - 仅一个分类：没有分类栏，只让出搜索行（HomeTopBar.contentHeight）
/// 滑动隐藏开启且已收起时，只剩分类栏那一格（ArkTS 的搜索行让出去），
/// 顶部留白随之缩短，视频更早顶到分类栏下方。
class NativeTopSpacer extends StatelessWidget {
  const NativeTopSpacer({super.key});

  /// 多个分类标签时：顶栏展开对应的留白高度
  static const double expandedHeight = HomeTopBar.height;

  /// 仅一个分类标签时：顶栏展开对应的留白高度
  static const double singleExpandedHeight = HomeTopBar.contentHeight;

  /// 多个分类标签时：搜索行收起后只剩分类栏
  static const double collapsedHeight = HomeTopBar.tabsHeight;

  /// 仅一个分类标签时没有分类栏，收起后顶部不留白
  static const double singleCollapsedHeight = 0;

  /// ArkTS 顶栏自身的高度，用于启用原生顶栏时调整刷新指示器高度
  static const double barExpandedHeight = HomeTopBar.height;
  static const double barCollapsedHeight = HomeTopBar.tabsHeight;

  /// 留白高度的过渡节奏，与 Index.ets 的 TOP_BAR_MOTION_DURATION /
  /// TOP_BAR_MOTION_CURVE、以及 HomeTopBar 的收起动画同源：三处不同步时，
  /// 列表内容与悬浮层会以几种节奏收缩，重合处出现相对滑动。
  static const Duration _motionDuration = HomeTopBar.motionDuration;
  static const Cubic _motionCurve = HomeTopBar.motionCurve;

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

  /// 顶栏是否已因滑动隐藏；隐藏后 ArkTS 的搜索行让出去，分类栏还在。
  static bool get _collapsed => _homeController?.topBarCollapsed.value ?? false;

  /// 首页其他非滚动容器（如分区左侧标签栏）的静态留白高度。
  /// 禁用原生顶栏时返回 0。
  /// 按分类标签数量区分：
  /// - 仅一个分类：只有 ArkTS 搜索行（收起后为 0）
  /// - 多个分类：搜索行 + 分类栏（收起后只剩分类栏）
  static double staticHeight(BuildContext context) {
    if (!_active) return 0;
    final single = (_homeController?.tabs.length ?? 0) <= 1;
    final topHeight = _collapsed
        ? (single ? singleCollapsedHeight : collapsedHeight)
        : (single ? singleExpandedHeight : expandedHeight);
    final statusBarHeight = HarmonyChannel.rootTopInset(context);
    // 需要加上状态栏高度
    return max(0.0, topHeight + statusBarHeight);
  }

  /// 下拉刷新指示器的顶部偏移（RefreshIndicator.edgeOffset）。
  ///
  /// 列表本身是全屏沉浸的，转圈默认贴着列表顶边（= 状态栏下沿）出现，
  /// 会被悬浮的分类栏整个盖住。此处把它下移到悬浮层底边，转圈仍按
  /// displacement 落在「可视顶边下方」，与非沉浸页面观感一致。
  static double refreshEdgeOffset(BuildContext context) {
    if (!_active) return 0;
    final barHeight = _collapsed ? barCollapsedHeight : barExpandedHeight;
    final statusBarHeight = HarmonyChannel.rootTopInset(context);
    // 需要加上状态栏高度
    return max(0.0, barHeight + statusBarHeight);
  }

  @override
  Widget build(BuildContext context) {
    // 各 Tab 页处于 keepAlive 状态，不随 HomePage 重建，需用 Obx
    // 确保 nativeTopBarActive 异步就绪 / 滑动隐藏状态变化后高度自动更新。
    //
    // 高度用与 HomeTopBar、ArkTS 顶栏同一套时长与曲线做补间：留白一变列表内容
    // 就会被推移同样的距离，三者同步才不会在重合处露出相对滑动。
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
