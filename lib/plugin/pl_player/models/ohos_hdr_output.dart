import 'package:PiliPlus/models/common/video/video_quality.dart';

/// 鸿蒙 HDR 输出时传给 mpv 的两项参数：`--ohos-hdr-mode` 与 `--target-peak`。
///
/// 只有平台视图（全屏）能把 HDR 交给系统合成。纹理路径（内嵌、画中画）上
/// Flutter 会把视频当 sRGB 采样，所以那里必须让 mpv 自己色调映射到 SDR，
/// 与 media-kit 762fdc63 的做法一致；否则 PQ 画面会直接泛白。
abstract final class OhosHdrOutput {
  /// 传给 mpv 的 `--ohos-hdr-mode`，决定向鸿蒙上报哪种 HDR 类型。
  ///
  /// 只影响**信令**，不影响画面：`vo=gpu-next` 下 libplacebo 一定会跑一遍完整
  /// 渲染，没有任何「直通」路径。
  ///
  /// - SDR 片源：null，由 mpv 保持默认。
  /// - HDR 片源但不输出 HDR（开关关闭、面板明确不支持、或走纹理路径）：必须
  ///   显式发 `no`，**不能**返回 null。null 会让 media_kit 省掉这个属性，mpv 落回
  ///   默认的 `auto`，在 HDR 片源上照样输出 PQ。`no` 让 mpv 把画面映射到 SDR。
  /// - 原生 HDR Vivid：`vivid`。**不能用 `auto`**：auto 要靠 ohos_common.c 从帧
  ///   的 CUVA side data 认出片源，而鸿蒙硬解不解析 SEI，auto 会一路落到 hdr10。
  ///   面板能力**未知**时按支持处理，只有明确查到不支持才退回 hdr10。
  /// - 杜比视界：鸿蒙没有 DV 信令。libplacebo 应用 RPU 后画面已是成品 PQ，
  ///   按 Vivid 上报只是借标签让面板拉峰值亮度，画面仍是杜比视界。它自己没有
  ///   CUVA 载荷，所以反过来取保守口径：没有确证支持就上报 hdr10。
  /// - HDR10 / HDR10+：如实上报 hdr10。HDR10+ 是 ST 2094-40，与 Vivid 的 CUVA
  ///   没有转换关系，贴错标签只会让合成器丢弃或误解析。
  static String? mode({
    required VideoQuality? quality,
    required bool hdrPlayback,
    required bool platformView,
    required bool displayMaySupportVivid,
    required bool displaySupportsVivid,
  }) {
    if (quality == null || !quality.isHDR) {
      return null;
    }
    if (!hdrPlayback || !platformView) {
      return 'no';
    }
    if (quality.isHDRVivid) {
      return displayMaySupportVivid ? 'vivid' : 'hdr10';
    }
    if (quality.isDolbyVision) {
      return displaySupportsVivid ? 'vivid' : 'hdr10';
    }
    return 'hdr10';
  }

  /// 传给 mpv 的 `--target-peak`（面板峰值亮度，nit）。
  ///
  /// HDR 输出时必须给：`gpu-next` 一定会做色调映射，不给的话 libplacebo 按 PQ
  /// 的名义峰值 10000 nit 反推，高光被无谓地压暗。SDR 输出（纹理路径）时
  /// 反过来必须不给：SDR 目标配上上千 nit 的峰值，整幅画面都会被压暗。
  static double? targetPeak({
    required bool hdrPlayback,
    required bool platformView,
    required int peakNits,
  }) => hdrPlayback && platformView ? peakNits.toDouble() : null;
}
