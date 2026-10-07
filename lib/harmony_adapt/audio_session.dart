import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';

/// Same-application native audio policy, including mpv's OHAudio renderer.
/// Only the HarmonyOS audio handler uses this channel; other platforms continue
/// to use audio_session. Never suppress mandatory system interruptions.
abstract final class HarmonyAudioSession {
  static final _interruptions =
      StreamController<AudioInterruptionEvent>.broadcast();
  static final _channel = const MethodChannel('pili/audio_session')
    ..setMethodCallHandler((call) async {
      if (call.method == 'onDeactivated') {
        // API 12: 0 = lower priority (mandatory loss), 1 = idle timeout.
        // Unknown future reasons are conservatively treated as focus loss.
        final timedOut = call.arguments == 1;
        _interruptions.add(
          AudioInterruptionEvent(
            !timedOut,
            timedOut
                ? AudioInterruptionType.unknown
                : AudioInterruptionType.pause,
          ),
        );
      }
    });

  static Stream<AudioInterruptionEvent> get interruptionEventStream =>
      _interruptions.stream;

  static Future<bool> setActive(
    bool active, {
    required bool mixWithOthers,
  }) async =>
      await _channel.invokeMethod<bool>('setActive', {
        'active': active,
        'mixWithOthers': mixWithOthers,
      }) ??
      false;
}
