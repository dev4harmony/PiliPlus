import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle, TextBox;

import 'package:flutter/gestures.dart'
    show PointerCancelEvent, PointerDeviceKind, PointerDownEvent, PointerUpEvent, kTouchSlop;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/src/compat/paragraph.dart' as compat;
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
    List<RenderObject> Function()? paragraphsOf,
  }) : _paragraphsOf = paragraphsOf;

  final List<RenderObject> Function()? _paragraphsOf;

  List<RenderObject>? _cachedParagraphs;
  bool _paragraphsDirty = true;

  /// 枚举段落；缓存命中时直接复用。
  ///
  /// 段落集合在拖选过程中不会变，逐帧重走整棵子树没有必要；滚动只会改变变换，
  /// 而变换是每次查询时现算的，不影响缓存有效性。段落被卸载（attached 为 false）
  /// 或收到非边缘事件（拖选开始）时重建。
  List<RenderObject> _paragraphs() {
    final List<RenderObject> Function()? provider = _paragraphsOf;
    if (provider == null) {
      return const <RenderObject>[];
    }
    final List<RenderObject>? cached = _cachedParagraphs;
    if (cached != null &&
        !_paragraphsDirty &&
        cached.every((RenderObject paragraph) => paragraph.attached)) {
      return cached;
    }
    final List<RenderObject> fresh = provider();
    _cachedParagraphs = fresh;
    _paragraphsDirty = false;
    return fresh;
  }

  /// 在 [globalPosition] 处选中整段（触摸三击用）。
  ///
  /// SDK 的 `SelectableRegion` 只在精确指针（鼠标）时才在第三次点击调
  /// `_selectParagraphAt`（见 selectable_region.dart 的三击分支），触摸设备直接跳过。
  /// 这里由 shim 自己的手势检测补上同一条事件。
  void selectParagraphAt(Offset globalPosition) {
    dispatchSelectionEvent(
      SelectParagraphSelectionEvent(globalPosition: globalPosition),
    );
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
    final List<RenderObject> paragraphs = _paragraphs();
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
  Rect? _rowAt(List<RenderObject> paragraphs, Rect block, double dy) {
    Rect? row;
    for (final RenderObject paragraph in paragraphs) {
      final RenderBox parentBox = paragraph as RenderBox;
      if (!paragraph.attached || !parentBox.hasSize) {
        continue;
      }
      final Matrix4 transform = paragraph.getTransformTo(null);
      final Rect paragraphRect = MatrixUtils.transformRect(
        transform,
        Offset.zero & parentBox.size,
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
      final String plainText = switch (paragraph) {
        RenderParagraph p => p.text.toPlainText(),
        compat.RenderParagraph p => p.text.toPlainText(),
        _ => '',
      };
      final int length = plainText.length;
      if (length == 0) {
        continue;
      }
      final TextSelection entire = TextSelection(
        baseOffset: 0,
        extentOffset: length,
      );
      // shim 接管 Text 后，业务文本由 compat.RenderParagraph 渲染，
      // 这里两套段落都要能夹取。
      final List<TextBox> boxes = switch (paragraph) {
        RenderParagraph p => p.getBoxesForSelection(
          entire,
          boxHeightStyle: BoxHeightStyle.max,
        ),
        compat.RenderParagraph p => p.getBoxesForSelection(
          entire,
          boxHeightStyle: BoxHeightStyle.max,
        ),
        _ => const <TextBox>[],
      };
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

/// 收集本子树里的段落（SDK 与 shim 的 compat 两套 [RenderParagraph] 都算）。
class _ParagraphScopeBox extends RenderProxyBox {
  /// 递归遍历子树，把段落收集进 [into]。
  void collect(List<RenderObject> into) {
    void visit(RenderObject node) {
      if (node is RenderParagraph || node is compat.RenderParagraph) {
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
///
/// 另外顺带承担两件 SDK 没给触摸设备做的事：
///
/// 1. **三击选整段**：SDK 的 `SelectableRegion` 在第三次点击时只有在精确指针
///    （鼠标）下才调 `_selectParagraphAt`（`_isPrecisePointerDevice` 只认
///    `PointerDeviceKind.mouse`），触摸/手写笔直接跳过。这里用 raw `Listener`
///    自己数三击并下发 `SelectParagraphSelectionEvent`。
/// 2. 三击后重弹菜单：SDK 的三击分支不会调 `_showToolbar`（双击时弹的菜单是
///    单词选区的旧内容），这里用 `SelectionOverlay.showToolbar` 按新选区重弹一次。
class EdgeClampingSelectionScope extends StatefulWidget {
  /// 创建作用域。
  const EdgeClampingSelectionScope({
    super.key,
    required this.child,
    this.contextMenuBuilder,
  });

  /// 被包裹的子树。
  final Widget child;

  /// 与 [SelectionArea] 的 `contextMenuBuilder` 同一份（含记录 state 的包装），
  /// 三击选中整段后用它重弹菜单。
  final Widget Function(BuildContext, SelectableRegionState)? contextMenuBuilder;

  @override
  State<EdgeClampingSelectionScope> createState() =>
      _EdgeClampingSelectionScopeState();
}

class _EdgeClampingSelectionScopeState extends State<EdgeClampingSelectionScope> {
  final GlobalKey _scopeKey = GlobalKey();

  late final EdgeClampingSelectionContainerDelegate _delegate =
      EdgeClampingSelectionContainerDelegate(paragraphsOf: _paragraphs);

  List<RenderObject> _paragraphs() {
    final RenderObject? root = _scopeKey.currentContext?.findRenderObject();
    if (root is! _ParagraphScopeBox) {
      return const <RenderObject>[];
    }
    final List<RenderObject> out = <RenderObject>[];
    root.collect(out);
    return out;
  }

  // ---- 触摸三击选段 ----

  Offset? _downPosition;
  Duration? _downTime;
  Offset? _lastTapPosition;
  Duration? _lastTapTime;
  int _tapCount = 0;

  /// 嵌套 SelectionArea 时内层先处理，外层在同一轮指针序列里跳过。
  static int _lastHandledMicros = 0;

  /// 与 SDK 的 `_isPrecisePointerDevice` 相反：非鼠标（触摸/手写笔等）才需要补三击。
  bool _isTouchLike(PointerDeviceKind kind) => kind != PointerDeviceKind.mouse;

  void _onPointerDown(PointerDownEvent event) {
    _downPosition = event.position;
    _downTime = event.timeStamp;
    final Duration? last = _lastTapTime;
    if (last != null &&
        event.timeStamp - last > const Duration(milliseconds: 350)) {
      _tapCount = 0;
      _lastTapTime = null;
      _lastTapPosition = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final Offset? down = _downPosition;
    final Duration? downTime = _downTime;
    _downPosition = null;
    _downTime = null;
    if (down == null || downTime == null || !_isTouchLike(event.kind)) {
      return;
    }
    // 拖动 / 长按都不算「击」。
    if ((event.position - down).distance > kTouchSlop) {
      return;
    }
    if (event.timeStamp - downTime > const Duration(milliseconds: 500)) {
      return;
    }

    final Duration? lastTime = _lastTapTime;
    final Offset? lastPosition = _lastTapPosition;
    final bool continues =
        lastTime != null &&
        lastPosition != null &&
        event.timeStamp - lastTime <= const Duration(milliseconds: 350) &&
        (event.position - lastPosition).distance <= kTouchSlop;
    _tapCount = continues ? _tapCount + 1 : 1;
    _lastTapTime = event.timeStamp;
    _lastTapPosition = event.position;
    if (_tapCount < 3) {
      return;
    }
    _tapCount = 0;
    _lastTapTime = null;
    _lastTapPosition = null;
    _handleTripleTap(event.position);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _downPosition = null;
    _downTime = null;
  }

  void _handleTripleTap(Offset globalPosition) {
    final int now = DateTime.now().microsecondsSinceEpoch;
    if (now - _lastHandledMicros < 200000) {
      return;
    }
    _lastHandledMicros = now;
    // 选中整段：delegate 会把事件下发给子树里的段落，并在 super 之后更新缓存。
    _delegate.selectParagraphAt(globalPosition);

    final Widget Function(BuildContext, SelectableRegionState)? builder =
        widget.contextMenuBuilder;
    final SelectableRegionState? state =
        context.findAncestorStateOfType<SelectableRegionState>();
    if (builder == null || state == null) {
      return;
    }
    // ignore: invalid_use_of_visible_for_testing_member
    final SelectionOverlay? overlay = state.selectionOverlay;
    // `showToolbar` 内部是 ContextMenuController.show，会替换掉双击时弹出的旧菜单。
    overlay?.showToolbar(
      context: context,
      contextMenuBuilder: (BuildContext ctx) => builder(ctx, state),
    );
  }

  @override
  void dispose() {
    // SelectionContainer 只负责解绑 _selectionContainerContext，不会 dispose delegate。
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: _ParagraphScope(
        key: _scopeKey,
        child: SelectionContainer(delegate: _delegate, child: widget.child),
      ),
    );
  }
}
