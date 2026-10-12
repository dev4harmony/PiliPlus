import 'package:flutter/gestures.dart' show VerticalDragGestureRecognizer;
import 'package:material_ui/material_ui.dart';

const double kBottomSheetDragHeight = 45.0;

const double _minFlingVelocity = 700.0;
const double _closeProgressThreshold = 0.5;

/// A [BottomSheet] that tracks drags through a [VerticalDragGestureRecognizer]
/// fed by a [Listener], instead of the internal `RawGestureDetector` of
/// [BottomSheet].
///
/// The upstream project extends the SDK's public `BottomSheetState` to build
/// this widget, but the HarmonyOS Flutter SDK keeps the bottom sheet state
/// private. This port reimplements the same widget against the public API.
// ignore: camel_case_types
class BottomSheet_ extends StatefulWidget {
  const BottomSheet_({
    super.key,
    this.animationController,
    this.enableDrag = true,
    this.onDragStart,
    this.onDragEnd,
    this.constraints,
    required this.onClosing,
    required this.builder,
    this.dragHeight = kBottomSheetDragHeight,
  });

  final AnimationController? animationController;
  final bool enableDrag;
  final BottomSheetDragStartHandler? onDragStart;
  final BottomSheetDragEndHandler? onDragEnd;
  final BoxConstraints? constraints;
  final VoidCallback onClosing;
  final WidgetBuilder builder;

  /// Only pointers that go down within this distance from the top of the
  /// sheet start a drag.
  final double dragHeight;

  @override
  State<BottomSheet_> createState() => _BottomSheet_State();
}

// ignore: camel_case_types
class _BottomSheet_State extends State<BottomSheet_> {
  final GlobalKey _childKey = GlobalKey(debugLabel: 'BottomSheet child');

  _VerticalDragGestureRecognizer? _verticalDragGestureRecognizer;

  _VerticalDragGestureRecognizer get verticalDragGestureRecognizer =>
      _verticalDragGestureRecognizer ??=
          _VerticalDragGestureRecognizer(
              debugOwner: this,
              dragHeight: widget.dragHeight,
            )
            ..onStart = handleDragStart
            ..onUpdate = handleDragUpdate
            ..onEnd = handleDragEnd
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
            ..onlyAcceptDragOnThreshold = true;

  double get _childHeight {
    final RenderBox renderBox =
        _childKey.currentContext!.findRenderObject()! as RenderBox;
    return renderBox.size.height;
  }

  bool get _dismissUnderway =>
      widget.animationController!.status == AnimationStatus.reverse;

  void handleDragStart(DragStartDetails details) {
    widget.onDragStart?.call(details);
  }

  void handleDragUpdate(DragUpdateDetails details) {
    assert(
      widget.enableDrag && widget.animationController != null,
      "'BottomSheet_.animationController' cannot be null when "
      "'BottomSheet_.enableDrag' is true.",
    );
    if (_dismissUnderway) {
      return;
    }
    widget.animationController!.value -= details.primaryDelta! / _childHeight;
  }

  void handleDragEnd(DragEndDetails details) {
    assert(
      widget.enableDrag && widget.animationController != null,
      "'BottomSheet_.animationController' cannot be null when "
      "'BottomSheet_.enableDrag' is true.",
    );
    if (_dismissUnderway) {
      return;
    }
    var isClosing = false;
    if (details.velocity.pixelsPerSecond.dy > _minFlingVelocity) {
      final double flingVelocity =
          -details.velocity.pixelsPerSecond.dy / _childHeight;
      if (widget.animationController!.value > 0.0) {
        widget.animationController!.fling(velocity: flingVelocity);
      }
      if (flingVelocity < 0.0) {
        isClosing = true;
      }
    } else if (widget.animationController!.value < _closeProgressThreshold) {
      if (widget.animationController!.value > 0.0) {
        widget.animationController!.fling(velocity: -1.0);
      }
      isClosing = true;
    } else {
      widget.animationController!.forward();
    }

    widget.onDragEnd?.call(details, isClosing: isClosing);

    if (isClosing) {
      widget.onClosing();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    verticalDragGestureRecognizer.addPointer(event);
  }

  @override
  void dispose() {
    super.dispose();
    _verticalDragGestureRecognizer?.dispose();
    _verticalDragGestureRecognizer = null;
  }

  @override
  Widget build(BuildContext context) {
    Widget bottomSheet = KeyedSubtree(
      key: _childKey,
      child: widget.builder(context),
    );

    if (widget.constraints != null &&
        widget.constraints != const BoxConstraints()) {
      bottomSheet = Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: widget.constraints!,
          child: bottomSheet,
        ),
      );
    }

    if (widget.enableDrag) {
      return Listener(
        onPointerDown: _onPointerDown,
        child: bottomSheet,
      );
    }

    return bottomSheet;
  }
}

class _VerticalDragGestureRecognizer extends VerticalDragGestureRecognizer {
  _VerticalDragGestureRecognizer({
    super.debugOwner,
    this.dragHeight = kBottomSheetDragHeight,
  });

  final double dragHeight;

  @override
  bool isPointerAllowed(PointerEvent event) {
    return event.localPosition.dy < dragHeight &&
        super.isPointerAllowed(event as PointerDownEvent);
  }
}
