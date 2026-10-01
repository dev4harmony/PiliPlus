import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/utils/player_rebuild_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> log;
  late bool hasPlayer;
  late bool stale;
  late Future<void> Function() onRebuild;

  PlayerRebuildQueue create() => PlayerRebuildQueue(
    hasPlayer: () => hasPlayer,
    isStale: () => stale,
    rebuild: () async {
      log.add('rebuild');
      await onRebuild();
    },
    onError: (error, _) => log.add('error:$error'),
  );

  setUp(() {
    log = [];
    hasPlayer = true;
    stale = true;
    // 真实的重建会让「已生效」的渲染路径追上当前需要的那一条
    onRebuild = () async => stale = false;
  });

  test(
    'a rebuild requested during a load waits for the load to finish',
    () async {
      final queue = create();
      final load = Completer<void>();
      final loading = queue.run(() async {
        log.add('load:start');
        await load.future;
        log.add('load:end');
      });
      final rebuilding = queue.requestRebuild();
      await pumpEventQueue();
      expect(log, ['load:start']);
      load.complete();
      await Future.wait([loading, rebuilding]);
      expect(log, ['load:start', 'load:end', 'rebuild']);
    },
  );

  test('back-to-back requests rebuild once', () async {
    final queue = create();
    final gate = Completer<void>();
    onRebuild = () async {
      await gate.future;
      stale = false;
    };
    final first = queue.requestRebuild();
    final second = queue.requestRebuild();
    await pumpEventQueue();
    gate.complete();
    await Future.wait([first, second]);
    expect(log, ['rebuild']);
  });

  test(
    'a request that is no longer needed when its turn comes does nothing',
    () async {
      final queue = create();
      final load = Completer<void>();
      final loading = queue.run(() => load.future);
      final rebuilding = queue.requestRebuild();
      // 例如排队期间又退回了原来的全屏状态
      stale = false;
      load.complete();
      await Future.wait([loading, rebuilding]);
      expect(log, isEmpty);
    },
  );

  test('does nothing without a player', () async {
    hasPlayer = false;
    await create().requestRebuild();
    expect(log, isEmpty);
  });

  test('a failed rebuild is reported instead of thrown', () async {
    onRebuild = () async => throw StateError('boom');
    await create().requestRebuild();
    expect(log, ['rebuild', 'error:Bad state: boom']);
  });

  test('the next request retries a failed rebuild although the player is '
      'gone', () async {
    final queue = create();
    onRebuild = () {
      // 旧播放器已经 dispose，新的没建起来
      hasPlayer = false;
      return Future.error(StateError('boom'));
    };
    await queue.requestRebuild();
    onRebuild = () async {
      hasPlayer = true;
      stale = false;
    };
    await queue.requestRebuild();
    // 重试成功后不再欠着：之后没有播放器（例如页面已销毁）就不该再建
    hasPlayer = false;
    await queue.requestRebuild();
    expect(log, ['rebuild', 'error:Bad state: boom', 'rebuild']);
  });

  test('a player brought back by a later load cancels the retry', () async {
    final queue = create();
    onRebuild = () {
      hasPlayer = false;
      return Future.error(StateError('boom'));
    };
    await queue.requestRebuild();
    // setDataSource 按当前渲染路径建好了新播放器
    await queue.run(() async {
      hasPlayer = true;
      stale = false;
    });
    await queue.requestRebuild();
    hasPlayer = false;
    await queue.requestRebuild();
    expect(log, ['rebuild', 'error:Bad state: boom']);
  });

  test('an error handler that throws does not escape the request', () async {
    // 调用方都是 unawaited，漏出去就是未处理的异步异常
    final queue = PlayerRebuildQueue(
      hasPlayer: () => true,
      isStale: () => true,
      rebuild: () => Future.error(StateError('boom')),
      onError: (_, _) => throw StateError('toast failed'),
    );
    await expectLater(queue.requestRebuild(), completes);
  });

  test('tail completes only after every queued task has run', () async {
    // dispose 前要等在途的加载 / 重建收尾，靠的就是 tail
    final queue = create();
    expect(queue.tail, isNull);
    final load = Completer<void>();
    unawaited(queue.run(() => load.future));
    unawaited(queue.requestRebuild());
    var drained = false;
    unawaited(queue.tail!.then((_) => drained = true));
    await pumpEventQueue();
    expect(drained, isFalse);
    load.complete();
    await pumpEventQueue();
    expect(drained, isTrue);
    expect(log, ['rebuild']);
  });

  test('a failed load does not block the tasks queued behind it', () async {
    final queue = create();
    final failing = queue.run(() async => throw StateError('load failed'));
    final next = queue.run(() async => log.add('next'));
    await expectLater(failing, throwsStateError);
    await next;
    expect(log, ['next']);
  });
}
