import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/utils/mpv_handle_releaser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> log;
  late List<(Duration, void Function())> timers;

  MpvHandleReleaser create() => MpvHandleReleaser(
    detachEvents: () => log.add('detach'),
    quit: () => log.add('quit'),
    destroy: () => log.add('destroy'),
    schedule: (duration, callback) {
      timers.add((duration, callback));
      return Timer(Duration.zero, () {});
    },
  );

  void fireTimers() {
    final pending = [...timers];
    timers.clear();
    for (final (_, callback) in pending) {
      callback();
    }
  }

  setUp(() {
    log = [];
    timers = [];
  });

  test('never destroys the handle synchronously', () {
    create().release(quitCore: false);

    expect(log, ['detach']);
    expect(timers, hasLength(1));
  });

  test('defers destroy by the same delay media_kit NativePlayer uses', () {
    create().release(quitCore: false);

    expect(timers.single.$1, const Duration(seconds: 5));
  });

  test('destroys the handle only after events are detached', () {
    create().release(quitCore: false);
    fireTimers();

    expect(log, ['detach', 'destroy']);
  });

  test('asks a core that is still transcoding to quit right away', () {
    create().release(quitCore: true);

    expect(log, ['detach', 'quit']);
    fireTimers();
    expect(log, ['detach', 'quit', 'destroy']);
  });

  test('does not send quit to a core that already shut down', () {
    create().release(quitCore: false);
    fireTimers();

    expect(log, isNot(contains('quit')));
  });

  test('a shutdown racing a cancel releases the handle once', () {
    create()
      ..release(quitCore: false)
      ..release(quitCore: true);
    fireTimers();

    expect(log, ['detach', 'destroy']);
  });
}
