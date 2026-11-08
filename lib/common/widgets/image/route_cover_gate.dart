import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 页面被顶层不透明路由覆盖时，把 [child]（封面图等大图）从树上摘掉、
/// 只显示 [placeholder]，让已解码的图片（`ui.Image` / GPU 纹理）能被回收；
/// 页面重新可见时自动挂回 [child]。
///
/// 依赖 Flutter 的既有行为：`Overlay` 会把被不透明路由盖住的 route 的
/// `TickerMode` 置为 disabled。使用这个信号不需要额外的 NavigatorObserver，
/// 也不会误伤盖在上面的新页面（新页面的 TickerMode 仍是 enabled）。
class RouteCoverGate extends StatelessWidget {
  const RouteCoverGate({
    super.key,
    required this.child,
    required this.placeholder,
  });

  final Widget child;
  final Widget placeholder;

  /// 同一次覆盖只清一次图片缓存。
  static bool _cacheCleared = false;

  @override
  Widget build(BuildContext context) {
    if (TickerMode.valuesOf(context).enabled) {
      _cacheCleared = false;
      return child;
    }
    if (!_cacheCleared) {
      _cacheCleared = true;
      // ImageCache 自己还持有一份解码结果，只销毁 widget 的引用回收不掉，
      // 等这批图片子树卸载后的这一帧再清。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final imageCache = PaintingBinding.instance.imageCache;
        if (kDebugMode) {
          debugPrint(
            'RouteCoverGate: 页面被覆盖，清图片缓存 '
            '${imageCache.currentSizeBytes >> 10} KB, '
            'live=${imageCache.liveImageCount}',
          );
        }
        imageCache.clear();
      });
    }
    return placeholder;
  }
}
