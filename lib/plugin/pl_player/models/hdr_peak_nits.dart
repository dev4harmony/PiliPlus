/// 「HDR 峰值亮度」设置：HDR 画面在屏幕上的峰值（nit），由用户按屏幕能力填写。
/// 关闭「匹配视频亮度」时片源的峰值映射到这里，即 mpv 的 `--target-peak`。
///
/// 开启「匹配视频亮度」时不使用，见 [OhosHdrOutput.targetPeak]。
abstract final class HdrPeakNits {
  /// 未设置时的取值：1000 nit 是 HDR 的常用参考亮度（HLG 名义参考显示器、
  /// 多数 HDR10 母版的峰值）。
  static const int defaultValue = 1000;

  /// 设置里滑块的步进。
  static const int step = 100;

  /// 低于 SDR 参考白（203 nit）的屏幕谈不上 HDR，再低只会把整幅画面压暗。
  static const int min = 200;

  /// PQ 的名义峰值，也是 mpv `--target-peak` 允许的上限。
  static const int max = 10000;

  static bool isValid(int value) => value >= min && value <= max;

  /// 把滑块位置吸附到 [step] 的整数倍，并限制在 [min]..[max]。
  static int snap(double value) =>
      ((value / step).round() * step).clamp(min, max);

  /// 解析设置对话框里的输入；不是整数或超出 [min]..[max] 时返回 null。
  static int? tryParse(String input) {
    final value = int.tryParse(input.trim());
    return value != null && isValid(value) ? value : null;
  }

  /// 读取存储值；缺失、类型不对或超出范围时回退到 [defaultValue]。
  static int sanitize(Object? stored) =>
      stored is int && isValid(stored) ? stored : defaultValue;
}
