/// 鸿蒙窗口形态在 Dart 侧的事实状态。
///
/// 只保存「窗口现在是什么形态」，不做任何副作用：小窗缩放、装饰栏策略等由
/// [WindowBridge] 依据这些事实决定。数据来源是原生上报的窗口快照
/// （getWindowSnapshot 拉取一次 + onWindowSnapshot 推送），快照字段全部为
/// bool/number，见 ArkTS 侧 WindowState.readSnapshot。
///
/// [landscape] 是唯一的例外：它表示「播放器当前是否以全屏横屏渲染」，原生侧
/// 不持有这个判断，由 WindowBridge.syncPlayerLandscape 回填。
abstract final class WindowFacts {
  /// 是否处于系统「自由窗口模式」（2in1/PC、平板自由多窗、平板电脑模式）。
  static bool isFreeWindowMode = false;

  /// 是否处于系统小窗/受限窗口（原生 windowStatus 为 FLOATING）。
  ///
  /// 自由窗口模式下窗口同样恒为 FLOATING，故两者要结合看，见
  /// [isMiniWindowLandscape]。
  static bool isMiniWindow = false;

  /// 播放器当前是否按全屏横屏渲染。原生不持有，由播放器回传。
  static bool landscape = false;

  /// 应用窗口是否处于受限窗口模式（分屏/自由多窗/悬浮窗等非全屏窗口）。
  ///
  /// 此模式下窗口宽高比不代表设备方向，且窗口无法旋转到全屏横屏，仍应按
  /// isFullScreen 渲染全屏布局。
  static bool isWindowMode = false;

  /// 原生自绘标题带是否可见（仅自由窗口形态有意义）。
  static bool titleBarVisible = false;

  /// 原生自绘标题带是否被鼠标唤出（仅「全屏自动收起」态可能为 true）。
  ///
  /// 唤出期间原生会把标题带高度并进顶部安全区，播放器的顶部那排按钮据此
  /// 整体下移，避免被呼出的标题带盖住。
  static bool titleBarRevealed = false;

  /// 原生自绘标题带高度（vp，原生 TITLE_BAR_HEIGHT）。
  static double titleBarHeight = 0;

  /// 窗口是否处于内容全屏（隐藏系统栏，窗口仍占满屏）。
  static bool isContentFullScreen = false;

  /// 是否「横屏小窗」：系统小窗内把横屏视频切到了全屏。
  ///
  /// 实测仅此状态下进画中画会黑屏（小窗内不全屏进画中画画面正常），也仅此
  /// 状态需要套 0.75 缩放与 enableLandscapeMultiWindow。自由窗口模式虽然同样
  /// 是 FLOATING，但那是普通桌面窗口，不适用。
  static bool get isMiniWindowLandscape =>
      isMiniWindow && landscape && !isFreeWindowMode;

  /// 应用一次原生窗口快照。
  ///
  /// 缺字段（null）时保留旧值，避免旧版本原生只推部分字段时把状态清成
  /// false。landscape 不在快照内，不在此更新。
  static void applySnapshot(Map<Object?, Object?>? snapshot) {
    if (snapshot == null) return;
    bool? readBool(String key) {
      final value = snapshot[key];
      return value is bool ? value : null;
    }

    isFreeWindowMode = readBool('isFreeWindowMode') ?? isFreeWindowMode;
    isMiniWindow = readBool('isMiniWindow') ?? isMiniWindow;
    isWindowMode = readBool('isWindowMode') ?? isWindowMode;
    titleBarVisible = readBool('titleBarVisible') ?? titleBarVisible;
    titleBarRevealed = readBool('titleBarRevealed') ?? false;
    isContentFullScreen = readBool('contentFullScreen') ?? isContentFullScreen;
    titleBarHeight =
        (snapshot['titleBarHeight'] as num?)?.toDouble() ?? titleBarHeight;
  }
}
