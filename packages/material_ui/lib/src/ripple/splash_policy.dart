import 'package:flutter/material.dart' show InkRipple, InkSplash, InteractiveInkFeatureFactory, ThemeData;

import 'package:material_ui/src/ripple/adaptive_ink_ripple.dart';

/// 是否启用自适应水波纹。所有平台统一启用：
///
/// · Android（M3）：SDK 本来就用 InkSparkle，本包不介入（见 resolveSplashFactory）；
/// · iOS / macOS / Windows / Linux / Fuchsia / Web / 鸿蒙：把 InkRipple 换成
///   InkSparkle 的等价实现，让触摸反馈在各平台一致。
///
/// shader 不可用（如测试环境、加载失败）时该实现内部退化为纯 Canvas 圆。
bool get isRippleTarget => true;

/// 自适应工厂。shader 就绪时走 P1（InkSparkle 复刻），未就绪/失败时退化为 P0
/// （纯 Canvas 圆）。
const InteractiveInkFeatureFactory kAdaptiveSplashFactory = AdaptiveInkRipple.splashFactory;

/// 把"通用默认"的 factory 换成自适应实现。
///
/// 用 [identical] 而非 ==：InkRipple/InkSplash 的工厂是 const 单例，命中即代表
/// 调用方没有特意选型。InkSparkle（Android 显式选用）、NoSplash、业务自定义
/// 工厂一律原样返回。
InteractiveInkFeatureFactory resolveSplashFactory(InteractiveInkFeatureFactory requested) {
  if (!isRippleTarget) {
    return requested;
  }
  if (identical(requested, InkRipple.splashFactory) ||
      identical(requested, InkSplash.splashFactory)) {
    return kAdaptiveSplashFactory;
  }
  return requested;
}

final Map<ThemeData, ThemeData> _themeCache = Map<ThemeData, ThemeData>.identity();

/// 只替换 splashFactory，其余字段沿用，业务侧传入的 ThemeData 不被改写。
///
/// 业务显式选了 InkSparkle / NoSplash 时保持原样：这里只覆盖"通用默认"。
ThemeData withRippleSplash(ThemeData data) {
  final InteractiveInkFeatureFactory resolved = resolveSplashFactory(data.splashFactory);
  if (identical(resolved, data.splashFactory)) {
    return data;
  }
  final ThemeData? cached = _themeCache[data];
  if (cached != null) {
    return cached;
  }
  final ThemeData themed = data.copyWith(splashFactory: resolved);
  if (_themeCache.length > 16) {
    _themeCache.clear();
  }
  _themeCache[data] = themed;
  return themed;
}