import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/utils/platform_video_backdrop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  late RxBool rx;
  late List<String> sent;
  late Completer<void> frame;
  late bool alive;

  PlatformVideoBackdrop create({bool enabled = true}) => PlatformVideoBackdrop(
    rx: rx,
    enabled: enabled,
    isAlive: () => alive,
    // 记录发送瞬间 rx 的值，用来断言先后顺序
    send: (active) async => sent.add('$active@rx=${rx.value}'),
    nextFrame: () => frame.future,
  );

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    rx = false.obs;
    sent = [];
    frame = Completer<void>();
    alive = true;
  });

  test('off Harmony only writes rx and never talks to ArkTS', () async {
    create(enabled: false)
      ..update(true)
      ..update(false)
      ..reset();
    frame.complete();
    await flush();
    expect(rx.value, isFalse);
    expect(sent, isEmpty);
  });

  test('entering sends true before Flutter turns transparent', () {
    create().update(true);
    expect(sent, ['true@rx=false']);
    expect(rx.value, isTrue);
  });

  test('leaving turns Flutter opaque first and restores the root after the '
      'frame', () async {
    final backdrop = create()..update(true);
    sent.clear();
    backdrop.update(false);
    expect(rx.value, isFalse);
    await flush();
    expect(sent, isEmpty);
    frame.complete();
    await flush();
    expect(sent, ['false@rx=false']);
  });

  test('re-entering before the frame drops the pending false', () async {
    create()
      ..update(true)
      ..update(false)
      ..update(true);
    frame.complete();
    await flush();
    expect(sent, ['true@rx=false', 'true@rx=false']);
    expect(rx.value, isTrue);
  });

  test('a rebuild that finishes after dispose cannot turn the root black', () {
    alive = false;
    create().update(true);
    expect(sent, isEmpty);
    expect(rx.value, isTrue);
  });

  test('after dispose the pending false is dropped because reset already '
      'sent it', () async {
    final backdrop = create()
      ..update(true)
      ..update(false);
    alive = false;
    backdrop.reset();
    frame.complete();
    await flush();
    expect(sent, ['true@rx=false', 'false@rx=false']);
  });

  // 返回主页（onCloseAll）会在全屏状态下直接 dispose：若只发 false 而 rx 仍为
  // true，Flutter 各层还是透明的，根 Stack 却已恢复为白色，退出途中闪白边。
  test('reset makes Flutter opaque before restoring the root', () {
    create()
      ..update(true)
      ..reset();
    expect(rx.value, isFalse);
    expect(sent, ['true@rx=false', 'false@rx=false']);
  });
}
