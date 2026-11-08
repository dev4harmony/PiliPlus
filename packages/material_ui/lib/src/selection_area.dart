import 'package:flutter/material.dart' as flutter;
import 'package:flutter/rendering.dart' show RenderBox, SelectedContent;
import 'package:flutter/widgets.dart';

/// 空断言兜底的 [SelectionArea]：行为与 SDK 版本一致，只替换默认的上下文菜单构造器。
///
/// 崩溃现场（专栏/文章这类长文 + 可滚动场景，长按弹菜单时必现）：
/// ```
/// #0 SelectableRegionState.endGlyphHeight (selectable_region.dart:1802)
/// #1 SelectableRegionState.contextMenuAnchors (selectable_region.dart:1626)
/// #2 AdaptiveTextSelectionToolbar.selectableRegion (adaptive_text_selection_toolbar.dart:187)
/// #3 SelectionArea._defaultContextMenuBuilder (selection_area.dart:106)
/// ```
/// 根因：SDK 的 `startGlyphHeight` / `endGlyphHeight` 直接对
/// `SelectionGeometry.startSelectionPoint!` / `endSelectionPoint!` 强解包，而这两个
/// 字段按设计可为 null —— 选择端点滚出视口（或被 scrollable 的 keepAlive 撑住）时
/// 就是 null。SDK 内部其它调用点（`_createSelectionOverlay`、`_updateSelectionOverlay`、
/// `selectionEndpoints`）都写了 `?? 另一端点` 的兜底，唯独这两个公开 getter 漏了，
/// 于是 `contextMenuAnchors` 一取就崩。
///
/// 这里不碰 SDK、也不改业务调用点：`SelectableRegionState.selectionEndpoints` 内部
/// 已自带兜底，`SelectionOverlay.lineHeightAtStart/End` 也是同一个 `??` 兜底值，
/// 用它们重建与 `contextMenuAnchors` 等价的锚点即可。
///
/// 注意：如果哪天把本包退回成纯 `export 'package:flutter/material.dart'`，这个兜底
/// 就没了，长文阅读页会重新 `Null check operator used on a null value`。
class SelectionArea extends StatelessWidget {
  /// 与 SDK 版构造签名保持一致，方便无感替换。
  const SelectionArea({
    super.key,
    this.focusNode,
    this.selectionControls,
    this.contextMenuBuilder,
    this.magnifierConfiguration,
    this.onSelectionChanged,
    required this.child,
  });

  /// {@macro flutter.material.SelectionArea.magnifierConfiguration}
  final TextMagnifierConfiguration? magnifierConfiguration;

  /// {@macro flutter.material.SelectionArea.focusNode}
  final FocusNode? focusNode;

  /// {@macro flutter.material.SelectionArea.selectionControls}
  final TextSelectionControls? selectionControls;

  /// {@macro flutter.material.SelectionArea.contextMenuBuilder}
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;

  /// {@macro flutter.material.SelectionArea.onSelectionChanged}
  final ValueChanged<SelectedContent?>? onSelectionChanged;

  /// {@macro flutter.widgets.ProxyWidget.child}
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return flutter.SelectionArea(
      focusNode: focusNode,
      selectionControls: selectionControls,
      contextMenuBuilder: contextMenuBuilder ?? _nullSafeContextMenuBuilder,
      magnifierConfiguration: magnifierConfiguration,
      onSelectionChanged: onSelectionChanged,
      child: child,
    );
  }
}

/// 与 `SelectionArea._defaultContextMenuBuilder` 等价，但锚点不再走会崩的
/// `SelectableRegionState.contextMenuAnchors`。
Widget _nullSafeContextMenuBuilder(
  BuildContext context,
  SelectableRegionState selectableRegionState,
) {
  return flutter.AdaptiveTextSelectionToolbar.buttonItems(
    // 菜单项与 SDK 默认完全一致（复制/全选等），只是换了锚点来源。
    buttonItems: selectableRegionState.contextMenuButtonItems,
    anchors: _contextMenuAnchors(selectableRegionState),
  );
}

/// `SelectableRegionState.contextMenuAnchors` 的 null 安全版本。
///
/// 差异只有一处：右击（secondary tap）时 SDK 用落点定位菜单，而那个落点是私有
/// 字段、应用层拿不到，这里统一按选区几何定位。长按选择的场景与 SDK 完全一致。
TextSelectionToolbarAnchors _contextMenuAnchors(
  SelectableRegionState selectableRegionState,
) {
  final RenderObject? renderObject =
      selectableRegionState.context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return const TextSelectionToolbarAnchors(primaryAnchor: Offset.zero);
  }

  // `selectionOverlay` 标了 @visibleForTesting，但它是 read-only 的公开 getter，
  // 且是两个行高唯一的应用层入口（那两行高本身就是 SDK 里的 `??` 兜底结果）。
  // ignore: invalid_use_of_visible_for_testing_member
  final SelectionOverlay? overlay = selectableRegionState.selectionOverlay;
  final List<TextSelectionPoint> selectionEndpoints;
  try {
    selectionEndpoints = selectableRegionState.selectionEndpoints;
  } on Object {
    // 首尾端点同时为 null（整段选区都在视口外）。SDK 在这一步也会崩，
    // 没有可参照的位置，退化成选区区域左上角。
    return TextSelectionToolbarAnchors(
      primaryAnchor: renderObject.localToGlobal(Offset.zero),
    );
  }

  // 两个行高在 SelectionOverlay 里始终是 `start?.lineHeight ?? end!.lineHeight`
  // 的结果，不会为空；overlay 尚未挂上时给 0，退化为按基线定位。
  return TextSelectionToolbarAnchors.fromSelection(
    renderBox: renderObject,
    startGlyphHeight: overlay?.lineHeightAtStart ?? 0,
    endGlyphHeight: overlay?.lineHeightAtEnd ?? 0,
    selectionEndpoints: selectionEndpoints,
  );
}
