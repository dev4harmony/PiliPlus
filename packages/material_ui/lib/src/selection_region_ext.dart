import 'package:flutter/material.dart'
    show ContextMenuButtonItem, SelectableRegionState;
import 'package:flutter/widgets.dart' show ValueChanged, ValueGetter;
import 'package:material_ui/src/selection_menu.dart';

/// 上游 `lib/utils/extension/selectable_region_ext.dart` 的等价实现。
///
/// 上游这份扩展依赖 `lib/scripts/selectable_region.patch` 给
/// [SelectableRegionState] 补了两个公开成员：
///
/// ```dart
/// Selectable? get selectable;              // 用来取 getSelectedContent()
/// SelectionGeometry get selectionDelegate; // 用来判断 status == uncollapsed
/// ```
///
/// 鸿蒙用的 Flutter SDK（3.44/3.47）不打这个补丁，应用层也拿不到这两个私有字段。
/// 所以在 shim 里换一条等价的公开路径：
///
///   - `SelectionArea` 会在选区变化时把当前选中文字记到
///     [SelectionMenuSelectionCache]（见 `src/selection_area.dart`、
///     `src/selection_edge_clamp.dart`）；
///   - [selectedText] 直接读缓存，[isUncollapsed] 退化成「缓存里有非空文字」。
///
/// 其余四个方法（[addLaunchMenuIfNeeded]、[onMenuPressed]、[hideAndClear]）与上游
/// 逐字一致，只把 app 侧的「打开 / 站内搜索」两个动作换成
/// [SelectionMenuConfig] 注入（本包不能反向 import `package:PiliPlus/...`）。
///
/// 应用侧 `lib/utils/extension/selectable_region_ext.dart` 把它原样转出，所有
/// 调用点保持上游写法；等鸿蒙 SDK 打上 `selectable_region.patch` 之后，把本文件
/// 删掉、恢复上游实现即可。
extension SelectableRegionStateExt on SelectableRegionState {
  static final _schemeRegex = RegExp(r'[\w\-]+://\S');

  /// 在工具栏里插入「打开 / 站内搜索」（上游同名方法）。
  void addLaunchMenuIfNeeded(
    List<ContextMenuButtonItem> buttonItems, {
    required int index,
  }) {
    if (isUncollapsed) {
      final isScheme = selectedText?.startsWith(_schemeRegex) == true;
      buttonItems.insertOrAdd(
        index,
        ContextMenuButtonItem(
          label: isScheme ? '打开' : '站内搜索',
          onPressed: () => onMenuPressed(
            isScheme
                ? SelectionMenuConfig.openLink ?? (_) {}
                : SelectionMenuConfig.searchText ?? (_) {},
          ),
        ),
      );
    }
  }

  // TODO(ohos): 上游是 `selectable?.getSelectedContent()?.plainText`
  // （`lib/scripts/selectable_region.patch` 放出的 `selectable`）。
  // 鸿蒙 SDK 未打补丁，改读 shim 选区容器缓存的文本，见文件头说明。
  String? get selectedText => SelectionMenuSelectionCache.plainText;

  // TODO(ohos): 上游是
  // `selectionDelegate.value.status == SelectionStatus.uncollapsed`。
  // 同上依赖 SDK 补丁，这里退化成「缓存的选中文字非空」。
  bool get isUncollapsed => selectedText != null;

  /// 取出选中文字 → 收起工具栏并清空选区 → 回调（上游同名方法）。
  void onMenuPressed(
    ValueChanged<String> callback, {
    ValueGetter<String?>? content,
  }) {
    final text = content?.call() ?? selectedText;
    hideAndClear();
    if (text != null && text.isNotEmpty) {
      callback(text);
    }
  }

  /// 收起工具栏并清空选区（上游同名方法）。
  void hideAndClear() {
    hideToolbar();
    clearSelection();
  }
}

/// 与 app 侧 `lib/utils/extension/iterable_ext.dart` 的 `insertOrAdd` 相同语义。
extension _InsertOrAddExt<T> on List<T> {
  void insertOrAdd(int index, T element) {
    if (length <= index) {
      add(element);
    } else {
      insert(index, element);
    }
  }
}
