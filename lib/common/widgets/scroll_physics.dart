import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/gestures.dart' show HorizontalDragGestureRecognizer;
import 'package:flutter/physics.dart' show FrictionSimulation;
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

// ---------------------------------------------------------------------------
// 鸿蒙 ArkUI 列表惯性滑动（fling）与边缘回弹（EdgeEffect.Spring）
//
// 参数与曲线取自 arkui_ace_engine：
//   scrollable.cpp        惯性摩擦、抬手速度整形、StartSpringMotion
//   scroll_spring_effect  越界后 StartSpringMotion(position, velocity, 边界)
//   scrollable_theme.h    scroll_able_spring_response = 0.417
// 行为：
//   · 抬手速度整形：v = 手势速度 × 1.5（慢速甩用 1.2），钳位 ±9000vp/s
//     ——增益折进衰减系数而非直接乘速度，见 [ArkuiFlingSimulation]（否则会滑不停）
//   · 滑行距离 = v / (4.2 × friction)，friction 默认 0.75
//   · 速度衰减 v(t) = v₀·e^(-4.2f·t)
//   · 衰减到 120 物理 px/s（÷dpr，约 37 逻辑像素/s）停止；低于此速度不产生惯性
//   · 慢速甩动 friction = 1.0
//   · 撞到边界：摩擦立刻结束，位置停在边界，剩余速度交给弹簧
//   · 越界拖动：跟手 1:1（没有 iOS 的橡皮筋阻尼）
//   · 松手回弹：ResponsiveSpringMotion(0.417s, 0.99)，接近临界阻尼、干脆不振荡
// ArkUI 用 vp，Flutter 的逻辑像素与之等价，数值可直接搬过来。
// ---------------------------------------------------------------------------

/// ArkUI FRICTION_SCALE：滑行距离 = v / ([_arkuiFrictionScale] × friction)
const double _arkuiFrictionScale = 4.2;

/// 抬手速度放大系数（ArkUI flingVelocityScale，API11+）
const double _arkuiVelocityScale = 1.5;

/// 低于该速度视为"慢速甩动"，速度放大与摩擦系数都换另一套
const double _arkuiSlowVelocity = 3000;
const double _arkuiSlowVelocityScale = 1.2;
const double _arkuiSlowFriction = 1.0;

/// 默认摩擦系数（ArkUI API12+ / 主题 scroll_able_friction）
const double _arkuiFriction = 0.75;

/// 甩动速度上限 9000vp/s（ArkUI MAX_VELOCITY）
const double _arkuiMaxFlingVelocity = 9000;

/// ArkUI 的偏移量、手势速度内部都是**物理 px**，所以
/// FRICTION_VELOCITY_THRESHOLD = 120 也是物理 px/s；Flutter 的 velocity 是逻辑
/// 像素/s，必须 ÷ dpr 才是同一个量级（dpr=3.25 时约 37）。
/// 若直接当逻辑像素用，收尾速度是原生的 3.25 倍，最后一帧要跳 6~7 个物理像素
/// 才停住，观感就是"戛然而止"。
double get _devicePixelRatio =>
    PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;

/// 停止阈值（ArkUI FRICTION_VELOCITY_THRESHOLD = 120 物理 px/s）
double get _arkuiStopVelocity => 120 / _devicePixelRatio;

// 注：ArkUI 另有起甩阈值 START_FRICTION_VELOCITY_THRESHOLD = 240，但它比的是
// **整形后**的速度（×1.5 / ×1.2），换算过来约 50~60 逻辑像素/s，与 Flutter 自己
// 的 `minFlingVelocity = 50` 基本重合，因此不再单独判——而且这个判据会被
// `createBallisticSimulation` 在惯性动画被重建时反复执行，取大了会把尾部提前掐断。

/// ArkUI 边缘弹簧的 response（自然振荡周期，秒）与阻尼比
const double _arkuiSpringResponse = 0.417;
const double _arkuiSpringDampingRatio = 0.99;

/// ArkUI `ResponsiveSpringMotion(0.417, 0.99)` 换算成 Flutter 的
/// [SpringDescription]：ω = 2π / response，阻尼比 0.99（接近临界阻尼，
/// 回弹干脆、几乎不振荡，和 iOS 那种明显回弹不一样）。
final SpringDescription kArkuiSpringDescription =
    SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: math.pow(2 * math.pi / _arkuiSpringResponse, 2).toDouble(),
      ratio: _arkuiSpringDampingRatio,
    );

/// ArkUI 的收尾判据：速度衰减到 120 物理 px/s 或距终点不足 1px。
/// 注意 [FrictionSimulation.isDone] 只看 `tolerance.velocity`，`distance` 不参与，
/// 所以尾部长度完全由上面的 `_arkuiStopVelocity` 决定。
Tolerance get _arkuiTolerance =>
    Tolerance(velocity: _arkuiStopVelocity, distance: 1);

/// ArkUI 的惯性曲线：界内指数衰减的摩擦阶段 + 撞边后的弹簧回弹阶段。
///
/// 等价关系：ArkUI 的 `v(t) = scale·v₀·e^(-λt)`（λ = 4.2f）落到 Flutter 的
/// [FrictionSimulation] 时取 `drag = e^(-λ/scale)`、初速仍传 v₀：这样
/// `dx(0)` 恒等于传进来的速度，`x(∞) = x₀ + scale·v₀/λ` 也正好等于 ArkUI 的
/// 滑行距离（与"直接乘速度"完全等价，只是把增益折进了衰减系数）。
///
/// **必须保持 `dx(0) == 传入的 velocity`**：`BallisticScrollActivity` 在内容
/// 尺寸变化时会拿当前速度重新调一次 `createBallisticSimulation`
/// （`applyNewDimensions()` → `goBallistic(velocity)`）。若在那里对速度乘
/// ×1.5/×1.2，每重建一次就再放大一次，衰减追不上增益时速度会指数增长并顶到
/// ±9000 上限，表现就是"轻轻一划就一路滑到列表底部才停"。
class ArkuiFlingSimulation extends Simulation {
  ArkuiFlingSimulation({
    required double position,
    required double velocity,
    required this.leadingExtent,
    required this.trailingExtent,
    required double friction,
    required this.velocityScale,
    required this.bounce,
    super.tolerance,
  }) {
    _friction = FrictionSimulation(
      // drag 是"每过 1 秒剩余的速度比例"；ArkUI 的抬手速度增益 scale 折进
      // 衰减系数（λ' = λ/scale），保证初速不被二次放大
      math.exp(-_arkuiFrictionScale * friction / velocityScale),
      position,
      velocity,
      tolerance: tolerance,
    );
    if (!bounce) {
      return;
    }
    final finalX = _friction.finalX;
    if (velocity > 0 && finalX > trailingExtent) {
      _springTime = _friction.timeAtX(trailingExtent);
      _spring = _edgeSpring(trailingExtent, _friction.dx(_springTime));
    } else if (velocity < 0 && finalX < leadingExtent) {
      _springTime = _friction.timeAtX(leadingExtent);
      _spring = _edgeSpring(leadingExtent, _friction.dx(_springTime));
    }
  }

  final double leadingExtent;
  final double trailingExtent;

  /// 撞到边界后是否接着跑 ArkUI 的弹簧回弹（EdgeEffect.Spring）
  final bool bounce;

  /// ArkUI 的抬手速度增益（快速 1.5 / 慢速 1.2），已折进衰减系数
  final double velocityScale;

  late final FrictionSimulation _friction;
  Simulation? _spring;

  /// 摩擦阶段结束、弹簧阶段开始的时间；[double.infinity] 表示不会撞边
  double _springTime = double.infinity;
  double _timeOffset = 0;

  /// ArkUI 撞边时的处理：摩擦停在边界，位置仍是边界，速度原样交给弹簧
  Simulation _edgeSpring(double extent, double velocity) {
    return ScrollSpringSimulation(
      kArkuiSpringDescription,
      extent,
      extent,
      velocity,
      tolerance: tolerance,
    );
  }

  Simulation _simulation(double time) {
    final isSpring = time > _springTime;
    _timeOffset = isSpring && _springTime.isFinite ? _springTime : 0;
    return (isSpring ? _spring! : _friction)..tolerance = tolerance;
  }

  @override
  double x(double time) => _simulation(time).x(time - _timeOffset);

  @override
  double dx(double time) => _simulation(time).dx(time - _timeOffset);

  @override
  bool isDone(double time) => _simulation(time).isDone(time - _timeOffset);

  @override
  String toString() =>
      'ArkuiFlingSimulation(friction: ${_friction.toString()}, '
      'extent: $leadingExtent..$trailingExtent)';
}

/// 把惯性曲线和边缘回弹都换成鸿蒙 ArkUI 原生列表的表现。
///
/// · 界内甩动：ArkUI 的指数摩擦（见 [ArkuiFlingSimulation]）
/// · 越界拖动：跟手 1:1，没有 iOS 的橡皮筋阻尼
/// · 松手/撞边回弹：ArkUI 的 EdgeEffect.Spring（[kArkuiSpringDescription]）
///
/// 是否允许越界仍由 [parent] 决定：挂 `ClampingScrollPhysics` 就贴边不动，
/// 挂 `RangeMaintainingScrollPhysics` 则可以越界并由本类负责回弹。
/// `bounce: false` 时连内部弹簧阶段也去掉，纯撞边停住。
class ArkuiScrollPhysics extends ScrollPhysics {
  const ArkuiScrollPhysics({
    this.friction = _arkuiFriction,
    this.bounce = true,
    super.parent,
  });

  /// 摩擦系数，越大滑行越短；ArkUI 默认为 0.75
  final double friction;

  /// 是否保留 ArkUI 的边缘弹簧（EdgeEffect.Spring）
  final bool bounce;

  @override
  ArkuiScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ArkuiScrollPhysics(
      friction: friction,
      bounce: bounce,
      parent: buildParent(ancestor),
    );
  }

  @override
  double get maxFlingVelocity => _arkuiMaxFlingVelocity;

  /// 边缘弹簧用 ArkUI 的参数，而不是 Flutter 默认/iOS 的
  @override
  SpringDescription get spring => kArkuiSpringDescription;

  /// ArkUI 越界拖动不做阻尼：手指走多少，列表走多少
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return offset;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      // 拖出边界后松手：ArkUI 是"从边界带着剩余速度起弹簧"
      if (!bounce) {
        return parent?.createBallisticSimulation(position, velocity);
      }
      final target = position.pixels > position.maxScrollExtent
          ? position.maxScrollExtent
          : position.minScrollExtent;
      return ScrollSpringSimulation(
        kArkuiSpringDescription,
        position.pixels,
        target,
        velocity,
        tolerance: _arkuiTolerance,
      );
    }
    // 速度已低于停止阈值：不必再建模拟（也避免 goBallistic(0) 建出空动画）。
    // 这里不能取 ArkUI 的 240——`createBallisticSimulation` 会在惯性动画被重建时
    // 拿当前速度反复调用，取大了会让尾部在 240px/s 处就被 goIdle() 掐断。
    if (velocity.abs() < _arkuiStopVelocity) {
      return null;
    }
    final isSlow = velocity.abs() <= _arkuiSlowVelocity;
    final double velocityScale = isSlow
        ? _arkuiSlowVelocityScale
        : _arkuiVelocityScale;
    // 不要在这里乘 velocityScale：增益已经折进衰减系数（见 [ArkuiFlingSimulation]），
    // 否则每次 `applyNewDimensions` 重建模拟都会再放大一次、变成"滑不停"。
    // ArkUI 的 ±9000 上限作用在整形后的速度上，等价于原始速度钳到 ±9000/scale。
    final double limit = _arkuiMaxFlingVelocity / velocityScale;
    return ArkuiFlingSimulation(
      position: position.pixels,
      velocity: velocity.clamp(-limit, limit).toDouble(),
      leadingExtent: position.minScrollExtent,
      trailingExtent: position.maxScrollExtent,
      // 摩擦系数必须为正，否则 drag 会退化成 1（距离发散）
      friction: isSlow
          ? _arkuiSlowFriction
          : (friction > 0 ? friction : _arkuiFriction),
      velocityScale: velocityScale,
      bounce: bounce,
      tolerance: _arkuiTolerance,
    );
  }
}
