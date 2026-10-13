import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/plugin/pl_player/models/ohos_hdr_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hdrTiers = [
    VideoQuality.hdr,
    VideoQuality.hdrVivid,
    VideoQuality.dolbyVision,
  ];

  // 默认：面板支持 HDR Vivid，HDR 片源，开着「匹配视频亮度」
  OhosOutput output({
    VideoQuality? quality = VideoQuality.hdr,
    bool hdrEnabled = true,
    bool displayHasNoHdr = false,
    bool maySupportVivid = true,
    bool pipMode = false,
    int peakNits = 1000,
    bool matchVideo = true,
  }) => OhosHdrOutput.output(
    hdrEnabled: hdrEnabled,
    quality: quality,
    displayHasNoHdr: displayHasNoHdr,
    displayMaySupportVivid: maySupportVivid,
    pipMode: pipMode,
    peakNits: peakNits,
    matchVideo: matchVideo,
  );

  const hdrOutput = (platformView: true, hdrMode: 'auto', targetPeak: null);
  const textureOutput = (platformView: false, hdrMode: 'no', targetPeak: null);

  group('OhosHdrOutput.output', () {
    test('gives every HDR tier the same output, so tier switches keep the '
        'player', () {
      // HDR 类型由 mpv 读码流决定，几档 HDR 之间切换不必重建播放器
      final outputs = {
        for (final quality in hdrTiers) output(quality: quality),
      };
      expect(outputs, hasLength(1));
      expect(outputs.single, hdrOutput);
    });

    test('keeps SDR tiers and an unknown quality on the texture path', () {
      // 纹理会被 Flutter 当成 sRGB 采样，PQ 画面直接泛白，所以显式发 no
      expect(output(quality: VideoQuality.super4K), textureOutput);
      expect(output(quality: VideoQuality.high1080), textureOutput);
      expect(output(quality: null), textureOutput);
    });

    test('differs between SDR and HDR sources, so that switch rebuilds', () {
      expect(output(quality: VideoQuality.high1080), isNot(output()));
    });

    test('turns HDR off explicitly when HDR playback is disabled', () {
      expect(output(hdrEnabled: false), textureOutput);
      expect(output(hdrEnabled: false, maySupportVivid: false), textureOutput);
    });

    test('stays on the texture path on a panel known to lack HDR', () {
      expect(output(displayHasNoHdr: true), textureOutput);
    });

    test('falls back to the texture path in picture-in-picture', () {
      // PiP 是另一块 XComponent，平台视图跟不过去
      expect(output(pipMode: true), textureOutput);
      expect(output(pipMode: true, maySupportVivid: false), textureOutput);
    });

    test('sticks to static HDR10 signalling on panels without HDR Vivid', () {
      expect(
        output(maySupportVivid: false),
        (platformView: true, hdrMode: 'hdr10', targetPeak: null),
      );
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

    test('leaves the peak to mpv on the texture path', () {
      // SDR 输出配上上千 nit 的目标峰值，libplacebo 会把整幅画面压暗
      expect(
        output(quality: VideoQuality.high1080, matchVideo: false),
        textureOutput,
      );
      expect(output(hdrEnabled: false, matchVideo: false), textureOutput);
      expect(output(displayHasNoHdr: true, matchVideo: false), textureOutput);
      expect(output(pipMode: true, matchVideo: false), textureOutput);
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
