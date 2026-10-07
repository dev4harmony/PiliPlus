import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/harmony_adapt/audio_session.dart';
import 'package:PiliPlus/services/audio_session.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  const ohosChannel = MethodChannel('pili/audio_session');
  final calls = <MethodCall>[];
  bool failNativeRequest = false;
  late Directory tempDir;
  AudioSessionHandler? handler;
  AudioSessionHandler getHandler() => handler ??= AudioSessionHandler();
  late Completer<void> configurationReady;

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.ohos;
    tempDir = await Directory.systemTemp.createTemp('piliplus-audio-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox<dynamic>('setting');
    configurationReady = Completer<void>()..complete();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(sessionChannel, (
      call,
    ) async {
      if (call.method == 'getConfiguration') return null;
      if (call.method == 'setConfiguration') {
        await configurationReady.future;
      }
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(ohosChannel, (
      call,
    ) async {
      calls.add(call);
      if (failNativeRequest) {
        throw PlatformException(code: 'audio_session_error', message: 'denied');
      }
      return true;
    });
  });

  setUp(() async {
    calls.clear();
    failNativeRequest = false;
    await GStorage.setting.clear();
  });

  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sessionChannel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(ohosChannel, null);
    debugDefaultTargetPlatformOverride = null;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('activation waits for asynchronous session configuration', () async {
    configurationReady = Completer<void>();
    final activation = getHandler().setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);

    configurationReady.complete();
    expect(await activation, isTrue);
    expect(calls.first.method, 'setActive');
  });

  test('default-off retains the existing pause-others policy', () async {
    expect(Pref.allowConcurrentPlayback, isFalse);
    expect(await getHandler().setActive(true), isTrue);
    expect(calls.first.arguments, {'active': true, 'mixWithOthers': false});
  });

  test('enabled preference activates the HarmonyOS mix policy', () async {
    await GStorage.setting.put(SettingBoxKey.allowConcurrentPlayback, true);
    expect(Pref.allowConcurrentPlayback, isTrue);
    expect(await getHandler().setActive(true), isTrue);
    expect(calls.first.arguments, {'active': true, 'mixWithOthers': true});
  });

  test('disabling restores pause-others on the next activation', () async {
    await GStorage.setting.put(SettingBoxKey.allowConcurrentPlayback, true);
    await getHandler().setActive(true);
    await GStorage.setting.put(SettingBoxKey.allowConcurrentPlayback, false);
    calls.clear();
    await getHandler().setActive(true);
    expect(calls.first.arguments, {'active': true, 'mixWithOthers': false});
  });

  test('explicit pause still forwards the deactivation request', () async {
    await GStorage.setting.put(SettingBoxKey.allowConcurrentPlayback, true);
    expect(await getHandler().setActive(false), isTrue);
    expect(calls.first.method, 'setActive');
    expect(calls.first.arguments, {'active': false, 'mixWithOthers': true});
  });

  test(
    'native request failures are handled without hanging playback',
    () async {
      failNativeRequest = true;
      expect(await getHandler().setActive(true), isFalse);
      expect(await getHandler().setActive(false), isFalse);
      failNativeRequest = false;
      expect(await getHandler().setActive(true), isTrue);
    },
  );

  test('mandatory focus loss is still delivered in mixing mode', () async {
    await GStorage.setting.put(SettingBoxKey.allowConcurrentPlayback, true);
    await getHandler().setActive(true);
    final interruption = HarmonyAudioSession.interruptionEventStream.first;
    binding.defaultBinaryMessenger.handlePlatformMessage(
      'pili/audio_session',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onDeactivated', 0),
      ),
      (_) {},
    );
    final event = await interruption;
    expect(event.begin, isTrue);
    expect(event.type, AudioInterruptionType.pause);
  });

  test('idle timeout is not reported as a new interruption', () async {
    await getHandler().setActive(false);
    final interruption = HarmonyAudioSession.interruptionEventStream.first;
    binding.defaultBinaryMessenger.handlePlatformMessage(
      'pili/audio_session',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onDeactivated', 1),
      ),
      (_) {},
    );
    final event = await interruption;
    expect(event.begin, isFalse);
    expect(event.type, AudioInterruptionType.unknown);
  });

  test(
    'the preference survives closing and reopening the settings box',
    () async {
      // Use an independent box so test order/filtering doesn't close the global
      // late-final settings box used by the other tests.
      final persisted = await Hive.openBox<dynamic>('persisted-setting');
      await persisted.put(SettingBoxKey.allowConcurrentPlayback, true);
      await persisted.close();
      final reopened = await Hive.openBox<dynamic>('persisted-setting');
      expect(reopened.get(SettingBoxKey.allowConcurrentPlayback), isTrue);
      await reopened.close();
    },
  );
}
