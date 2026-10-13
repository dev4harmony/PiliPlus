import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/plugin/pl_player/models/ohos_hdr_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hdrTiers = [
    VideoQuality.hdr,
    VideoQuality.hdrVivid,
    VideoQuality.dolbyVision,
  ];

  bool playback(
    VideoQuality? quality, {
    bool enabled = true,
    bool displayHasNoHdr = false,
  }) => OhosHdrOutput.hdrPlayback(
    enabled: enabled,
    quality: quality,
    displayHasNoHdr: displayHasNoHdr,
  );

  OhosOutput output({
    bool hdrPlayback = true,
    bool pipMode = false,
    bool maySupportVivid = true,
    int peakNits = 1000,
    bool matchVideo = true,
  }) => OhosHdrOutput.output(
    hdrPlayback: hdrPlayback,
    pipMode: pipMode,
    displayMaySupportVivid: maySupportVivid,
    peakNits: peakNits,
    matchVideo: matchVideo,
  );

  const textureOutput = (platformView: false, hdrMode: 'no', targetPeak: null);

  group('OhosHdrOutput.hdrPlayback', () {
    test('treats every HDR tier as HDR', () {
      for (final quality in hdrTiers) {
        expect(playback(quality), isTrue, reason: quality.name);
      }
    });

    test('keeps SDR tiers and an unknown quality in SDR', () {
      expect(playback(VideoQuality.super4K), isFalse);
      expect(playback(VideoQuality.high1080), isFalse);
      expect(playback(null), isFalse);
    });

    test('stays in SDR when HDR playback is switched off', () {
      expect(playback(VideoQuality.hdr, enabled: false), isFalse);
    });

    test('stays in SDR on a panel known to lack HDR', () {
      expect(playback(VideoQuality.hdr, displayHasNoHdr: true), isFalse);
    });
  });

  group('OhosHdrOutput.output', () {
    test('gives every HDR tier the same output, so tier switches keep the '
        'player', () {
      // HDR 类型由 mpv 读码流决定，几档 HDR 之间切换不必重建播放器
      final outputs = {
        for (final quality in hdrTiers) output(hdrPlayback: playback(quality)),
      };
      expect(outputs, hasLength(1));
      expect(
        outputs.single,
        (platformView: true, hdrMode: 'auto', targetPeak: null),
      );
    });

    test('differs between SDR and HDR sources, so that switch rebuilds', () {
      expect(output(hdrPlayback: false), textureOutput);
      expect(output(hdrPlayback: false), isNot(output()));
    });

    test('falls back to the texture path in picture-in-picture', () {
      // PiP 是另一块 XComponent，平台视图跟不过去
      expect(output(pipMode: true), textureOutput);
    });

    test('sticks to static HDR10 signalling on panels without HDR Vivid', () {
      expect(output(maySupportVivid: false).hdrMode, 'hdr10');
    });

    test('follows the peak setting once matching the video is off', () {
      expect(
        output(matchVideo: false),
        (platformView: true, hdrMode: 'auto', targetPeak: 1000.0),
      );
      expect(output(matchVideo: false), isNot(output()));
      expect(
        output(matchVideo: false, peakNits: 1200),
        isNot(output(matchVideo: false)),
      );
    });
  });

  group('OhosHdrOutput.mode', () {
    String mode({
      bool hdrPlayback = true,
      bool platformView = true,
      bool maySupportVivid = true,
    }) => OhosHdrOutput.mode(
      hdrPlayback: hdrPlayback,
      platformView: platformView,
      displayMaySupportVivid: maySupportVivid,
    );

    test('lets mpv signal HDR from the bitstream on the platform view', () {
      // 杜比视界、HDR10+、HDR Vivid、HDR10 都由 mpv 按码流里的元数据决定
      expect(mode(), 'auto');
    });

    test('sticks to static HDR10 signalling on panels without HDR Vivid', () {
      expect(mode(maySupportVivid: false), 'hdr10');
    });

    test('turns HDR off explicitly when HDR playback is disabled', () {
      expect(mode(hdrPlayback: false), 'no');
      expect(mode(hdrPlayback: false, maySupportVivid: false), 'no');
    });

    test('keeps the texture path in SDR so Flutter never shows raw PQ', () {
      // SDR 片源、画中画：纹理会被 Flutter 当成 sRGB 采样，PQ 画面直接泛白
      expect(mode(platformView: false), 'no');
      expect(mode(platformView: false, maySupportVivid: false), 'no');
    });
  });

  group('OhosHdrOutput.targetPeak', () {
    double? target({
      bool hdrPlayback = true,
      bool platformView = true,
      bool matchVideo = false,
    }) => OhosHdrOutput.targetPeak(
      hdrPlayback: hdrPlayback,
      platformView: platformView,
      peakNits: 1000,
      matchVideo: matchVideo,
    );

    test('passes the setting on the platform view', () {
      expect(target(), 1000.0);
    });

    test('passes no peak when matching the video', () {
      // 不传时 mpv 以片源自身的峰值为目标，高光不会被压缩
      expect(target(matchVideo: true), isNull);
    });

    test('leaves the peak to mpv on the texture path', () {
      // SDR 输出配上上千 nit 的目标峰值，libplacebo 会把整幅画面压暗
      expect(target(platformView: false), isNull);
      expect(target(platformView: false, matchVideo: true), isNull);
    });

    test('leaves the peak to mpv when HDR playback is disabled', () {
      expect(target(hdrPlayback: false), isNull);
      expect(target(hdrPlayback: false, platformView: false), isNull);
    });
  });

  group('OhosHdrOutput.measuresPeak', () {
    test('measures the real peak when tone mapping to the setting', () {
      // 有的 HDR10 片源标 1000 nit，画面却到 10000 nit：只信元数据的话，比它
      // 亮的部分要么被压成一片，要么原样交给屏幕截断
      expect(OhosHdrOutput.measuresPeak(output(matchVideo: false)), isTrue);
    });

    test('leaves the peak alone when matching the video', () {
      // 匹配视频亮度时目标就是片源自己标的峰值；测出更高的峰值反而会让 mpv
      // 压缩画面，违背不做变换的约定
      expect(OhosHdrOutput.measuresPeak(output()), isFalse);
    });

    test('does not measure on the texture path or other platforms', () {
      expect(OhosHdrOutput.measuresPeak(textureOutput), isFalse);
      expect(
        OhosHdrOutput.measuresPeak(output(matchVideo: false, pipMode: true)),
        isFalse,
      );
      expect(OhosHdrOutput.measuresPeak(null), isFalse);
    });
  });
}
