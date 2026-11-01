import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';

/// 系统栏（状态栏 + 导航栏）期望状态的**唯一下发点**。
///
/// 期望状态本身留在上游 [fullscreen.dart] 的 showSystemBar_，这里只把它翻译
/// 成带 revision 与 epoch 的状态同步：原生据此丢弃乱序到达的旧消息（快速进出
/// 全屏时 Dart 侧的异步调用可能乱序落地）。
abstract final class SystemBars {
  /// 本次启动的会话标记。原生只接受 epoch 相同的消息，避免热重启前的残留状态
  /// 覆盖新会话。取值范围压到 31 位，对应 ArkTS 侧的 int。
  static final int _epoch = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

  /// 单调递增的版本号，每次下发 +1。
  static int _revision = 0;

  /// 下发系统栏显隐。[hidden] 为 true 即隐藏（沉浸）。
  static Future<void> sync({required bool hidden}) =>
      HarmonyChannel.setSystemBarsHidden(
        hidden: hidden,
        revision: ++_revision,
        epoch: _epoch,
      );

  /// 重发当前期望状态（如首帧后原生可能已重置系统栏）。
  static Future<void> resync({required bool hidden}) => sync(hidden: hidden);
}
