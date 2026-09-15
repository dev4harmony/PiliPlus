/// 鸿蒙分支替身：上游此文件是 jnigen 生成的 Android JNI 绑定（依赖 `jni` 包及
/// android/ 下的 Java 类）。`jni` 的原生构建钩子在鸿蒙目标上不可用，而所有调用点
/// 都由 `Platform.isAndroid` 守卫，鸿蒙运行时不会执行到这里，因此只保留同名 API
/// 形态，实现全部为空操作。
///
/// 如需恢复安卓构建：在 pubspec 中加回 `jni`，再用 `dart run tool/jnigen.dart`
/// 重新生成本文件即可。
library;

/// 对应 jni 的 `JObject`，仅提供调用点用到的 `release()`。
class Runnable {
  const Runnable._();

  static Runnable implement(Object impl) => const Runnable._();

  void release() {}
}

/// 对应 jnigen 生成的 `Runnable` 实现包装。
class $Runnable {
  const $Runnable({required this.run});

  final void Function() run;
}

abstract final class AndroidHelper {
  static bool get isPipMode => false;

  static bool get isPipAvailable => false;

  static bool get isFoldable => false;

  static int sdkInt() => 0;

  static void updatePipActions(int engineId, bool isLive, bool playing) {}

  static void updateDocProvider(bool enabled) {}

  static bool isDomainVerified(String domain) => false;

  static String? openUrl(String url) => null;
}

/// 对应 jnigen 生成的 Java -> Dart 回调注册点。
abstract final class AndroidHelper$ToDart {
  static Runnable? onUserLeaveHint;

  static Runnable? onConfigurationChanged;
}
