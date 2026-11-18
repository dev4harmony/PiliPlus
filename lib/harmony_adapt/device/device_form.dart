/// 鸿蒙设备形态在 Dart 侧的镜像：首帧前由原生拉取一次，变化时由原生推送。
///
/// 只保存两个事实，不做任何副作用：
/// - [portraitForm]：是否「细长竖屏」形态（直板机 / 大折叠外屏），供方向策略
///   （`OrientationPolicy`）决定「锁竖屏 / 跟随系统」；
/// - [horizontalLayout]：横屏适配自动值，**仅决定布局**（全页面统一，不区分
///   播放页/非播放页）。鸿蒙上不再提供用户开关：直板机、小折叠、折叠外屏为
///   false；大折叠 / 阔折叠 / 三折叠内屏与平板 / 2in1 为 true。
///
/// 判定规则见原生 `DeviceForm.ets`（只按 deviceType + 折叠显示模式 + 当前
/// 屏幕宽高比，不读设备型号）。
abstract final class HarmonyDeviceForm {
  /// 细长竖屏形态（方向策略用）。
  static bool portraitForm = false;

  /// 横屏适配自动值（布局用，全页面统一）。
  static bool horizontalLayout = false;

  static void update({
    required bool portraitForm,
    required bool horizontalLayout,
  }) {
    HarmonyDeviceForm.portraitForm = portraitForm;
    HarmonyDeviceForm.horizontalLayout = horizontalLayout;
  }
}
