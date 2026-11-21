import 'package:PiliPlus/harmony_adapt/device/device_form.dart';
import 'package:PiliPlus/harmony_adapt/device/horizontal_layout_mode.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/harmony_adapt/orientation/harmony_orientation.dart';
import 'package:PiliPlus/harmony_adapt/window/window_facts.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:os_type/os_type.dart';

/// 鸿蒙方向策略的唯一决策点。
///
/// 原则：应用不按设备型号、不读系统旋转锁，只声明「这个状态允许哪些方向」，
/// 具体朝向仍由系统按重力/智感/旋转锁决定。
///
/// 设备形态有两个方向事实（见 `HarmonyDeviceForm`）：
/// - [portraitForm]：细长竖屏（屏幕长宽比 ≥1.9 的手机 / 大折叠外屏），决定
///   **非播放页**锁竖屏与启动方向；
/// - [portraitPlayerForm]：播放页按手机竖屏形态处理（手机类设备且不是横屏
///   适配布局，含 Pura X 内屏 / Pura X View / 阔直板等宽屏手机，也含细长
///   手机与折叠外屏），决定**播放页**方向。
///
/// 两者分开：宽屏手机虽然不开横屏适配布局，非播放页仍然允许横屏；但播放页
/// 必须按手机形态处理，否则退出全屏后系统会保持横屏，出现「竖屏布局 + 横屏
/// 窗口」，且 `canPop` 的 `horizontalScreen || isPortrait` 不满足导致退不出页面。
///
/// 策略 = f(设备形态, 页面类型, 当前视频方向, 是否全屏, 窗口方向)：
///
/// | 形态 | 页面类型 | 视频方向 | 全屏 | 策略 |
/// | --- | --- | --- | --- | --- |
/// | 任意 | 非播放页（portraitForm=true） | - | - | [portraitOnly] |
/// | 任意 | 非播放页（portraitForm=false） | - | - | [followSystem] |
/// | 非 portraitPlayerForm | 播放页 | 任意 | 任意 | [followSystem] |
/// | portraitPlayerForm | 播放页（视频/直播） | 竖屏视频/竖屏直播流 | 任意 | [portraitOnly] |
/// | portraitPlayerForm | 播放页 | 横屏视频 | 否 | [userPortrait] |
/// | portraitPlayerForm | 播放页 | 横屏视频 | 是（锁关，窗口已是横屏） | [followSystem] |
/// | portraitPlayerForm | 播放页 | 横屏视频 | 是（锁关，窗口是竖屏） | [userLandscape] |
/// | portraitPlayerForm | 播放页 | 横屏视频 | 是（锁开） | [landscapeOnly] |
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
/// 横屏视频全屏会读一次系统「自动旋转」开关（= 旋转锁定是否关闭）来选择策略：
/// 锁关时 USER_ROTATION_LANDSCAPE 的四方向跟随同时支持 180° 翻转和转竖屏
/// 自动退全屏；锁开时它不再跟随传感器，180° 翻转会失效，因此改用
/// AUTO_ROTATION_LANDSCAPE（仅横向两方向、不受锁控制）。
///
/// 退出全屏只是把「是否全屏」置 false，重算结果自然是当前页面应有的策略；
/// `portraitOnly` 由离开播放页的路由事件触发，不存在「退出全屏该回哪个策略」
/// 的歧义。
abstract final class OrientationPolicy {
  /// 细长竖屏形态（非播放页锁竖屏 / 启动方向用；原生按屏幕长宽比判定）。
  static bool _portraitForm = false;

  /// 播放页是否按手机竖屏形态处理（原生按 deviceType + 横屏适配布局判定）。
  static bool _portraitPlayerForm = false;

  /// 最上层是否播放页（/videoV、/liveRoom），由 ShellBarsObserver 维护。
  static bool _onPlayerPage = false;

  /// 播放器是否处于全屏。
  static bool _fullScreen = false;

  /// 当前播放的视频/直播流是否为竖屏（由播放器解析尺寸后同步）。
  static bool _videoVertical = false;

  /// 系统「自动旋转」开关是否开启（旋转锁定关闭）。
  ///
  /// 只影响「横屏视频全屏」用哪条策略：锁关用 [userLandscape]（临时转横后
  /// 四方向跟随，180° 翻转、转竖屏自动退全屏都正常）；锁开用
  /// [landscapeOnly]（仅横向两方向、不受锁控制，180° 翻转可用，但窗口不会
  /// 转竖屏退出）。初始化与进入全屏时刷新。
  static bool _autoRotateEnabled = true;

  static HarmonyOrientationPolicy? _applied;
  static bool _initialized = false;

  /// 生效的「播放页按手机竖屏形态处理」：强制启用横屏适配后布局已是横屏，
  /// 播放页方向应与平板一致，不再按手机形态临时转竖屏。
  static bool get _effectivePortraitPlayerForm =>
      _portraitPlayerForm &&
      Pref.harmonyHorizontalLayoutMode != HorizontalLayoutMode.forceOn;

  /// 当前状态下应有的策略。
  static HarmonyOrientationPolicy get current {
    // 非播放页：「横屏适配模式」优先——强制启用允许横屏，强制禁用锁竖屏；
    // 自适应时只有细长竖屏形态锁竖屏，宽屏手机（Pura X 内屏 / Pura X View /
    // 阔直板等）与平板仍然允许横屏。
    if (!_onPlayerPage) {
      return switch (Pref.harmonyHorizontalLayoutMode) {
        HorizontalLayoutMode.forceOn => .followSystem,
        HorizontalLayoutMode.forceOff => .portraitOnly,
        HorizontalLayoutMode.adaptive =>
          _portraitForm ? .portraitOnly : .followSystem,
      };
    }
    // 播放页：不是手机竖屏播放形态（平板 / 2in1 / 按横屏适配布局的折叠内屏、
    // 强制启用横屏适配等）跟随系统，横屏布局与方向自洽。
    if (!_effectivePortraitPlayerForm) return .followSystem;
    // 竖屏视频（含竖屏直播流）：非全屏与全屏都锁竖向，对齐 B 站。
    if (_videoVertical) return .portraitOnly;
    // 横屏视频非全屏：USER_ROTATION_PORTRAIT —— 进入播放页 / 退出全屏时向
    // 系统发一次「临时转回竖屏」，之后恢复跟随传感器（锁开则不跟随）。
    // 横置手机进入播放页因此会先正常落到竖屏非全屏；退出全屏也会先转回竖屏，
    // 避免窗口保持横屏后被「窗口横屏自动进全屏」重新拉回全屏。
    if (!_fullScreen) return .userPortrait;
    // 横屏视频全屏：
    // - 旋转锁定关闭：临时转横后恢复四方向跟随（180° 翻转、转回竖屏自动退全屏）
    // - 旋转锁定打开：仅横向两方向跟随（180° 翻转可用，但不会转竖屏退出，
    //   只能点按钮退出）
    // 受限窗口（分屏/悬浮窗/自由多窗）里系统忽略方向策略，保持原逻辑，不按
    // 旋转锁定状态切换，避免留下不同的待生效策略。
    if (!WindowFacts.isWindowMode &&
        !WindowFacts.isFreeWindowMode &&
        !_autoRotateEnabled) {
      return .landscapeOnly;
    }
    // 窗口已经是横屏时（例如用户转动设备后自动进全屏）不再重新请求旋转，
    // 避免系统重选横屏方向造成「先左转再 180°」；否则临时转到横屏。
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
    HarmonyChannel.onDeviceFormChange = _onDeviceFormChanged;
    final form = await HarmonyChannel.getDeviceForm();
    // 原生 EntryAbility 在首帧前已按形态设过一次策略；这里拿到形态就再收口一次，
    // 拿不到（通道暂不可用）则不覆盖原生决策，等后续路由/形态事件再算。
    if (form != null) {
      // 横屏适配自动值也在这里落到 Dart 镜像，供 Pref.horizontalScreen 读取。
      HarmonyDeviceForm.update(
        portraitForm: form.portraitForm,
        portraitPlayerForm: form.portraitPlayerForm,
        horizontalLayout: form.horizontalLayout,
      );
      _portraitForm = form.portraitForm;
      _portraitPlayerForm = form.portraitPlayerForm;
    }
    // 旋转锁定状态只影响「手机竖屏播放形态设备的横屏视频全屏」，其它形态不读，
    // 避免多一次通道往返。
    if (_portraitPlayerForm) {
      final autoRotate = await HarmonyChannel.getAutoRotateEnabled();
      if (autoRotate != null) {
        _autoRotateEnabled = autoRotate;
      }
    }
    _initialized = true;
    if (form != null) {
      await _sync(force: true);
    }
  }

  /// 原生推送：折叠/展开、内外屏切换。
  ///
  /// 横屏适配自动值由通道 handler 同步进 `HarmonyDeviceForm`；这里只处理方向
  /// 策略依赖的两个形态事实。
  static void _onDeviceFormChanged(
    bool portraitForm,
    bool portraitPlayerForm,
    bool horizontalLayout,
  ) {
    if (_portraitForm == portraitForm &&
        _portraitPlayerForm == portraitPlayerForm) {
      return;
    }
    _portraitForm = portraitForm;
    _portraitPlayerForm = portraitPlayerForm;
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

  /// 横屏适配模式变化：非播放页方向随模式变，重新下发一次策略。
  static void onHorizontalLayoutModeChanged() => _sync(force: true);

  /// 播放器解析出的视频/直播流方向变化。
  ///
  /// 竖屏视频在手机竖屏播放形态设备的播放页整页锁竖向（非全屏与全屏一致），
  /// 对齐 B 站：转动设备窗口不动、也不会先转过去再被拉回来。
  static void setVideoVertical(bool value) {
    if (_videoVertical == value) return;
    _videoVertical = value;
    _sync();
  }

  /// 播放器进出全屏；返回策略下发完成的 Future，供进入全屏后等待转向。
  static Future<void> setFullScreen(bool value) async {
    if (_fullScreen == value) return;
    _fullScreen = value;
    // 只有「手机竖屏播放形态设备 + 横屏视频全屏 + 非受限窗口」需要按旋转锁定
    // 状态选策略；其它情况（平板/2in1/横屏布局折叠内屏、竖屏视频、分屏/悬浮窗/
    // 自由多窗）保持原策略，不做额外读取。
    if (value &&
        _effectivePortraitPlayerForm &&
        !_videoVertical &&
        !WindowFacts.isWindowMode &&
        !WindowFacts.isFreeWindowMode) {
      final autoRotate = await HarmonyChannel.getAutoRotateEnabled();
      if (autoRotate != null) {
        _autoRotateEnabled = autoRotate;
      }
    }
    await _sync();
  }

  static Future<void> _sync({bool force = false}) async {
    if (!OS.isHarmony || !_initialized) return;
    final target = current;
    if (!force && target == _applied) return;
    _applied = target;
    await HarmonyOrientation.apply(target);
  }
}
