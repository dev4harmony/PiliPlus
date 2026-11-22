import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle, TextBox;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/src/selection_haptics.dart';
import 'package:material_ui/src/selection_menu.dart';

/// 把「横向越界」的选区边夹回手指所在的那一行，而不是吸附到整段首/尾。
///
/// ## 问题
///
/// 文章页是 SelectionArea + 逐段 htmlRender。在段落里横向拖出文字右边界时，
/// SDK 会把端点拉去**整段末尾**（表现为「整段被选中」），而不是停在手指那一行的行尾。
///
/// 根因在 RenderParagraph 的 _SelectableFragment._updateSelectionEdge
/// （rendering/paragraph.dart:1981）：
///
///     final Offset adjustedOffset = SelectionUtils.adjustDragOffset(_rect, localPosition, ...);
///
/// adjustDragOffset（rendering/selection.dart:355）只有两个出口：_rect 内原样返回，
/// 否则返回 _rect.topLeft 或 _rect.bottomRight。而 _rect 是这个 fragment **所有行
/// box 的并集**（paragraph.dart 的 Rect get _rect），所以只要横向出界，端点必然
/// 飞到整段首/尾。
///
/// ## 为什么不能用 boundingBoxes
///
/// 最初的写法是靠 Selectable.boundingBoxes 找「手指所在的行」。这在 SelectionArea
/// 下是错的：事件到达的 Selectable 是 Text 自己那层 SelectionContainer
/// （widgets/text.dart 的 _SelectableTextContainer），它的实现是
/// [(renderObject as RenderBox).paintBounds] —— **一整块矩形，没有任何行信息**。
/// 夹取于是把 x 夹到这块盒子的左右边，而这块盒子又覆盖了全部行，
/// adjustDragOffset 的 contains 判定依旧溢出，端点照样飞到整段末尾。净效果是空操作。
///
/// 只有在段落直接注册到容器的场合（boundingBoxes 退化成逐行 TextBox）才生效，
/// 所以单测能过、真机不生效。
///
/// ## 现在的做法
///
/// 绕开 boundingBoxes，从渲染子树里自己找 RenderParagraph，用公开 API
/// RenderParagraph.getBoxesForSelection 拿到**逐行**矩形（这一份才是准的），
/// 按手指 dy 命中哪一行，把 dx 夹进该行，再下发给子级。夹好之后
/// adjustDragOffset 的 contains 命中，端点就落在手指那一行的行首/行尾。
///
/// 边界要向内收 1 像素：contains / <= 是闭区间判定，正好压在矩形边上会被当成越界，
/// 又回到吸附整段的老路。
class EdgeClampingSelectionContainerDelegate extends StaticSelectionContainerDelegate {
  /// 创建 delegate。
  ///
  /// [paragraphsOf] 用来枚举本容器子树里的 [RenderParagraph]；不传则退化成
  /// SDK 原行为（整段吸附）。
  EdgeClampingSelectionContainerDelegate({
    List<RenderParagraph> Function()? paragraphsOf,
  }) : _paragraphsOf = paragraphsOf;

  final List<RenderParagraph> Function()? _paragraphsOf;

  List<RenderParagraph>? _cachedParagraphs;
  bool _paragraphsDirty = true;

  /// 枚举段落；缓存命中时直接复用。
  ///
  /// 段落集合在拖选过程中不会变，逐帧重走整棵子树没有必要；滚动只会改变变换，
  /// 而变换是每次查询时现算的，不影响缓存有效性。段落被卸载（attached 为 false）
  /// 或收到非边缘事件（拖选开始）时重建。
  List<RenderParagraph> _paragraphs() {
    final List<RenderParagraph> Function()? provider = _paragraphsOf;
    if (provider == null) {
      return const <RenderParagraph>[];
    }
    final List<RenderParagraph>? cached = _cachedParagraphs;
    if (cached != null &&
        !_paragraphsDirty &&
        cached.every((RenderParagraph paragraph) => paragraph.attached)) {
      return cached;
    }
    final List<RenderParagraph> fresh = provider();
    _cachedParagraphs = fresh;
    _paragraphsDirty = false;
    return fresh;
  }

  @override
  SelectionResult dispatchSelectionEventToChild(
    Selectable selectable,
    SelectionEvent event,
  ) {
    return super.dispatchSelectionEventToChild(selectable, _clamp(selectable, event));
  }

  /// 每次选区事件后把「当前选中文本」记到 [SelectionMenuSelectionCache]。
  ///
  /// SelectableRegionState 既拿不到 _selectable（私有），公开的 textEditingValue 又只是
  /// 占位符 '_' / '__'，所以选中文字只能从我们这层容器
  /// （SelectionHandler.getSelectedContent()，公开 API）捞出来给菜单用。
  /// 记录放在 super 之后，保证拿到的是本次事件生效后的选区。
  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (event is! SelectionEdgeUpdateEvent) {
      // 拖选开始 / 清空 / 全选：段落集合可能刚变化，下一条边缘事件重建缓存。
      _paragraphsDirty = true;
    }
    final SelectionResult result = super.dispatchSelectionEvent(event);
    final String? text =
        event is ClearSelectionEvent ? null : getSelectedContent()?.plainText;
    SelectionMenuSelectionCache.record(text);
    // 只要是「按压 + 选区内容变化」就轻震：手指滑到文字外/手柄外也生效，
    // 因为按压状态来自全局指针路由而不是命中测试（见 selection_haptics.dart）。
    if (event is SelectionEdgeUpdateEvent) {
      notifySelectionChanged(text);
    }
    return result;
  }

  /// 把「横向越界」的选区边事件夹到手指所在的那一行内。
  ///
  /// 只处理 [SelectionEdgeUpdateEvent]。判定规则：
  ///
  /// - 手指 dy 落在本可选中块内、且命中某一行：把 dx 夹进该行，dy 保持不变。
  /// - 手指 dy 落在本块之外（纵向越界，比如拖到上一段/下一段）：**原样返回**。
  ///   这一条很关键：_updateSelectionEdge 靠 getResultBasedOnRect(_rect, ...) 返回
  ///   next/previous 让上层 delegate 继续往相邻段落走；如果这里把 dy 一起夹回最近的
  ///   行，会被判成 SelectionResult.end，跨段落拖选就会卡在当前段落。
  /// - 找不到任何段落 / 没有命中行：原样返回，退化成 SDK 原行为。
  SelectionEvent _clamp(Selectable selectable, SelectionEvent event) {
    if (event is! SelectionEdgeUpdateEvent) {
      return event;
    }
    final List<RenderParagraph> paragraphs = _paragraphs();
    if (paragraphs.isEmpty) {
      return event;
    }

    final Offset position = event.globalPosition;
    // 本可选中块（可能是 Text 那层容器）的全局矩形。
    final Rect block = MatrixUtils.transformRect(
      selectable.getTransformTo(null),
      Offset.zero & selectable.size,
    );
    if (position.dy < block.top || position.dy > block.bottom) {
      return event;
    }

    final Rect? row = _rowAt(paragraphs, block, position.dy);
    if (row == null) {
      return event;
    }

    // 收 1 像素：adjustDragOffset 用的是 contains / <= 判定，正好落在矩形边界上
    // 会被判成「越界」，于是又回到吸附整段首/尾的老路。行宽很小时按一半收，避免区间为负。
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

  /// 找出 [dy] 落在哪一行，返回该行的全局矩形。
  ///
  /// 只考虑与本块 [block] 有交集的段落 —— 否则夹到别的段落上会把事件挪走，
  /// 打断 SDK 的跨段落遍历。同一 dy 命中多行（并排多栏）时取并集。
  Rect? _rowAt(List<RenderParagraph> paragraphs, Rect block, double dy) {
    Rect? row;
    for (final RenderParagraph paragraph in paragraphs) {
      if (!paragraph.attached || !paragraph.hasSize) {
        continue;
      }
      final Matrix4 transform = paragraph.getTransformTo(null);
      final Rect paragraphRect = MatrixUtils.transformRect(
        transform,
        Offset.zero & paragraph.size,
      );
      if (paragraphRect.right < block.left ||
          paragraphRect.left > block.right ||
          paragraphRect.bottom < block.top ||
          paragraphRect.top > block.bottom) {
        continue;
      }
      if (dy < paragraphRect.top || dy > paragraphRect.bottom) {
        continue;
      }
      final int length = paragraph.text.toPlainText().length;
      if (length == 0) {
        continue;
      }
      final List<TextBox> boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: length),
        boxHeightStyle: BoxHeightStyle.max,
      );
      for (final TextBox box in boxes) {
        final Rect globalBox = MatrixUtils.transformRect(transform, box.toRect());
        if (dy < globalBox.top || dy > globalBox.bottom) {
          continue;
        }
        row = row == null ? globalBox : row.expandToInclude(globalBox);
      }
    }
    return row;
  }

  @override
  void dispose() {
    _cachedParagraphs = null;
    super.dispose();
  }
}

/// 收集本子树里的 [RenderParagraph]。
class _ParagraphScopeBox extends RenderProxyBox {
  /// 递归遍历子树，把段落收集进 [into]。
  void collect(List<RenderParagraph> into) {
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        into.add(node);
      }
      node.visitChildren(visit);
    }

    visitChildren(visit);
  }
}

class _ParagraphScope extends SingleChildRenderObjectWidget {
  const _ParagraphScope({super.key, super.child});

  @override
  _ParagraphScopeBox createRenderObject(BuildContext context) =>
      _ParagraphScopeBox();

  @override
  void updateRenderObject(BuildContext context, _ParagraphScopeBox renderObject) {}
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
  State<EdgeClampingSelectionScope> createState() =>
      _EdgeClampingSelectionScopeState();
}

class _EdgeClampingSelectionScopeState extends State<EdgeClampingSelectionScope> {
  final GlobalKey _scopeKey = GlobalKey();

  late final EdgeClampingSelectionContainerDelegate _delegate =
      EdgeClampingSelectionContainerDelegate(paragraphsOf: _paragraphs);

  List<RenderParagraph> _paragraphs() {
    final RenderObject? root = _scopeKey.currentContext?.findRenderObject();
    if (root is! _ParagraphScopeBox) {
      return const <RenderParagraph>[];
    }
    final List<RenderParagraph> out = <RenderParagraph>[];
    root.collect(out);
    return out;
  }

  @override
  void dispose() {
    // SelectionContainer 只负责解绑 _selectionContainerContext，不会 dispose delegate。
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ParagraphScope(
      key: _scopeKey,
      child: SelectionContainer(delegate: _delegate, child: widget.child),
    );
  }
}
