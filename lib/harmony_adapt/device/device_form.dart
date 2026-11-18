/// 鸿蒙设备形态在 Dart 侧的镜像：首帧前由原生拉取一次，变化时由原生推送。
///
/// 只保存三个事实，不做任何副作用：
/// - [portraitForm]：是否「细长竖屏」形态（deviceType=phone 且屏幕长宽比≥1.9，
///   直板机 / 大折叠外屏）。决定**非播放页**是否锁竖屏与启动方向；
/// - [portraitPlayerForm]：播放页是否按手机竖屏形态处理（手机类且当前不是
///   横屏适配布局，含 Pura X 内屏 / Pura X View / 阔直板等宽屏手机）。决定
///   **播放页**方向（退出全屏临时转竖屏、竖屏视频锁竖向、全屏转横屏）；
/// - [horizontalLayout]：横屏适配自动值，**仅决定布局**（全页面统一，不区分
///   播放页/非播放页）。鸿蒙上不再提供用户开关：直板机、小折叠、折叠外屏为
///   false；大折叠 / 阔折叠 / 三折叠内屏与平板 / 2in1 为 true。
///
/// 两个方向事实分开：宽屏手机虽然不开横屏适配布局，非播放页仍可横屏；
/// 但播放页要按手机形态处理，避免退出全屏后卡在横屏非全屏状态。
///
/// 判定规则见原生 `DeviceForm.ets`（不读设备型号）：[horizontalLayout] 按
/// deviceType + 折叠显示模式 + 当前屏幕宽高比推导；[portraitForm] 只看屏幕
/// 长宽比；[portraitPlayerForm] 与 [horizontalLayout] 反向（手机类设备）。
abstract final class HarmonyDeviceForm {
  /// 细长竖屏形态（非播放页锁竖屏 / 启动方向用）。
  static bool portraitForm = false;

  /// 播放页按手机竖屏形态处理（播放页方向策略用）。
  static bool portraitPlayerForm = false;

  /// 横屏适配自动值（布局用，全页面统一）。
  static bool horizontalLayout = false;

  static void update({
    required bool portraitForm,
    required bool portraitPlayerForm,
    required bool horizontalLayout,
  }) {
    HarmonyDeviceForm.portraitForm = portraitForm;
    HarmonyDeviceForm.portraitPlayerForm = portraitPlayerForm;
    HarmonyDeviceForm.horizontalLayout = horizontalLayout;
  }
}
