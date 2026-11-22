// SDK `Text` 的同名兼容实现：把文本改用 shim 的 compat `RichText`/`RenderParagraph`
// 渲染，从而能修正选中高亮的行高（见 `src/compat/paragraph.dart` 的
// `_SelectableFragment.paint`）。
//
// 为什么需要接管：
//   - 选中高亮由文本 render object 自己画。SDK 的 `RenderParagraph` 用
//     `BoxHeightStyle.tight`，而还原前用的 `SelectableText`（RenderEditable）
//     用 `EditableText.defaultSelectionHeightStyle`（native 上是
//     `includeLineSpacingMiddle`），所以接回 `SelectionArea` 后高亮明显变矮。
//   - SDK 的 `Text` 内部 new 的是 SDK 的 `RichText`/`RenderParagraph`，shim 改不到；
//     隐藏 SDK `Text` 后业务代码仍然写 `Text`，但落到兼容实现上，高亮高度即可
//     对齐 SDK 的 RenderEditable。
//
// 代码与 Flutter SDK `widgets/text.dart` 的 `Text` / `_SelectableTextContainer` /
// `_RichText` / `_SelectableTextContainerDelegate` / `_OverridingTextStyleTextSpanUtils`
// 保持一致，只把 `RichText` 换成 compat 版本；升级 SDK 时对照该文件同步即可。
//
// 注意：其他包内部自建的 `RichText`（如 flutter_html）不受这里影响。
library;

import 'dart:math';

import 'dart:ui' as ui show TextHeightBehavior;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' hide RenderParagraph;
import 'package:flutter/widgets.dart' hide RenderParagraph, RichText, Text;
import 'package:material_ui/src/compat/paragraph.dart' show RenderParagraph;
import 'package:material_ui/src/compat/rich_text.dart' show RichText;

class Text extends StatelessWidget {
  /// Creates a text widget.
  ///
  /// If the [style] argument is null, the text will use the style from the
  /// closest enclosing [DefaultTextStyle].
  ///
  /// The [overflow] property's behavior is affected by the [softWrap] argument.
  /// If the [softWrap] is true or null, the glyph causing overflow, and those
  /// that follow, will not be rendered. Otherwise, it will be shown with the
  /// given overflow option.
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null,
       assert(
         textScaler == null || textScaleFactor == null,
         'textScaleFactor is deprecated and cannot be specified when textScaler is specified.',
       );

  /// Creates a text widget with a [InlineSpan].
  ///
  /// The following subclasses of [InlineSpan] may be used to build rich text:
  ///
  /// * [TextSpan]s define text and children [InlineSpan]s.
  /// * [WidgetSpan]s define embedded inline widgets.
  ///
  /// See [RichText] which provides a lower-level way to draw text.
  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null,
       assert(
         textScaler == null || textScaleFactor == null,
         'textScaleFactor is deprecated and cannot be specified when textScaler is specified.',
       );

  /// The text to display.
  ///
  /// This will be null if a [textSpan] is provided instead.
  final String? data;

  /// The text to display as a [InlineSpan].
  ///
  /// This will be null if [data] is provided instead.
  final InlineSpan? textSpan;

  /// If non-null, the style to use for this text.
  ///
  /// If the style's "inherit" property is true, the style will be merged with
  /// the closest enclosing [DefaultTextStyle]. Otherwise, the style will
  /// replace the closest enclosing [DefaultTextStyle].
  ///
  /// The user or platform may override this [style]'s [TextStyle.fontWeight],
  /// [TextStyle.height], [TextStyle.letterSpacing], and [TextStyle.wordSpacing]
  /// via a [MediaQuery] ancestor's [MediaQueryData.boldText],
  /// [MediaQueryData.lineHeightScaleFactorOverride],
  /// [MediaQueryData.letterSpacingOverride], and [MediaQueryData.wordSpacingOverride]
  /// regardless of its [TextStyle.inherit] value.
  final TextStyle? style;

  /// {@macro flutter.painting.textPainter.strutStyle}
  ///
  /// The user or platform may override this [strutStyle]'s [StrutStyle.height]
  /// via a [MediaQuery] ancestor's [MediaQueryData.lineHeightScaleFactorOverride].
  final StrutStyle? strutStyle;

  /// How the text should be aligned horizontally.
  final TextAlign? textAlign;

  /// The directionality of the text.
  ///
  /// This decides how [textAlign] values like [TextAlign.start] and
  /// [TextAlign.end] are interpreted.
  ///
  /// This is also used to disambiguate how to render bidirectional text. For
  /// example, if the [data] is an English phrase followed by a Hebrew phrase,
  /// in a [TextDirection.ltr] context the English phrase will be on the left
  /// and the Hebrew phrase to its right, while in a [TextDirection.rtl]
  /// context, the English phrase will be on the right and the Hebrew phrase on
  /// its left.
  ///
  /// Defaults to the ambient [Directionality], if any.
  final TextDirection? textDirection;

  /// Used to select a font when the same Unicode character can
  /// be rendered differently, depending on the locale.
  ///
  /// It's rarely necessary to set this property. By default its value
  /// is inherited from the enclosing app with `Localizations.localeOf(context)`.
  ///
  /// See [RenderParagraph.locale] for more information.
  final Locale? locale;

  /// Whether the text should break at soft line breaks.
  ///
  /// If false, the glyphs in the text will be positioned as if there was unlimited horizontal space.
  final bool? softWrap;

  /// How visual overflow should be handled.
  ///
  /// If this is null [TextStyle.overflow] will be used, otherwise the value
  /// from the nearest [DefaultTextStyle] ancestor will be used.
  final TextOverflow? overflow;

  /// Deprecated. Will be removed in a future version of Flutter. Use
  /// [textScaler] instead.
  ///
  /// The number of font pixels for each logical pixel.
  ///
  /// For example, if the text scale factor is 1.5, text will be 50% larger than
  /// the specified font size.
  ///
  /// The value given to the constructor as textScaleFactor. If null, will
  /// use the [MediaQueryData.textScaleFactor] obtained from the ambient
  /// [MediaQuery], or 1.0 if there is no [MediaQuery] in scope.
  @Deprecated(
    'Use textScaler instead. '
    'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
    'This feature was deprecated after v3.12.0-2.0.pre.',
  )
  final double? textScaleFactor;

  /// {@macro flutter.painting.textPainter.textScaler}
  final TextScaler? textScaler;

  /// An optional maximum number of lines for the text to span, wrapping if necessary.
  /// If the text exceeds the given number of lines, it will be truncated according
  /// to [overflow].
  ///
  /// If this is 1, text will not wrap. Otherwise, text will be wrapped at the
  /// edge of the box.
  ///
  /// If this is null, but there is an ambient [DefaultTextStyle] that specifies
  /// an explicit number for its [DefaultTextStyle.maxLines], then the
  /// [DefaultTextStyle] value will take precedence. You can use a [RichText]
  /// widget directly to entirely override the [DefaultTextStyle].
  final int? maxLines;

  /// {@template flutter.widgets.Text.semanticsLabel}
  /// An alternative semantics label for this text.
  ///
  /// If present, the semantics of this widget will contain this value instead
  /// of the actual text. This will overwrite any of the semantics labels applied
  /// directly to the [TextSpan]s.
  ///
  /// This is useful for replacing abbreviations or shorthands with the full
  /// text value:
  ///
  /// ```dart
  /// const Text(r'$$', semanticsLabel: 'Double dollars')
  /// ```
  /// {@endtemplate}
  final String? semanticsLabel;

  /// A unique identifier for the semantics node for this widget.
  ///
  /// This is useful for cases where the text widget needs to have a uniquely
  /// identifiable ID that is recognized through the automation tools without
  /// having a dependency on the actual content of the text that can possibly be
  /// dynamic in nature.
  final String? semanticsIdentifier;

  /// {@macro flutter.painting.textPainter.textWidthBasis}
  final TextWidthBasis? textWidthBasis;

  /// {@macro dart.ui.textHeightBehavior}
  final ui.TextHeightBehavior? textHeightBehavior;

  /// The color to use when painting the selection.
  ///
  /// This is ignored if [SelectionContainer.maybeOf] returns null
  /// in the [BuildContext] of the [Text] widget.
  ///
  /// If null, the ambient [DefaultSelectionStyle] is used (if any); failing
  /// that, the selection color defaults to [DefaultSelectionStyle.defaultColor]
  /// (semi-transparent grey).
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final DefaultTextStyle defaultTextStyle = DefaultTextStyle.of(context);
    TextStyle? effectiveTextStyle = style;
    if (style == null || style!.inherit) {
      effectiveTextStyle = defaultTextStyle.style.merge(style);
    }
    if (MediaQuery.boldTextOf(context)) {
      effectiveTextStyle = effectiveTextStyle!.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    // TODO(Renzo-Olivares): Investigate ways the framework can automatically
    // apply MediaQueryData.paragraphSpacingOverride to its own text components.
    // See: https://github.com/flutter/flutter/issues/177953 and https://github.com/flutter/flutter/issues/177408.
    final double? lineHeightScaleFactor = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
    final double? letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
    final double? wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
    final TextSpan effectiveTextSpan = _OverridingTextStyleTextSpanUtils.applyTextSpacingOverrides(
      lineHeightScaleFactor: lineHeightScaleFactor,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textSpan: TextSpan(
        style: effectiveTextStyle,
        text: data,
        locale: locale,
        children: textSpan != null ? <InlineSpan>[textSpan!] : null,
      ),
    );
    final StrutStyle? effectiveStrutStyle = strutStyle?.merge(
      StrutStyle(height: lineHeightScaleFactor),
    );
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    final TextScaler textScaler = switch ((this.textScaler, textScaleFactor)) {
      (final TextScaler textScaler, _) => textScaler,
      // For unmigrated apps, fall back to textScaleFactor.
      (null, final double textScaleFactor) => TextScaler.linear(textScaleFactor),
      (null, null) => MediaQuery.textScalerOf(context),
    };
    late Widget result;
    if (registrar != null) {
      result = MouseRegion(
        cursor: DefaultSelectionStyle.of(context).mouseCursor ?? SystemMouseCursors.text,
        child: _SelectableTextContainer(
          textAlign: textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start,
          textDirection:
              textDirection, // RichText uses Directionality.of to obtain a default if this is null.
          locale:
              locale, // RichText uses Localizations.localeOf to obtain a default if this is null
          softWrap: softWrap ?? defaultTextStyle.softWrap,
          overflow: overflow ?? effectiveTextStyle?.overflow ?? defaultTextStyle.overflow,
          textScaler: textScaler,
          maxLines: maxLines ?? defaultTextStyle.maxLines,
          strutStyle: effectiveStrutStyle,
          textWidthBasis: textWidthBasis ?? defaultTextStyle.textWidthBasis,
          textHeightBehavior:
              textHeightBehavior ??
              defaultTextStyle.textHeightBehavior ??
              DefaultTextHeightBehavior.maybeOf(context),
          selectionColor:
              selectionColor ??
              DefaultSelectionStyle.of(context).selectionColor ??
              DefaultSelectionStyle.defaultColor,
          text: effectiveTextSpan,
        ),
      );
    } else {
      result = RichText(
        textAlign: textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start,
        textDirection:
            textDirection, // RichText uses Directionality.of to obtain a default if this is null.
        locale: locale, // RichText uses Localizations.localeOf to obtain a default if this is null
        softWrap: softWrap ?? defaultTextStyle.softWrap,
        overflow: overflow ?? effectiveTextStyle?.overflow ?? defaultTextStyle.overflow,
        textScaler: textScaler,
        maxLines: maxLines ?? defaultTextStyle.maxLines,
        strutStyle: effectiveStrutStyle,
        textWidthBasis: textWidthBasis ?? defaultTextStyle.textWidthBasis,
        textHeightBehavior:
            textHeightBehavior ??
            defaultTextStyle.textHeightBehavior ??
            DefaultTextHeightBehavior.maybeOf(context),
        selectionColor:
            selectionColor ??
            DefaultSelectionStyle.of(context).selectionColor ??
            DefaultSelectionStyle.defaultColor,
        text: effectiveTextSpan,
      );
    }
    if (semanticsLabel != null || semanticsIdentifier != null) {
      result = Semantics(
        textDirection: textDirection,
        label: semanticsLabel,
        identifier: semanticsIdentifier,
        child: ExcludeSemantics(excluding: semanticsLabel != null, child: result),
      );
    }
    return result;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('data', data, showName: false));
    if (textSpan != null) {
      properties.add(
        textSpan!.toDiagnosticsNode(name: 'textSpan', style: DiagnosticsTreeStyle.transition),
      );
    }
    style?.debugFillProperties(properties);
    properties.add(EnumProperty<TextAlign>('textAlign', textAlign, defaultValue: null));
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection, defaultValue: null));
    properties.add(DiagnosticsProperty<Locale>('locale', locale, defaultValue: null));
    properties.add(
      FlagProperty(
        'softWrap',
        value: softWrap,
        ifTrue: 'wrapping at box width',
        ifFalse: 'no wrapping except at line break characters',
        showName: true,
      ),
    );
    properties.add(EnumProperty<TextOverflow>('overflow', overflow, defaultValue: null));
    properties.add(DoubleProperty('textScaleFactor', textScaleFactor, defaultValue: null));
    properties.add(IntProperty('maxLines', maxLines, defaultValue: null));
    properties.add(
      EnumProperty<TextWidthBasis>('textWidthBasis', textWidthBasis, defaultValue: null),
    );
    properties.add(
      DiagnosticsProperty<ui.TextHeightBehavior>(
        'textHeightBehavior',
        textHeightBehavior,
        defaultValue: null,
      ),
    );
    if (semanticsLabel != null) {
      properties.add(StringProperty('semanticsLabel', semanticsLabel));
    }
    if (semanticsIdentifier != null) {
      properties.add(StringProperty('semanticsIdentifier', semanticsIdentifier));
    }
  }
}

class _SelectableTextContainer extends StatefulWidget {
  const _SelectableTextContainer({
    required this.text,
    required this.textAlign,
    this.textDirection,
    required this.softWrap,
    required this.overflow,
    required this.textScaler,
    this.maxLines,
    this.locale,
    this.strutStyle,
    required this.textWidthBasis,
    this.textHeightBehavior,
    required this.selectionColor,
  });

  final TextSpan text;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final bool softWrap;
  final TextOverflow overflow;
  final TextScaler textScaler;
  final int? maxLines;
  final Locale? locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final Color selectionColor;

  @override
  State<_SelectableTextContainer> createState() => _SelectableTextContainerState();
}

class _SelectableTextContainerState extends State<_SelectableTextContainer> {
  late final _SelectableTextContainerDelegate _selectionDelegate;
  final GlobalKey _textKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectionDelegate = _SelectableTextContainerDelegate(_textKey);
  }

  @override
  void dispose() {
    _selectionDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(
      delegate: _selectionDelegate,
      // Use [_RichText] wrapper so the underlying [RenderParagraph] can register
      // its [Selectable]s to the [SelectionContainer] created by this widget.
      child: _RichText(
        textKey: _textKey,
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        locale: widget.locale,
        softWrap: widget.softWrap,
        overflow: widget.overflow,
        textScaler: widget.textScaler,
        maxLines: widget.maxLines,
        strutStyle: widget.strutStyle,
        textWidthBasis: widget.textWidthBasis,
        textHeightBehavior: widget.textHeightBehavior,
        selectionColor: widget.selectionColor,
        text: widget.text,
      ),
    );
  }
}

class _RichText extends StatelessWidget {
  const _RichText({
    this.textKey,
    required this.text,
    required this.textAlign,
    this.textDirection,
    required this.softWrap,
    required this.overflow,
    required this.textScaler,
    this.maxLines,
    this.locale,
    this.strutStyle,
    required this.textWidthBasis,
    this.textHeightBehavior,
    required this.selectionColor,
  });

  final GlobalKey? textKey;
  final InlineSpan text;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final bool softWrap;
  final TextOverflow overflow;
  final TextScaler textScaler;
  final int? maxLines;
  final Locale? locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final Color selectionColor;

  @override
  Widget build(BuildContext context) {
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    return RichText(
      key: textKey,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionRegistrar: registrar,
      selectionColor: selectionColor,
      text: text,
    );
  }
}

// In practice some selectables like widgetspan shift several pixels. So when
// the vertical position diff is within the threshold, compare the horizontal
// position to make the compareScreenOrder function more robust.
const double _kSelectableVerticalComparingThreshold = 3.0;

class _SelectableTextContainerDelegate extends StaticSelectionContainerDelegate {
  _SelectableTextContainerDelegate(GlobalKey textKey) : _textKey = textKey;

  final GlobalKey _textKey;
  RenderParagraph get paragraph => _textKey.currentContext!.findRenderObject()! as RenderParagraph;

  @override
  SelectionResult handleSelectParagraph(SelectParagraphSelectionEvent event) {
    final SelectionResult result = _handleSelectParagraph(event);
    super.didReceiveSelectionBoundaryEvents();
    return result;
  }

  SelectionResult _handleSelectParagraph(SelectParagraphSelectionEvent event) {
    if (event.absorb) {
      for (var index = 0; index < selectables.length; index += 1) {
        dispatchSelectionEventToChild(selectables[index], event);
      }
      currentSelectionStartIndex = 0;
      currentSelectionEndIndex = selectables.length - 1;
      return SelectionResult.next;
    }

    // First pass, if the position is on a placeholder then dispatch the selection
    // event to the [Selectable] at the location and terminate.
    for (var index = 0; index < selectables.length; index += 1) {
      final bool selectableIsPlaceholder = !paragraph.selectableBelongsToParagraph(
        selectables[index],
      );
      if (selectableIsPlaceholder && selectables[index].boundingBoxes.isNotEmpty) {
        for (final Rect rect in selectables[index].boundingBoxes) {
          final Rect globalRect = MatrixUtils.transformRect(
            selectables[index].getTransformTo(null),
            rect,
          );
          if (globalRect.contains(event.globalPosition)) {
            currentSelectionStartIndex = currentSelectionEndIndex = index;
            return dispatchSelectionEventToChild(selectables[index], event);
          }
        }
      }
    }

    SelectionResult? lastSelectionResult;
    var foundStart = false;
    int? lastNextIndex;
    for (var index = 0; index < selectables.length; index += 1) {
      if (!paragraph.selectableBelongsToParagraph(selectables[index])) {
        if (foundStart) {
          final SelectionEvent synthesizedEvent = SelectParagraphSelectionEvent(
            globalPosition: event.globalPosition,
            absorb: true,
          );
          final SelectionResult result = dispatchSelectionEventToChild(
            selectables[index],
            synthesizedEvent,
          );
          if (selectables.length - 1 == index) {
            currentSelectionEndIndex = index;
            _flushInactiveSelections();
            return result;
          }
        }
        continue;
      }
      final SelectionGeometry existingGeometry = selectables[index].value;
      lastSelectionResult = dispatchSelectionEventToChild(selectables[index], event);
      if (index == selectables.length - 1 && lastSelectionResult == SelectionResult.next) {
        if (foundStart) {
          currentSelectionEndIndex = index;
        } else {
          currentSelectionStartIndex = currentSelectionEndIndex = index;
        }
        return SelectionResult.next;
      }
      if (lastSelectionResult == SelectionResult.next) {
        if (selectables[index].value == existingGeometry && !foundStart) {
          lastNextIndex = index;
        }
        if (selectables[index].value != existingGeometry && !foundStart) {
          assert(selectables[index].boundingBoxes.isNotEmpty);
          assert(selectables[index].value.selectionRects.isNotEmpty);
          final bool selectionAtStartOfSelectable = selectables[index].boundingBoxes[0].overlaps(
            selectables[index].value.selectionRects[0],
          );
          var startIndex = 0;
          if (lastNextIndex != null && selectionAtStartOfSelectable) {
            startIndex = lastNextIndex + 1;
          } else {
            startIndex = lastNextIndex == null && selectionAtStartOfSelectable ? 0 : index;
          }
          for (var i = startIndex; i < index; i += 1) {
            final SelectionEvent synthesizedEvent = SelectParagraphSelectionEvent(
              globalPosition: event.globalPosition,
              absorb: true,
            );
            dispatchSelectionEventToChild(selectables[i], synthesizedEvent);
          }
          currentSelectionStartIndex = startIndex;
          foundStart = true;
        }
        continue;
      }
      if (index == 0 && lastSelectionResult == SelectionResult.previous) {
        return SelectionResult.previous;
      }
      if (selectables[index].value != existingGeometry) {
        if (!foundStart && lastNextIndex == null) {
          currentSelectionStartIndex = 0;
          for (var i = 0; i < index; i += 1) {
            final SelectionEvent synthesizedEvent = SelectParagraphSelectionEvent(
              globalPosition: event.globalPosition,
              absorb: true,
            );
            dispatchSelectionEventToChild(selectables[i], synthesizedEvent);
          }
        }
        currentSelectionEndIndex = index;
        // Geometry has changed as a result of select paragraph, need to clear the
        // selection of other selectables to keep selection in sync.
        _flushInactiveSelections();
      }
      return SelectionResult.end;
    }
    assert(lastSelectionResult == null);
    return SelectionResult.end;
  }

  SelectionResult _adjustSelection(SelectionEdgeUpdateEvent event, {required bool isEnd}) {
    assert(() {
      if (isEnd) {
        assert(currentSelectionEndIndex < selectables.length && currentSelectionEndIndex >= 0);
        return true;
      }
      assert(currentSelectionStartIndex < selectables.length && currentSelectionStartIndex >= 0);
      return true;
    }());
    SelectionResult? finalResult;
    // Determines if the edge being adjusted is within the current viewport.
    //  - If so, we begin the search for the new selection edge position at the
    //    currentSelectionEndIndex/currentSelectionStartIndex.
    //  - If not, we attempt to locate the new selection edge starting from
    //    the opposite end.
    //  - If neither edge is in the current viewport, the search for the new
    //    selection edge position begins at 0.
    //
    // This can happen when there is a scrollable child and the edge being adjusted
    // has been scrolled out of view.
    final isCurrentEdgeWithinViewport = isEnd
        ? value.endSelectionPoint != null
        : value.startSelectionPoint != null;
    final isOppositeEdgeWithinViewport = isEnd
        ? value.startSelectionPoint != null
        : value.endSelectionPoint != null;
    int newIndex = switch ((isEnd, isCurrentEdgeWithinViewport, isOppositeEdgeWithinViewport)) {
      (true, true, true) => currentSelectionEndIndex,
      (true, true, false) => currentSelectionEndIndex,
      (true, false, true) => currentSelectionStartIndex,
      (true, false, false) => 0,
      (false, true, true) => currentSelectionStartIndex,
      (false, true, false) => currentSelectionStartIndex,
      (false, false, true) => currentSelectionEndIndex,
      (false, false, false) => 0,
    };
    bool? forward;
    late SelectionResult currentSelectableResult;
    // This loop sends the selection event to one of the following to determine
    // the direction of the search.
    //  - currentSelectionEndIndex/currentSelectionStartIndex if the current edge
    //    is in the current viewport.
    //  - The opposite edge index if the current edge is not in the current viewport.
    //  - Index 0 if neither edge is in the current viewport.
    //
    // If the result is `SelectionResult.next`, this loop look backward.
    // Otherwise, it looks forward.
    //
    // The terminate condition are:
    // 1. the selectable returns end, pending, none.
    // 2. the selectable returns previous when looking forward.
    // 2. the selectable returns next when looking backward.
    while (newIndex < selectables.length && newIndex >= 0 && finalResult == null) {
      currentSelectableResult = dispatchSelectionEventToChild(selectables[newIndex], event);
      switch (currentSelectableResult) {
        case SelectionResult.end:
        case SelectionResult.pending:
        case SelectionResult.none:
          finalResult = currentSelectableResult;
        case SelectionResult.next:
          if (forward == false) {
            newIndex += 1;
            finalResult = SelectionResult.end;
          } else if (newIndex == selectables.length - 1) {
            finalResult = currentSelectableResult;
          } else {
            forward = true;
            newIndex += 1;
          }
        case SelectionResult.previous:
          if (forward ?? false) {
            newIndex -= 1;
            finalResult = SelectionResult.end;
          } else if (newIndex == 0) {
            finalResult = currentSelectableResult;
          } else {
            forward = false;
            newIndex -= 1;
          }
      }
    }
    if (isEnd) {
      final bool forwardSelection = currentSelectionEndIndex >= currentSelectionStartIndex;
      if (forward != null &&
          ((!forwardSelection && forward && newIndex >= currentSelectionStartIndex) ||
              (forwardSelection && !forward && newIndex <= currentSelectionStartIndex))) {
        currentSelectionStartIndex = currentSelectionEndIndex;
      }
      currentSelectionEndIndex = newIndex;
    } else {
      final bool forwardSelection = currentSelectionEndIndex >= currentSelectionStartIndex;
      if (forward != null &&
          ((!forwardSelection && !forward && newIndex <= currentSelectionEndIndex) ||
              (forwardSelection && forward && newIndex >= currentSelectionEndIndex))) {
        currentSelectionEndIndex = currentSelectionStartIndex;
      }
      currentSelectionStartIndex = newIndex;
    }
    _flushInactiveSelections();
    return finalResult!;
  }

  /// The compare function this delegate used for determining the selection
  /// order of the [Selectable]s.
  ///
  /// Sorts the [Selectable]s by their top left [Rect].
  @override
  Comparator<Selectable> get compareOrder => _compareScreenOrder;

  static int _compareScreenOrder(Selectable a, Selectable b) {
    // Attempt to sort the selectables under a [_SelectableTextContainerDelegate]
    // by the top left rect.
    final Rect rectA = MatrixUtils.transformRect(a.getTransformTo(null), a.boundingBoxes.first);
    final Rect rectB = MatrixUtils.transformRect(b.getTransformTo(null), b.boundingBoxes.first);
    final int result = _compareVertically(rectA, rectB);
    if (result != 0) {
      return result;
    }
    return _compareHorizontally(rectA, rectB);
  }

  /// Compares two rectangles in the screen order solely by their vertical
  /// positions.
  ///
  /// Returns positive if a is lower, negative if a is higher, 0 if their
  /// order can't be determine solely by their vertical position.
  static int _compareVertically(Rect a, Rect b) {
    // The rectangles overlap so defer to horizontal comparison.
    if ((a.top - b.top < _kSelectableVerticalComparingThreshold &&
            a.bottom - b.bottom > -_kSelectableVerticalComparingThreshold) ||
        (b.top - a.top < _kSelectableVerticalComparingThreshold &&
            b.bottom - a.bottom > -_kSelectableVerticalComparingThreshold)) {
      return 0;
    }
    if ((a.top - b.top).abs() > _kSelectableVerticalComparingThreshold) {
      return a.top > b.top ? 1 : -1;
    }
    return a.bottom > b.bottom ? 1 : -1;
  }

  /// Compares two rectangles in the screen order by their horizontal positions
  /// assuming one of the rectangles enclose the other rect vertically.
  ///
  /// Returns positive if a is lower, negative if a is higher.
  static int _compareHorizontally(Rect a, Rect b) {
    // a encloses b.
    if (a.left - b.left < precisionErrorTolerance && a.right - b.right > -precisionErrorTolerance) {
      return -1;
    }
    // b encloses a.
    if (b.left - a.left < precisionErrorTolerance && b.right - a.right > -precisionErrorTolerance) {
      return 1;
    }
    if ((a.left - b.left).abs() > precisionErrorTolerance) {
      return a.left > b.left ? 1 : -1;
    }
    return a.right > b.right ? 1 : -1;
  }

  /// This method calculates a local [SelectedContentRange] based on the list
  /// of [selections] that are accumulated from the [Selectable] children under this
  /// delegate. This calculation takes into account the accumulated content
  /// length before the active selection, and returns null when either selection
  /// edge has not been set.
  SelectedContentRange? _calculateLocalRange(List<_SelectionInfo> selections) {
    if (currentSelectionStartIndex == -1 || currentSelectionEndIndex == -1) {
      return null;
    }
    var startOffset = 0;
    var endOffset = 0;
    var foundStart = false;
    bool forwardSelection = currentSelectionEndIndex >= currentSelectionStartIndex;
    if (currentSelectionEndIndex == currentSelectionStartIndex) {
      // Determining selection direction is inaccurate if currentSelectionStartIndex == currentSelectionEndIndex.
      // Use the range from the selectable within the selection as the source of truth for selection direction.
      final SelectedContentRange rangeAtSelectableInSelection =
          selectables[currentSelectionStartIndex].getSelection()!;
      forwardSelection =
          rangeAtSelectableInSelection.endOffset >= rangeAtSelectableInSelection.startOffset;
    }
    for (var index = 0; index < selections.length; index++) {
      final _SelectionInfo selection = selections[index];
      if (selection.range == null) {
        if (foundStart) {
          return SelectedContentRange(
            startOffset: forwardSelection ? startOffset : endOffset,
            endOffset: forwardSelection ? endOffset : startOffset,
          );
        }
        startOffset += selection.contentLength;
        endOffset = startOffset;
        continue;
      }
      final int selectionStartNormalized = min(
        selection.range!.startOffset,
        selection.range!.endOffset,
      );
      final int selectionEndNormalized = max(
        selection.range!.startOffset,
        selection.range!.endOffset,
      );
      if (!foundStart) {
        // Because a RenderParagraph may split its content into multiple selectables
        // we have to consider at what offset a selectable starts at relative
        // to the RenderParagraph, when the selectable is not the start of the content.
        final bool shouldConsiderContentStart =
            index > 0 && paragraph.selectableBelongsToParagraph(selectables[index]);
        startOffset +=
            (selectionStartNormalized -
                    (shouldConsiderContentStart
                        ? paragraph
                              .getPositionForOffset(
                                selectables[index].boundingBoxes.first.centerLeft,
                              )
                              .offset
                        : 0))
                .abs();
        endOffset = startOffset + (selectionEndNormalized - selectionStartNormalized).abs();
        foundStart = true;
      } else {
        endOffset += (selectionEndNormalized - selectionStartNormalized).abs();
      }
    }
    assert(
      foundStart,
      'The start of the selection has not been found despite this selection delegate having an existing currentSelectionStartIndex and currentSelectionEndIndex.',
    );
    return SelectedContentRange(
      startOffset: forwardSelection ? startOffset : endOffset,
      endOffset: forwardSelection ? endOffset : startOffset,
    );
  }

  /// Returns a [SelectedContentRange] considering the [SelectedContentRange]
  /// from each [Selectable] child managed under this delegate.
  ///
  /// When nothing is selected or either selection edge has not been set,
  /// this method will return `null`.
  @override
  SelectedContentRange? getSelection() {
    final selections = <_SelectionInfo>[
      for (final Selectable selectable in selectables)
        (contentLength: selectable.contentLength, range: selectable.getSelection()),
    ];
    return _calculateLocalRange(selections);
  }

  // From [SelectableRegion].

  // Clears the selection on all selectables not in the range of
  // currentSelectionStartIndex..currentSelectionEndIndex.
  //
  // If one of the edges does not exist, then this method will clear the selection
  // in all selectables except the existing edge.
  //
  // If neither of the edges exist this method immediately returns.
  void _flushInactiveSelections() {
    if (currentSelectionStartIndex == -1 && currentSelectionEndIndex == -1) {
      return;
    }
    if (currentSelectionStartIndex == -1 || currentSelectionEndIndex == -1) {
      final int skipIndex = currentSelectionStartIndex == -1
          ? currentSelectionEndIndex
          : currentSelectionStartIndex;
      for (var i = 0; i < selectables.length; i++) {
        if (i == skipIndex) {
          continue;
        }
        dispatchSelectionEventToChild(selectables[i], const ClearSelectionEvent());
      }
      return;
    }
    final int skipStart = min(currentSelectionStartIndex, currentSelectionEndIndex);
    final int skipEnd = max(currentSelectionStartIndex, currentSelectionEndIndex);
    for (var index = 0; index < selectables.length; index += 1) {
      if (index >= skipStart && index <= skipEnd) {
        continue;
      }
      dispatchSelectionEventToChild(selectables[index], const ClearSelectionEvent());
    }
  }

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    if (event.granularity != TextGranularity.paragraph) {
      return super.handleSelectionEdgeUpdate(event);
    }
    updateLastSelectionEdgeLocation(
      globalSelectionEdgeLocation: event.globalPosition,
      forEnd: event.type == SelectionEventType.endEdgeUpdate,
    );
    if (event.type == SelectionEventType.endEdgeUpdate) {
      return currentSelectionEndIndex == -1
          ? super.handleSelectionEdgeUpdate(event)
          : _adjustSelection(event, isEnd: true);
    }
    return currentSelectionStartIndex == -1
        ? super.handleSelectionEdgeUpdate(event)
        : _adjustSelection(event, isEnd: false);
  }
}

/// The length of the content that can be selected, and the range that is
/// selected.
typedef _SelectionInfo = ({int contentLength, SelectedContentRange? range});

/// A utility class for overriding the text styles of a [TextSpan] tree.
// When changes are made to this class, the equivalent API in editable_text.dart
// must also be updated.
// TODO(Renzo-Olivares): Remove after investigating a solution for overriding all
// styles for children in an [InlineSpan] tree, see: https://github.com/flutter/flutter/issues/177952.
class _OverridingTextStyleTextSpanUtils {
  static TextSpan applyTextSpacingOverrides({
    double? lineHeightScaleFactor,
    double? letterSpacing,
    double? wordSpacing,
    required TextSpan textSpan,
  }) {
    if (lineHeightScaleFactor == null && letterSpacing == null && wordSpacing == null) {
      return textSpan;
    }
    return _applyTextStyleOverrides(
      TextStyle(
        height: lineHeightScaleFactor,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
      ),
      textSpan,
    );
  }

  static TextSpan _applyTextStyleOverrides(TextStyle overrideTextStyle, TextSpan textSpan) {
    return TextSpan(
      text: textSpan.text,
      children: textSpan.children?.map((InlineSpan child) {
        if (child is TextSpan && child.runtimeType == TextSpan) {
          return _applyTextStyleOverrides(overrideTextStyle, child);
        }
        return child;
      }).toList(),
      style: textSpan.style?.merge(overrideTextStyle) ?? overrideTextStyle,
      recognizer: textSpan.recognizer,
      mouseCursor: textSpan.mouseCursor,
      onEnter: textSpan.onEnter,
      onExit: textSpan.onExit,
      semanticsLabel: textSpan.semanticsLabel,
      semanticsIdentifier: textSpan.semanticsIdentifier,
      locale: textSpan.locale,
      spellOut: textSpan.spellOut,
    );
  }
}
