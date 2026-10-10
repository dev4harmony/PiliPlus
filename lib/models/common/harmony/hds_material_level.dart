import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 鸿蒙沉浸光感材质等级，对应 `hdsMaterial.MaterialLevel`
/// （SystemCapability.UIDesign.HDSComponent.Core，6.1.0(23)+）。
///
/// [value] 必须与 ArkTS 侧枚举值一致，`harmonyChannel.setTabMaterialLevel`
/// 直接按该值下发，原生 `Index.ets` 用它取 `hdsMaterial.MaterialLevel`。
enum HdsMaterialLevel implements EnumWithLabel {
  /// 精美。性能开销较大
  exquisite('精美', 0),
  /// 轻柔。
  gentle('轻柔', 1),
  /// 流畅。性能开销较小
  smooth('流畅', 2),
  /// 由系统按设备性能自适应材质等级。
  adaptive('系统自适应', 10),
  ;

  final String label;

  /// ArkTS `hdsMaterial.MaterialLevel` 枚举值
  final int value;

  const HdsMaterialLevel(this.label, this.value);
}
