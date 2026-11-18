import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show PlatformDispatcher;
import 'package:flutter/gestures.dart'
    show
        Offset,
        GestureRecognizer,
        PointerDownEvent,
        HorizontalDragGestureRecognizer,
        DeviceGestureSettings,
        PointerDeviceKind,
        kPrecisePointerHitSlop,
        kTouchSlop,
        PointerPanZoomStartEvent;

mixin InitialPositionMixin on GestureRecognizer {
  Offset? _initialPosition;
  Offset? get initialPosition => _initialPosition;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _initialPosition = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _initialPosition = event.position;
    super.addAllowedPointerPanZoom(event);
  }
}

class CustomHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer
    with InitialPositionMixin {
  CustomHorizontalDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  });

  @override
  DeviceGestureSettings get gestureSettings => _gestureSettings;
  final _gestureSettings = DeviceGestureSettings(touchSlop: touchSlopH);

  /// 横滑判定的角度系数：`|dx| > |dy| * angleFactor`。
  ///
  /// 上游（Flutter SDK 补丁版）固定为 3；鸿蒙侧为了简介/评论区页签更容易
  /// 触发横向切换，默认放宽到 1（见 [_calcAngle] 注释）。图片查看器需要
  /// 保持上游的 3，避免捏合手势被误判成横滑，见
  /// `ImageHorizontalDragGestureRecognizer.angleFactor`。
  double get angleFactor => 1.0;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return _computeHitSlop(
      globalDistanceMoved.abs(),
      gestureSettings,
      pointerDeviceKind,
      _initialPosition,
      lastPosition.global,
      angleFactor,
    );
  }

  @override
  Type get runtimeType => HorizontalDragGestureRecognizer;
}

double touchSlopH = Pref.touchSlopH;

bool _computeHitSlop(
  double globalDistanceMoved,
  DeviceGestureSettings settings,
  PointerDeviceKind kind,
  Offset? initialPosition,
  Offset lastPosition,
  double angleFactor,
) {
  switch (kind) {
    case .mouse:
      return globalDistanceMoved > kPrecisePointerHitSlop;
    case .stylus:
    case .invertedStylus:
    case .unknown:
    case .touch:
      return globalDistanceMoved > settings.touchSlop! &&
          _calcAngle(initialPosition!, lastPosition, angleFactor);
    case .trackpad:
      return globalDistanceMoved > settings.touchSlop! &&
          _calcAngle(initialPosition!, lastPosition, angleFactor);
  }
}

bool _calcAngle(
  Offset initialPosition,
  Offset lastPosition,
  double angleFactor,
) {
  final offset = lastPosition - initialPosition;
  // angleFactor == 1：只要水平位移 > 垂直位移即算横滑（上游为 dx > 3·dy，
  // 过于苛刻，鸿蒙侧为了让简介/评论区左右切换更容易触发而放宽）。
  // 图片查看器传 3，保持与上游一致的捏合/斜滑判定。
  return offset.dx.abs() > offset.dy.abs() * angleFactor;
}

final deviceTouchSlop = _calcDeviceTouchSlop();

double _calcDeviceTouchSlop() {
  final view = PlatformDispatcher.instance.views.first;
  final physicalTouchSlop = view.gestureSettings.physicalTouchSlop;
  return physicalTouchSlop == null
      ? kTouchSlop
      : physicalTouchSlop / view.devicePixelRatio;
}
