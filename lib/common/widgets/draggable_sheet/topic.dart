import 'package:material_ui/material_ui.dart';

/// Downstream-only (HarmonyOS fork) sheet variant that starts the inner scroll
/// position at a given pixel offset, mirroring upstream's
/// `initialScrollOffset` widget parameter via a dedicated subclass.
class TopicDraggableScrollableSheet extends DraggableScrollableSheet {
  const TopicDraggableScrollableSheet({
    super.key,
    super.initialChildSize,
    super.minChildSize,
    super.maxChildSize,
    super.expand,
    super.snap,
    super.snapSizes,
    super.snapAnimationDuration,
    super.controller,
    super.shouldCloseOnMinExtent,
    required super.builder,
    this.initialScrollOffset = 0.0,
  });

  final double initialScrollOffset;

  @override
  State<DraggableScrollableSheet> createState() =>
      _TopicDraggableScrollableSheetState();
}

class _TopicDraggableScrollableSheetState
    extends DraggableScrollableSheetState {
  @override
  void initScrollController() {
    scrollController = _TopicDraggableScrollableSheetScrollController(
      extent: extent,
      initialScrollOffset:
          (widget as TopicDraggableScrollableSheet).initialScrollOffset,
    );
  }
}

class _TopicDraggableScrollableSheetScrollController
    extends DraggableScrollableSheetScrollController {
  _TopicDraggableScrollableSheetScrollController({
    required super.extent,
    double initialScrollOffset = 0.0,
  }) : _initialScrollOffset = initialScrollOffset;

  @override
  double get initialScrollOffset => _initialScrollOffset;
  final double _initialScrollOffset;

  @override
  DraggableScrollableSheetScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _TopicDraggableScrollableSheetScrollPosition(
      physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
      context: context,
      oldPosition: oldPosition,
      getExtent: () => extent,
      initialPixels: _initialScrollOffset,
    );
  }
}

class _TopicDraggableScrollableSheetScrollPosition
    extends DraggableScrollableSheetScrollPosition {
  _TopicDraggableScrollableSheetScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required super.getExtent,
    required super.initialPixels,
  });
}
