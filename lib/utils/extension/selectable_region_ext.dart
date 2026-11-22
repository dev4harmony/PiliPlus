// 上游 2.2.1 的 `SelectableRegionStateExt` 直接实现在本文件里，但依赖
// `lib/scripts/selectable_region.patch` 把 `SelectableRegionState` 的私有成员
// （`selectable` / `selectionDelegate`）放出来。
//
// 鸿蒙用的 Flutter SDK 不打这些补丁（Flutter 3.44 上也没有等价公开 API），所以把
// 扩展的等价实现放在 `packages/material_ui` shim 里 —— 选中文字改由 shim 的
// `SelectionArea` 容器缓存提供，其余方法（`addLaunchMenuIfNeeded` /
// `onMenuPressed` / `hideAndClear`）与上游逐字一致。
//
// 这里只做转出，所有调用点保持上游写法：
//   state.selectedText / state.isUncollapsed / state.addLaunchMenuIfNeeded(...)
// 等价的 patch 位置见 packages/material_ui/lib/src/selection_region_ext.dart。
export 'package:material_ui/selection_region_ext.dart'
    show SelectableRegionStateExt;
