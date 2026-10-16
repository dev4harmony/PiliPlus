import 'dart:async' show Completer;

// Port of the Flutter framework's private `_StandardBottomSheet` /
// `PersistentBottomSheetController` internals, which are not public in the
// HarmonyOS Flutter SDK.
// ignore_for_file: library_private_types_in_public_api

import 'package:PiliPlus/common/widgets/scaffold/bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart'
    show RenderStack, BoxHitTestResult, StackParentData;

class MiniScaffold extends StatefulWidget {
  const MiniScaffold({
    super.key,
    required this.body,
  });

  final Widget body;

  static MiniScaffoldState of(BuildContext context) {
    return context.findAncestorStateOfType<MiniScaffoldState>()!;
  }

  static MiniScaffoldState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<MiniScaffoldState>();
  }

  @override
  State<MiniScaffold> createState() => MiniScaffoldState();
}

class MiniScaffoldState extends State<MiniScaffold>
    with TickerProviderStateMixin {
  final _dismissedBottomSheets = <_StandardBottomSheet>[];
  MiniBottomSheetController? _currentBottomSheet;
  LocalHistoryEntry? _persistentSheetHistoryEntry;

  void _closeCurrentBottomSheet() {
    if (_currentBottomSheet != null) {
      if (!_currentBottomSheet!.isLocalHistoryEntry) {
        _currentBottomSheet!.close();
      }
      assert(() {
        _currentBottomSheet?.completer.future.whenComplete(() {
          assert(_currentBottomSheet == null);
        });
        return true;
      }());
    }
  }

  MiniBottomSheetController _buildBottomSheet(
    WidgetBuilder builder, {
    required bool isPersistent,
    required AnimationController animationController,
    BoxConstraints? constraints,
    bool? enableDrag,
    bool shouldDisposeAnimationController = true,
    double dragHeight = kBottomSheetDragHeight,
  }) {
    final completer = Completer<void>();
    final bottomSheetKey = GlobalKey<_StandardBottomSheetState>();
    late _StandardBottomSheet bottomSheet;

    var removedEntry = false;
    var doingDispose = false;

    void removePersistentSheetHistoryEntryIfNeeded() {
      assert(isPersistent);
      if (_persistentSheetHistoryEntry != null) {
        _persistentSheetHistoryEntry!.remove();
        _persistentSheetHistoryEntry = null;
      }
    }

    void removeCurrentBottomSheet() {
      removedEntry = true;
      if (_currentBottomSheet == null) {
        return;
      }
      assert(_currentBottomSheet!.widget == bottomSheet);
      assert(bottomSheetKey.currentState != null);

      if (isPersistent) {
        removePersistentSheetHistoryEntryIfNeeded();
      }

      bottomSheetKey.currentState!.close();
      setState(() {
        _currentBottomSheet = null;
      });

      if (!animationController.isDismissed) {
        _dismissedBottomSheets.add(bottomSheet);
      }
      completer.complete();
    }

    final LocalHistoryEntry? entry = isPersistent
        ? null
        : LocalHistoryEntry(
            onRemove: () {
              if (!removedEntry &&
                  _currentBottomSheet?.widget == bottomSheet &&
                  !doingDispose) {
                removeCurrentBottomSheet();
              }
            },
          );

    void removeEntryIfNeeded() {
      if (!isPersistent && !removedEntry) {
        assert(entry != null);
        entry!.remove();
        removedEntry = true;
      }
    }

    bottomSheet = _StandardBottomSheet(
      key: bottomSheetKey,
      animationController: animationController,
      enableDrag: enableDrag ?? !isPersistent,
      dragHeight: dragHeight,
      onClosing: () {
        if (_currentBottomSheet == null) {
          return;
        }
        assert(_currentBottomSheet!.widget == bottomSheet);
        removeEntryIfNeeded();
      },
      onDismissed: () {
        if (_dismissedBottomSheets.contains(bottomSheet)) {
          setState(() {
            _dismissedBottomSheets.remove(bottomSheet);
          });
        }
      },
      onDispose: () {
        doingDispose = true;
        removeEntryIfNeeded();
        if (shouldDisposeAnimationController) {
          animationController.dispose();
        }
      },
      builder: builder,
      isPersistent: isPersistent,
      constraints: constraints,
    );

    if (!isPersistent) {
      ModalRoute.of(context)!.addLocalHistoryEntry(entry!);
    }

    return MiniBottomSheetController(
      bottomSheet,
      completer,
      entry != null ? entry.remove : removeCurrentBottomSheet,
      (VoidCallback fn) {
        bottomSheetKey.currentState?.setState(fn);
      },
      !isPersistent,
    );
  }

  MiniBottomSheetController showBottomSheet(
    WidgetBuilder builder, {
    BoxConstraints? constraints,
    bool? enableDrag,
    AnimationController? transitionAnimationController,
    AnimationStyle? sheetAnimationStyle,
    double dragHeight = kBottomSheetDragHeight,
  }) {
    assert(debugCheckHasMediaQuery(context));

    _closeCurrentBottomSheet();
    final AnimationController controller =
        (transitionAnimationController ??
              BottomSheet.createAnimationController(
                this,
                sheetAnimationStyle: sheetAnimationStyle,
              ))
          ..forward();
    setState(() {
      _currentBottomSheet = _buildBottomSheet(
        builder,
        isPersistent: false,
        animationController: controller,
        constraints: constraints,
        enableDrag: enableDrag,
        dragHeight: dragHeight,
        shouldDisposeAnimationController: transitionAnimationController == null,
      );
    });
    return _currentBottomSheet!;
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetStack(
      clipBehavior: .none,
      alignment: .bottomCenter,
      children: [
        widget.body,
        ..._dismissedBottomSheets,
        ?_currentBottomSheet?.widget,
      ],
    );
  }
}

/// A controller for the bottom sheet currently shown by [MiniScaffoldState].
///
/// This is a port of the SDK's `PersistentBottomSheetController`, which is not
/// publicly constructible in the HarmonyOS Flutter SDK.
class MiniBottomSheetController {
  MiniBottomSheetController(
    this.widget,
    this.completer,
    this.close,
    this.setState,
    this.isLocalHistoryEntry,
  );

  final _StandardBottomSheet widget;
  final Completer<void> completer;
  final VoidCallback close;
  final StateSetter? setState;
  final bool isLocalHistoryEntry;
}

class _StandardBottomSheet extends StatefulWidget {
  const _StandardBottomSheet({
    super.key,
    required this.animationController,
    this.enableDrag = true,
    required this.onClosing,
    required this.onDismissed,
    required this.builder,
    this.isPersistent = false,
    this.constraints,
    this.onDispose,
    this.dragHeight = kBottomSheetDragHeight,
  });

  final AnimationController
  animationController; // we control it, but it must be disposed by whoever created it.
  final bool enableDrag;
  final VoidCallback? onClosing;
  final VoidCallback? onDismissed;
  final VoidCallback? onDispose;
  final WidgetBuilder builder;
  final bool isPersistent;
  final BoxConstraints? constraints;
  final double dragHeight;

  @override
  _StandardBottomSheetState createState() => _StandardBottomSheetState();
}

class _StandardBottomSheetState extends State<_StandardBottomSheet> {
  // Same curve as the SDK's `_standardBottomSheetCurve` (`standardEasing`).
  static const Curve _standardBottomSheetCurve = Easing.legacy;

  ParametricCurve<double> animationCurve = _standardBottomSheetCurve;

  @override
  void initState() {
    super.initState();
    assert(widget.animationController.isForwardOrCompleted);
    widget.animationController.addStatusListener(_handleStatusChange);
  }

  @override
  void dispose() {
    widget.animationController.removeStatusListener(_handleStatusChange);
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  void didUpdateWidget(_StandardBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.animationController == oldWidget.animationController);
  }

  void close() {
    widget.animationController.reverse();
    widget.onClosing?.call();
  }

  void _handleDragStart(DragStartDetails details) {
    // Allow the bottom sheet to track the user's finger accurately.
    animationCurve = Curves.linear;
  }

  void _handleDragEnd(DragEndDetails details, {bool? isClosing}) {
    // Allow the bottom sheet to animate smoothly from its current position.
    animationCurve = Split(
      widget.animationController.value,
      endCurve: _standardBottomSheetCurve,
    );
  }

  void _handleStatusChange(AnimationStatus status) {
    if (status.isDismissed) {
      widget.onDismissed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = BottomSheet_(
      animationController: widget.animationController,
      enableDrag: widget.enableDrag,
      onDragStart: _handleDragStart,
      onDragEnd: _handleDragEnd,
      onClosing: widget.onClosing!,
      builder: widget.builder,
      constraints: widget.constraints,
      dragHeight: widget.dragHeight,
    );
    if (widget.enableDrag) {
      return AnimatedBuilder(
        animation: widget.animationController,
        builder: (context, child) => Align(
          alignment: AlignmentDirectional.topStart,
          heightFactor: animationCurve.transform(
            widget.animationController.value,
          ),
          child: child,
        ),
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: widget.animationController,
      builder: (context, child) => Opacity(
        opacity: widget.animationController.value,
        child: child,
      ),
      child: child,
    );
  }
}

class BottomSheetStack extends Stack {
  const BottomSheetStack({
    super.key,
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
    super.children,
  });

  @override
  RenderBottomSheetStack createRenderObject(BuildContext context) {
    return RenderBottomSheetStack(
      alignment: alignment,
      textDirection: textDirection ?? Directionality.maybeOf(context),
      fit: fit,
      clipBehavior: clipBehavior,
    );
  }
}

class RenderBottomSheetStack extends RenderStack {
  RenderBottomSheetStack({
    super.children,
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
  });

  /// HitTest lastChild only
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    if (child != null) {
      final childParentData = child.parentData! as StackParentData;
      return result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          assert(transformed == position - childParentData.offset);
          final isHit = child.hitTest(result, position: transformed);
          if (childParentData.previousSibling != null) {
            return false;
          } else {
            return isHit;
          }
        },
      );
    }
    return false;
  }
}
