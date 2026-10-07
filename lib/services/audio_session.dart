import 'package:PiliPlus/harmony_adapt/audio_session.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:os_type/os_type.dart';

class AudioSessionHandler {
  late AudioSession session;
  bool _playInterrupted = false;
  late final Future<void> _ready;

  Future<bool> setActive(bool active) async {
    // AudioSession 的策略作用于同应用的原生音频流（包括 mpv/OHAudio）。
    // 必须在音频流启动前完成激活；关闭开关时沿用插件原有的暂停其他应用策略。
    if (OS.isHarmony) {
      // 不走 fork 的 setActive：它没有真正停用原生会话，并会重复注册监听。
      try {
        await _ready;
        return await HarmonyAudioSession.setActive(
          active,
          mixWithOthers: Pref.allowConcurrentPlayback,
        );
      } catch (error) {
        // Autoplay/pause can be fire-and-forget. A failed native request must not
        // become an unhandled error or prevent final player cleanup.
        debugPrint('HarmonyOS audio session request failed: $error');
        return false;
      }
    }
    await _ready;
    return session.setActive(active);
  }

  AudioSessionHandler() {
    _ready = initSession();
  }

  Future<void> initSession() async {
    session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    (OS.isHarmony
            ? HarmonyAudioSession.interruptionEventStream
            : session.interruptionEventStream)
        .listen((event) {
          final playerStatus = PlPlayerController.getPlayerStatusIfExists();
          // final player = PlPlayerController.getInstance();
          if (event.begin) {
            if (OS.isHarmony && event.type != AudioInterruptionType.duck) {
              // Focus can be lost while activation is pending and UI still says
              // paused. Cancel that pending start even when there is nothing to pause.
              PlPlayerController.cancelPendingPlayOnInterruption();
            }
            if (playerStatus != PlayerStatus.playing) return;
            // if (!player.playerStatus.playing) return;
            switch (event.type) {
              case AudioInterruptionType.duck:
                PlPlayerController.setVolumeIfExists(
                  (PlPlayerController.getVolumeIfExists() ?? 0) * 0.5,
                  showIndicator: false,
                );
                // player.setVolume(player.volume.value * 0.5);
                break;
              case AudioInterruptionType.pause:
                PlPlayerController.pauseIfExists(isInterrupt: true);
                // player.pause(isInterrupt: true);
                _playInterrupted = true;
                break;
              case AudioInterruptionType.unknown:
                PlPlayerController.pauseIfExists(isInterrupt: true);
                // player.pause(isInterrupt: true);
                _playInterrupted = true;
                break;
            }
          } else {
            switch (event.type) {
              case AudioInterruptionType.duck:
                PlPlayerController.setVolumeIfExists(
                  (PlPlayerController.getVolumeIfExists() ?? 0) * 2,
                  showIndicator: false,
                );
                // player.setVolume(player.volume.value * 2);
                break;
              case AudioInterruptionType.pause:
                if (_playInterrupted) PlPlayerController.playIfExists();
                //player.play();
                break;
              case AudioInterruptionType.unknown:
                break;
            }
            _playInterrupted = false;
          }
        });

    // 耳机拔出暂停
    session.becomingNoisyEventStream.listen((_) {
      PlPlayerController.pauseIfExists();
      // final player = PlPlayerController.getInstance();
      // if (player.playerStatus.playing) {
      //   player.pause();
      // }
    });
  }
}
