import 'package:flutter/widgets.dart';

/// 监听应用生命周期，进入后台后清理 Flutter 内存图片缓存
class ImageMemoryCleaner with WidgetsBindingObserver {
  ImageMemoryCleaner._internal();

  static final ImageMemoryCleaner instance = ImageMemoryCleaner._internal();

  void register() {
    WidgetsBinding.instance.addObserver(this);
  }

  void unregister() {
    WidgetsBinding.instance.removeObserver(this);
  }

  void clearImageCache() {
    try {
      PaintingBinding.instance.imageCache.clear();
    } catch (_) {
      // 忽略清理过程中的异常
    }
  }

  /// 系统内存压力
  /// 进后台也会给应用发内存压力通知
  @override
  void didHaveMemoryPressure() {
    // 打时间戳便于在 hilog 里确认这条通道（引擎 RequestBackgroundImageCacheCleanup）
    // 是否真的送达；目前没有任何日志证明它被调用过。
    debugPrint(
      'ImageMemoryCleaner: clear image cache on memoryPressure '
      '@${DateTime.now().toIso8601String()}',
    );
    clearImageCache();
  }
}
