import 'dart:async';

/// 释放挂着事件循环的 mpv_handle，保证不在事件循环底下销毁它。
///
/// media_kit 的 Initializer 在 [detachEvents] 之后仍会再碰一次 handle：
/// Isolate 实现要等被 mpv_wakeup 唤醒后才退出 mpv_wait_event 循环，
/// NativeCallable 实现则在当前事件回调返回后继续 mpv_wait_event。这时
/// mpv_terminate_destroy 若已同步执行，就是 use-after-free（动态截图闪退）。
/// 所以 [destroy] 一律延后 [destroyDelay]，与 media_kit NativePlayer.dispose
/// 的做法一致，也就不会在 MPV_EVENT_SHUTDOWN 的回调里同步销毁 handle。
///
/// [release] 只生效一次：转码结束与用户取消可能先后到达，重复
/// mpv_terminate_destroy 是 double free。
class MpvHandleReleaser {
  MpvHandleReleaser({
    required this.detachEvents,
    required this.quit,
    required this.destroy,
    this.schedule = Timer.new,
  });

  /// 与 media_kit NativePlayer.dispose 延后 mpv_terminate_destroy 的时长一致。
  static const destroyDelay = Duration(seconds: 5);

  /// 停止事件回调（Initializer.dispose）。
  final void Function() detachEvents;

  /// 让仍在转码的 core 立刻退出，免得延后销毁期间继续占用 CPU。
  final void Function() quit;

  /// mpv_terminate_destroy。
  final void Function() destroy;

  final Timer Function(Duration duration, void Function() callback) schedule;

  bool _released = false;

  /// [quitCore]：core 仍在运行（用户取消）时为 true；收到
  /// MPV_EVENT_SHUTDOWN 后 core 已在退出，传 false。
  void release({required bool quitCore}) {
    if (_released) return;
    _released = true;
    detachEvents();
    if (quitCore) quit();
    schedule(destroyDelay, destroy);
  }
}
