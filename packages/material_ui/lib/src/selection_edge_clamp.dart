import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/src/selection_menu.dart';

/// 把“越界拖拽”的选区边吸附到手指所在那一行，而不是整段的首/尾。
///
/// ## 为什么需要它
///
/// 专栏/文章页是 `SelectionArea` + `CustomScrollView` + 逐段 `htmlRender`，一段文字
/// 就是 `RenderParagraph` 里的**一个** `Selectable`：`RenderParagraph` 只在
/// PlaceholderSpan 处切分 `_SelectableFragment`（SDK
/// `rendering/paragraph.dart:_createSelectableFragments`），而该 fragment 的 `_rect`
/// 是这一段**所有行 box 的并集**（`paragraph.dart:3589 Rect get _rect`）。
///
/// 拖动手柄时，SDK 在 `_SelectableFragment._updateSelectionEdge` 里调
/// `SelectionUtils.adjustDragOffset(_rect, localPosition)`（`paragraph.dart:1981`），
/// 这个方法只有两个出口（`rendering/selection.dart:355-371`）：
///
/// ```dart
/// if (point.dy <= rect.top || point.dy <= rect.bottom && point.dx <= rect.left) {
///   return direction == ltr ? rect.topLeft : rect.topRight;      // Area 1
/// } else {
///   return direction == ltr ? rect.bottomRight : rect.bottomLeft; // Area 2
/// }
/// ```
///
/// 于是手指只要横向滑出文字边界（哪怕正对着第 3 行），端点就会被拉去**整段的
/// 起点/末尾** —— 表现为“整段都被选中”。这不是鸿蒙 fork 的差异：
/// `flutter/flutter@master` 的 `adjustDragOffset`、`_updateSelectionEdge` 与本地
/// fork 逐行相同，所以只能由应用层在**事件下发到叶子之前**改写坐标。
///
/// ## 怎么改写
///
/// 手柄的拖拽手势在 SDK 的 `SelectionHandleOverlay` 里（自带
/// `RawGestureDetector + PanGestureRecognizer`），`TextSelectionControls.buildHandle`
/// 只拿得到 `onTap`，应用层拦不到 delta；但 `SelectionContainer` /
/// `StaticSelectionContainerDelegate` 是公开 API，`dispatchSelectionEventToChild`
/// 可以覆写 —— 在这里把 `SelectionEdgeUpdateEvent.globalPosition` 按
/// `Selectable.boundingBoxes` 夹回当前选择块内，`adjustDragOffset` 的 Area 1/2
/// 分支就不会命中，端点自然落在“手指水平对应的那一行”的行首/行尾：
///
/// * 段落直接注册到本容器时，`boundingBoxes` 是**逐行**的 TextBox，能精确到行；
/// * 子树里还有自己的 `SelectionContainer` 时（比如 `Text` 自带的那层），
///   `boundingBoxes` 退化成该容器的 paintBounds；但因为只夹 x、保留 y，事件落到
///   子容器后仍然按手指那一行的 y 定位，效果一致。
///
/// 边界要再向内收 1 像素：`adjustDragOffset` 用 `contains` / `<=` 判断，正好压在
/// 矩形边上会被当成越界，又回到吸附整段的老路。
class EdgeClampingSelectionContainerDelegate extends StaticSelectionContainerDelegate {
  /// 创建 delegate。
  EdgeClampingSelectionContainerDelegate();

  @override
  SelectionResult dispatchSelectionEventToChild(Selectable selectable, SelectionEvent event) {
    return super.dispatchSelectionEventToChild(selectable, _clamp(selectable, event));
  }

  /// 每次选区事件后把「当前选中文本」记到 [SelectionMenuSelectionCache]。
  ///
  /// `SelectableRegionState` 既拿不到 `_selectable`（私有），公开的
  /// `textEditingValue` 又只是占位符 `'_'` / `'__'`，所以选中文字只能从我们这层
  /// 容器（`SelectionHandler.getSelectedContent()`，公开 API）捞出来给菜单用。
  /// 记录放在 super 之后，保证拿到的是本次事件生效后的选区。
  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final SelectionResult result = super.dispatchSelectionEvent(event);
    SelectionMenuSelectionCache.record(
      event is ClearSelectionEvent ? null : getSelectedContent()?.plainText,
    );
    return result;
  }

  /// 把「横向越界」的选区边事件夹到手指所在的那一行内。
  ///
  /// 只处理 `SelectionEdgeUpdateEvent`。判定规则：
  ///
  /// - 手指 dy 落在某一行里（横向溢出文本列）：把 dx 夹进该行，dy 保持不变。
  ///   这样 `adjustDragOffset` 的 `contains` 命中，端点落在该行行首/行尾；
  /// - 手指 dy 落在所有行之外（纵向越界，比如拖到上一段/下一段）：
  ///   **原样返回**。这一条很关键：`_SelectableFragment._updateSelectionEdge`
  ///   （`rendering/paragraph.dart:1969` 起）靠 `getResultBasedOnRect(_rect, localPosition)`
  ///   返回 `next`/`previous` 让上层 delegate 继续往相邻段落走；如果这里把 dy 一起夹回
  ///   最近的行，会被判成 `SelectionResult.end`，跨段落拖选就会卡在当前段落。
  /// - 非边界事件、或拿不到行 box：原样返回。
  SelectionEvent _clamp(Selectable selectable, SelectionEvent event) {
    if (event is! SelectionEdgeUpdateEvent) {
      return event;
    }
    final List<Rect> boxes = selectable.boundingBoxes;
    if (boxes.isEmpty) {
      return event;
    }

    final Offset position = event.globalPosition;
    final Matrix4 transform = selectable.getTransformTo(null);

    // 手指 dy 落在哪些行里；命中的多行（并排的多栏换行）取并集，等价于该 dy 的水平范围。
    Rect? rowAtPointer;
    for (final Rect localBox in boxes) {
      final Rect globalBox = MatrixUtils.transformRect(transform, localBox);
      if (position.dy >= globalBox.top && position.dy <= globalBox.bottom) {
        rowAtPointer = rowAtPointer == null ? globalBox : rowAtPointer.expandToInclude(globalBox);
      }
    }

    // 纵向越界（拖到本段之外）不夹取，交给 SDK 用 next/previous 继续跨段遍历。
    final Rect? row = rowAtPointer;
    if (row == null) {
      return event;
    }

    // 收 1 像素：`adjustDragOffset` 用的是 `contains` / `<=` 判定，正好落在矩形边界上
    // 会被判成“越界”，于是又回到吸附整段首/尾的老路。行宽很小时按一半收，避免区间为负。
    final double insetX = math.min(1.0, row.width / 2);
    final double dx = position.dx.clamp(row.left + insetX, row.right - insetX);
    if (dx == position.dx) {
      return event;
    }
    final Offset clamped = Offset(dx, position.dy);
    return switch (event.type) {
      SelectionEventType.endEdgeUpdate => SelectionEdgeUpdateEvent.forEnd(
        globalPosition: clamped,
        granularity: event.granularity,
      ),
      _ => SelectionEdgeUpdateEvent.forStart(
        globalPosition: clamped,
        granularity: event.granularity,
      ),
    };
  }

  /// 释放内部状态。
  @override
  void dispose() {
    super.dispose();
  }
}

/// 给 [SelectionArea] 的子树挂一层夹取边界的 [SelectionContainer]。
///
/// 必须是 StatefulWidget：delegate 要在整棵子树生命周期内保持同一个实例
/// （[SelectionContainer] 用它做 registrar，每帧换实例会不断重注册）。
class EdgeClampingSelectionScope extends StatefulWidget {
  /// 创建作用域。
  const EdgeClampingSelectionScope({super.key, required this.child});

  /// 被包裹的子树。
  final Widget child;

  @override
  State<EdgeClampingSelectionScope> createState() => _EdgeClampingSelectionScopeState();
}

class _EdgeClampingSelectionScopeState extends State<EdgeClampingSelectionScope> {
  final EdgeClampingSelectionContainerDelegate _delegate =
      EdgeClampingSelectionContainerDelegate();

  @override
  void dispose() {
    // SelectionContainer 只负责解绑 _selectionContainerContext，不会 dispose delegate。
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}
