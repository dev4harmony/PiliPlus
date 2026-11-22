/// 上游 `lib/utils/extension/selectable_region_ext.dart` 的等价扩展（单独作为公开
/// 入口导出，app 侧那个文件原样转出它，上游调用点的 import 保持不变）。
///
/// 单独开一个入口而不是从 `material_ui.dart` 一起导出，是为了让 app 侧对
/// `PiliPlus/utils/extension/selectable_region_ext.dart` 的 import 仍然是「必要」的
/// （否则两条路径都能拿到同一个扩展，分析器会报 unnecessary_import）。
library;

export 'src/selection_region_ext.dart' show SelectableRegionStateExt;
