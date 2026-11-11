import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:material_ui/src/ohos_selection_theme.dart';

/// 鸿蒙（OpenHarmony）样式的选中文字工具栏。
///
/// ## 与 SDK 默认工具栏的差别
///
/// 鸿蒙上 `AdaptiveTextSelectionToolbar` 走的是 Material 分支
/// （`adaptive_text_selection_toolbar.dart:319-327`）：44 高、圆角 22、
/// M3 surface 底、与锚点间距 8、按**选区包围盒中心**对齐。原生鸿蒙是：
///
/// - 40vp 高的**胶囊**（= 28vp 按钮 + 上下各 6vp 内边距），左右内边距 6vp，
///   按钮 28 高 / 圆角 14 / 左右内边距 12 / 文字 14fp W400，按钮之间 4vp；
/// - 每项是纯文字按钮（无图标、无分割线），按下底色 #19182431；
/// - 定位见 [OhosTextSelectionToolbarLayoutDelegate]（原生
///   `select_overlay_layout_algorithm.cpp:348-527` 的 `ComputeSelectMenuPosition`）。
///
/// 尺寸/颜色全部来自 [OhosSelectionTheme]（真实主题值，出处见该文件头）。
class OhosTextSelectionToolbar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // 与 SDK 的 `AdaptiveTextSelectionToolbar.buttonItems` 保持一致：
    // 没有任何可用项时整条菜单不出现，别留一个空胶囊。
    if (buttonItems.isEmpty) {
      return const SizedBox.shrink();
    }
    final MediaQueryData media = MediaQuery.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final double safeTop =
        media.padding.top + OhosSelectionTheme.menuSafeSpacing;
    final double safeBottom =
        math.max(media.padding.bottom, media.viewInsets.bottom) +
        OhosSelectionTheme.menuSafeSpacing;
    final double maxWidth = math.min(
      OhosSelectionTheme.menuMaxWidth,
      media.size.width - OhosSelectionTheme.menuSafeSpacing * 2,
    );

    final List<Widget> children = <Widget>[];
    for (int i = 0; i < buttonItems.length; i++) {
      if (i > 0) {
        // 原生 `MENU_BUTTON_SPACING = 4.0_vp`。
        children.add(const SizedBox(width: 4));
      }
      children.add(_OhosToolbarButton(item: buttonItems[i]));
    }

    // 原生菜单底色本身不透明，但新材质会再叠一层背景模糊
    // （`menu_background_blur_style` = COMPONENT_ULTRA_THICK，底色 alpha 0.85）。
    // 这里同序：先模糊下垫内容，再叠一层半透明底色；阴影画在裁剪之外。
    // 真机若发现模糊有性能/兼容问题，把 `menuBlurEnabled` 置 false 即可退回纯色。
    Widget content = Container(
      // 单行 40vp = 28 按钮 + 上下各 6 内边距。
      height: OhosSelectionTheme.menuToolbarHeight,
      padding: const EdgeInsets.all(OhosSelectionTheme.menuPadding),
      color: OhosSelectionTheme.menuBackground(
        brightness,
      ).withValues(alpha: OhosSelectionTheme.menuBackgroundAlpha),
      // 固定**单行横向**排布（原生的样子）。项多到超过最大宽时只能横向滚动 ——
      // 彻底解决需要像原生那样折叠成「更多」，这里暂不做。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
    if (OhosSelectionTheme.menuBlurEnabled) {
      content = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: OhosSelectionTheme.menuBlurSigma,
          sigmaY: OhosSelectionTheme.menuBlurSigma,
        ),
        child: content,
      );
    }
    final Widget capsule = DecoratedBox(
      decoration: const BoxDecoration(
        // 高 40、原生圆角给的是按钮高 28（大于半高），渲染后就是胶囊。
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
        anchorX: anchorX,
        anchorTop: anchorTop,
        anchorBottom: anchorBottom,
        gapAbove: gapAbove,
        gapBelow: gapBelow,
        safeTop: safeTop,
        safeBottom: safeBottom,
        sideLimit: OhosSelectionTheme.menuSafeSpacing,
        maxWidth: maxWidth,
      ),
      child: capsule,
    );
  }
}

/// 鸿蒙菜单定位（对应原生 `ComputeSelectMenuPosition`）：
///
/// 1. x：以 [anchorX]（两端选区端点中点）居中，再夹进左右 [sideLimit] 安全边；
/// 2. y：菜单**底边**落在 `anchorTop - gapAbove`（选区首行上沿再往上，避让手柄球）；
/// 3. 上方不够放（`y < safeTop`）→ 翻到选区下方 `anchorBottom + gapBelow`
///    （下方要避让止手柄/光标的球，所以间距比上方大）；
/// 4. 最后整体夹进 `[safeTop, 屏幕高 - 安全区]`，保证不压状态栏/键盘。
class OhosTextSelectionToolbarLayoutDelegate
    extends SingleChildLayoutDelegate {
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

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: OhosSelectionTheme.menuToolbarHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double x = _clamp(
      anchorX - childSize.width / 2,
      sideLimit,
      size.width - childSize.width - sideLimit,
    );
    double y = anchorTop - gapAbove - childSize.height;
    if (y < safeTop) {
      // 上方放不下：翻到选区下方（原生 LessNotEqual(y, menuHeight) 分支）。
      y = anchorBottom + gapBelow;
    }
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
        maxWidth != oldDelegate.maxWidth;
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

/// 单个菜单项：28vp 高的胶囊文字按钮，按下时铺 `#19182431`（原生没有水波纹）。
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
          child: Container(
            constraints: const BoxConstraints(
              minWidth: OhosSelectionTheme.menuButtonMinWidth,
              minHeight: OhosSelectionTheme.menuButtonHeight,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: OhosSelectionTheme.menuButtonPaddingHorizontal,
            ),
            decoration: BoxDecoration(
              // 亮色是 10% 黑、暗色是 10% 白（暗色下叠黑看不出来，见 OhosSelectionTheme）。
              color: _pressed
                  ? OhosSelectionTheme.menuPressed(theme.brightness)
                  : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(OhosSelectionTheme.menuButtonRadius),
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: OhosSelectionTheme.menuFontSize,
                fontWeight: OhosSelectionTheme.menuFontWeight,
                color: OhosSelectionTheme.menuTextColor(theme.brightness),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
