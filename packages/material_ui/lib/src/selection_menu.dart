/// 选中文字工具栏里「分享 / 打开 / 站内搜索」三个动作的实现。
///
/// ## 为什么要在 shim 里再做一遍
///
/// framework 自带的分享项只在 Android 且选区未折叠时出现：
/// `SelectableRegion.getSelectableButtonItems`（SDK `widgets/selectable_region.dart:302`）
/// 里对 `TargetPlatform.ohos` 直接给 `false`，而且它按下后走的是
/// `SystemChannels.platform.invokeMethod('Share.invoke', ...)` —— 鸿蒙引擎没有这个
/// method channel，按了没反应。所以这三个按钮只能自己做。
///
/// ## 为什么用注入而不是直接 import
///
/// 本包是被 app 依赖的底层包（path 依赖），不能反向 import `package:PiliPlus/...`，
/// 也不能为了分享拖进 `share_plus`。所以实际动作由 app 在启动时通过
/// [SelectionMenuConfig] 注入一次（见 `lib/utils/selection_menu_wiring.dart`），
/// 这里只保留「什么时候该出现哪个按钮」的逻辑。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/src/ohos_selection_theme.dart';
import 'package:material_ui/src/selection_platform.dart';
import 'package:material_ui/src/selection_toolbar.dart';

/// app 侧注入的三个动作。未注入的项不会出现在菜单里。
class SelectionMenuConfig {
  const SelectionMenuConfig._();

  /// 分享纯文本（app 侧接 `ShareUtils.shareText`）。
  static void Function(String text)? shareText;

  /// 打开选中的链接（app 侧接 `PageUtils.handleWebview`）。
  static void Function(String text)? openLink;

  /// 站内搜索选中文字（app 侧接搜索结果页路由）。
  static void Function(String text)? searchText;

  /// 清空已注入的动作，主要给测试用。
  static void reset() {
    shareText = null;
    openLink = null;
    searchText = null;
  }
}

/// 移动端平台名（桌面端不提供分享按钮：`ShareUtils` 在桌面端只是复制，按钮没意义）。
///
/// 这里比对 `toString()` 而不是写 `TargetPlatform.ohos` 之类的枚举字面量：本包要能
/// 被没有 `TargetPlatform.ohos` 的官方 SDK 编译通过（那时只是永远不命中鸿蒙）。
const Set<String> _mobilePlatformNames = {
  'TargetPlatform.android',
  'TargetPlatform.iOS',
  'TargetPlatform.fuchsia',
  'TargetPlatform.ohos',
};

bool _isMobile(TargetPlatform platform) =>
    _mobilePlatformNames.contains(platform.toString());

final RegExp _schemeRegex = RegExp(r'[\w\-]+://\S');

/// 把「分享 / 打开 / 站内搜索」三项加工进 `buttonItems`。
///
/// **顺序：全部追加在末尾**（app 注入的项统一排在 SDK 自带项之后），这样系统/框架的
/// 原生项始终占据工具栏前几位，不会被应用自定义动作挤到折叠区里。三项之间的相对
/// 顺序是：分享 → 打开/站内搜索。
///
/// 两个路径（`SelectableText` 的 [EditableTextState] 与 [SelectionArea] 的
/// [SelectableRegionState]）共用这一份逻辑，保证多端一致。
List<ContextMenuButtonItem> ensureSelectionMenuButtons(
  List<ContextMenuButtonItem> buttonItems, {
  required String? Function() selectedTextOf,
  required VoidCallback hideToolbar,

  /// 覆盖平台判断，仅供测试；缺省取 [defaultTargetPlatform]。
  TargetPlatform? platform,
}) {
  final TargetPlatform target = platform ?? defaultTargetPlatform;
  if (_isMobile(target) && SelectionMenuConfig.shareText != null) {
    // framework 默认的分享项在鸿蒙上无效，先清掉再补自己的。
    buttonItems
      ..removeWhere((item) => item.type == ContextMenuButtonType.share)
      ..add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.share,
          onPressed: () {
            final String? text = selectedTextOf();
            hideToolbar();
            if (text != null && text.trim().isNotEmpty) {
              SelectionMenuConfig.shareText?.call(text);
            }
          },
        ),
      );
  }

  final String? text = selectedTextOf()?.trim();
  final bool isScheme = text != null && _schemeRegex.hasMatch(text);
  final void Function(String text)? action = isScheme
      ? SelectionMenuConfig.openLink
      : SelectionMenuConfig.searchText;
  if (text == null || text.isEmpty || action == null) {
    return buttonItems;
  }
  buttonItems.add(
    ContextMenuButtonItem(
      label: isScheme ? '打开' : '站内搜索',
      onPressed: () {
        hideToolbar();
        action(text);
      },
    ),
  );
  return buttonItems;
}

/// 记录「最近一次选区内容」，供 [buildSelectionContextMenu] 取用。
///
/// [SelectionArea] 这条路径拿不到选中文字：`SelectableRegionState._selectable` 是私有
/// 的，公开的 `textEditingValue` 只是占位符 `'_'` / `'__'`（`selectable_region.dart:558`
/// 与 `:1891`），`onSelectionChanged` 又只给内容不给 state。可行的公开入口只有我们
/// 自己那层 [SelectionContainer] 的 delegate（`SelectionHandler.getSelectedContent()`），
/// 所以由 [EdgeClampingSelectionContainerDelegate] 在每次选区事件后把文本记在这里。
///
/// 同一时刻只有一个活动选区，单槽缓存足够；每次事件都会覆盖，不存在读到上一页残留
/// 文本的路径（弹菜单必然先有选区事件）。
class SelectionMenuSelectionCache {
  const SelectionMenuSelectionCache._();

  static String? _plainText;

  /// 最近一次选区内容；空选区为 null。
  static String? get plainText => _plainText;

  /// 由选区容器在事件分发后调用。
  static void record(String? text) {
    _plainText = (text == null || text.isEmpty) ? null : text;
  }
}

/// [SelectionArea] 路径（[SelectableRegionState]）的上下文菜单。
///
/// 与 SDK 默认菜单相比只多三件事：换成 null 安全的锚点（
/// [nullSafeContextMenuAnchors]）、选中文字从 [SelectionMenuSelectionCache] 取、
/// 追加分享等按钮。
///
/// 鸿蒙上换成 [OhosTextSelectionToolbar]（40vp 胶囊 + 原生对齐规则），锚点用
/// [ohosToolbarAnchors]；其它平台保持 SDK 的 Material 菜单。
Widget buildSelectionContextMenu(
  BuildContext context,
  SelectableRegionState selectableRegionState,
) {
  final List<ContextMenuButtonItem> buttonItems = ensureSelectionMenuButtons(
    selectableRegionState.contextMenuButtonItems,
    selectedTextOf: () => SelectionMenuSelectionCache.plainText,
    hideToolbar: selectableRegionState.hideToolbar,
  );
  if (isOhosPlatform) {
    final Widget? ohos = _buildOhosToolbarForRegion(
      selectableRegionState,
      buttonItems,
    );
    if (ohos != null) {
      return ohos;
    }
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: buttonItems,
    anchors: nullSafeContextMenuAnchors(selectableRegionState),
  );
}

/// 鸿蒙工具栏锚点（root overlay 全局坐标）。
class OhosToolbarAnchors {
  /// 创建锚点。
  const OhosToolbarAnchors({
    required this.anchorX,
    required this.anchorTop,
    required this.anchorBottom,
    required this.isCollapsed,
  });

  /// 选区**两端**端点的 x 中点。多行选区时与包围盒中心不同 —— 原生
  /// `ComputeSelectMenuPosition` 用的是 `(firstHandle.X + secondHandle.X) / 2`。
  final double anchorX;

  /// 选区首行上沿（已夹进文本控件可视区）。
  final double anchorTop;

  /// 选区末行下沿（已夹进文本控件可视区）。
  final double anchorBottom;

  /// 是否折叠选区（光标）。折叠时没有手柄球，菜单与文字的间距只算 8vp。
  final bool isCollapsed;
}

/// 由选区端点算鸿蒙菜单锚点。
///
/// 两端点都是**渲染盒局部坐标**（`TextSelectionPoint.point`），这里一次转成全局；
/// y 再夹进文本控件的可视矩形，避免选区滚出视口后菜单被顶到屏幕边缘。
OhosToolbarAnchors ohosToolbarAnchors({
  required RenderBox renderBox,
  required List<TextSelectionPoint> selectionEndpoints,
  required double lineHeight,
}) {
  final Offset start = renderBox.localToGlobal(selectionEndpoints.first.point);
  final Offset end = renderBox.localToGlobal(selectionEndpoints.last.point);
  final Rect field = Rect.fromPoints(
    renderBox.localToGlobal(Offset.zero),
    renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero)),
  );
  double clampY(double value) {
    if (value < field.top) {
      return field.top;
    }
    return value > field.bottom ? field.bottom : value;
  }

  final double height = lineHeight > 0 ? lineHeight : 0;
  return OhosToolbarAnchors(
    anchorX: (start.dx + end.dx) / 2,
    // 端点 dy 是行**下沿**，减一个行高才是首行上沿。
    anchorTop: clampY(math.min(start.dy, end.dy) - height),
    anchorBottom: clampY(math.max(start.dy, end.dy)),
    isCollapsed: (start - end).distance < 0.5,
  );
}

/// [SelectionArea]（[SelectableRegionState]）路径的鸿蒙工具栏；
/// 拿不到几何信息时返回 null（退回 Material）。
Widget? _buildOhosToolbarForRegion(
  SelectableRegionState selectableRegionState,
  List<ContextMenuButtonItem> buttonItems,
) {
  final RenderObject? renderObject = selectableRegionState.context
      .findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return null;
  }
  // ignore: invalid_use_of_visible_for_testing_member
  final SelectionOverlay? overlay = selectableRegionState.selectionOverlay;
  final List<TextSelectionPoint> endpoints;
  try {
    endpoints = selectableRegionState.selectionEndpoints;
  } on Object {
    return null;
  }
  return buildOhosTextSelectionToolbar(
    renderBox: renderObject,
    endpoints: endpoints,
    lineHeight: overlay?.lineHeightAtStart ?? 0,
    buttonItems: buttonItems,
  );
}

/// [SelectableText]（只读 [EditableText]）路径的鸿蒙工具栏。
///
/// 返回 null 表示拿不到选区几何（首帧还没 layout、选区非法），调用方应退回
/// SDK 的 Material 菜单。
Widget? _buildOhosToolbarForEditableText(
  EditableTextState editableTextState,
  List<ContextMenuButtonItem> buttonItems,
) {
  final TextSelection selection = editableTextState.textEditingValue.selection;
  if (!selection.isValid) {
    return null;
  }
  final RenderEditable renderEditable;
  final List<TextSelectionPoint> endpoints;
  try {
    renderEditable = editableTextState.renderEditable;
    endpoints = renderEditable.getEndpointsForSelection(selection);
  } on Object {
    // 首帧还没 layout（`renderEditable` 是 late final）或选区非法。
    return null;
  }
  return buildOhosTextSelectionToolbar(
    renderBox: renderEditable,
    endpoints: endpoints,
    lineHeight: renderEditable.preferredLineHeight,
    buttonItems: buttonItems,
  );
}

/// 直接按「渲染盒 + 选区端点」构建鸿蒙工具栏。
///
/// 给**非 SDK 的** `EditableTextState` 用：仓库里
/// `lib/common/widgets/flutter/text_field/` 是 SDK 的改造副本，它的
/// `EditableTextState` 与 `RenderEditable` 都自成一型、传不进
/// [buildEditableTextSelectionMenu]；但两边都是 `RenderBox`，端点也共用 SDK 的
/// [TextSelectionPoint]，所以把几何拆出来传即可复用同一条实现
/// （发布动态 / 发布评论的输入框就走这里）。
///
/// 非鸿蒙或端点为空时返回 null，调用方退回自己的 Material 菜单。
Widget? buildOhosTextSelectionToolbar({
  required RenderBox renderBox,
  required List<TextSelectionPoint> endpoints,
  required double lineHeight,
  required List<ContextMenuButtonItem> buttonItems,
}) {
  if (!isOhosPlatform || endpoints.isEmpty) {
    return null;
  }
  final OhosToolbarAnchors anchors = ohosToolbarAnchors(
    renderBox: renderBox,
    selectionEndpoints: endpoints,
    lineHeight: lineHeight,
  );
  return OhosTextSelectionToolbar(
    anchorX: anchors.anchorX,
    anchorTop: anchors.anchorTop,
    anchorBottom: anchors.anchorBottom,
    // 上方：非折叠选区的起手柄球挂在首行上沿之外，菜单要连球一起避开
    // （与文字间距 8 + 手柄直径 14）；折叠光标上方只有输入框自己画的光标，留 8 即可。
    gapAbove: anchors.isCollapsed
        ? OhosSelectionTheme.menuSpacingWithText
        : OhosSelectionTheme.menuSpacingWithText +
              OhosSelectionTheme.handleOuterDiameter,
    // 下方：止手柄的球、折叠光标的球都挂在行下沿之外占 14vp，恒定 8 + 14，
    // 否则菜单会压住把柄（真机反馈）。
    gapBelow:
        OhosSelectionTheme.menuSpacingWithText +
        OhosSelectionTheme.handleOuterDiameter,
    buttonItems: buttonItems,
  );
}

/// `SelectableRegionState.contextMenuAnchors` 的 null 安全版本。
///
/// SDK 的实现在选区端点滚出视口时会对 `startSelectionPoint!` / `endSelectionPoint!`
/// 强解包并抛 `Null check operator used on a null value`（见
/// `src/selection_area.dart` 顶部注释里的崩溃栈）。这里改用三个自带兜底的公开数据源：
/// `selectionEndpoints`（内部 `start?.localPosition ?? end!.localPosition`）与
/// `SelectionOverlay.lineHeightAtStart/End`（内部 `start?.lineHeight ?? end!.lineHeight`）。
///
/// 行为差异只有一处：右击（secondary tap）时 SDK 用落点定位菜单，而那个落点是私有
/// 字段、应用层拿不到，这里统一按选区几何定位；长按选择的场景与 SDK 完全一致。
TextSelectionToolbarAnchors nullSafeContextMenuAnchors(
  SelectableRegionState selectableRegionState,
) {
  final RenderObject? renderObject = selectableRegionState.context
      .findRenderObject();
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

  return TextSelectionToolbarAnchors.fromSelection(
    renderBox: renderObject,
    startGlyphHeight: overlay?.lineHeightAtStart ?? 0,
    endGlyphHeight: overlay?.lineHeightAtEnd ?? 0,
    selectionEndpoints: selectionEndpoints,
  );
}

/// [SelectableText]（内部为只读 [EditableText]）路径的上下文菜单。
///
/// `EditableTextState` 有公开的 `contextMenuAnchors`，不需要 null 兜底；这里只是把
/// 分享等按钮加工抽到 shim，和 [SelectionArea] 路径共用同一份实现。
/// 鸿蒙上同样换成 [OhosTextSelectionToolbar]。
Widget buildEditableTextSelectionMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final List<ContextMenuButtonItem> buttonItems = ensureSelectionMenuButtons(
    editableTextState.contextMenuButtonItems,
    selectedTextOf: () => _selectedTextOf(editableTextState),
    hideToolbar: editableTextState.hideToolbar,
  );
  return buildEditableTextSelectionMenuWithItems(
    editableTextState,
    buttonItems,
  );
}

/// 用**调用方自己组好的**菜单项渲染 `SelectableText` / `TextField` 的上下文菜单。
///
/// 只有需要额外插自定义按钮的调用点才用得上（目前是「自由复制」弹窗：它要加
/// 「文本/表情」「加入过滤」）。鸿蒙上得到与默认菜单一致的 [OhosTextSelectionToolbar]；
/// 其它平台仍是 Material 菜单。
Widget buildEditableTextSelectionMenuWithItems(
  EditableTextState editableTextState,
  List<ContextMenuButtonItem> buttonItems,
) {
  if (isOhosPlatform) {
    final Widget? ohos = _buildOhosToolbarForEditableText(
      editableTextState,
      buttonItems,
    );
    if (ohos != null) {
      return ohos;
    }
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: buttonItems,
    anchors: editableTextState.contextMenuAnchors,
  );
}

/// 读取 [EditableTextState] 当前选中文本，无选中返回 null。
String? _selectedTextOf(EditableTextState state) {
  final TextSelection selection = state.textEditingValue.selection;
  if (!selection.isValid || selection.isCollapsed) {
    return null;
  }
  return selection.textInside(state.textEditingValue.text);
}
