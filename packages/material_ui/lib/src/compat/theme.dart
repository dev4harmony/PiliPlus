import 'package:flutter/material.dart' hide AnimatedTheme, Theme;
import 'package:flutter/material.dart' as sdk show AnimatedTheme, Theme;
import 'package:material_ui/src/ripple/splash_policy.dart';

/// SDK Theme 的等价物：套用业务传入的 ThemeData 时顺带注入鸿蒙水波纹。
///
/// GetMaterialApp 内部直接构造 SDK 的 MaterialApp，业务侧传进来的 ThemeData
/// 不受本包控制；任何一处 Theme(data: ...) 都会把 splashFactory 重置回
/// InkRipple，所以这里在业务侧的 Theme 上兜底。除此之外行为与 SDK 一致。
class Theme extends StatelessWidget {
  const Theme({super.key, required this.data, required this.child});

  final ThemeData data;
  final Widget child;

  static ThemeData of(BuildContext context) => sdk.Theme.of(context);

  static Brightness brightnessOf(BuildContext context) => sdk.Theme.brightnessOf(context);

  static Brightness? maybeBrightnessOf(BuildContext context) =>
      sdk.Theme.maybeBrightnessOf(context);

  @override
  Widget build(BuildContext context) {
    return sdk.Theme(data: withRippleSplash(data), child: child);
  }
}

/// SDK AnimatedTheme 的等价物，注入逻辑同 [Theme]。
class AnimatedTheme extends StatelessWidget {
  const AnimatedTheme({
    super.key,
    required this.data,
    this.curve = Curves.linear,
    this.duration = kThemeAnimationDuration,
    this.onEnd,
    required this.child,
  });

  final ThemeData data;
  final Curve curve;
  final Duration duration;
  final VoidCallback? onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return sdk.AnimatedTheme(
      data: withRippleSplash(data),
      curve: curve,
      duration: duration,
      onEnd: onEnd,
      child: child,
    );
  }
}
