import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 鸿蒙「横屏适配模式」：在设备形态自动判定之上再覆盖一层用户意图。
///
/// 只影响布局层面的横屏适配（`Pref.horizontalScreen`），不改变原生方向策略
/// 依赖的 `portraitPlayerForm`。
enum HorizontalLayoutMode with EnumWithLabel {
  /// 按设备形态与当前屏幕自动判定（见原生 `DeviceForm.ets`）。
  adaptive('自适应'),

  /// 强制开启横屏适配布局。
  forceOn('强制启用'),

  /// 强制关闭横屏适配布局。
  forceOff('强制禁用');

  @override
  final String label;

  const HorizontalLayoutMode(this.label);
}
