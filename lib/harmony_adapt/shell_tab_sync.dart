import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:get/get.dart';

/// ArkTS HDS 底栏「隐藏 → 显示」的那一刻，把 Flutter 侧页签幂等地对齐回原生
/// 当前页签（首页 / 动态 / 我的）。
///
/// 底栏在子页面 / 弹层 / 横屏期间被隐藏（ArkTS 侧 `.visibility(None)`），重新
/// 显示时原生 HdsTabs 与 Flutter 当前页签可能已经不一致；同时那条「显示底栏」
/// 的链路也不能变成一次内容重载。所以这里先比对：**一致即彻底 no-op**——不刷新
/// 列表、不回顶部、不震动；只有真的不一致时，才借用原生底栏点击的那条切页链路
/// 静默切过去。
///
/// 为什么不直接把 `showTab`（[MainController.setIndex]）当幂等操作用：那条链路
/// 以「用户点了底栏」为前提，页签**相同**时会走 toTopOrRefresh / onRefresh，正
/// 好就是底栏重新显示时要避免的界面刷新。故必须先在外面判等，绝不进那个分支。
abstract class ShellTabSync {
  /// 底栏页签类型（[NavigationBarType] 序号）→ 当前配置下的位置序号。
  static const _types = NavigationBarType.values;

  /// [typeIndex] 为原生底栏当前页签的 [NavigationBarType] 序号（不是位置序号：
  /// 设置里改过 Navbar 排序后二者不同，拿位置去比会切错页）；
  /// [dispatch] 为原生底栏点击的切页入口（[MainController.setIndex] 的包装），
  /// 借它切换可以跳过回传 ArkTS，避免自己转一圈又回头。
  static void align(int typeIndex, {void Function(int index)? dispatch}) {
    if (typeIndex < 0 || typeIndex >= _types.length || dispatch == null) {
      return;
    }
    // 冷启动早期 / 主页已关闭时没有 MainController，直接忽略
    if (!Get.isRegistered<MainController>()) return;
    final mainController = Get.find<MainController>();
    // 按「页签类型」而非位置对齐：该页签被用户从 Navbar 里删掉时 indexOf 为 -1
    final index = mainController.navigationBars.indexOf(_types[typeIndex]);
    if (index < 0) return;
    // 幂等：两侧已经一致，一个副作用都不要有
    if (mainController.selectedIndex.value == index) return;
    dispatch(index);
  }
}
