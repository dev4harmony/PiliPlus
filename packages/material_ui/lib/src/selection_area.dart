import 'package:flutter/material.dart' as flutter;
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/widgets.dart';
import 'package:material_ui/src/selection_edge_clamp.dart';
import 'package:material_ui/src/selection_handle.dart';
import 'package:material_ui/src/selection_magnifier.dart';
import 'package:material_ui/src/selection_menu.dart';
import 'package:material_ui/src/selection_platform.dart';

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
/// 用它们重建与 `contextMenuAnchors` 等价的锚点即可（见
/// `src/selection_menu.dart` 的 `nullSafeContextMenuAnchors`）。
///
/// 菜单项本身也换成了本包自己的实现：鸿蒙上 framework 不给分享项、且它走
/// `Share.invoke` 通道（引擎没有），改由 app 注入的 [SelectionMenuConfig] 提供。
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
      // 鸿蒙用「杆 + 球」手柄（见 src/selection_handle.dart）；其它平台保持
      // SDK 按平台自选的结果，不传就用 SDK 的默认值。
      selectionControls: selectionControls ??
          (isOhosPlatform ? ohosTextSelectionHandleControls : null),
      contextMenuBuilder: contextMenuBuilder ?? _nullSafeContextMenuBuilder,
      // 鸿蒙用 112×72 的胶囊镜片（见 src/selection_magnifier.dart）；不传时 SDK 会回落到
      // Material 的 77×38。其它平台保持 null，让 SDK 自己按平台挑。
      magnifierConfiguration:
          magnifierConfiguration ??
          (isOhosPlatform ? ohosTextMagnifierConfiguration : null),
      onSelectionChanged: onSelectionChanged,
      // 手柄拖出文字左右边界时，SDK 会把端点吸附到整段的首/尾（见
      // selection_edge_clamp.dart 的说明）。这层容器在事件下发到叶子前把坐标夹回
      // 手指所在那一行，让“整段被选中”变回“选到手指那一行”。
      child: EdgeClampingSelectionScope(child: child),
    );
  }
}

/// 默认菜单：本包自己的实现（null 安全锚点 + 分享/打开/站内搜索按钮）。
Widget _nullSafeContextMenuBuilder(
  BuildContext context,
  SelectableRegionState selectableRegionState,
) {
  return buildSelectionContextMenu(context, selectableRegionState);
}
