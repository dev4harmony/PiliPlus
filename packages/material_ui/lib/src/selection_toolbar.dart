import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/src/ohos_selection_theme.dart';

/// 鸿蒙（OpenHarmony）样式的选中文字工具栏。
///
/// ## 与 SDK 默认工具栏的差别
///
/// 鸿蒙上 `AdaptiveTextSelectionToolbar` 走的是 Material 分支
/// （`adaptive_text_selection_toolbar.dart:319-327`）：44 高、圆角 22、
/// M3 surface 底、与锚点间距 8、按**选区包围盒中心**对齐。原生鸿蒙是：
///
/// - 胶囊底 + **单行横向**排布的纯文字按钮（无图标、无分割线）；
/// - 尺寸/颜色取自 [OhosSelectionTheme]（真实主题值，出处见该文件头），并在原生
///   14fp 的基础上整体缩到 13fp：工具栏高 37（= 26 按钮 + 上下 5.5）、按钮圆角 13、
///   按钮左右内边距 11、圆角取工具栏高的一半；
/// - 底色**跟随应用背景色**（`ThemeData.scaffoldBackgroundColor`，与手柄球的填充色
///   同源）再往白色方向泛一点点（[OhosSelectionTheme.menuBackgroundWhiten]），
///   不做背景模糊 —— 半透明 + 模糊在自定义背景/浅色主题下会把底色染灰；
/// - 定位见 [OhosTextSelectionToolbarLayoutDelegate]（原生
///   `select_overlay_layout_algorithm.cpp:348-527` 的 `ComputeSelectMenuPosition`）；
/// - **横向放不下时**，把**右侧**放不下的项收进二级菜单（竖向展开在同一胶囊里），
///   溢出按钮固定在该行**最右端**（见 [_OhosToolbarOverflowButton]），与 SDK 的
///   Material 工具栏一致；展开/收起是 160ms 的快速形变动画（`AnimatedSize`）。
class OhosTextSelectionToolbar extends StatefulWidget {
  /// 创建工具栏。锚点均为 **overlay 全局坐标**。
  const OhosTextSelectionToolbar({
    super.key,
    required this.anchorX,
    required this.anchorTop,
    required this.anchorBottom,
    required this.gapAbove,
    required this.gapBelow,
    required this.buttonItems,
  });

  /// 横向锚点：选区**两端**的 x 中点（不是包围盒中心，多行选区时两者不同）。
  final double anchorX;

  /// 选区首行**上沿**。
  final double anchorTop;

  /// 选区末行**下沿**，菜单在上方放不下时翻到这里下面。
  final double anchorBottom;

  /// 放在选区**上方**时，菜单底边离 [anchorTop] 的距离。
  ///
  /// 上方有手柄球（非折叠选区）时 = `text_overlay_menu_spacing_with_text`(8vp)
  /// + 手柄直径(14vp)：菜单底边正好压在那颗球的上方；折叠光标上方只有光标本身，
  /// 只留 8vp。
  final double gapAbove;

  /// 放在选区**下方**时，菜单顶边离 [anchorBottom] 的距离。
  ///
  /// 止手柄的球和折叠光标的球都挂在行下方（占 14vp），所以这里恒为 8 + 14 = 22vp，
  /// 否则菜单会压住把柄（真机上反馈过）。
  final double gapBelow;

  /// 菜单项，顺序即展示顺序；文案由
  /// [AdaptiveTextSelectionToolbar.getButtonLabel]（沿用 SDK 的多语言）决定，
  /// 但 [ContextMenuButtonItem.label] 优先。
  final List<ContextMenuButtonItem> buttonItems;

  @override
  State<OhosTextSelectionToolbar> createState() =>
      _OhosTextSelectionToolbarState();
}

class _OhosTextSelectionToolbarState extends State<OhosTextSelectionToolbar> {
  /// 二级菜单（右侧被收起的项）是否展开。
  bool _overflowOpen = false;

  @override
  void didUpdateWidget(OhosTextSelectionToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 菜单项变了就收回去：否则可能出现「展开态但已经没有隐藏项」的破状态
    // （SDK 的 `_TextSelectionToolbarOverflowableState.didUpdateWidget` 同样处理）。
    if (!listEquals(widget.buttonItems, oldWidget.buttonItems)) {
      _overflowOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 与 SDK 的 `AdaptiveTextSelectionToolbar.buttonItems` 保持一致：
    // 没有任何可用项时整条菜单不出现，别留一个空胶囊。
    if (widget.buttonItems.isEmpty) {
      return const SizedBox.shrink();
    }
    final MediaQueryData media = MediaQuery.of(context);
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final double safeTop =
        media.padding.top + OhosSelectionTheme.menuSafeSpacing;
    final double safeBottom =
        math.max(media.padding.bottom, media.viewInsets.bottom) +
        OhosSelectionTheme.menuSafeSpacing;
    final double maxWidth = math.min(
      OhosSelectionTheme.menuMaxWidth,
      media.size.width - OhosSelectionTheme.menuSafeSpacing * 2,
    );

    // 收起态高度是定值（37），据此先判断菜单该放上方还是下方；展开态沿用同一方向，
    // 只让胶囊朝「远离选区」的一端长高，视觉上不会有跳变。
    const double closedHeight = OhosSelectionTheme.menuToolbarHeight;
    final double aboveRoom = widget.anchorTop - widget.gapAbove - safeTop;
    final bool isAbove = aboveRoom >= closedHeight;
    final double availableHeight = math.max(
      closedHeight,
      isAbove
          ? aboveRoom
          : media.size.height -
                safeBottom -
                (widget.anchorBottom + widget.gapBelow),
    );

    // 项之间的间距由自定义 layout 统一处理（`OhosSelectionTheme.menuButtonSpacing`），
    // 这里不再插 `SizedBox` 占位 —— 展开成竖排时占位块会变成一整行空白。
    final List<Widget> children = <Widget>[
      for (final ContextMenuButtonItem item in widget.buttonItems)
        _OhosToolbarButton(item: item),
    ];

    // 底色 = 应用背景色（与手柄球的内芯同源），再往白里泛一点点区分层次。
    final Color background = _effectiveBackground(theme, brightness);

    // 原生菜单底色不透明，且**不做背景模糊**：模糊会把底色染成灰、与"跟随应用背景色"
    // 冲突，也在部分后端掉帧。
    //
    // `AnimatedSize` 负责展开/收起的**快速**形变（160ms easeOutCubic）：收起态是
    // 定高 37、展开态按行数变高，动画只是把这两个尺寸之间的跳变抹平，属于「hero 式」
    // 的即时扩张，不改变定位规则（展开态仍朝远离选区的一侧长高）。
    final Widget content = Container(
      padding: const EdgeInsets.all(OhosSelectionTheme.menuPadding),
      color: background,
      child: AnimatedSize(
        duration: OhosSelectionTheme.menuOverflowAnimationDuration,
        curve: Curves.easeOutCubic,
        alignment: isAbove ? Alignment.bottomCenter : Alignment.topCenter,
        child: _OhosToolbarItemsLayout(
          overflowOpen: _overflowOpen,
          isAbove: isAbove,
          spacing: OhosSelectionTheme.menuButtonSpacing,
          spacingCollapsed: OhosSelectionTheme.menuButtonSpacingCollapsed,
          itemHeight: OhosSelectionTheme.menuButtonHeight,
          navButtonWidth: OhosSelectionTheme.menuOverflowButtonWidth,
          minExpandedWidth: OhosSelectionTheme.menuOverflowMinWidth,
          children: <Widget>[
            // 第一个子节点固定是溢出/收起按钮（同 SDK 的
            // `_TextSelectionToolbarItemsLayout`），没有溢出时它不参与绘制；
            // 绘制时固定在该行**最右端**。
            _OhosToolbarOverflowButton(
              expanded: _overflowOpen,
              onPressed: () {
                setState(() => _overflowOpen = !_overflowOpen);
              },
            ),
            ...children,
          ],
        ),
      ),
    );

    final Widget capsule = DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(
          Radius.circular(OhosSelectionTheme.menuCornerRadius),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(
          Radius.circular(OhosSelectionTheme.menuCornerRadius),
        ),
        child: content,
      ),
    );

    // 出场只有淡入淡出，由 SDK 的 `_SelectionToolbarWrapper` 里的 FadeTransition 驱动
    // （`SelectionOverlay.fadeDuration` = 150ms，改不了也不改 SDK），这里不叠任何动画。
    return CustomSingleChildLayout(
      delegate: OhosTextSelectionToolbarLayoutDelegate(
        anchorX: widget.anchorX,
        anchorTop: widget.anchorTop,
        anchorBottom: widget.anchorBottom,
        gapAbove: widget.gapAbove,
        gapBelow: widget.gapBelow,
        safeTop: safeTop,
        safeBottom: safeBottom,
        sideLimit: OhosSelectionTheme.menuSafeSpacing,
        maxWidth: maxWidth,
        isAbove: isAbove,
        availableHeight: availableHeight,
      ),
      child: capsule,
    );
  }

  /// 菜单底色：优先 `scaffoldBackgroundColor`（再往白色方向泛一点点），
  /// 无效时退回原生菜单底色。
  static Color _effectiveBackground(ThemeData theme, Brightness brightness) {
    final Color scaffold = theme.scaffoldBackgroundColor;
    if (scaffold.a == 0) {
      return OhosSelectionTheme.menuBackground(brightness);
    }
    return OhosSelectionTheme.whitenMenuBackground(scaffold);
  }
}

/// 鸿蒙菜单定位（对应原生 `ComputeSelectMenuPosition`）：
///
/// 1. x：以 [anchorX]（两端选区端点中点）居中，再夹进左右 [sideLimit] 安全边；
/// 2. y：菜单**底边**落在 `anchorTop - gapAbove`（选区首行上沿再往上，避让手柄球）；
/// 3. 上方不够放（`y < safeTop`）→ 翻到选区下方 `anchorBottom + gapBelow`
///    （下方要避让止手柄/光标的球，所以间距比上方大）；
/// 4. 最后整体夹进 `[safeTop, 屏幕高 - 安全区]`，保证不压状态栏/键盘。
class OhosTextSelectionToolbarLayoutDelegate extends SingleChildLayoutDelegate {
  /// 创建定位委托。
  const OhosTextSelectionToolbarLayoutDelegate({
    required this.anchorX,
    required this.anchorTop,
    required this.anchorBottom,
    required this.gapAbove,
    required this.gapBelow,
    required this.safeTop,
    required this.safeBottom,
    required this.sideLimit,
    required this.maxWidth,
    required this.isAbove,
    required this.availableHeight,
  });

  /// 横向锚点（两端选区端点 x 中点）。
  final double anchorX;

  /// 选区首行上沿。
  final double anchorTop;

  /// 选区末行下沿。
  final double anchorBottom;

  /// 放在上方时菜单底边离 [anchorTop] 的距离。
  final double gapAbove;

  /// 放在下方时菜单顶边离 [anchorBottom] 的距离。
  final double gapBelow;

  /// 顶部安全边（状态栏 + 16vp）。
  final double safeTop;

  /// 底部安全边（导航条/键盘 + 16vp）。
  final double safeBottom;

  /// 左右安全边。
  final double sideLimit;

  /// 菜单最大宽（442vp 与屏宽减去安全边取小）。
  final double maxWidth;

  /// 菜单是否放在选区上方。收起态高度固定，由 [OhosTextSelectionToolbar] 先行判定，
  /// 展开态沿用同一方向（只朝远离选区的一侧长高）。
  final bool isAbove;

  /// 展开二级菜单时最多允许多高（收起态恒为 [OhosSelectionTheme.menuToolbarHeight]）。
  final double availableHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: availableHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double x = _clamp(
      anchorX - childSize.width / 2,
      sideLimit,
      size.width - childSize.width - sideLimit,
    );
    double y = isAbove
        ? anchorTop - gapAbove - childSize.height
        : anchorBottom + gapBelow;
    y = _clamp(y, safeTop, size.height - childSize.height - safeBottom);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(OhosTextSelectionToolbarLayoutDelegate oldDelegate) {
    return anchorX != oldDelegate.anchorX ||
        anchorTop != oldDelegate.anchorTop ||
        anchorBottom != oldDelegate.anchorBottom ||
        gapAbove != oldDelegate.gapAbove ||
        gapBelow != oldDelegate.gapBelow ||
        safeTop != oldDelegate.safeTop ||
        safeBottom != oldDelegate.safeBottom ||
        sideLimit != oldDelegate.sideLimit ||
        maxWidth != oldDelegate.maxWidth ||
        isAbove != oldDelegate.isAbove ||
        availableHeight != oldDelegate.availableHeight;
  }

  static double _clamp(double value, double lower, double upper) {
    if (upper < lower) {
      upper = lower;
    }
    if (value < lower) {
      return lower;
    }
    return value > upper ? upper : value;
  }
}

/// 单个菜单项：26vp 高的胶囊文字按钮，按下时铺 `#19182431`（原生没有水波纹）。
class _OhosToolbarButton extends StatefulWidget {
  const _OhosToolbarButton({required this.item});

  final ContextMenuButtonItem item;

  @override
  State<_OhosToolbarButton> createState() => _OhosToolbarButtonState();
}

class _OhosToolbarButtonState extends State<_OhosToolbarButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String label = AdaptiveTextSelectionToolbar.getButtonLabel(
      context,
      widget.item,
    );
    return Semantics(
      button: true,
      label: label,
      // 高亮用 pointer 事件而不是 `onTapDown`：`TapGestureRecognizer` 的 onTapDown
      // 要等竞技场结算或 100ms 超时才回调，快速点击根本走不到，真机上表现为
      // 「点了没有按下态」；`Listener` 在 pointer down 当帧就能拿到。
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.item.onPressed,
          // 注意不能用 `Container(alignment: ...)`：带 alignment 的 Container 会**撑满**
          // 父给的最大宽度（单行布局里父给的是整条菜单的可用宽），于是每个按钮都占满
          // 一整行、布局算不出「哪几项放得下」。这里用 `Center(widthFactor: 1)` 让按钮
          // 收缩到文字宽度 + 内边距。
          child: DecoratedBox(
            decoration: BoxDecoration(
              // 亮色是 10% 黑、暗色是 10% 白（暗色下叠黑看不出来，见 OhosSelectionTheme）。
              color: _pressed
                  ? OhosSelectionTheme.menuPressed(theme.brightness)
                  : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(OhosSelectionTheme.menuButtonRadius),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: OhosSelectionTheme.menuButtonMinWidth,
                minHeight: OhosSelectionTheme.menuButtonHeight,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OhosSelectionTheme.menuButtonPaddingHorizontal,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: OhosSelectionTheme.menuFontSize,
                      fontWeight: OhosSelectionTheme.menuFontWeight,
                      color: OhosSelectionTheme.menuTextColor(theme.brightness),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 溢出/收起按钮：把左侧放不下的项收进二级菜单，或从二级菜单收回单行。
///
/// 图标尺寸与文字按钮对齐（[OhosSelectionTheme.menuOverflowIconSize]），按下的高亮、
/// 圆角、语义与 [_OhosToolbarButton] 一致，视觉上就是同一排里的一员。
class _OhosToolbarOverflowButton extends StatefulWidget {
  const _OhosToolbarOverflowButton({
    required this.expanded,
    required this.onPressed,
  });

  /// 二级菜单是否正展开：展开时显示 `expand_less`（收回去）。
  final bool expanded;

  final VoidCallback onPressed;

  @override
  State<_OhosToolbarOverflowButton> createState() =>
      _OhosToolbarOverflowButtonState();
}

class _OhosToolbarOverflowButtonState
    extends State<_OhosToolbarOverflowButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // 多语言 tooltip 沿用 SDK 的 `moreButtonTooltip` / `backButtonTooltip`
    // （`_TextSelectionToolbarOverflowButton` 用的就是这两个）。
    final MaterialLocalizations? localizations =
        Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
    final String? tooltip = widget.expanded
        ? localizations?.backButtonTooltip
        : localizations?.moreButtonTooltip;
    return Semantics(
      button: true,
      label: tooltip,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _pressed
                  ? OhosSelectionTheme.menuPressed(theme.brightness)
                  : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(OhosSelectionTheme.menuButtonRadius),
              ),
            ),
            child: ConstrainedBox(
              // 高度给实际盒子（[menuButtonHeight]），宽度只留最小宽；横向由
              // `Center(widthFactor: 1)` 收缩到内容宽。
              constraints: const BoxConstraints(
                minWidth: OhosSelectionTheme.menuOverflowButtonWidth,
                minHeight: OhosSelectionTheme.menuButtonHeight,
                maxHeight: OhosSelectionTheme.menuButtonHeight,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Icon(
                  widget.expanded
                      // 注：本仓库的 Flutter fork（`icons.dart`）里没有
                      // `expand_more_round` 这个名字，四角圆润版就是
                      // `expand_more_rounded` / `expand_less_rounded`
                      // （`icons.dart:9452` / `:9440`）。
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: OhosSelectionTheme.menuOverflowIconSize,
                  color: OhosSelectionTheme.menuTextColor(theme.brightness),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 菜单项排布：单行横向；放不下时把**右侧**放不下的项收进二级菜单。
///
/// 第一个子节点固定是溢出按钮（同上层的约定），其余是菜单项。行为参考 SDK 的
/// `_RenderTextSelectionToolbarItemsLayout`（`material/text_selection_toolbar.dart:432`），
/// 区别是展开态把被收起的项竖向堆叠（宽度取其中最宽者，且不小于
/// [minExpandedWidth]），按钮按 [isAbove] 放在远离选区的那一端。
class _OhosToolbarItemsLayout extends MultiChildRenderObjectWidget {
  const _OhosToolbarItemsLayout({
    required this.overflowOpen,
    required this.isAbove,
    required this.spacing,
    required this.spacingCollapsed,
    required this.itemHeight,
    required this.navButtonWidth,
    required this.minExpandedWidth,
    required super.children,
  });

  /// 二级菜单是否展开。
  final bool overflowOpen;

  /// 菜单是否位于选区上方：展开时按钮放在**远离选区**的一端（上方 → 底部）。
  final bool isAbove;

  /// 展开态（竖排）的项间距（原生 `MENU_BUTTON_SPACING` = 4vp）。
  final double spacing;

  /// 收起态（单行）相邻项之间的间距；按产品要求贴紧为 0，
  /// 两侧仍由工具栏的 [OhosSelectionTheme.menuPadding] 留白。
  final double spacingCollapsed;

  /// 单行高度（= 按钮高）。
  final double itemHeight;

  /// 溢出按钮的横向占位。
  final double navButtonWidth;

  /// 展开态胶囊的最小宽度（约 4 个字宽），避免只剩窄项时瘦成一条细柱。
  final double minExpandedWidth;

  @override
  _RenderOhosToolbarItems createRenderObject(BuildContext context) {
    return _RenderOhosToolbarItems(
      overflowOpen: overflowOpen,
      isAbove: isAbove,
      spacing: spacing,
      spacingCollapsed: spacingCollapsed,
      itemHeight: itemHeight,
      navButtonWidth: navButtonWidth,
      minExpandedWidth: minExpandedWidth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOhosToolbarItems renderObject,
  ) {
    renderObject
      ..overflowOpen = overflowOpen
      ..isAbove = isAbove
      ..spacing = spacing
      ..spacingCollapsed = spacingCollapsed
      ..itemHeight = itemHeight
      ..navButtonWidth = navButtonWidth
      ..minExpandedWidth = minExpandedWidth;
  }
}

/// 子节点的布局数据：偏移 + 是否绘制（收起态隐藏被折叠项、展开态隐藏单行项）。
class _OhosToolbarItemsParentData extends ContainerBoxParentData<RenderBox> {
  bool shouldPaint = true;
}

class _RenderOhosToolbarItems extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _OhosToolbarItemsParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _OhosToolbarItemsParentData
        > {
  _RenderOhosToolbarItems({
    required bool overflowOpen,
    required bool isAbove,
    required double spacing,
    required double spacingCollapsed,
    required double itemHeight,
    required double navButtonWidth,
    required double minExpandedWidth,
  }) : _overflowOpen = overflowOpen,
       _isAbove = isAbove,
       _spacing = spacing,
       _spacingCollapsed = spacingCollapsed,
       _itemHeight = itemHeight,
       _navButtonWidth = navButtonWidth,
       _minExpandedWidth = minExpandedWidth;

  bool _overflowOpen;
  bool get overflowOpen => _overflowOpen;
  set overflowOpen(bool value) {
    if (_overflowOpen == value) {
      return;
    }
    _overflowOpen = value;
    markNeedsLayout();
  }

  bool _isAbove;
  bool get isAbove => _isAbove;
  set isAbove(bool value) {
    if (_isAbove == value) {
      return;
    }
    _isAbove = value;
    markNeedsLayout();
  }

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) {
      return;
    }
    _spacing = value;
    markNeedsLayout();
  }

  double _spacingCollapsed;
  double get spacingCollapsed => _spacingCollapsed;
  set spacingCollapsed(double value) {
    if (_spacingCollapsed == value) {
      return;
    }
    _spacingCollapsed = value;
    markNeedsLayout();
  }

  double _itemHeight;
  double get itemHeight => _itemHeight;
  set itemHeight(double value) {
    if (_itemHeight == value) {
      return;
    }
    _itemHeight = value;
    markNeedsLayout();
  }

  double _navButtonWidth;
  double get navButtonWidth => _navButtonWidth;
  set navButtonWidth(double value) {
    if (_navButtonWidth == value) {
      return;
    }
    _navButtonWidth = value;
    markNeedsLayout();
  }

  double _minExpandedWidth;
  double get minExpandedWidth => _minExpandedWidth;
  set minExpandedWidth(double value) {
    if (_minExpandedWidth == value) {
      return;
    }
    _minExpandedWidth = value;
    markNeedsLayout();
  }

  /// 收起态最后一个可见的项下标（大于它的项进二级菜单）；-1 表示全部可见。
  int _lastVisible = -1;

  /// 是否有项被收起（= 是否绘制溢出按钮）。
  bool _hasOverflow = false;

  /// 从左往右贪心塞，返回能完整放下的**最后**下标（含）。
  ///
  /// [gap] 是相邻项之间的间距：收起态传 [spacingCollapsed]（产品要求贴紧为 0），
  /// 展开态不用这个函数。放不下时返回 `-1`，表示一个都放不下。
  int _fitFromLeft(List<RenderBox> items, double available, double gap) {
    double used = 0;
    int last = -1;
    for (int i = 0; i < items.length; i++) {
      final double width = items[i].size.width + (i > 0 ? gap : 0);
      if (used + width > available) {
        break;
      }
      used += width;
      last = i;
    }
    return last;
  }

  @override
  void performLayout() {
    final RenderBox? nav = firstChild;
    if (nav == null) {
      size = constraints.smallest;
      return;
    }
    final double maxWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : double.infinity;
    final BoxConstraints childConstraints = BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: itemHeight,
    );

    nav.layout(childConstraints, parentUsesSize: true);
    final List<RenderBox> items = <RenderBox>[];
    RenderBox? child = childAfter(nav);
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      items.add(child);
      child = childAfter(child);
    }

    // 先按「全部可见」量一遍，算出从哪里开始放不下（收起态项间距为 spacingCollapsed）。
    int last = _fitFromLeft(items, maxWidth, spacingCollapsed);
    // 单个项就比最大宽还长时，也要显示第一项（宁可裁切，不能整排消失）。
    if (last < 0 && items.isNotEmpty) {
      last = 0;
    }
    bool hasOverflow = last < items.length - 1;
    if (hasOverflow) {
      // 溢出按钮本身也要占位（用它真实布局出来的宽度），再收一轮。
      final int withNav = _fitFromLeft(
        items,
        math.max(0, maxWidth - nav.size.width - spacingCollapsed),
        spacingCollapsed,
      );
      last = withNav < 0 && items.isNotEmpty ? 0 : withNav;
      hasOverflow = last < items.length - 1;
    }
    _lastVisible = last;
    _hasOverflow = hasOverflow;

    final _OhosToolbarItemsParentData navData =
        nav.parentData! as _OhosToolbarItemsParentData;
    // 没有溢出时即使处于展开态也按单行铺（否则会剩一个空胶囊 + 一个按钮）。
    if (overflowOpen && _hasOverflow) {
      _layoutExpanded(items, nav, navData);
    } else {
      _layoutSingleRow(items, nav, navData, maxWidth);
    }
  }

  /// 收起态：单行横向，从左往右排可见项；溢出按钮固定在**行尾右侧**。
  ///
  /// 相邻项之间**不留间距**（[spacingCollapsed]，产品要求贴紧）；两侧的留白由
  /// 工具栏容器的 `menuPadding` 提供，这里不再额外加。
  void _layoutSingleRow(
    List<RenderBox> items,
    RenderBox nav,
    _OhosToolbarItemsParentData navData,
    double maxWidth,
  ) {
    double x = 0;
    for (int i = 0; i < items.length; i++) {
      final _OhosToolbarItemsParentData data =
          items[i].parentData! as _OhosToolbarItemsParentData;
      if (i > _lastVisible) {
        data.shouldPaint = false;
        continue;
      }
      data
        ..shouldPaint = true
        ..offset = Offset(
          x,
          math.max(0, (itemHeight - items[i].size.height) / 2),
        );
      x += items[i].size.width + spacingCollapsed;
    }
    if (_hasOverflow) {
      final double navX = x > 0 ? x : 0;
      navData
        ..shouldPaint = true
        ..offset = Offset(navX, 0);
      x = navX + nav.size.width;
    } else {
      navData.shouldPaint = false;
      x = x > 0 ? x - spacingCollapsed : 0;
    }
    size = Size(math.min(x, maxWidth), itemHeight);
  }

  /// 展开态：只显示被收起的项 + 溢出按钮，纵向排列。
  ///
  /// 宽度取「被收起项里最宽的那个」，但**不小于 [minExpandedWidth]**（约 4 个字宽），
  /// 免得只剩一两个窄项时胶囊瘦成细柱。可用高度放不下全部被收起项时（极端长菜单），
  /// 只铺能放下的那几项，并把溢出按钮**务必**放在可用高度之内 —— 按钮被裁掉就再也
  /// 收不回去了。
  void _layoutExpanded(
    List<RenderBox> items,
    RenderBox nav,
    _OhosToolbarItemsParentData navData,
  ) {
    final double maxWidth = constraints.maxWidth;
    final double maxHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : double.infinity;
    final int hiddenStart = _lastVisible + 1;
    final int hiddenCount = math.max(0, items.length - hiddenStart);
    double desired = math.max(minExpandedWidth, navButtonWidth);
    for (int i = hiddenStart; i < items.length; i++) {
      desired = math.max(desired, items[i].size.width);
    }
    final double width = math.min(maxWidth, desired);
    final double rowHeight = itemHeight + spacing;
    // 行数上限 = 可用高度里能放下的行数（含溢出按钮那一行）。
    final int maxRows = maxHeight.isFinite
        ? math.max(1, ((maxHeight + spacing) / rowHeight).floor())
        : hiddenCount + 1;
    final int shownItems = math.min(hiddenCount, math.max(0, maxRows - 1));

    double y = 0;
    // 按钮放在远离选区的一端：菜单在上方 → 按钮落到最下面。
    final bool navAtBottom = isAbove;
    if (!navAtBottom) {
      nav.layout(
        BoxConstraints.tightFor(width: width, height: itemHeight),
        parentUsesSize: true,
      );
      navData
        ..shouldPaint = true
        ..offset = Offset.zero;
      y += rowHeight;
    } else {
      navData.shouldPaint = false;
    }

    for (int i = 0; i < items.length; i++) {
      final _OhosToolbarItemsParentData data =
          items[i].parentData! as _OhosToolbarItemsParentData;
      final bool shown = i >= hiddenStart && i < hiddenStart + shownItems;
      data.shouldPaint = shown;
      if (!shown) {
        continue;
      }
      items[i].layout(
        BoxConstraints.tightFor(width: width, height: itemHeight),
        parentUsesSize: true,
      );
      data.offset = Offset(0, y);
      y += rowHeight;
    }

    if (navAtBottom) {
      // 上面已经吃掉行数上限，这里一定放得下；仍夹一次，避免浮点误差把它推出边界。
      final double navTop = maxHeight.isFinite
          ? math.max(0, math.min(y, maxHeight - itemHeight))
          : y;
      nav.layout(
        BoxConstraints.tightFor(width: width, height: itemHeight),
        parentUsesSize: true,
      );
      navData
        ..shouldPaint = true
        ..offset = Offset(0, navTop);
      y = navTop + rowHeight;
    }

    y = y > 0 ? y - spacing : 0;
    size = Size(width, maxHeight.isFinite ? math.min(y, maxHeight) : y);
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OhosToolbarItemsParentData) {
      child.parentData = _OhosToolbarItemsParentData();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    visitChildren((RenderObject child) {
      final RenderBox box = child as RenderBox;
      final _OhosToolbarItemsParentData data =
          box.parentData! as _OhosToolbarItemsParentData;
      if (!data.shouldPaint) {
        return;
      }
      context.paintChild(box, data.offset + offset);
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final _OhosToolbarItemsParentData data =
          child.parentData! as _OhosToolbarItemsParentData;
      if (data.shouldPaint) {
        final bool isHit = result.addWithPaintOffset(
          offset: data.offset,
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) {
            return child!.hitTest(result, position: transformed);
          },
        );
        if (isHit) {
          return true;
        }
      }
      child = data.previousSibling;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitChildren((RenderObject child) {
      final _OhosToolbarItemsParentData data =
          child.parentData! as _OhosToolbarItemsParentData;
      if (data.shouldPaint) {
        visitor(child);
      }
    });
  }
}
