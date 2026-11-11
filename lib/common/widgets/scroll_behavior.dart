import 'dart:io' show Platform;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:os_type/os_type.dart';

const Set<PointerDeviceKind> desktopDragDevices = {
  .touch,
  .mouse,
  .trackpad,
  .stylus,
  .invertedStylus,
  .unknown,
};

class CustomScrollBehavior extends MaterialScrollBehavior {
  const CustomScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (Platform.isAndroid) {
      return StretchingOverscrollIndicator(
        axisDirection: details.direction,
        clipBehavior: details.decorationClipBehavior ?? .hardEdge,
        child: child,
      );
    }
    return child;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => desktopDragDevices;
}

class NoOverscrollIndicator extends CustomScrollBehavior {
  const NoOverscrollIndicator();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// 鸿蒙上列表的手感对齐 ArkUI 原生列表。
///
/// 惯性曲线、越界拖动、边缘回弹全部由 [ArkuiScrollPhysics] 提供
/// （指数摩擦 + 抬手速度 ×1.5 + EdgeEffect.Spring，见
/// `packages/material_ui/lib/src/arkui_scroll_physics.dart` 顶部注释），
/// 不再使用 iOS 的 BouncingScrollPhysics：没有橡皮筋阻尼，
/// 回弹是 ArkUI 那套接近临界阻尼的弹簧。
/// 过滚动指示沿用 [CustomScrollBehavior]：ohos 上非 Platform.isAndroid，
/// 走 return child，无拉伸/发光（ArkUI 的 Spring 也没有这些视觉）。
class HarmonyScrollBehavior extends CustomScrollBehavior {
  const HarmonyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (OS.isHarmony) {
      return const ArkuiScrollPhysics(
        parent: RangeMaintainingScrollPhysics(),
      );
    }
    return super.getScrollPhysics(context);
  }
}
