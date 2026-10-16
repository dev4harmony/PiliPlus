import 'package:flutter/gestures.dart'
    show
        DoubleTapGestureRecognizer,
        GestureBinding,
        GestureDoubleTapCallback,
        PointerCancelEvent,
        PointerDownEvent,
        PointerEvent,
        PointerUpEvent;

/// Records when the second tap of a double tap was released, so the image
/// viewer can tell a double tap apart from the single tap that follows it.
///
/// Upstream patches the SDK (`lib/scripts/double_tap_gesture.patch`) to expose
/// `checkUp(buttons, event)`. The HarmonyOS Flutter SDK is not patched, so this
/// uses public API only: a pointer route registered ahead of the superclass
/// remembers the latest pointer-up time, and [onDoubleTap] is wrapped to copy
/// it into [timeStamp] right before the caller's callback runs.
class ImageDoubleTapGestureRecognizer extends DoubleTapGestureRecognizer {
  ImageDoubleTapGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  });

  Duration timeStamp = .zero;

  Duration _lastUpTimeStamp = .zero;

  GestureDoubleTapCallback? _onDoubleTap;

  @override
  GestureDoubleTapCallback? get onDoubleTap =>
      _onDoubleTap == null ? null : _handleDoubleTap;

  @override
  set onDoubleTap(GestureDoubleTapCallback? value) => _onDoubleTap = value;

  void _handleDoubleTap() {
    timeStamp = _lastUpTimeStamp;
    _onDoubleTap?.call();
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // Routes run in insertion order: registering before the superclass makes
    // the up time available when it recognizes the double tap.
    GestureBinding.instance.pointerRouter.addRoute(
      event.pointer,
      _recordPointerUp,
    );
    super.addAllowedPointer(event);
  }

  void _recordPointerUp(PointerEvent event) {
    if (event is PointerUpEvent) {
      _lastUpTimeStamp = event.timeStamp;
    } else if (event is! PointerCancelEvent) {
      return;
    }
    GestureBinding.instance.pointerRouter.removeRoute(
      event.pointer,
      _recordPointerUp,
    );
  }
}
