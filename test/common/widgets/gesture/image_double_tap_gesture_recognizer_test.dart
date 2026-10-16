import 'package:PiliPlus/common/widgets/gesture/image_double_tap_gesture_recognizer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ImageDoubleTapGestureRecognizer recognizer;
  late int doubleTaps;

  Future<void> pumpTarget(WidgetTester tester) {
    return tester.pumpWidget(
      Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: recognizer.addPointer,
        child: const SizedBox.expand(),
      ),
    );
  }

  Future<void> tap(
    WidgetTester tester,
    int pointer, {
    required Duration down,
    required Duration up,
  }) async {
    final testPointer = TestPointer(pointer);
    await tester.sendEventToBinding(
      testPointer.down(const Offset(10, 10), timeStamp: down),
    );
    await tester.pump(up - down);
    await tester.sendEventToBinding(testPointer.up(timeStamp: up));
  }

  setUp(() {
    doubleTaps = 0;
    recognizer = ImageDoubleTapGestureRecognizer()
      ..onDoubleTap = () => doubleTaps++;
  });

  tearDown(() => recognizer.dispose());

  testWidgets('records the second tap up time when a double tap fires', (
    tester,
  ) async {
    await pumpTarget(tester);

    await tap(
      tester,
      1,
      down: const Duration(milliseconds: 10),
      up: const Duration(milliseconds: 60),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tap(
      tester,
      2,
      down: const Duration(milliseconds: 160),
      up: const Duration(milliseconds: 210),
    );
    await tester.pumpAndSettle();

    expect(doubleTaps, 1);
    expect(recognizer.timeStamp, const Duration(milliseconds: 210));
  });

  testWidgets('a single tap leaves the time stamp untouched', (tester) async {
    await pumpTarget(tester);

    await tap(
      tester,
      1,
      down: const Duration(milliseconds: 10),
      up: const Duration(milliseconds: 60),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(doubleTaps, 0);
    expect(recognizer.timeStamp, Duration.zero);
  });

  test('is not allowed to track pointers without a double tap callback', () {
    final idle = ImageDoubleTapGestureRecognizer();
    addTearDown(idle.dispose);

    expect(idle.onDoubleTap, isNull);
    expect(
      idle.isPointerAllowed(const PointerDownEvent(buttons: kPrimaryButton)),
      isFalse,
    );
  });
}
