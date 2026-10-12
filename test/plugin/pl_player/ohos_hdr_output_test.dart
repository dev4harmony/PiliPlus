import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/plugin/pl_player/models/ohos_hdr_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? mode(
    VideoQuality? quality, {
    bool hdrPlayback = true,
    bool platformView = true,
    bool maySupportVivid = true,
    bool supportsVivid = true,
  }) => OhosHdrOutput.mode(
    quality: quality,
    hdrPlayback: hdrPlayback,
    platformView: platformView,
    displayMaySupportVivid: maySupportVivid,
    displaySupportsVivid: supportsVivid,
  );

  group('OhosHdrOutput.mode', () {
    test('leaves SDR sources to mpv', () {
      expect(mode(null), isNull);
      expect(mode(VideoQuality.super4K), isNull);
      expect(mode(VideoQuality.high1080, platformView: false), isNull);
    });

    test('turns HDR off explicitly when HDR playback is disabled', () {
      expect(mode(VideoQuality.hdr, hdrPlayback: false), 'no');
      expect(mode(VideoQuality.hdrVivid, hdrPlayback: false), 'no');
      expect(mode(VideoQuality.dolbyVision, hdrPlayback: false), 'no');
    });

    test('keeps the texture path in SDR so Flutter never shows raw PQ', () {
      // 内嵌 / 画中画：纹理会被 Flutter 当成 sRGB 采样，PQ 画面直接泛白
      expect(mode(VideoQuality.hdr, platformView: false), 'no');
      expect(mode(VideoQuality.hdrVivid, platformView: false), 'no');
      expect(mode(VideoQuality.dolbyVision, platformView: false), 'no');
    });

    test('reports HDR10 as hdr10 on the platform view', () {
      expect(mode(VideoQuality.hdr), 'hdr10');
    });

    test('reports native Vivid as vivid unless the panel rules it out', () {
      expect(mode(VideoQuality.hdrVivid), 'vivid');
      expect(mode(VideoQuality.hdrVivid, maySupportVivid: false), 'hdr10');
    });

    test('borrows the Vivid tag for Dolby Vision only when confirmed', () {
      expect(mode(VideoQuality.dolbyVision), 'vivid');
      expect(mode(VideoQuality.dolbyVision, supportsVivid: false), 'hdr10');
    });
  });

  group('OhosHdrOutput.targetPeak', () {
    test('passes the panel peak on the platform view', () {
      expect(
        OhosHdrOutput.targetPeak(
          hdrPlayback: true,
          platformView: true,
          peakNits: 1000,
        ),
        1000.0,
      );
    });

    test('leaves the peak to mpv on the texture path', () {
      // SDR 输出配上 1600 nit 的目标峰值，libplacebo 会把整幅画面压暗
      expect(
        OhosHdrOutput.targetPeak(
          hdrPlayback: true,
          platformView: false,
          peakNits: 1000,
        ),
        isNull,
      );
    });

    test('leaves the peak to mpv when HDR playback is disabled', () {
      expect(
        OhosHdrOutput.targetPeak(
          hdrPlayback: false,
          platformView: false,
          peakNits: 1000,
        ),
        isNull,
      );
    });
  });

  group('OhosHdrOutput.targetPeak matching the video', () {
    // mpv 的 sig-peak 以 SDR 参考白 203 nit 为 1
    double sigPeak(double nits) => nits / 203;

    double? target({
      double? videoSigPeak,
      bool matchVideo = true,
      bool platformView = true,
    }) => OhosHdrOutput.targetPeak(
      hdrPlayback: true,
      platformView: platformView,
      peakNits: 1000,
      matchVideo: matchVideo,
      videoSigPeak: videoSigPeak,
    );

    test('follows the peak in the stream metadata', () {
      expect(target(videoSigPeak: sigPeak(4000)), 4000.0);
      expect(target(videoSigPeak: sigPeak(1600)), 1600.0);
    });

    test('uses the reference when the stream carries no peak', () {
      // 没有 HDR10 元数据时 mpv 把 PQ 片源记成名义峰值 10000 nit
      expect(target(videoSigPeak: sigPeak(10000)), 1000.0);
      expect(target(videoSigPeak: null), 1000.0);
      expect(target(videoSigPeak: 0), 1000.0);
    });

    test('ignores a peak below what mpv accepts', () {
      expect(target(videoSigPeak: sigPeak(5)), 1000.0);
    });

    test('keeps the setting when matching is off', () {
      expect(target(videoSigPeak: sigPeak(4000), matchVideo: false), 1000.0);
    });

    test('still leaves the texture path to mpv', () {
      expect(target(videoSigPeak: sigPeak(4000), platformView: false), isNull);
    });
  });

  group('OhosHdrOutput.videoPeakNits', () {
    test('converts sig-peak to whole nits', () {
      expect(OhosHdrOutput.videoPeakNits(1000 / 203), 1000);
    });

    test('treats the PQ nominal peak as unknown', () {
      expect(OhosHdrOutput.videoPeakNits(10000 / 203), isNull);
    });
  });
}
