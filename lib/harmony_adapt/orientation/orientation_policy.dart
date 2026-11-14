import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/harmony_adapt/orientation/harmony_orientation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:os_type/os_type.dart';

/// 鸿蒙方向策略的唯一决策点。
///
/// 原则：应用不按设备型号、不读系统旋转锁，只声明「这个状态允许哪些方向」，
/// 具体朝向仍由系统按重力/智感/旋转锁决定。
///
/// 策略 = f(设备形态, 页面类型, 当前视频方向, 是否全屏, 窗口方向)：
///
/// | 设备形态 | 页面类型 | 视频方向 | 全屏 | 策略 |
/// | --- | --- | --- | --- | --- |
/// | 细长竖屏（直板机 / 大折叠外屏） | 非播放页 | - | - | [portraitOnly] |
/// | 细长竖屏 | 播放页（视频/直播） | 竖屏视频/竖屏直播流 | 任意 | [portraitOnly] |
/// | 细长竖屏 | 播放页 | 横屏视频 | 否 | [userPortrait] |
/// | 细长竖屏 | 播放页 | 横屏视频 | 是（窗口已是横屏） | [followSystem] |
/// | 细长竖屏 | 播放页 | 横屏视频 | 是（窗口是竖屏） | [userLandscape] |
/// | 其它（平板/2in1/阔折叠/阔直板/折叠内屏） | 任意 | 任意 | 任意 | [followSystem] |
///
/// 竖屏视频锁竖向对齐 B 站：不论旋转锁定与设备方向，非全屏与全屏都保持竖向。
/// 该策略在**进入播放页、视频方向已知时**就生效（由播放器尺寸回调同步），
/// 不是等进全屏才设，因此转动设备时窗口不会先转过去再被拉回来。
///
/// 非全屏横屏视频用 [userPortrait]（USER_ROTATION_PORTRAIT）：进入播放页 /
/// 退出全屏时向系统发一次「临时转回竖屏」，之后恢复跟随传感器（锁开则不再
/// 跟随）。因此横置手机进入播放页会先正常落到竖屏非全屏；退出全屏也会先转回
/// 竖屏，不会被「窗口横屏自动进全屏」再拉回全屏。
///
/// 退出全屏只是把「是否全屏」置 false，重算结果自然是当前页面应有的策略；
/// `portraitOnly` 由离开播放页的路由事件触发，不存在「退出全屏该回哪个策略」
/// 的歧义。
abstract final class OrientationPolicy {
  /// 当前是否「细长竖屏」形态（原生按 deviceType + 屏幕长宽比判定）。
  static bool _portraitForm = false;

  /// 最上层是否播放页（/videoV、/liveRoom），由 ShellBarsObserver 维护。
  static bool _onPlayerPage = false;

  /// 播放器是否处于全屏。
  static bool _fullScreen = false;

  /// 当前播放的视频/直播流是否为竖屏（由播放器解析尺寸后同步）。
  static bool _videoVertical = false;

  static HarmonyOrientationPolicy? _applied;
  static bool _initialized = false;

  /// 当前状态下应有的策略。
  static HarmonyOrientationPolicy get current {
    if (!_portraitForm) return .followSystem;
    if (!_onPlayerPage) return .portraitOnly;
    // 竖屏视频（含竖屏直播流）：非全屏与全屏都锁竖向，对齐 B 站。
    if (_videoVertical) return .portraitOnly;
    // 横屏视频非全屏：USER_ROTATION_PORTRAIT —— 进入播放页 / 退出全屏时向
    // 系统发一次「临时转回竖屏」，之后恢复跟随传感器（锁开则不跟随）。
    // 横置手机进入播放页因此会先正常落到竖屏非全屏；退出全屏也会先转回竖屏，
    // 避免窗口保持横屏后被「窗口横屏自动进全屏」重新拉回全屏。
    if (!_fullScreen) return .userPortrait;
    // 横屏视频全屏：窗口已经是横屏时（例如用户转动设备后自动进全屏）不再
    // 重新请求旋转，避免系统重选横屏方向造成「先左转再 180°」；否则临时
    // 转到横屏，之后跟随传感器——旋转锁关闭时转回竖屏会连窗口一起转回竖屏
    // 并触发自动退出全屏，旋转锁打开时保持横屏、只能点按钮退出。
    return _windowIsLandscape ? .followSystem : .userLandscape;
  }

  /// 当前非全屏播放页是否刚向系统发过「临时转竖屏」（USER_ROTATION_PORTRAIT）。
  /// 退出全屏后调用方可据此等待窗口真正变成竖屏，再切非全屏布局，避免旋转
  /// 过程中先闪一帧横屏非全屏布局。
  static bool get isTemporaryPortrait => current == .userPortrait;

  /// 当前窗口是否已是横屏。按引擎上报的窗口尺寸判断，不读屏幕方向属性。
  static bool get _windowIsLandscape {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final size = views.first.physicalSize;
    return size.width > size.height;
  }

  /// 启动时（首帧前）初始化：取设备形态并应用一次。
  static Future<void> init() async {
    if (!OS.isHarmony) return;
    HarmonyChannel.onDeviceFormChange = setPortraitForm;
    final form = await HarmonyChannel.getDeviceForm();
    // 原生 EntryAbility 在首帧前已按形态设过一次策略；这里拿到形态就再收口一次，
    // 拿不到（通道暂不可用）则不覆盖原生决策，等后续路由/形态事件再算。
    if (form != null) {
      _portraitForm = form;
    }
    _initialized = true;
    if (form != null) {
      await _sync(force: true);
    }
  }

  /// 原生推送：折叠/展开导致形态变化。
  static void setPortraitForm(bool value) {
    if (_portraitForm == value) return;
    _portraitForm = value;
    _sync();
  }

  /// 路由变化：最上层是否播放页。
  ///
  /// 离开播放页不会清空全屏标记：从全屏视频页压入新页面（如 UP 主主页）时
  /// 播放器仍处于全屏，返回后需要恢复 landscapeOnly；只有在播放页内退出全屏
  /// 才会通过 `_setFullScreen` 把标记置 false。
  static void setPlayerPage(bool value) {
    if (_onPlayerPage == value) return;
    _onPlayerPage = value;
    _sync();
  }

  /// 播放器解析出的视频/直播流方向变化。
  ///
  /// 竖屏视频在竖屏形态设备的播放页整页锁竖向（非全屏与全屏一致），对齐
  /// B 站：转动设备窗口不动、也不会先转过去再被拉回来。
  static void setVideoVertical(bool value) {
    if (_videoVertical == value) return;
    _videoVertical = value;
    _sync();
  }

  /// 播放器进出全屏；返回策略下发完成的 Future，供进入全屏后等待转向。
  static Future<void> setFullScreen(bool value) {
    if (_fullScreen == value) return Future.value();
    _fullScreen = value;
    return _sync();
  }

  static Future<void> _sync({bool force = false}) async {
    if (!OS.isHarmony || !_initialized) return;
    final target = current;
    if (!force && target == _applied) return;
    _applied = target;
    await HarmonyOrientation.apply(target);
  }
}
