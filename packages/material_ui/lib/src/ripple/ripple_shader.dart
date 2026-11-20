import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// 'shaders/ink_sparkle.frag' 的加载与就绪状态。
///
/// 该 shader 由 flutter_tools 对所有平台无条件 sideload（asset.dart 的
/// _getFrameworkShaders），鸿蒙包内已编译为 IPLR 格式，无需自带资产、无需改
/// pubspec。加载失败只记录一次闩锁，永久降级为纯 Canvas 绘制，异常不得进入
/// paint 阶段。
class RippleShader {
  RippleShader._();

  static const String asset = 'shaders/ink_sparkle.frag';

  static ui.FragmentProgram? _program;
  static bool _failed = false;
  static bool _loading = false;
  static bool _warmedUp = false;

  /// 已编译好的 program；null 表示尚未就绪或已失败。
  static ui.FragmentProgram? get program => _program;

  static bool get available => _program != null;

  /// 幂等加载。第一个点击即可触发，之后全局复用。
  static void ensureLoaded() {
    if (_program != null || _failed || _loading) {
      return;
    }
    _loading = true;
    unawaited(
      ui.FragmentProgram.fromAsset(asset).then<void>(
        (ui.FragmentProgram program) => _program = program,
        onError: (Object error, StackTrace stack) {
          _failed = true;
        },
      ).whenComplete(() => _loading = false),
    );
  }

  /// 启动空闲帧预热，让首屏之后的点击直接命中 shader，避免首击走降级路径。
  static void warmUp() {
    if (_warmedUp) {
      return;
    }
    _warmedUp = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      ensureLoaded();
    });
  }
}
