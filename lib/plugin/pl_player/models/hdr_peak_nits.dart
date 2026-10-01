/// 鸿蒙 HDR 色调映射用的面板峰值亮度（nit），即传给 mpv 的 `--target-peak`。
///
/// 鸿蒙没有公开查询面板峰值亮度的接口（`display` 只给得出支持哪些 HDR 格式），
/// 所以由用户在设置里按屏幕参数填写。
abstract final class HdrPeakNits {
  /// 未设置时的取值。按 SLM-W32（典型 700 nit / 峰值 1600 nit）标定，也是
  /// 目前 HDR 机型比较常见的量级。
  static const int defaultValue = 1600;

  /// 低于 SDR 参考白（203 nit）的屏幕谈不上 HDR，再低只会把整幅画面压暗。
  static const int min = 200;

  /// PQ 的名义峰值，也是 mpv `--target-peak` 允许的上限。
  static const int max = 10000;

  static bool isValid(int value) => value >= min && value <= max;

  /// 解析设置对话框里的输入；不是整数或超出 [min]..[max] 时返回 null。
  static int? tryParse(String input) {
    final value = int.tryParse(input.trim());
    return value != null && isValid(value) ? value : null;
  }

  /// 读取存储值；缺失、类型不对或超出范围时回退到 [defaultValue]。
  static int sanitize(Object? stored) =>
      stored is int && isValid(stored) ? stored : defaultValue;
}
