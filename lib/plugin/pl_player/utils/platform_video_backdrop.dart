import 'dart:async';

import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

/// HDR 平台视图模式下「黑边」的背景色同步。
///
/// 平台视图合成在 Flutter 表面之下，而且只有拟合后的视频矩形那么大
/// （media_kit 的 `_RenderOhosPlatformVideoGeometry` 按 `getTransformTo(null)`
/// 上报），XComponent 的黑底也只盖这一块。这一模式下播放器各层 Flutter 都画
/// 透明（统一以 [rx] 为准），矩形以外的黑边会一路透到 `Index.ets` 的根 Stack。
/// 根 Stack 平时是启动背景色（浅色主题为白），又不能常黑（上游 2c4e56a98：
/// 一镜到底动画右侧黑块），所以只在 [rx] 为 true 期间通知 ArkTS 把它涂黑。
///
/// 各方向都按「不闪白」排序：
///  - 进入：先发 true 再置 [rx]。平台消息在调用时就同步发出，先于 [rx] 触发的
///    那一帧。这里**不能** await：调用方正处在 `_usesPlatformView` 赋值与
///    `_initPlayer()` 之间，插一个 await，全屏状态就可能在这期间变化，
///    播放器的真实配置与 `_usesPlatformView` 对不上。
///  - 退出：先置 [rx] 让 Flutter 恢复不透明，等这一帧出去再发 false。
///  - 销毁：[reset] 先置 [rx] 再同步发 false，两者在同一个同步段内完成。
///
/// [isAlive] 为 false（播放器已 dispose）时不再发 true：dispose 已经通过
/// [reset] 发过 false，迟到的重建流程若再发 true，根 Stack 会一直黑到下一个
/// 播放器创建为止。
class PlatformVideoBackdrop {
  PlatformVideoBackdrop({
    required this.rx,
    required this.enabled,
    required this.isAlive,
    Future<void> Function(bool active)? send,
    Future<void> Function()? nextFrame,
  }) : _send = send ?? HarmonyChannel.setPlatformVideoActive,
       _nextFrame = nextFrame ?? _endOfFrame;

  final RxBool rx;

  /// 仅鸿蒙为 true；其余平台只维护 [rx]。
  final bool enabled;
  final bool Function() isAlive;
  final Future<void> Function(bool active) _send;
  final Future<void> Function() _nextFrame;

  static Future<void> _endOfFrame() => SchedulerBinding.instance.endOfFrame;

  /// 渲染路径确定后调用，是 [rx] 在播放期间唯一的写入口。
  void update(bool value) {
    if (!enabled) {
      rx.value = value;
      return;
    }
    if (value) {
      if (isAlive()) {
        unawaited(_send(true));
      }
      rx.value = true;
      return;
    }
    rx.value = false;
    unawaited(_restoreAfterFrame());
  }

  Future<void> _restoreAfterFrame() async {
    await _nextFrame();
    // 这一帧期间又切回了平台视图，或者播放器已经 dispose（dispose 自己发过 false）
    if (rx.value || !isAlive()) return;
    await _send(false);
  }

  /// 播放器彻底销毁时调用：先置 [rx] 让 Flutter 恢复不透明，再同步发出 false。
  ///
  /// 不等帧，也不看 [isAlive]：之后迟到的 [update] 因 [isAlive] 为 false 不会
  /// 再发 true，这里的 false 就是最终值。先清 [rx] 是为了「全屏状态下直接
  /// dispose」的路径（例如全屏里点返回主页走 onCloseAll）：否则 Flutter 各层
  /// 仍是透明的，根 Stack 却已恢复为白色，退出途中会闪白边。
  void reset() {
    rx.value = false;
    if (!enabled) return;
    unawaited(_send(false));
  }
}
