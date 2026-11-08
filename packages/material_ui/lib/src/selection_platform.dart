import 'package:flutter/foundation.dart' show defaultTargetPlatform;

/// 当前平台是否是鸿蒙。
///
/// 这里刻意用 `toString()` 比较而不是 `== TargetPlatform.ohos`：本包要能被
/// 没有 `TargetPlatform.ohos` 枚举的官方 SDK 编译（那时只是永远返回 false），
/// 只有鸿蒙 fork 才会命中。
bool get isOhosPlatform => defaultTargetPlatform.toString() == 'TargetPlatform.ohos';
