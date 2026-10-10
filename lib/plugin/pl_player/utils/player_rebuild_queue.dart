/// 播放器初始化与渲染路径重建共用的串行队列。
///
/// setDataSource 和渲染路径重建（进出全屏、画中画切换平台视图 / 纹理或 HDR
/// 信令）都会 dispose 旧 Player 再建新的。两者交错执行时，同一个 Player 会被
/// dispose 两次，还会多建出一个没人持有的 Player，所以一律排进 [run]。
///
/// 重建请求到了队头才判断 [isStale]：排队期间状态可能已经变回去（例如快速
/// 进出全屏），请求时的判断到执行时就过期了。
///
/// 重建失败交给 [onError]，并记下待重试：旧播放器此时通常已经 dispose，
/// 下一次请求即使没有播放器也要再建一次，否则会一直停在黑屏上。
class PlayerRebuildQueue {
  PlayerRebuildQueue({
    required this.hasPlayer,
    required this.isStale,
    required this.rebuild,
    required this.onError,
  });

  final bool Function() hasPlayer;

  /// 已生效的渲染路径与当前需要的不一致。
  final bool Function() isStale;
  final Future<void> Function() rebuild;
  final void Function(Object error, StackTrace stackTrace) onError;

  Future<void>? _tail;
  bool _retryPending = false;

  /// 队尾任务；全部排队任务执行完才完成。dispose 前用它等在途任务收尾。
  Future<void>? get tail => _tail;

  /// 排在队尾执行 [task]。前一个任务失败不阻塞本次。
  Future<void> run(Future<void> Function() task) {
    final previous = _tail;
    final run = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // 前一个任务失败不阻塞本次
        }
      }
      await task();
    }();
    _tail = run;
    return run;
  }

  /// 请求按当前状态重建播放器；不需要时什么都不做。
  Future<void> requestRebuild() => run(() async {
    if (hasPlayer()) {
      if (!isStale()) {
        _retryPending = false;
        return;
      }
    } else if (!_retryPending) {
      return;
    }
    try {
      await rebuild();
      _retryPending = false;
    } catch (e, s) {
      _retryPending = true;
      try {
        onError(e, s);
      } catch (_) {
        // 调用方都是 unawaited，报错本身再失败（例如退出途中弹不出 toast）
        // 也不能变成未处理的异步异常
      }
    }
  });
}
