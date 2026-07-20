import 'package:PiliPlus/common/widgets/scale_app.dart';
import 'package:PiliPlus/harmony_adapt/continuation.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:os_type/os_type.dart';

abstract class HarmonyChannel {
  static double? _systemFontWeightScale;
  
  static double? get systemFontWeightScale => _systemFontWeightScale;
  
  static final MethodChannel _channel = const MethodChannel('harmonyChannel')
    ..setMethodCallHandler(handler);

  static Future<dynamic> handler(MethodCall call) async {
    switch (call.method) {
      case 'onFloatingWindowChange':
        onLandscapeOrMiniWindowChange(null, call.arguments['isFloatingWindow']);
        break;
      case 'onFontWeightScaleChange':
        final fontWeightScale = call.arguments['fontWeightScale'] as double?;
        _systemFontWeightScale = fontWeightScale;
        if (Pref.appFontWeight == -1) {
          Get.updateMyAppTheme();
        }
        break;
      // 源端 onContinue 拉取当前播放状态
      case 'getContinuationState':
        return HarmonyContinuation.currentState();
      // 对端应用已在运行时被接续唤醒
      case 'onContinuationRestore':
        checkPendingContinuation();
        break;
      default:
        break;
    }
  }

  /// 取走 ETS 侧暂存的接续数据并跳转视频页。冷启动在首帧后调用，
  /// 热启动由 onContinuationRestore 推送触发；数据取走即清除，不会重复跳转。
  static Future<void> checkPendingContinuation() async {
    try {
      final data = await _channel.invokeMethod<String>(
        'getPendingContinuation',
      );
      HarmonyContinuation.restore(data);
    } on PlatformException catch (_) {}
  }

  /// “可接续”状态按持有者管理：视频播放器/直播间/音频页/专栏页在存续期间
  /// 持有，任一持有者存在时系统显示接续入口，全部释放后置为不可接续。
  /// 列表保持持有顺序（最新在尾部），接续时从最近的持有者生成快照。
  static final List<Object> _continuationOwners = [];

  static List<Object> get continuationOwners => _continuationOwners;

  static void holdContinuation(Object owner) {
    if (!OS.isHarmony) return;
    final wasEmpty = _continuationOwners.isEmpty;
    _continuationOwners
      ..remove(owner)
      ..add(owner);
    if (wasEmpty) {
      _setContinuationActive(true);
    }
  }

  static void releaseContinuation(Object owner) {
    if (!OS.isHarmony) return;
    if (_continuationOwners.remove(owner) && _continuationOwners.isEmpty) {
      _setContinuationActive(false);
    }
  }

  static void _setContinuationActive(bool active) {
    _channel.invokeMethod('setContinuationActive', {'active': active});
  }

  /// 测试用，ai生成信息请忽略这部分更改
  static Future csy(value) {
    return _channel.invokeMethod('csy', {'value': value});
  }

  /// 获取系统当前字重设置（仅 Harmony 平台）
  static Future<void> initSystemFontWeight() async {
    if (!OS.isHarmony) return;
    try {
      // 触发 ArkTS 侧发送当前系统字重值
      await _channel.invokeMethod('getSystemFontWeightScale');
    } on PlatformException catch (_) {}
  }

  /// 横屏小窗的缩放比例固定值
  static const _miniWindowLandscapeScale = 0.75;
  static bool _landscape = false;
  static bool _miniWindow = false;

  /// 当前是否处于系统自由小窗（悬浮窗/全景多窗）。小窗内窗口宽高比不代表
  /// 设备方向，基于方向的自动全屏等逻辑应据此跳过。
  static bool get isMiniWindow => _miniWindow;

  /// 当方向或小窗变化
  static Future<void> onLandscapeOrMiniWindowChange(
    bool? landscape,
    bool? miniWindow,
  ) async {
    landscape ??= _landscape;
    miniWindow ??= _miniWindow;
    if (_landscape == landscape && _miniWindow == miniWindow) return;
    _landscape = landscape;
    _miniWindow = miniWindow;
    if (_miniWindow && _landscape) {
      _setMiniWindowLandscape(true);
      ScaledWidgetsFlutterBinding.instance.scaleFactor =
          _miniWindowLandscapeScale;
    } else {
      ScaledWidgetsFlutterBinding.instance.scaleFactor = Pref.uiScale;
      _setMiniWindowLandscape(false);
    }
  }

  static void _setMiniWindowLandscape(bool landscape) {
    _channel.invokeMethod('setMiniWindowLandscape', {'landscape': landscape});
  }

  static void autoRotateLandscape() {
    _channel.invokeMethod('autoRotateLandscape');
  }

  /// 自由多窗装饰栏按钮（全屏/最小化/关闭）的颜色跟随应用颜色模式而非
  /// 下方内容：浅色模式下深色按钮叠在播放页黑色顶部上视觉不可见。顶部为
  /// 深色内容的页面（视频/直播播放页）在可见期间持有此状态，使按钮切为
  /// 浅色风格；无人持有时恢复跟随系统。用持有者集合而非开关，规避
  /// 路由切换（如视频页跳视频页）中生命周期回调顺序的不确定性。
  static final Set<Object> _darkDecorOwners = <Object>{};

  static void holdDecorDark(Object owner) {
    if (!OS.isHarmony) return;
    final wasEmpty = _darkDecorOwners.isEmpty;
    _darkDecorOwners.add(owner);
    if (wasEmpty) {
      _setDecorButtonDark(true);
    }
  }

  static void releaseDecorDark(Object owner) {
    if (!OS.isHarmony) return;
    if (_darkDecorOwners.remove(owner) && _darkDecorOwners.isEmpty) {
      _setDecorButtonDark(false);
    }
  }

  static void _setDecorButtonDark(bool dark) {
    _channel.invokeMethod('setDecorButtonDark', {'dark': dark});
  }
}
