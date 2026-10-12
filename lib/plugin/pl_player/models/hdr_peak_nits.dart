/// 鸿蒙 HDR 输出的峰值亮度（nit），即传给 mpv 的 `--target-peak`。
///
/// 鸿蒙没有公开查询面板峰值亮度的接口（`display` 只给得出支持哪些 HDR 格式），
/// 所以由用户在设置里填写。开启「匹配视频亮度」时它是参考亮度：只在片源
/// 没有亮度元数据时使用，见 [OhosHdrOutput.targetPeak]。
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
