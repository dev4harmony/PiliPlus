import 'package:flutter/material.dart'
    show
        ContextMenuButtonItem,
        SelectableRegionState,
        TextSelectionToolbarAnchors;
import 'package:flutter/material.dart' as flutter;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, Widget;
import 'package:material_ui/src/selection_menu.dart';
import 'package:material_ui/src/selection_platform.dart';

/// SDK [flutter.AdaptiveTextSelectionToolbar] 的同名兼容实现。
///
/// 上游业务代码（`SelectionText` / 动态 / 直播 / 评论 / 各弹窗）都是先自己组好
/// `buttonItems`，再 `AdaptiveTextSelectionToolbar.buttonItems(...)` 出菜单。
/// 还原成上游写法后，鸿蒙样式（胶囊工具栏、原生定位、折叠二级菜单）和「分享」
/// 按钮就没地方挂了，于是把这两个动作挪到这里：
///
/// 1. 渲染前统一补「分享」项（[ensureShareButton]），保持还原前的菜单内容；
/// 2. 若本次菜单由 shim 的 [SelectionArea] 构建（构造时能拿到
///    [SelectableRegionState]），换成鸿蒙样式工具栏
///    （[buildOhosToolbarForRegion]），拿不到几何信息时退回 SDK 的 Material 菜单。
///
/// 构造函数与 SDK 的 `buttonItems` / `children` 一致，隐藏 SDK 同名类后业务代码
/// 无需改动；等鸿蒙样式工具栏下线时可以连同本文件一起删除。
///
/// 注意：只实现了 `buttonItems` / `children` 两个构造（仓库里实际用到的），
/// SDK 的 `editable` / `editableText` / `selectableRegion` 三个便捷构造没有被
/// 用到 —— 对仓库里那份 `EditableTextState` 改造副本它们本来也传不进去。
class AdaptiveTextSelectionToolbar extends StatelessWidget {
  /// 直接给子控件（见 SDK 同名构造）。
  ///
  /// 不能是 `const`：`buttonItems` 构造要在构造期抓取当前 [SelectableRegionState]。
  // ignore: prefer_const_constructors_in_immutables
  AdaptiveTextSelectionToolbar({
    super.key,
    required this.children,
    required this.anchors,
  }) : buttonItems = null,
       state = null;

  /// 由 [ContextMenuButtonItem] 列表构建（见 SDK 同名构造）。
  AdaptiveTextSelectionToolbar.buttonItems({
    super.key,
    required List<ContextMenuButtonItem> buttonItems,
    required this.anchors,
  }) : buttonItems = List<ContextMenuButtonItem>.unmodifiable(buttonItems),
       children = null,
       // 只有在 shim 的 SelectionArea 调用 contextMenuBuilder 期间才非空，
       // 见 SelectionMenuSelectionCache.beginMenu。
       state = SelectionMenuSelectionCache.currentState;

  /// 直接渲染的子控件；与 [buttonItems] 二选一。
  final List<Widget>? children;

  /// 由 [ContextMenuButtonItem] 生成的菜单项；与 [children] 二选一。
  final List<ContextMenuButtonItem>? buttonItems;

  /// 菜单锚点（SDK 语义，仅在退回 Material 菜单时使用）。
  final TextSelectionToolbarAnchors anchors;

  /// 构建本菜单的 [SelectableRegionState]；非 SelectionArea 路径为 null。
  final SelectableRegionState? state;

  /// SDK 同名静态方法，透传给 [flutter.AdaptiveTextSelectionToolbar]。
  static String getButtonLabel(
    BuildContext context,
    ContextMenuButtonItem buttonItem,
  ) {
    return flutter.AdaptiveTextSelectionToolbar.getButtonLabel(
      context,
      buttonItem,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ContextMenuButtonItem>? items = buttonItems;
    if (items == null) {
      return flutter.AdaptiveTextSelectionToolbar(
        anchors: anchors,
        children: children!,
      );
    }
    final SelectableRegionState? state = this.state;
    final List<ContextMenuButtonItem> decorated =
        List<ContextMenuButtonItem>.of(items);
    if (state != null) {
      // 只在菜单位于 SelectionArea 内时补分享：那条路径才有可靠的选中文字
      // （SelectionMenuSelectionCache），文本输入框的菜单仍保持 SDK 内容。
      ensureShareButton(
        decorated,
        selectedTextOf: () => SelectionMenuSelectionCache.plainText,
        hideToolbar: state.hideToolbar,
      );
      if (isOhosPlatform) {
        final Widget? ohos = buildOhosToolbarForRegion(state, decorated);
        if (ohos != null) {
          return ohos;
        }
      }
    }
    return flutter.AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: decorated,
    );
  }
}
