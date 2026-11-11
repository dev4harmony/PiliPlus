/// 鸿蒙（OpenHarmony）文本选择体系的**真实主题值**（手柄 / 光标 / 选中高亮 / 工具栏 / 放大镜）。
///
/// ## 数据来源
///
/// 之前 `D:\ohos` 里只能看到 C++ 侧的 fallback（例如 `handle_outer_diameter` 缺省
/// 14vp 只是 `GetAttr` 的第二参数），真实值在系统主题包里。取自 gitcode 上的
/// OpenHarmony 仓库（2026-11，`master`）：
///
/// - `openharmony/global_system_resources`
///   - `systemres/main/resources/base/element/pattern.json`
///     —— 只存 token 引用（`$float:` / `$color:`），按 pattern 分组：
///     `ohos_text_overlay_pattern`、`ohos_textfield_pattern`、`ohos_text_pattern`、
///     `ohos_rich_editor_pattern`、`ohos_select_pattern`（新菜单项从 `select_pattern` 取）；
///   - `systemres/main/resources/base/element/float.json` / `color.json`
///     —— `$float:` / `$color:` 的字面值；
///   - `systemres/main/resources/dark/element/color.json`
///     —— 暗色覆盖（**只有颜色分亮暗**，`pattern.json` 没有 dark 版本，尺寸两套相同）。
/// - `openharmony/arkui_ace_engine`（消费方，用来确认每个 token 被谁读走、缺省值是多少）
///   - `frameworks/core/components/text_overlay/text_overlay_theme.h`
///   - `frameworks/core/components/text_field/textfield_theme.h`
///   - `frameworks/core/components/select/select_theme.h`（新菜单）
///   - `frameworks/core/components_ng/pattern/select_overlay/magnifier.h`
///
/// 每个常量都标了对应的 OH token，方便以后对照升级。
library;

import 'dart:ui' show Brightness, Color, FontWeight;

/// 鸿蒙文本选择相关的主题数值。
class OhosSelectionTheme {
  const OhosSelectionTheme._();

  // ---------------------------------------------------------------------------
  // 手柄（`ohos_text_overlay_pattern`）
  // ---------------------------------------------------------------------------

  /// 手柄球**外径**（`handle_outer_diameter` → `ohos_id_text_overlay_outer_handle_diameter`
  /// = 14vp）。与行高无关，是固定值。
  static const double handleOuterDiameter = 14;

  /// 手柄球**内径**（`handle_inner_diameter` = 12vp）：球心的实心填充圆。
  static const double handleInnerDiameter = 12;

  /// 外圈描边宽，也是杆宽。主题里没有这个 key，
  /// `TextOverlayTheme::GetHandleDiameterStrokeWidth()` / `GetHandleLineWidth()` 硬编码 2vp。
  static const double handleStrokeWidth = 2;

  /// 杆宽 = 光标宽（手柄矩形宽）。`textfield_pattern` 没有 `cursor_width`，
  /// 因此走 `TextFieldTheme::GetCursorWidth()` 的缺省 2vp。
  static const double handleLineWidth = 2;

  /// 手柄触摸热区半径（`GetHandleHotZoneRadius()` = `handle_outer_diameter` = 14vp）。
  /// 实际热区：横 `2×14`，纵向在线高基础上**向外**再扩 `2×14`（`select_overlay_pattern.cpp`
  /// 的 `UpdateHandleHotZone`）。
  static const double handleHotZoneRadius = 14;

  /// 手柄外圈/杆颜色（`handle_outer_color` → `$color:icon_emphasize` → `$color:brand_icon`）。
  static const Color handleOuterLight = Color(0xFF007DFF);
  static const Color handleOuterDark = Color(0xFF5291FF);

  /// 手柄内芯颜色（`handle_inner_color` → `$color:comp_background_primary` → `$color:white`）。
  static const Color handleInnerLight = Color(0xFFFFFFFF);
  static const Color handleInnerDark = Color(0xFFE5E5E5);

  /// 手柄单把柄（光标）无操作后自动隐藏的时间：
  /// `select_overlay_pattern.cpp` 的 `HIDDEN_HANDLE_TIMER_MS = 4000`。
  static const Duration handleAutoHideDelay = Duration(milliseconds: 4000);

  static Color handleOuterColor(Brightness brightness) =>
      brightness == Brightness.dark ? handleOuterDark : handleOuterLight;

  static Color handleInnerColor(Brightness brightness) =>
      brightness == Brightness.dark ? handleInnerDark : handleInnerLight;

  // ---------------------------------------------------------------------------
  // 光标（`ohos_textfield_pattern` / `ohos_text_pattern`）
  // ---------------------------------------------------------------------------

  /// 光标颜色（`cursor_color` = `$color:font_emphasize`；
  /// Text 组件是 `text_caret_color` = `$color:font_emphasize`）。
  static const Color caretLight = Color(0xFF007DFF);
  static const Color caretDark = Color(0xFF5291FF);

  /// 光标宽（无主题 key，`TextFieldTheme` 缺省 2vp）与圆角（`textfield_cursor_radius` = 0）。
  static const double caretWidth = 2;
  static const double caretRadius = 0;

  static Color caretColor(Brightness brightness) =>
      brightness == Brightness.dark ? caretDark : caretLight;

  // ---------------------------------------------------------------------------
  // 选中区域高亮
  // ---------------------------------------------------------------------------

  /// 选中文字背景（`bg_color_selected` → `$color:comp_emphasize_secondary`）。
  /// TextField 与 Text 共用同一个 token。
  static const Color selectionHighlightLight = Color(0x33007DFF);
  static const Color selectionHighlightDark = Color(0x33006CDE);

  /// RichEditor 的选中背景（`ohos_rich_editor_pattern.selected_background_color`）。
  static const Color richEditorSelectionHighlightLight = Color(0x33007DFF);
  static const Color richEditorSelectionHighlightDark = Color(0x66006CDE);

  /// 文本浮层上的「悬停/高亮」色（`text_overlay_highlight_color` = #33A479FF，亮暗相同）。
  static const Color overlayHighlight = Color(0x33A479FF);

  static Color selectionHighlight(Brightness brightness) =>
      brightness == Brightness.dark
          ? selectionHighlightDark
          : selectionHighlightLight;

  // ---------------------------------------------------------------------------
  // 选中菜单 / 工具栏（`ohos_text_overlay_pattern` + `ohos_select_pattern`）
  // ---------------------------------------------------------------------------

  /// 工具栏总高：`TextOverlayTheme::GetMenuToolbarHeight()` 硬编码 40vp，
  /// 正好等于 按钮高 28vp + 上下内边距 2×6vp。
  static const double menuToolbarHeight = 40;

  /// 按钮高/最小宽（`text_overlay_menu_button_height` = 28vp、`..._width` = 30vp）。
  static const double menuButtonHeight = 28;
  static const double menuButtonMinWidth = 30;

  /// 菜单整体内边距（`text_overlay_menu_padding_*` → `$float:padding_level3` = 6vp）。
  static const double menuPadding = 6;

  /// 按钮左右内边距（`text_overlay_menu_button_padding_left/right` → `padding_level6` = 12vp），
  /// 上下为 0（`padding_level0`）。
  static const double menuButtonPaddingHorizontal = 12;

  /// 按钮圆角。主题里没有 key，`TextOverlayTheme` 缺省 14vp = 按钮高的一半（胶囊）。
  static const double menuButtonRadius = 14;

  /// 菜单容器圆角。原生 `TextOverlayComponent::BuildAnimation` 给的是按钮高
  /// （28vp，大于半高），渲染结果就是胶囊；这里直接取工具栏高的一半。
  static const double menuCornerRadius = menuToolbarHeight / 2;

  /// 菜单与文字的间距（`text_overlay_menu_spacing_with_text` = **8vp**）。
  /// 注意不是 0：`ComputeSelectMenuPosition` 里菜单底边离选区首行上沿 =
  /// 本值 + 手柄直径（14vp）= **22vp**。
  static const double menuSpacingWithText = 8;

  /// 菜单与屏幕/视口边缘的安全距（`text_overlay_menu_safe_spacing` → `padding_level8` = 16vp）。
  static const double menuSafeSpacing = 16;

  /// 按钮文字：`text_overlay_text_font_size` = 14fp，字重
  /// `text_overlay_button_text_font_weight` = 4（OH 的 FontWeight 枚举 0..8 → W400）。
  static const double menuFontSize = 14;
  static const FontWeight menuFontWeight = FontWeight.w400;

  /// 菜单最大宽（主题无 key，`MAX_OVERLAY_MENU_WIDTH` = 442vp）与水平间距
  /// （`OVERLAY_MENU_HORIZONTAL_GAP` = 16vp）。
  static const double menuMaxWidth = 442;
  static const double menuHorizontalGap = 16;

  /// 菜单背景（`menu_bg_color` → `$color:ohos_id_color_dialog_bg`）。
  static const Color menuBackgroundLight = Color(0xFFFFFFFF);
  static const Color menuBackgroundDark = Color(0xFF202224);

  /// 菜单项文字色：新菜单走 `select_pattern.menu_text_color`
  /// （`$color:ohos_id_color_text_primary`）；老 overlay 的 `text_overlay_pattern.text_color`
  /// 是 `$color:font_primary`，暗色下**没有覆盖**（仍是 #182431），属遗留路径，不要用。
  static const Color menuTextLight = Color(0xFF182431);
  static const Color menuTextDark = Color(0xDBFFFFFF);

  /// 按压/悬停底色。
  ///
  /// 亮色：`button_bg_color_clicked` = #19182431、`button_bg_color_hovered` = #0C182431
  /// （10% / 5% 黑）。暗色主题里这两个 token 被整体换成了**白色**覆盖
  /// （`dark/element/color.json` 里对应项是 #19ffffff / #0cffffff），否则深色菜单上
  /// 再叠一层黑根本看不出来 —— 真机反馈过「深色模式看不出按下效果」。
  static const Color menuPressedLight = Color(0x19182431);
  static const Color menuHoveredLight = Color(0x0C182431);
  static const Color menuPressedDark = Color(0x19FFFFFF);
  static const Color menuHoveredDark = Color(0x0CFFFFFF);

  /// 按压底色，按亮暗主题取。
  static Color menuPressed(Brightness brightness) => brightness == Brightness.dark
      ? menuPressedDark
      : menuPressedLight;

  /// 悬停底色，按亮暗主题取。
  static Color menuHovered(Brightness brightness) => brightness == Brightness.dark
      ? menuHoveredDark
      : menuHoveredLight;

  /// 菜单描边：主题里 `text_overlay_menu_border_width` = 0vp、颜色 #33000000，
  /// 也就是**不画**边框。
  static const double menuBorderWidth = 0;

  /// 菜单底色透明度
  static const double menuBackgroundAlpha = 0.4;

  /// 是否给菜单加背景模糊。真机若出现兼容/性能问题（`BackdropFilter` 在部分
  /// 后端会掉帧或渲染异常），把它置 false 就退回「纯色 + 半透明」。
  static const bool menuBlurEnabled = true;

  /// 背景模糊强度（Flutter 的 `ImageFilter.blur` sigma）。
  static const double menuBlurSigma = 12;

  // 菜单的出现/消失：**纯淡入淡出**（150ms）。
  //
  // 时长由 SDK 的 `SelectionOverlay.fadeDuration` 决定（`_SelectionToolbarWrapper` 里的
  // FadeTransition 同时负责淡入和淡出），它是 `static const`、不改 SDK 就没法从外部调；
  // 本包不再叠加任何缩放/淡入动画。
  //
  // 原生选择菜单自带 0.6 → 1 的缩放（`select_pattern.menu_animation_scale`，
  // 150ms，`fast_out_slow_in`），但按产品要求这里**不做缩放**，只保留淡入淡出。

  static Color menuBackground(Brightness brightness) =>
      brightness == Brightness.dark ? menuBackgroundDark : menuBackgroundLight;

  static Color menuTextColor(Brightness brightness) =>
      brightness == Brightness.dark ? menuTextDark : menuTextLight;

  // ---------------------------------------------------------------------------
  // 放大镜（来自 arkui 代码常量，不在主题里）
  // `frameworks/core/components_ng/pattern/select_overlay/magnifier.h` +
  // `magnifier_controller.cpp`
  // ---------------------------------------------------------------------------

  /// 镜片尺寸 112 × 72 vp，圆角 36vp（胶囊），放大 1.4 倍。
  static const double magnifierWidth = 112;
  static const double magnifierHeight = 72;
  static const double magnifierCornerRadius = 36;
  static const double magnifierScale = 1.4;

  /// 镜片中心在触点上方 80vp（`MAGNIFIER_OFFSETY`），贴屏幕/控件边缘时会压缩这段距离。
  static const double magnifierVerticalOffset = 80;

  /// 阴影 23vp / 强度 0.05；外轮廓 3（render 侧按 px 处理）+ 白色 50%
  /// （暗色 80%）。
  static const double magnifierShadowSize = 23;
  static const double magnifierShadowStrength = 0.05;

  /// 镜片外轮廓宽度，单位是**物理像素**。
  ///
  /// `magnifier.h` 里 `MAGNIFIER_BORDERWIDTH = 3.0f` 没走 `ConvertToPx()`
  /// （同一个结构里 width/height/cornerRadius 都是 `.ConvertToPx()`），说明它直接喂给
  /// 渲染服务的像素值。换算成逻辑像素要除以 `devicePixelRatio`，否则 3x 屏上会粗 3 倍
  /// —— 之前就是这么写粗的。
  static const double magnifierBorderWidthPx = 3;
  static const double magnifierBorderOpacityLight = 0.5;
  static const double magnifierBorderOpacityDark = 0.8;

  /// 淡入/淡出 150ms，`Curves::FRICTION`。
  static const Duration magnifierFadeDuration = Duration(milliseconds: 150);
}
