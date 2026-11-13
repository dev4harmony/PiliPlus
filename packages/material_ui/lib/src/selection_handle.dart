import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart' hide SelectionArea;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/src/ohos_selection_theme.dart';

/// 鸿蒙（`TargetPlatform.ohos`）下的文本选择手柄：**杆 + 球**造型。
///
/// ## 为什么要换掉 Material 的水滴
///
/// SDK 的 `MaterialTextSelectionControls.buildHandle`（`package:flutter/src/material/
/// text_selection.dart`）画的是 22x22 的水滴（`_TextSelectionHandlePainter` 在左上
/// 象限挖一个方块再旋转 45°/90°），是 Android 的观感。鸿蒙的手柄是「一根细杆 + 一端
/// 一个环」，尺寸见 [OhosSelectionTheme]（取自系统主题，不是代码里的缺省值）：
///
/// - 球：描边圆心直径 **14vp**、内芯 12vp、描边 **2vp**（描边跨在半径上，所以**视觉
///   外径 16vp**），**固定不随行高缩放**；
/// - 杆：宽 **2vp**（= 光标宽）、圆头、长度 = 文本行高，与行严格同高；
/// - 球与杆相切：起手柄的球贴在这一行的**上沿之外**，止手柄的球贴在**下沿之外**；
/// - 折叠光标：原生是「杆 + 球」，杆压在光标上、球挂在行下方
///   （`select_overlay_content_modifier.cpp:339-371` 的 `handleOnTop=false`）。
///   **这里只画球**：Flutter 的 `RenderEditable` 自己会画一根闪烁光标，再叠一根杆
///   会出现重影/粗细跳变（真机验证过），所以杆交给输入框、我们只补下方那颗球。
///
/// ## 与 SDK overlay 的配合（定位的关键，别改错）
///
/// `_SelectionHandleOverlayState.build`（SDK `widgets/text_selection.dart:2081`）把
/// 手柄放在 `CompositedTransformFollower(offset: -handleAnchor - padding.topLeft)`，
/// leader 是选区端点，也就是文本行的**下沿**（折叠光标则是光标下沿）。所以 widget 里
/// 任一点 `q` 的全局位置是 `选区端点 + (q - handleAnchor)`，
/// **`getHandleAnchor` 返回的点会落在行的下沿上**。
///
/// - 起（左）手柄：盒子比图形高出一截热区，球在上、杆在下，锚点取杆的下端，
///   于是杆正好压住这一行、球挂在行上方 [OhosHandleMetrics.hotZoneOutward] 处；
/// - 止（右）手柄：球在下、杆在上，锚点取杆的下端（= 行下沿）。**不再用
///   `Transform.rotate`**：几何本身已经上下对称，直接画更省事，也不会因为旋转
///   把锚点算错（早先版本右手柄就掉到文字下方过）；
/// - 折叠光标：盒子与止手柄同形（锚点 = 行下沿），但**只画下方那颗球**，
///   杆由输入框自己的光标负责（见上面「折叠光标」那条）。
///
/// ## 热区
///
/// 原生热区（`select_overlay_pattern.cpp:177-246` 的 `UpdateHandleHotZone`）是
/// 横向 `2 * hotZone` = 28vp、纵向在线高之外再**向外**扩 `2 * hotZone` = 28vp，
/// 也就是「往外多给、往正文少给」。这里把盒子直接做成 28 × (行高 + 28)，图形贴在
/// 靠正文那一侧；SDK 只会在盒子小于 48 时**以盒子中心对称**补足，图形位置不受影响。
///
/// ## 拖动手感
///
/// 原生拖手柄时每越过一个字符就轻震一下（`StartVibratorByIndexChange` →
/// `StartVibraFeedback("slide")`）。Flutter 里这条触发点在 SDK 的
/// `SelectionOverlay.selectionEndpoints` setter 里，且只对 android 生效；不改 SDK 的话
/// 就在手柄自己身上做：`Listener` 拿到 pointer down/move，走 [OhosSelectionHaptics]
/// 节流后触发。指针按下时命中结果已被缓存，后续 move/up 会一直送到同一个 Listener。
class OhosTextSelectionHandleControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  /// 创建控件。无状态，可直接用 [ohosTextSelectionHandleControls] 这个共享实例。
  OhosTextSelectionHandleControls();

  @override
  Size getHandleSize(double textLineHeight) {
    return OhosHandleMetrics.forLineHeight(textLineHeight).size;
  }

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textHeight, [
    VoidCallback? onTap,
  ]) {
    final ThemeData theme = Theme.of(context);
    final Color foreground =
        TextSelectionTheme.of(context).selectionHandleColor ??
        theme.colorScheme.primary;
    // 球心是挖空的，填充要用页面底色（原生是 `handle_inner_color`，
    // 亮色纯白 / 暗色 #E5E5E5，见 OhosSelectionTheme.handleInnerColor）。
    final Color background = theme.scaffoldBackgroundColor;
    final Size size = getHandleSize(textHeight);

    return SizedBox.fromSize(
      size: size,
      child: _HapticHandle(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.translucent,
          child: CustomPaint(
            size: size,
            painter: OhosSelectionHandlePainter(
              foreground: foreground,
              background: background,
              textLineHeight: textHeight,
              // 起手柄球在上，止手柄/折叠光标球在下。
              ballAbove: type == TextSelectionHandleType.left,
              // 输入框自己会画闪烁光标：折叠光标再画一根杆就和它叠在一起，
              // 真机上表现为「重影 / 宽度忽粗忽细」。只保留球。
              drawBar: type != TextSelectionHandleType.collapsed,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final OhosHandleMetrics metrics = OhosHandleMetrics.forLineHeight(
      textLineHeight,
    );
    return switch (type) {
      TextSelectionHandleType.left => metrics.leftAnchor,
      TextSelectionHandleType.right => metrics.rightAnchor,
      TextSelectionHandleType.collapsed => metrics.collapsedAnchor,
    };
  }
}

/// 手柄几何。四处（`getHandleSize` / `buildHandle` / `getHandleAnchor` / painter）
/// 必须共用同一套数字，否则锚点错位会表现成「手柄整根跑到文字上方或下方」。
///
/// 数值来源见 [OhosSelectionTheme]：外径 14vp、内径 12vp、描边/杆宽 2vp、
/// 热区半径 14vp；行高只决定杆长与盒子高度。
class OhosHandleMetrics {
  const OhosHandleMetrics._({
    required this.ballDiameter,
    required this.innerDiameter,
    required this.strokeWidth,
    required this.textLineHeight,
  });

  /// 按文本行高计算尺寸。
  factory OhosHandleMetrics.forLineHeight(double textLineHeight) {
    return OhosHandleMetrics._(
      ballDiameter: OhosSelectionTheme.handleOuterDiameter,
      innerDiameter: OhosSelectionTheme.handleInnerDiameter,
      strokeWidth: OhosSelectionTheme.handleStrokeWidth,
      textLineHeight: textLineHeight,
    );
  }

  /// 外圈**描边圆心所在的直径**（原生 `handle_outer_diameter` = 14vp，与行高无关）。
  ///
  /// 注意这不是视觉外径：原生 `PaintHandle` 用 `canvas.DrawCircle(…, handleRadius)`
  /// 配 2vp 的 pen，描边是跨在半径上的，所以**视觉外径 = 本值 + 描边宽 = 16vp**。
  /// 内芯是半径 6vp 的实心圆（`handle_inner_diameter` = 12vp）。
  final double ballDiameter;

  /// 内芯实心圆直径（原生 `handle_inner_diameter` = 12vp）。
  final double innerDiameter;

  /// 杆宽，也是球的描边宽度（原生 2vp）。
  final double strokeWidth;

  /// 文本行高，同时也是杆的长度。
  final double textLineHeight;

  /// 触摸热区在**远离正文**一侧额外延伸的距离：原生是 `2 * hotZone` = 28vp。
  double get hotZoneOutward => OhosSelectionTheme.handleHotZoneRadius * 2;

  /// 手柄盒子宽度 = 横向热区宽度（原生 `2 * hotZone` = 28vp）；球与杆水平居中。
  ///
  /// 小于 `kMinInteractiveDimension`(48)，SDK 会以盒子中心对称补足到 48，
  /// 于是有效横向热区是 ±24（比原生的 ±14 更宽松，但不影响图形位置）。
  double get width => OhosSelectionTheme.handleHotZoneRadius * 2;

  /// 手柄盒子高度 = 行高 + 外侧热区。
  double get height => textLineHeight + hotZoneOutward;

  /// 盒子尺寸。
  Size get size => Size(width, height);

  /// 杆长 = 文本行高（首尾与文字齐平，不上下出头）。
  double get barLength => textLineHeight;

  /// 球心横坐标（盒子水平正中）。
  double get ballCenterX => width / 2;

  /// 起手柄：球在行**上沿之外**、与行相切；杆占 `[hotZoneOutward, +行高]`。
  double get startBallCenterY => hotZoneOutward - ballDiameter / 2;
  double get startBarTop => hotZoneOutward;
  double get startBarBottom => hotZoneOutward + barLength;

  /// 止手柄 / 折叠光标：球在行**下沿之外**；杆占 `[0, 行高]`。
  double get endBallCenterY => barLength + ballDiameter / 2;
  double get endBarTop => 0;
  double get endBarBottom => barLength;

  /// 起（左）手柄的锚点：杆的下端，正好对齐行的下沿。
  Offset get leftAnchor => Offset(ballCenterX, startBarBottom);

  /// 止（右）手柄的锚点：杆的下端 (= 行下沿)，盒子从行上沿开始。
  Offset get rightAnchor => Offset(ballCenterX, endBarBottom);

  /// 折叠光标的锚点：光标下沿（leader 就是光标底部），与止手柄同形。
  Offset get collapsedAnchor => Offset(ballCenterX, endBarBottom);
}

/// 手绘「球 + 杆」，球贴在杆的一端。公开是为了让测试能直接光栅化取色验证配色。
class OhosSelectionHandlePainter extends CustomPainter {
  const OhosSelectionHandlePainter({
    required this.foreground,
    required this.background,
    required this.textLineHeight,
    required this.ballAbove,
    this.drawBar = true,
  });

  final Color foreground;
  final Color background;
  final double textLineHeight;

  /// 球在杆的上方还是下方：起手柄在上，止手柄/折叠光标在下。
  final bool ballAbove;

  /// 是否画杆。折叠光标靠输入框自己的光标，不再重复画（见 `buildHandle`）。
  final bool drawBar;

  @override
  void paint(Canvas canvas, Size size) {
    final OhosHandleMetrics metrics = OhosHandleMetrics.forLineHeight(
      textLineHeight,
    );
    final double cx = metrics.ballCenterX;
    final double barTop = ballAbove
        ? metrics.startBarTop
        : metrics.endBarTop;
    final double barBottom = ballAbove
        ? metrics.startBarBottom
        : metrics.endBarBottom;
    final double ballCenterY = ballAbove
        ? metrics.startBallCenterY
        : metrics.endBallCenterY;

    // 杆：圆头竖线，与文字行严格同高。
    if (drawBar) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            cx - metrics.strokeWidth / 2,
            barTop,
            cx + metrics.strokeWidth / 2,
            barBottom,
          ),
          Radius.circular(metrics.strokeWidth / 2),
        ),
        Paint()..color = foreground,
      );
    }

    // 球：按原生 `PaintHandle` 的画法 —— 先铺内芯实心圆（内径 12/2），再把描边
    // **跨在外径上**（`DrawCircle(…, handleRadius, penWidth=2)`），于是视觉外径
    // = 14 + 2 = 16vp。早先把描边画在半径内侧，视觉只有 14vp，比系统小一圈。
    final Offset ballCenter = Offset(cx, ballCenterY);
    canvas
      ..drawCircle(
        ballCenter,
        metrics.innerDiameter / 2,
        Paint()..color = background,
      )
      ..drawCircle(
        ballCenter,
        math.max(0, metrics.ballDiameter / 2),
        Paint()
          ..color = foreground
          ..style = PaintingStyle.stroke
          ..strokeWidth = metrics.strokeWidth,
      );
  }

  @override
  bool shouldRepaint(OhosSelectionHandlePainter oldDelegate) {
    return foreground != oldDelegate.foreground ||
        background != oldDelegate.background ||
        textLineHeight != oldDelegate.textLineHeight ||
        ballAbove != oldDelegate.ballAbove ||
        drawBar != oldDelegate.drawBar;
  }
}

/// 给 `SelectionArea` / `SelectionText` 用的共享实例。
final TextSelectionControls ohosTextSelectionHandleControls =
    OhosTextSelectionHandleControls();

/// 手柄拖动时的触感反馈，**带节流**。
///
/// 对应原生 `RichEditorPattern::StartVibratorByIndexChange`
/// （`VibratorUtils::StartVibraFeedback("slide")`）：拖手柄每越过一个字符轻震一下。
///
/// 为什么必须节流：`HapticFeedback.*` 是 method channel 调用，最终落到 OHOS 的振动器
/// 服务上执行；拖手柄时指针 move 每帧都有（一帧内还可能多次），逐次触发会把平台线程和
/// 马达刷爆 —— 真机表现就是拖动掉帧。这里限制最短间隔 60ms，观感仍是「一格一格」。
class OhosSelectionHaptics {
  const OhosSelectionHaptics._();

  /// 两次轻震之间的最短间隔。
  static const int intervalMs = 60;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _lastMs = -intervalMs;

  /// 触发一次选区轻震；距上次不足 [intervalMs] 时直接丢弃。
  static void selectionTick() {
    final int now = _clock.elapsedMilliseconds;
    if (now - _lastMs < intervalMs) {
      return;
    }
    _lastMs = now;
    HapticFeedback.lightImpact();
  }
}

/// 只给「真的在拖手柄」的手势发触感反馈。
///
/// 直接对 `Listener.onPointerMove` 每次都震是不行的（第一版就是这么踩的）：
///
/// 1. `SelectionOverlay` 的手柄外层是 `Visibility.maintain`，**不可见时仍然可命中**
///    （`maintainInteractivity` 默认为 true），残留的命中盒会吃到附近的点击与滑动；
/// 2. 手柄命中盒是 28 × (行高 + 28)，手指在选区端点附近、或者从手柄上滑过去滚页面时，
///    move 会持续送到这里 —— 真机表现就是「没拖也一直震」。
///
/// 所以这里加三重门槛，效果等价于原生「每越过一个字符震一下」：
///
/// - 指针位移先超过 [kTouchSlop]（纯点击不震）；
/// - 手柄**自身位置变了**（= 选区端点/光标真的移动了）；
/// - 指针此刻仍在手柄范围内（页面滚动时手柄会从手指下方滑走，之后自然不再触发）。
class _HapticHandle extends StatefulWidget {
  const _HapticHandle({required this.child});

  final Widget child;

  @override
  State<_HapticHandle> createState() => _HapticHandleState();
}

class _HapticHandleState extends State<_HapticHandle> {
  final GlobalKey _boxKey = GlobalKey();
  int? _pointer;
  Offset? _downPosition;
  Offset? _lastTopLeft;

  RenderBox? get _box {
    final RenderObject? renderObject =
        _boxKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    return renderObject;
  }

  void _handleDown(PointerDownEvent event) {
    _pointer = event.pointer;
    _downPosition = event.position;
    _lastTopLeft = _box?.localToGlobal(Offset.zero);
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final Offset? down = _downPosition;
    if (down == null || (event.position - down).distance < kTouchSlop) {
      return;
    }
    final RenderBox? box = _box;
    if (box == null) {
      return;
    }
    final Offset topLeft = box.localToGlobal(Offset.zero);
    // 手指已经离开手柄（滚动/被别的手势接管）：不震。
    if (!(topLeft & box.size).contains(event.position)) {
      return;
    }
    final bool handleMoved = _lastTopLeft != topLeft;
    _lastTopLeft = topLeft;
    if (handleMoved) {
      OhosSelectionHaptics.selectionTick();
    }
  }

  void _reset() {
    _pointer = null;
    _downPosition = null;
    _lastTopLeft = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: _boxKey,
      // 必须 translucent：子级（GestureDetector）命中后本层仍要留在事件路径上，
      // 否则拿不到 move。
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: (PointerUpEvent _) => _reset(),
      onPointerCancel: (PointerCancelEvent _) => _reset(),
      child: widget.child,
    );
  }
}
