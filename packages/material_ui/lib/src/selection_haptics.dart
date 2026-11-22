import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerEvent,
        PointerUpEvent;
import 'package:flutter/services.dart' show HapticFeedback;

/// 选区变化时的触感反馈，带节流。
///
/// 对应原生 `RichEditorPattern::StartVibratorByIndexChange`
/// （`VibratorUtils::StartVibraFeedback("slide")`）：选区每越过一个字符轻震一下。
///
/// 必须节流：`HapticFeedback.*` 是 method channel 调用，最终落到 OHOS 的振动器服务；
/// 拖选时指针 move 每帧都有（一帧内还可能多次），逐次触发会把平台线程和马达刷爆，
/// 真机表现是拖动掉帧。这里限制最短间隔 60ms，观感仍是「一格一格」。
class OhosSelectionHaptics {
  const OhosSelectionHaptics._();

  /// 两次轻震之间的最短间隔。
  static const int intervalMs = 60;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _lastMs = -intervalMs;

  /// 触发一次轻震；距上次不足 [intervalMs] 时直接丢弃。
  static void selectionTick() {
    final int now = _clock.elapsedMilliseconds;
    if (now - _lastMs < intervalMs) {
      return;
    }
    _lastMs = now;
    HapticFeedback.lightImpact();
  }

  /// 清空节流状态（测试用）。
  static void resetThrottle() {
    _lastMs = -intervalMs;
  }
}

/// 全局按压状态：当前是否有指针按在屏幕上。
///
/// 选区变化本身不知道自己是怎么来的 —— 长按拖选、拖手柄、键盘快捷键、程序化改选
/// 都会触发，而触感只该在「手按着并拖动」时出现。命中测试靠不住：手指一滑出文字
/// （或滑出 28x(行高+28) 的手柄热区）就收不到事件了，这正是「只在文字上才有震动」
/// 的成因。改用 [PointerRouter] 的全局路由，它与命中测试无关，手指滑到哪里都仍然算
/// 按着。
///
/// 全局路由只在鸿蒙且首次需要时才注册，进程内一条、幂等、不再摘除：单个回调的开销
/// 可以忽略，摘除反而会让「先拖动、后挂载」的时序变复杂。
class SelectionPointerTracker {
  SelectionPointerTracker._();

  /// 进程内唯一实例。
  static final SelectionPointerTracker instance = SelectionPointerTracker._();

  final Set<int> _downPointers = <int>{};
  bool _tracking = false;

  PointerDeviceKind? _lastPointerKind;

  /// 最近一次指针事件的设备类型；第一次指针事件之前为 null。
  ///
  /// 选区相关逻辑（比如「两端不允许交叉」）需要区分鼠标和触摸：鸿蒙 PC 用鼠标
  /// 从右往左拖选是正常操作（反向选区），不能按触摸手柄那样夹住。
  PointerDeviceKind? get lastPointerKind => _lastPointerKind;

  /// 上一次触发触感时的选中文字，用于过滤「内容没变也回调」。
  ///
  /// 每次有指针新按下时清空：不同控件、不同拖动会话之间不会互相压制。
  String? _lastText;

  /// 是否有指针正按在屏幕上。
  bool get isPressed => _downPointers.isNotEmpty;

  /// 开始监听全局指针事件。幂等、开销只有一次指针路由注册。
  ///
  /// 必须在**用户按下之前**调用（构建期最合适），否则按下事件已经过去，这一轮手势
  /// 会被误判成「没按着」。
  void startTracking() {
    if (_tracking) {
      return;
    }
    _tracking = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  /// 停止监听并清空状态（仅测试需要）。
  void stopTracking() {
    if (!_tracking) {
      return;
    }
    _tracking = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    _downPointers.clear();
    _lastPointerKind = null;
  }

  void _route(PointerEvent event) {
    _lastPointerKind = event.kind;
    if (event is PointerDownEvent) {
      if (_downPointers.isEmpty) {
        _lastText = null;
      }
      _downPointers.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downPointers.remove(event.pointer);
      if (_downPointers.isEmpty) {
        _lastText = null;
      }
    }
  }
}

/// 选区内容变为 [text] 时调用：只要手还按着（不论按在文字上还是文字外）就震一下。
///
/// 内部按 [text] 去重：同一段选区反复回调不会持续震动；内容真的变化才震。
///
/// 调用方必须在**按下之前**就已开始跟踪（见 [SelectionPointerTracker.startTracking]
/// 在构建期被调用），否则第一个手势会被当成「没按着」。
void notifySelectionChanged(String? text) {
  final SelectionPointerTracker tracker = SelectionPointerTracker.instance
    ..startTracking();
  if (!tracker.isPressed) {
    return;
  }
  if (text == tracker._lastText) {
    return;
  }
  tracker._lastText = text;
  OhosSelectionHaptics.selectionTick();
}
