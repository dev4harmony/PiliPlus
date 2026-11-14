// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async' show Completer;

import 'package:flutter/material.dart' hide BottomSheet, BottomSheetState;

import 'bottom_sheet.dart' show BottomSheet, BottomSheetState, BottomSheetDefaultsM3;

// lib/scripts/material/scaffold.patch：SDK `scaffold.dart` 里的私有
// `_StandardBottomSheet(State)` 在鸿蒙 SDK 不公开，这里按上游 patch 后的
// 公开面以同名类提供，供 app 侧 `MiniScaffold` 继承
// （lib/common/widgets/scaffold/mini_scaffold.dart 与上游逐字一致）。

/// The curve used by [StandardBottomSheetState] when the sheet is not being
/// dragged (`standardEasing`, mirrors SDK `scaffold.dart`).
const Curve standardBottomSheetCurve = standardEasing;

class StandardBottomSheet extends StatefulWidget {
  const StandardBottomSheet({
    super.key,
    required this.animationController,
    this.enableDrag = true,
    required this.onClosing,
    required this.onDismissed,
    required this.builder,
    this.isPersistent = false,
    this.constraints,
    this.onDispose,
  });

  final AnimationController animationController;

  final bool enableDrag;

  final VoidCallback? onClosing;

  final VoidCallback onDismissed;

  final WidgetBuilder builder;

  final bool isPersistent;

  final BoxConstraints? constraints;

  final VoidCallback? onDispose;

  @override
  StandardBottomSheetState<StandardBottomSheet> createState() =>
      StandardBottomSheetState<StandardBottomSheet>();
}

class StandardBottomSheetState<T extends StandardBottomSheet>
    extends State<T> {
  ParametricCurve<double> animationCurve = standardBottomSheetCurve;

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
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.animationController == oldWidget.animationController);
  }

  void close() {
    widget.animationController.reverse();
    widget.onClosing?.call();
  }

  void handleDragStart(DragStartDetails details) {
    // Allow the bottom sheet to track the user's finger accurately.
    animationCurve = Curves.linear;
  }

  void handleDragEnd(DragEndDetails details, {bool? isClosing}) {
    // Allow the bottom sheet to animate smoothly from its current position.
    animationCurve = Split(
      widget.animationController.value,
      endCurve: standardBottomSheetCurve,
    );
  }

  void _handleStatusChange(AnimationStatus status) {
    if (status.isDismissed) {
      widget.onDismissed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animationController,
      builder: (BuildContext context, Widget? child) {
        return Align(
          alignment: AlignmentDirectional.topStart,
          heightFactor: animationCurve.transform(
            widget.animationController.value,
          ),
          child: child,
        );
      },
      child: Semantics(
        container: true,
        onDismiss: !widget.isPersistent ? close : null,
        child: BottomSheet(
          animationController: widget.animationController,
          enableDrag: widget.enableDrag,
          onDragStart: handleDragStart,
          onDragEnd: handleDragEnd,
          onClosing: widget.onClosing!,
          builder: widget.builder,
          constraints: widget.constraints,
        ),
      ),
    );
  }
}

/// Controller for a bottom sheet hosted by `MiniScaffold` (upstream:
/// `ScaffoldState._buildBottomSheet` return type).
///
/// Mirrors SDK `ScaffoldFeatureController<PersistentBottomSheet..., void>` with
/// the `lib/scripts/material/scaffold.patch` public surface: `widget` /
/// `completer` getters, const constructor and `isLocalHistoryEntry`.
class PersistentBottomSheetController {
  const PersistentBottomSheetController(
    this.widget,
    this.completer,
    this.close,
    this.setState,
    this._isLocalHistoryEntry,
  );

  final StandardBottomSheet widget;

  final Completer<void> completer;

  /// Remove the sheet from the scaffold.
  final VoidCallback close;

  final StateSetter? setState;

  final bool _isLocalHistoryEntry;

  bool get isLocalHistoryEntry => _isLocalHistoryEntry;

  /// Completes when the sheet is no longer visible.
  Future<void> get closed => completer.future;
}
