import 'package:PiliPlus/harmony/window/window_facts.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';

/// 鸿蒙窗口形态 → Flutter 侧表现的桥接层。
///
/// 职责只有两件事：
/// 1. 启动时把原生窗口快照与安全区拉到 Dart 侧，并据此定下小窗缩放、装饰栏
///    策略这些必须首帧前就位的状态（否则装饰栏会先出现再收回）。
/// 2. 接收播放器回传的「当前是否全屏横屏」，补进 [WindowFacts] 后重算小窗
///    缩放——这个判断原生不持有，只能由播放器给。
///
/// 原生主动推送的窗口快照不在这里订阅：通道 handler 是唯一入口，见
/// [HarmonyChannel.applyWindowSnapshot]。
abstract final class WindowBridge {
  static bool _initialized = false;

  /// 启动时（首帧前）初始化窗口域，是**唯一入口**（main.dart 只调它）。
  ///
  /// 顺序与去重都收在这里，避免启动时连发两轮通道消息：
  /// 1. [HarmonyChannel.initWindowState]：老通道 getWindowState 基线（自由
  ///    多窗 / 受限窗口模式），顺带拉安全区并定下装饰栏策略；
  /// 2. [HarmonyChannel.refreshWindowSnapshot]：新快照（比 getWindowState 多
  ///    自绘标题带与内容全屏信息），状态翻转时内部已重算缩放与装饰栏；
  /// 3. 兜底各再对账一次：快照相对基线没变化时，第 2 步不会触发下发，而
  ///    scaleFactor 与装饰栏在首帧前仍需一个确定值。两处都是幂等空操作
  ///    （装饰栏比对上次下发值，scaleFactor 相等即 early return）。
  ///
  /// 重复调用是无害空操作。任一步失败都只是保持旧状态（原生旧版本没有对应
  /// method 时返回 null），不抛异常、不阻断启动。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await HarmonyChannel.initWindowState();
    await HarmonyChannel.refreshWindowSnapshot();
    HarmonyChannel.syncMiniWindowLandscape();
    HarmonyChannel.syncWindowDecor();
  }

  /// 播放器进出全屏横屏时回传，用于「横屏小窗」缩放与
  /// enableLandscapeMultiWindow。
  ///
  /// [landscape] 为当前是否以全屏横屏渲染（播放器自己的判断，非设备方向）。
  static void syncPlayerLandscape(bool landscape) {
    // 判等与落地都在通道里（那里同时维护 _landscape 本地镜像）：原生推送窗口
    // 快照时会用该镜像回填 WindowFacts.landscape，两侧只能有一个写入口，否则
    // 小窗缩放会因镜像分叉而漏算或重复计算。
    HarmonyChannel.onLandscapeOrMiniWindowChange(landscape, null);
  }
}
