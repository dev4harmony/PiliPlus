import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/gestures.dart' show HorizontalDragGestureRecognizer;
import 'package:material_ui/material_ui.dart';
import 'package:os_type/os_type.dart';

Widget tabBarView({
  required List<Widget> children,
  TabController? controller,
  HitTestBehavior hitTestBehavior = .opaque,
}) => RawGestureDetector(
  behavior: hitTestBehavior,
  // CustomHorizontalDragGestureRecognizer 把 runtimeType 覆盖成了
  // HorizontalDragGestureRecognizer（上游为了顶替 Scrollable 内置识别器），
  // RawGestureDetector 在 debug 下断言「实例 runtimeType == map 的 key」，
  // 因此这里必须以 HorizontalDragGestureRecognizer 为 key，否则 debug 包首页直接红屏
  gestures: {
    HorizontalDragGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          CustomHorizontalDragGestureRecognizer.new,
          (_) {},
        ),
  },
  child: TabBarView(
    controller: controller,
    physics: tabBarScrollPhysics,
    children: children,
  ),
);

SpringDescription kSpringDescription = _customSpringDescription();

SpringDescription _customSpringDescription() {
  final List<double> springDescription = Pref.springDescription;
  return SpringDescription(
    mass: springDescription[0],
    stiffness: springDescription[1],
    damping: springDescription[2],
  );
}

const tabBarScrollPhysics = _TabBarViewScrollPhysics();

class _TabBarViewScrollPhysics extends ClampingScrollPhysics {
  const _TabBarViewScrollPhysics({super.parent});

  @override
  _TabBarViewScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _TabBarViewScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => kSpringDescription;
}

mixin ReloadMixin {
  late bool reload = false;
}

class ReloadScrollPhysics extends AlwaysScrollableScrollPhysics {
  const ReloadScrollPhysics({super.parent, required this.controller});

  final ReloadMixin controller;

  @override
  ReloadScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ReloadScrollPhysics(
      parent: buildParent(ancestor),
      controller: controller,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (controller.reload) {
      controller.reload = false;
      return 0;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

// 鸿蒙的 [ArkuiScrollPhysics]（ArkUI fling 曲线 + EdgeEffect.Spring 的复刻，
// 参数与推导见该文件顶部注释）由 material_ui shim 提供：
// packages/material_ui/lib/src/arkui_scroll_physics.dart
final platformClampingPhysics = OS.isHarmony
    ? const ArkuiScrollPhysics(bounce: false, parent: ClampingScrollPhysics())
    : PlatformUtils.isDarwin
    ? const BouncingScrollPhysicsExt()
    : const ClampingScrollPhysics();

final platformAlwaysClampingPhysics = OS.isHarmony
    ? const AlwaysScrollableScrollPhysics(
        parent: ArkuiScrollPhysics(
          bounce: false,
          parent: ClampingScrollPhysics(),
        ),
      )
    : PlatformUtils.isDarwin
    ? const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysicsExt())
    : const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());

class BouncingScrollPhysicsExt extends BouncingScrollPhysics
    with ClampingBoundaryMixin {
  const BouncingScrollPhysicsExt({super.parent});

  @override
  BouncingScrollPhysicsExt applyTo(ScrollPhysics? ancestor) {
    return BouncingScrollPhysicsExt(parent: buildParent(ancestor));
  }
}

/// [ClampingScrollPhysics.applyBoundaryConditions]
mixin ClampingBoundaryMixin on ScrollPhysics {
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      // Underscroll.
      return value - position.pixels;
    }
    if (position.maxScrollExtent <= position.pixels &&
        position.pixels < value) {
      // Overscroll.
      return value - position.pixels;
    }
    if (value < position.minScrollExtent &&
        position.minScrollExtent < position.pixels) {
      // Hit top edge.
      return value - position.minScrollExtent;
    }
    if (position.pixels < position.maxScrollExtent &&
        position.maxScrollExtent < value) {
      // Hit bottom edge.
      return value - position.maxScrollExtent;
    }
    return 0.0;
  }
}
