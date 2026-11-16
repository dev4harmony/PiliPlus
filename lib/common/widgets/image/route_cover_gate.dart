import 'package:flutter/widgets.dart';

/// 页面被顶层不透明路由覆盖时，把 [child]（封面图等大图）从树上摘掉、
/// 只显示 [placeholder]，让已解码的图片（`ui.Image` / GPU 纹理）能被回收；
/// 页面重新可见时自动挂回 [child]。
///
/// 依赖 Flutter 的既有行为：`Overlay` 会把被不透明路由盖住的 route 的
/// `TickerMode` 置为 disabled。使用这个信号不需要额外的 NavigatorObserver，
/// 也不会误伤盖在上面的新页面（新页面的 TickerMode 仍是 enabled）。
///
/// 释放原理：卸载 [child] 后图片的 listener 归零，从 live 降级为普通
/// keepAlive 缓存条目（不受 100MB/64MB LRU 上限约束，不会自动淘汰），
/// 所以还需在卸载后的那一帧把 ImageCache 清掉，内存才真正下降。
/// 这里用全局 [ImageCache.clear] 而不是按 key evict：封面的 cache key
/// 经 cached_network_image_ce 内部 ResizeImage 包装、依赖 MediaQuery
/// 尺寸，在 widget 侧无法可靠枚举；而仍被上层页面显示的 live 图片
/// clear 不会动它们，代价只是其余条目返回时走一次磁盘重解码。
class RouteCoverGate extends StatefulWidget {
  const RouteCoverGate({
    super.key,
    required this.child,
    required this.placeholder,
  });

  final Widget child;
  final Widget placeholder;

  @override
  State<RouteCoverGate> createState() => _RouteCoverGateState();
}

class _RouteCoverGateState extends State<RouteCoverGate> {
  bool _covered = false;
  bool _purgedThisCover = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode.of 建立依赖后，覆盖状态变化会再次触发本方法
    final covered = !TickerMode.valuesOf(context).enabled;
    if (covered == _covered) {
      return;
    }
    _covered = covered;
    if (covered && !_purgedThisCover) {
      _purgedThisCover = true;
      // 等这一帧结束：child 已卸载、listener 已归零、图片已从 live
      // 降级为缓存条目，此时清理才真正释放解码内存。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_covered) {
          return;
        }
        final imageCache = PaintingBinding.instance.imageCache;
        debugPrint(
          'RouteCoverGate: 页面被覆盖，清图片缓存 '
          '${imageCache.currentSizeBytes >> 10} KB, '
          'live=${imageCache.liveImageCount}',
        );
        imageCache.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _covered ? widget.placeholder : widget.child;
  }
}
