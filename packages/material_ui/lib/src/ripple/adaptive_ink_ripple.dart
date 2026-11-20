import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_ui/src/ripple/ripple_shader.dart';

/// 自适应的水波纹，全平台统一。
///
/// shader 可用时复刻 Android 12 的 InkSparkle（617ms，噪点 + 粒子），不可用时
/// 退化为纯 Canvas 圆（450ms）。两种模式时长不同，所以在创建时确定，动画中途
/// 不会切换。
class AdaptiveInkRipple extends InteractiveInkFeature {
  AdaptiveInkRipple({
    required MaterialInkController controller,
    required super.referenceBox,
    required Color color,
    required Offset position,
    required TextDirection textDirection,
    bool containedInkWell = true,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    super.customBorder,
    double? radius,
    super.onRemoved,
    double? turbulenceSeed,
  }) : assert(containedInkWell || rectCallback == null),
       _borderRadius = borderRadius ?? BorderRadius.zero,
       _textDirection = textDirection,
       _baseRadius = radius ?? _getTargetRadius(referenceBox, containedInkWell, rectCallback),
       _clipCallback = _getClipCallback(referenceBox, containedInkWell, rectCallback),
       super(controller: controller, color: color) {
    RippleShader.ensureLoaded();
    _useShader = RippleShader.available;

    _controller = AnimationController(
      duration: _useShader ? _shaderDuration : _canvasDuration,
      vsync: controller.vsync,
    )
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_handleStatusChanged)
      ..forward();

    _alpha = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: 1), weight: 13),
      TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 27),
      TweenSequenceItem<double>(tween: Tween<double>(begin: 1, end: 0), weight: 60),
    ]).animate(_controller);

    final Animation<double> centerProgress = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: 1), weight: 50),
      TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 50),
    ]).animate(_controller);
    _center = _OffsetTween(
      begin: position,
      end: Offset(referenceBox.size.width / 2, referenceBox.size.height / 2),
    ).animate(centerProgress);

    if (_useShader) {
      _radiusScale = TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(tween: CurveTween(curve: Curves.fastOutSlowIn), weight: 75),
        TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 25),
      ]).animate(_controller);
      _sparkleAlpha = TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: 1), weight: 13),
        TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 27),
        TweenSequenceItem<double>(tween: Tween<double>(begin: 1, end: 0), weight: 50),
      ]).animate(_controller);
      _radius = const AlwaysStoppedAnimation<double>(0);
      _turbulenceSeed = turbulenceSeed ?? math.Random().nextDouble() * 1000.0;
    } else {
      _radius = _controller.drive(
        Tween<double>(
          begin: _baseRadius * _canvasRadiusBegin,
          end: _baseRadius * _canvasRadiusEnd,
        ).chain(CurveTween(curve: Curves.fastOutSlowIn)),
      );
      _radiusScale = const AlwaysStoppedAnimation<double>(1);
      _sparkleAlpha = const AlwaysStoppedAnimation<double>(0);
      _seedless = true;
    }

    controller.addInkFeature(this);
  }

  static const Duration _shaderDuration = Duration(milliseconds: 617);
  static const Duration _canvasDuration = Duration(milliseconds: 450);
  static const Duration _cancelDuration = Duration(milliseconds: 150);
  static const double _shaderRadiusMultiplier = 2.3;
  static const double _canvasRadiusBegin = 0.60;
  static const double _canvasRadiusEnd = 1.10;
  static const double _rotateRight = math.pi * 0.0078125;
  static const double _rotateLeft = -_rotateRight;
  static const double _noiseDensity = 2.1;

  final BorderRadius _borderRadius;
  final TextDirection _textDirection;
  final double _baseRadius;
  final RectCallback? _clipCallback;

  late final bool _useShader;
  late final AnimationController _controller;
  late final Animation<double> _alpha;
  late final Animation<double> _sparkleAlpha;
  late final Animation<double> _radiusScale;
  late final Animation<double> _radius;
  late final Animation<Offset> _center;

  double _turbulenceSeed = 0;
  bool _seedless = false;

  ui.FragmentShader? _fragmentShader;

  /// 供 InkWell/ThemeData 选用的工厂。
  static const InteractiveInkFeatureFactory splashFactory = _AdaptiveInkRippleFactory();

  @override
  void confirm() {}

  /// 手势取消时压到 150ms 内收尾，避免硬消失。
  @override
  void cancel() {
    if (_controller.isAnimating && _controller.value < 1.0) {
      _controller.animateTo(1.0, duration: _cancelDuration, curve: Curves.easeOut);
    }
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status.isCompleted) {
      dispose();
    }
  }

  @override
  void dispose() {
    _controller
      ..stop()
      ..dispose();
    _fragmentShader?.dispose();
    _fragmentShader = null;
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final ui.FragmentProgram? program = RippleShader.program;
    if (_useShader && program != null) {
      _paintShader(canvas, transform, program);
    } else {
      _paintCircle(canvas, transform);
    }
  }

  /// P0：纯 Canvas 圆，clip/transform 全部复用 SDK 的 paintInkCircle。
  void _paintCircle(Canvas canvas, Matrix4 transform) {
    final double alpha = _alpha.value;
    if (alpha <= 0) {
      return;
    }
    paintInkCircle(
      canvas: canvas,
      transform: transform,
      paint: Paint()..color = color.withValues(alpha: color.a * alpha),
      center: _center.value,
      radius: _radius.value,
      textDirection: _textDirection,
      customBorder: customBorder,
      borderRadius: _borderRadius,
      clipCallback: _clipCallback,
    );
  }

  /// P1：复用 SDK 已编译的 ink_sparkle.frag，uniform 布局与 InkSparkle 一致。
  void _paintShader(Canvas canvas, Matrix4 transform, ui.FragmentProgram program) {
    final ui.FragmentShader shader = _fragmentShader ??= program.fragmentShader();
    _updateShader(shader);

    canvas.save();
    final Offset? originOffset = MatrixUtils.getAsTranslation(transform);
    if (originOffset == null) {
      canvas.transform(transform.storage);
    } else {
      canvas.translate(originOffset.dx, originOffset.dy);
    }
    final Rect rect = _clipCallback?.call() ?? (Offset.zero & referenceBox.size);
    _clip(canvas, rect);
    // 只画裁剪矩形，不做全屏 drawPaint。
    canvas
      ..drawRect(rect, Paint()..shader = shader)
      ..restore();
  }

  void _clip(Canvas canvas, Rect rect) {
    final ShapeBorder? border = customBorder;
    if (border != null) {
      canvas.clipPath(border.getOuterPath(rect, textDirection: _textDirection));
    } else if (_borderRadius != BorderRadius.zero) {
      canvas.clipRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: _borderRadius.topLeft,
          topRight: _borderRadius.topRight,
          bottomLeft: _borderRadius.bottomLeft,
          bottomRight: _borderRadius.bottomRight,
        ),
      );
    } else {
      canvas.clipRect(rect);
    }
  }

  void _updateShader(ui.FragmentShader shader) {
    const double turbulenceScale = 1.5;
    final double phase = _seedless ? 0 : _turbulenceSeed + _radiusScale.value;
    final double rotation1 = phase * _rotateRight + 1.7 * math.pi;
    final double rotation2 = phase * _rotateLeft + 2.0 * math.pi;
    final double rotation3 = phase * _rotateRight + 2.75 * math.pi;
    final Size size = referenceBox.size;

    shader
      ..setFloat(0, color.r)
      ..setFloat(1, color.g)
      ..setFloat(2, color.b)
      ..setFloat(3, color.a)
      ..setFloat(4, _alpha.value)
      ..setFloat(5, _sparkleAlpha.value)
      ..setFloat(6, 1.0)
      ..setFloat(7, _radiusScale.value)
      ..setFloat(8, _center.value.dx)
      ..setFloat(9, _center.value.dy)
      ..setFloat(10, _baseRadius * _shaderRadiusMultiplier)
      ..setFloat(11, 1.0 / size.width)
      ..setFloat(12, 1.0 / size.height)
      ..setFloat(13, _noiseDensity / size.width)
      ..setFloat(14, _noiseDensity / size.height)
      ..setFloat(15, phase / 1000.0)
      ..setFloat(16, turbulenceScale * 0.5 + phase * 0.01 * math.cos(turbulenceScale * 0.55))
      ..setFloat(17, turbulenceScale * 0.5 + phase * 0.01 * math.sin(turbulenceScale * 0.55))
      ..setFloat(18, turbulenceScale * 0.2 + phase * -0.0066 * math.cos(turbulenceScale * 0.45))
      ..setFloat(19, turbulenceScale * 0.2 + phase * -0.0066 * math.sin(turbulenceScale * 0.45))
      ..setFloat(20, turbulenceScale + phase * -0.0066 * math.cos(turbulenceScale * 0.35))
      ..setFloat(21, turbulenceScale + phase * -0.0066 * math.sin(turbulenceScale * 0.35))
      ..setFloat(22, math.cos(rotation1))
      ..setFloat(23, math.sin(rotation1))
      ..setFloat(24, math.cos(rotation2))
      ..setFloat(25, math.sin(rotation2))
      ..setFloat(26, math.cos(rotation3))
      ..setFloat(27, math.sin(rotation3));
  }
}

class _OffsetTween extends Tween<Offset> {
  _OffsetTween({required super.begin, required super.end});

  @override
  Offset lerp(double t) => Offset.lerp(begin, end, t)!;
}

class _AdaptiveInkRippleFactory extends InteractiveInkFeatureFactory {
  const _AdaptiveInkRippleFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return AdaptiveInkRipple(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }
}

RectCallback? _getClipCallback(RenderBox referenceBox, bool containedInkWell, RectCallback? rectCallback) {
  if (rectCallback != null) {
    assert(containedInkWell);
    return rectCallback;
  }
  if (containedInkWell) {
    return () => Offset.zero & referenceBox.size;
  }
  return null;
}

double _getTargetRadius(RenderBox referenceBox, bool containedInkWell, RectCallback? rectCallback) {
  final Size size = rectCallback != null ? rectCallback().size : referenceBox.size;
  final double d1 = size.bottomRight(Offset.zero).distance;
  final double d2 = (size.topRight(Offset.zero) - size.bottomLeft(Offset.zero)).distance;
  return math.max(d1, d2) / 2.0;
}