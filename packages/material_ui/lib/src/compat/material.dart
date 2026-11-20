import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as sdk show Material;
import 'package:material_ui/src/ripple/splash_policy.dart';

/// SDK Material 的等价物，区别只是外面多套一层只改 splashFactory 的 Theme。
///
/// SDK 内部控件（TextButton/IconButton/ListTile/Chip/TabBar…）只认
/// Theme.of(context).splashFactory，而 Theme.of 读 SDK 私有 _InheritedTheme；
/// 用公开的 Theme 重新注入是唯一不改 SDK 的入口。ink 管线仍由 SDK Material
/// 提供，Material.of / MaterialInkController 行为不变。
///
/// key 必须落到内层 SDK Material 上，否则 GlobalKey<MaterialState> 取不到 state；
/// 因此外层包装不持有 key（调用点写法不变）。
class Material extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const Material({
    Key? key,
    this.type = MaterialType.canvas,
    this.elevation = 0.0,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.textStyle,
    this.borderRadius,
    this.shape,
    this.borderOnForeground = true,
    this.clipBehavior = Clip.none,
    this.animationDuration = kThemeChangeDuration,
    this.child,
    this.animateColor = false,
  }) : _key = key;

  final Key? _key;
  final Widget? child;
  final MaterialType type;
  final bool animateColor;
  final double elevation;
  final Color? color;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final TextStyle? textStyle;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;
  final bool borderOnForeground;
  final Clip clipBehavior;
  final Duration animationDuration;

  /// 默认波纹半径，与 SDK 同名常量一致。
  static const double defaultSplashRadius = sdk.Material.defaultSplashRadius;

  static MaterialInkController? maybeOf(BuildContext context) => sdk.Material.maybeOf(context);

  static MaterialInkController of(BuildContext context) => sdk.Material.of(context);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: withRippleSplash(Theme.of(context)),
      child: sdk.Material(
        key: _key,
        type: type,
        elevation: elevation,
        color: color,
        shadowColor: shadowColor,
        surfaceTintColor: surfaceTintColor,
        textStyle: textStyle,
        borderRadius: borderRadius,
        shape: shape,
        borderOnForeground: borderOnForeground,
        clipBehavior: clipBehavior,
        animationDuration: animationDuration,
        animateColor: animateColor,
        child: child,
      ),
    );
  }
}