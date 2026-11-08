import 'dart:math' as math;

import 'package:flutter/material.dart' hide SelectionArea;

/// 鸿蒙（`TargetPlatform.ohos`）下的文本选择手柄：**杆 + 球**造型。
///
/// ## 为什么要换掉 Material 的水滴
///
/// SDK 的 `MaterialTextSelectionControls.buildHandle`（`package:flutter/src/material/
/// text_selection.dart`）画的是 22x22 的水滴（`_TextSelectionHandlePainter` 在左上
/// 象限挖一个方块再旋转 45°/90°），是 Android 的观感。鸿蒙的手柄是「一根细杆 + 一端
/// 一个环」，所以这里重画：
///
/// - 球：**背景色填充 + 前景色描边**（描边宽度与杆一致）——深色主题下呈现为
///   「亮圈 + 深色芯」，压在彩色封面上也不会糊成一团；球径约为行高的 0.69 倍；
/// - 杆：实心前景色的一根圆头竖线，**与文字行严格同高**；
/// - 比例：球直径取行高的 [OhosHandleMetrics.ballDiameterToLineHeight] 倍（约 0.69），
///   杆与文字行同高；
/// - 热区：盒子比图形宽，左右不对称留白（外侧
///   [OhosHandleMetrics.hitExtendOutward]、内侧 [OhosHandleMetrics.hitExtendInward]），
///   于是起手柄的热区往左扩、止手柄往右扩，而图形位置不变。
///
/// ## 与 SDK overlay 的配合（定位的关键，别改错）
///
/// `_SelectionHandleOverlayState.build`（SDK `widgets/text_selection.dart:2081`）把
/// 手柄放在 `CompositedTransformFollower(offset: -handleAnchor - padding.topLeft)`，
/// leader 是选区端点，也就是文本行的**下沿**。所以 widget 里任一点 `q` 的全局位置是
/// `选区端点 + (q - handleAnchor)`——**`getHandleAnchor` 返回的点会落在行的下沿上**。
///
/// - 起（左）手柄：球在上、杆向下，锚点取杆的下端，于是杆正好压住这一行文字
///   （上沿对齐行首、下沿对齐行尾），球挂在文字行上方；
/// - 止（右）手柄：整体绕中心转 180°（球在下、杆向上），锚点取旋转后同样的位置，
///   杆仍然压住这一行，球挂在文字行下方。
///
/// 早先版本把右手锚点写成「height - barBottom」（= 0），右手整根就掉到文字下方了。
class OhosTextSelectionHandleControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  /// 创建控件。无状态，可直接用 [ohosTextSelectionHandleControls] 这个共享实例。
  OhosTextSelectionHandleControls();

  @override
  Size getHandleSize(double textLineHeight) {
    final OhosHandleMetrics metrics = OhosHandleMetrics.forLineHeight(
      textLineHeight,
    );
    return Size(metrics.width, metrics.height);
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
    // 球心是挖空的，填充要用页面底色。
    final Color background = theme.scaffoldBackgroundColor;
    final Size size = getHandleSize(textHeight);

    final Widget handle = SizedBox.fromSize(
      size: size,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: CustomPaint(
          size: size,
          painter: OhosSelectionHandlePainter(
            foreground: foreground,
            background: background,
            textLineHeight: textHeight,
            drawBar: type != TextSelectionHandleType.collapsed,
            // 折叠光标没有左右之分，必须让热区在光标两侧对称。
            centerInBox: type == TextSelectionHandleType.collapsed,
          ),
        ),
      ),
    );

    return switch (type) {
      // 球在上、杆向下。
      TextSelectionHandleType.left => handle,
      // 绕中心转 180°：球在下、杆向上。用旋转而不是 `scale(1, -1)`，
      // 保证变换矩阵行列式为正，不会触发渲染层的镜像处理。
      TextSelectionHandleType.right => Transform.rotate(
        angle: math.pi,
        child: handle,
      ),
      // 折叠光标只画球。
      TextSelectionHandleType.collapsed => handle,
    };
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

/// 手柄几何。三处（`getHandleSize` / `buildHandle` / `getHandleAnchor`）必须共用
/// 同一套数字，否则锚点错位会表现成「手柄整根跑到文字上方或下方」。
class OhosHandleMetrics {
  const OhosHandleMetrics._({
    required this.ballDiameter,
    required this.strokeWidth,
    required this.textLineHeight,
  });

  /// 按文本行高计算尺寸。
  factory OhosHandleMetrics.forLineHeight(double textLineHeight) {
    final double ballDiameter = math.max(
      _minBallDiameter,
      textLineHeight * ballDiameterToLineHeight,
    );
    final double strokeWidth = math.max(
      _minStrokeWidth,
      ballDiameter * strokeToBallDiameter,
    );
    return OhosHandleMetrics._(
      ballDiameter: ballDiameter,
      strokeWidth: strokeWidth,
      textLineHeight: textLineHeight,
    );
  }

  /// 球直径相对文本行高的比例。想整体调大小球改这一个数。
  ///
  /// 0.69 取在早期 0.55 与 0.825 之间：20 的行高下球径 13.8、半径 6.9，
  /// 与手柄杆长（≈ 行高）的比例接近截图里的观感。
  static const double ballDiameterToLineHeight = 0.69;

  /// 球直径下限，防止极小字号把手柄缩成看不见的点。
  static const double _minBallDiameter = 12;

  /// 杆宽的下限（逻辑像素）。
  static const double _minStrokeWidth = 2;

  /// 杆宽（也就是球描边宽）占球直径的比例。整体调粗细改这一个数。
  static const double strokeToBallDiameter = 0.12;

  /// 球的外径。
  final double ballDiameter;

  /// 杆宽，也是球的描边宽度。
  final double strokeWidth;

  /// 文本行高，同时也是杆的长度。
  final double textLineHeight;

  /// 触摸热区相对球边缘向**外侧**（远离正文那一侧）额外延伸的宽度。
  ///
  /// SDK 的 `_SelectionHandleOverlayState.build` 只把 `getHandleSize` 返回的矩形按
  /// `kMinInteractiveDimension`（48）**居中**补够，左右永远对称；想让「起手柄往左、
  /// 止手柄往右」各多一块热区、同时又少压向正文，只能把这个不对称做进盒子尺寸里：
  /// 盒子加宽，图形画在盒子靠正文那一侧，锚点按盒子坐标补偿，于是图形位置不变、
  /// 热区偏向外侧。
  static const double hitExtendOutward = 28;

  /// 触摸热区向**内侧**（压向正文）延伸的宽度，比 [hitExtendOutward] 小。
  static const double hitExtendInward = 10;

  /// 手柄盒子宽度，也就是水平触摸热区宽度。
  ///
  /// 恒大于 [kMinInteractiveDimension]，所以 SDK 那边的 `padding` 横向补零，
  /// 热区宽度完全由这里决定。
  double get width => ballDiameter + hitExtendOutward + hitExtendInward;

  /// 图形（球 + 杆）在盒子里的左边距：贴内侧放，把外侧留给触摸热区。
  double get contentLeft => hitExtendOutward;

  /// 球心横坐标。
  double get ballCenterX => contentLeft + ballDiameter / 2;

  /// 球心。
  Offset get ballCenter => Offset(ballCenterX, ballDiameter / 2);

  /// 杆的长度 = 文本行高（首尾与文字齐平，不上下出头）。
  double get barLength => textLineHeight;

  /// 杆顶端：贴住球的外缘再内缩一个描边宽，接缝处不漏光。
  double get barTop => ballDiameter - strokeWidth;

  /// 杆底端 = widget 最底边。
  double get barBottom => barTop + barLength;

  /// widget 总高。
  double get height => barBottom;

  /// 起（左）手柄的锚点：杆的下端，正好对齐行的下沿。
  ///
  /// x 必须取球心（而不是盒子中心）：图形是靠盒子内侧画的，锚点跟着图形走。
  /// 盒子在锚点左侧留 [hitExtendOutward] + 半个球，右侧留
  /// [hitExtendInward] + 半个球。
  Offset get leftAnchor => Offset(ballCenterX, barBottom);

  /// 止（右）手柄的锚点（旋转 180° 之后的坐标）。
  ///
  /// y：旋转后 `y' = height - y`，杆在 widget 里占 `[height - barBottom,
  /// height - barTop]` = `[0, barLength]`，下端即 `y' == barLength`。
  ///
  /// x：整体绕盒子中心转 180°，`x' = width - x`。要让**画出来的**球心落在选止
  /// 端点上，local x 得取 `width - ballCenterX`（= 半个球 + [hitExtendInward]）；
  /// 这样再转回去，外侧（右边）仍是 [hitExtendOutward] 的加宽热区。
  Offset get rightAnchor => Offset(width - ballCenterX, barLength);

  /// 折叠光标的锚点：球心。
  ///
  /// 折叠手柄不做 180° 旋转，[buildHandle] 会把球画在盒子正中
  /// （[OhosSelectionHandlePainter.centerInBox]），所以这里取盒子中心，
  /// 热区在光标左右仍然对称。
  Offset get collapsedAnchor => Offset(width / 2, ballDiameter / 2);
}

/// 手绘「球 + 杆」。公开是为了让测试能直接光栅化取色验证配色。
class OhosSelectionHandlePainter extends CustomPainter {
  const OhosSelectionHandlePainter({
    required this.foreground,
    required this.background,
    required this.textLineHeight,
    this.drawBar = true,
    this.centerInBox = false,
  });

  final Color foreground;
  final Color background;
  final double textLineHeight;

  /// 折叠光标不画杆。
  final bool drawBar;

  /// 把球画在盒子**水平正中**而不是靠内侧。
  ///
  /// 折叠光标（光标把手）不旋转、也没有左右之分，热区必须在光标两侧对称，
  /// 否则光标左边的可点区域会比右边窄一截。
  final bool centerInBox;

  @override
  void paint(Canvas canvas, Size size) {
    final OhosHandleMetrics metrics = OhosHandleMetrics.forLineHeight(
      textLineHeight,
    );
    final double cx = centerInBox
        ? size.width / 2
        : metrics.ballCenter.dx;
    final double radius = metrics.ballDiameter / 2;

    // 先画杆：圆头竖线，顶端被球盖住一段，接缝处不会出现豁口。
    if (drawBar) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            cx - metrics.strokeWidth / 2,
            metrics.barTop,
            cx + metrics.strokeWidth / 2,
            metrics.barBottom,
          ),
          Radius.circular(metrics.strokeWidth / 2),
        ),
        Paint()..color = foreground,
      );
    }

    // 球：背景色实心圆打底（盖住杆的穿入部分），再描一圈前景色。
    final Offset ballCenter = Offset(cx, metrics.ballCenter.dy);
    canvas
      ..drawCircle(ballCenter, radius, Paint()..color = background)
      ..drawCircle(
        ballCenter,
        radius - metrics.strokeWidth / 2,
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
        drawBar != oldDelegate.drawBar ||
        centerInBox != oldDelegate.centerInBox;
  }
}

/// 给 `SelectionArea` / `SelectionText` 用的共享实例。
final TextSelectionControls ohosTextSelectionHandleControls =
    OhosTextSelectionHandleControls();
