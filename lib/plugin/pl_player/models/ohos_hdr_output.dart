import 'package:PiliPlus/models/common/video/video_quality.dart';

/// 创建 Player 时就固定、之后改不了的鸿蒙视频输出：
/// - `platformView`：画面走平台视图（XComponent）还是 Flutter 纹理；
/// - `hdrMode`：传给 mpv 的 `--ohos-hdr-mode`；
/// - `targetPeak`：传给 mpv 的 `--target-peak`（nit），null 表示不传。
///
/// 与当前播放器的不一致就得重建播放器；record 按值比较，可以直接拿来判断。
typedef OhosOutput = ({bool platformView, String hdrMode, double? targetPeak});

/// 鸿蒙上的视频输出规则。
///
/// 只有平台视图能把 HDR 交给系统合成。纹理路径（SDR 片源、画中画）上 Flutter
/// 会把视频当 sRGB 采样，所以那里必须让 mpv 自己色调映射到 SDR，与
/// media-kit 762fdc63 的做法一致；否则 PQ 画面会直接泛白。
abstract final class OhosHdrOutput {
  /// 按设置、片源与面板能力决定 [OhosOutput]。
  ///
  /// 按 HDR 输出需要：开着「启用 HDR 视频」（[hdrEnabled]）、片源是 HDR 档位，
  /// 且面板没有**明确**表示不支持 HDR（[displayHasNoHdr]；能力未知按支持处理，
  /// 免得一次偶发的查询失败就把 HDR 关掉）。只看档位是不是 HDR：具体是哪种 HDR
  /// 由 mpv 读码流决定，所以几档 HDR 的输出完全一样，彼此切换不必重建播放器。
  ///
  /// **platformView**：HDR 片源走平台视图，与全屏状态无关，进出全屏不必重建
  /// 播放器。画中画除外：PiP 是另一块 XComponent，平台视图跟不过去，留在平台
  /// 视图上 PiP 窗口里是一片空白；退回纹理路径至少画面还在，只是没有 HDR。
  ///
  /// **hdrMode**：上报哪种 HDR 类型由 mpv 按**码流**决定，不看画质档位：
  /// - HDR10：静态元数据（SEI 137/144）；
  /// - HDR Vivid：原样转发片源的 CUVA 动态元数据；
  /// - 杜比视界 / HDR10+：鸿蒙没有对应的类型，动态元数据（DV L1、ST 2094-40）
  ///   换算成 HDR Vivid 元数据后上报，系统照样逐帧做显示适配。
  ///
  /// 平台视图上输出 HDR 时发 `auto`；面板明确不支持 HDR Vivid
  /// （[displayMaySupportVivid] 为 false）时发 `hdr10`，只用静态元数据。其余
  /// 情况（HDR 关闭、纹理路径）必须显式发 `no`：省掉这个属性的话 mpv 落回默认
  /// 的 `auto`，HDR 片源照样输出 PQ。
  ///
  /// **targetPeak**：要 mpv 色调映射到的屏幕峰值 [peakNits]。SDR 输出（纹理
  /// 路径）时不传：SDR 目标配上上千 nit 的峰值，整幅画面都会被压暗，那里由
  /// media-kit 显式设回 `auto`。[matchVideo]（「匹配视频亮度」）时也不传：输出
  /// 峰值就是片源自己的峰值，libplacebo 不压缩高光，鸿蒙按 PQ 的绝对亮度显示，
  /// 不随系统亮度变化。关闭时把片源的峰值色调映射到 [peakNits]，比它亮的内容
  /// 压进这个范围而不是被屏幕截断；mpv 上报的元数据描述的也是映射之后的画面。
  static OhosOutput output({
    required bool hdrEnabled,
    required VideoQuality? quality,
    required bool displayHasNoHdr,
    required bool displayMaySupportVivid,
    required bool pipMode,
    required int peakNits,
    required bool matchVideo,
  }) {
    final hdrPlayback =
        hdrEnabled && (quality?.isHDR ?? false) && !displayHasNoHdr;
    final platformView = hdrPlayback && !pipMode;
    return (
      platformView: platformView,
      hdrMode: switch ((platformView, displayMaySupportVivid)) {
        (false, _) => 'no',
        (true, true) => 'auto',
        (true, false) => 'hdr10',
      },
      targetPeak: platformView && !matchVideo ? peakNits.toDouble() : null,
    );
  }

  /// 是否让 mpv 在 GPU 上逐帧测量片源的实际峰值（`--hdr-compute-peak`）。
  ///
  /// 只在按设定峰值色调映射时测：有的 HDR10 片源标 1000 nit，画面却到 10000
  /// nit，只信元数据的话比标称值亮的部分要么被压成一片，要么原样交给屏幕截断。
  /// 杜比视界、HDR10+ 自带逐场景峰值，libplacebo 用它们，不另外测量。
  ///
  /// media-kit 为了省电默认关掉了测量（`hdr-compute-peak=no`）。「匹配视频
  /// 亮度」时也不能打开：目标就是片源自己标的峰值，测出更高的峰值会让 mpv
  /// 去压缩画面。
  static bool measuresPeak(OhosOutput? output) => output?.targetPeak != null;
}
