import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// 监听状态栏点击事件，实现点击状态栏返回顶部功能。
///
/// 通过 Get.currentRoute 检查避免后台页面误触发，
/// 模拟 Scaffold 的 _HitTestableAtOrigin 机制。
class StatusBarTapObserver with WidgetsBindingObserver {
  StatusBarTapObserver({
    required this.scrollController,
    required this.animateToTop,
  });

  final ScrollController scrollController;
  final VoidCallback animateToTop;

  /// 当前页面的路由名，用于判断是否在前台。
  String? routeName;

  StatusBarTapObserver register() {
    WidgetsBinding.instance.addObserver(this);
    return this;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void handleStatusBarTap() {
    if (routeName == null) return;
    if (Get.currentRoute != routeName) return;
    if (scrollController.hasClients) {
      animateToTop();
    }
  }
}
