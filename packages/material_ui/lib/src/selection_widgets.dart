/// 覆盖 `SelectableText` / `TextField` / `TextFormField`，让它们默认使用鸿蒙
/// 「杆 + 球」选择手柄（`ohosTextSelectionHandleControls`）和带分享 / 打开 /
/// 站内搜索的上下文菜单（`buildEditableTextSelectionMenu`）。
///
/// 为什么需要这一层：`selectionControls` 是 SDK 各 widget 自己按
/// `defaultTargetPlatform` 挑的（`selectable_text.dart:725-730`、
/// `text_field.dart:1665-1667` 都把 ohos 指向 `materialTextSelectionHandleControls`），
/// 应用侧不改 SDK 就只能逐个调用点传参。这三个类在 SDK 里的构造参数几乎一一对应
/// 自身字段，所以这里用 `super.` 参数原样转发（`TextFormField` 的参数只喂内部
/// builder、不对应字段，只能显式 `super(...)` 转发），只在 `selectionControls` /
/// `contextMenuBuilder` 上兜底，构造签名与 SDK 完全一致，调用点不用改。
///
/// 注意：这几个类与 SDK 的同名类**不同型**，`is TextField` 之类的判断会失效；
/// 本仓库没有这种用法（改动前全仓 grep 确认过）。等鸿蒙 fork 升到 3.47、Material
/// 自带这套修复后，删掉本文件与 `material_ui.dart` 里的 hide 即可。
library;

// 这些 SDK 参数本身已标 @Deprecated，包装类必须原样转发才能保持签名一致。
// ignore_for_file: deprecated_member_use

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart'
    hide SelectableText, TextField, TextFormField;
import 'package:flutter/material.dart'
    as flutter
    show SelectableText, TextField, TextFormField;
import 'package:flutter/services.dart'
    show MaxLengthEnforcement, TextInputFormatter;

import 'package:material_ui/src/selection_handle.dart';
import 'package:material_ui/src/selection_menu.dart';
import 'package:material_ui/src/selection_platform.dart';

/// 鸿蒙下回退到「杆 + 球」手柄与自定义菜单，其余平台完全保持 SDK 默认
/// （getter 返回 null，SDK 自己的平台分支接管）。
class SelectableText extends flutter.SelectableText {
  const SelectableText(
    super.data, {
    super.key,
    super.focusNode,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.textScaleFactor,
    super.textScaler,
    super.showCursor = false,
    super.autofocus = false,
    super.toolbarOptions,
    super.minLines,
    super.maxLines,
    super.cursorWidth = 2.0,
    super.cursorHeight,
    super.cursorRadius,
    super.cursorColor,
    super.selectionColor,
    super.selectionHeightStyle,
    super.selectionWidthStyle,
    super.dragStartBehavior = DragStartBehavior.start,
    super.enableInteractiveSelection = true,
    super.selectionControls,
    super.onTap,
    super.scrollPhysics,
    super.scrollBehavior,
    super.semanticsLabel,
    super.textHeightBehavior,
    super.textWidthBasis,
    super.onSelectionChanged,
    super.contextMenuBuilder = buildEditableTextSelectionMenu,
    super.magnifierConfiguration,
  });

  /// 见 [SelectableText]。
  const SelectableText.rich(
    super.textSpan, {
    super.key,
    super.focusNode,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.textScaleFactor,
    super.textScaler,
    super.showCursor = false,
    super.autofocus = false,
    super.toolbarOptions,
    super.minLines,
    super.maxLines,
    super.cursorWidth = 2.0,
    super.cursorHeight,
    super.cursorRadius,
    super.cursorColor,
    super.selectionColor,
    super.selectionHeightStyle,
    super.selectionWidthStyle,
    super.dragStartBehavior = DragStartBehavior.start,
    super.enableInteractiveSelection = true,
    super.selectionControls,
    super.onTap,
    super.scrollPhysics,
    super.scrollBehavior,
    super.semanticsLabel,
    super.textHeightBehavior,
    super.textWidthBasis,
    super.onSelectionChanged,
    super.contextMenuBuilder = buildEditableTextSelectionMenu,
    super.magnifierConfiguration,
  }) : super.rich();
  @override
  TextSelectionControls? get selectionControls =>
      super.selectionControls ??
      (isOhosPlatform ? ohosTextSelectionHandleControls : null);
}

/// 见 [SelectableText]。
class TextField extends flutter.TextField {
  const TextField({
    super.key,
    super.groupId = EditableText,
    super.controller,
    super.focusNode,
    super.undoController,
    super.decoration = const InputDecoration(),
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization = TextCapitalization.none,
    super.style,
    super.strutStyle,
    super.textAlign = TextAlign.start,
    super.textAlignVertical,
    super.textDirection,
    super.readOnly = false,
    super.toolbarOptions,
    super.showCursor,
    super.autofocus = false,
    super.statesController,
    super.obscuringCharacter = '•',
    super.obscureText = false,
    super.autocorrect,
    super.smartDashesType,
    super.smartQuotesType,
    super.enableSuggestions = true,
    super.maxLines = 1,
    super.minLines,
    super.expands = false,
    super.maxLength,
    super.maxLengthEnforcement,
    super.onChanged,
    super.onEditingComplete,
    super.onSubmitted,
    super.onAppPrivateCommand,
    super.inputFormatters,
    super.enabled,
    super.ignorePointers,
    super.cursorWidth = 2.0,
    super.cursorHeight,
    super.cursorRadius,
    super.cursorOpacityAnimates,
    super.cursorColor,
    super.cursorErrorColor,
    super.selectionHeightStyle,
    super.selectionWidthStyle,
    super.keyboardAppearance,
    super.scrollPadding = const EdgeInsets.all(20.0),
    super.dragStartBehavior = DragStartBehavior.start,
    super.enableInteractiveSelection,
    super.selectAllOnFocus,
    super.selectionControls,
    super.onTap,
    super.onTapAlwaysCalled = false,
    super.onTapOutside,
    super.onTapUpOutside,
    super.mouseCursor,
    super.buildCounter,
    super.scrollController,
    super.scrollPhysics,
    super.autofillHints = const <String>[],
    super.contentInsertionConfiguration,
    super.clipBehavior = Clip.hardEdge,
    super.restorationId,
    super.scribbleEnabled = true,
    super.stylusHandwritingEnabled =
        EditableText.defaultStylusHandwritingEnabled,
    super.enableIMEPersonalizedLearning = true,
    super.enableInlinePrediction,
    super.contextMenuBuilder = buildEditableTextSelectionMenu,
    super.canRequestFocus = true,
    super.spellCheckConfiguration,
    super.magnifierConfiguration,
    super.hintLocales,
  });
  @override
  TextSelectionControls? get selectionControls =>
      super.selectionControls ??
      (isOhosPlatform ? ohosTextSelectionHandleControls : null);
}

/// 见 [SelectableText]。
///
/// `TextFormField` 的构造参数只用于构建内部 `TextField`、不对应自身字段，所以这里
/// 只能显式 `super(...)` 逐个转发；`selectionControls` / `contextMenuBuilder` 在
/// 转发时兜底。它本身没有 `selectionControls` getter，故不需要覆写。
class TextFormField extends flutter.TextFormField {
  TextFormField({
    Key? key,
    Object groupId = EditableText,
    TextEditingController? controller,
    String? initialValue,
    FocusNode? focusNode,
    String? forceErrorText,
    InputDecoration? decoration = const InputDecoration(),
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? textInputAction,
    TextStyle? style,
    StrutStyle? strutStyle,
    TextDirection? textDirection,
    TextAlign textAlign = TextAlign.start,
    TextAlignVertical? textAlignVertical,
    bool autofocus = false,
    bool readOnly = false,
    @Deprecated(
      'Use `contextMenuBuilder` instead. '
      'This feature was deprecated after v3.3.0-0.5.pre.',
    )
    ToolbarOptions? toolbarOptions,
    bool? showCursor,
    String obscuringCharacter = '•',
    bool obscureText = false,
    bool autocorrect = true,
    SmartDashesType? smartDashesType,
    SmartQuotesType? smartQuotesType,
    bool enableSuggestions = true,
    MaxLengthEnforcement? maxLengthEnforcement,
    int? maxLines = 1,
    int? minLines,
    bool expands = false,
    int? maxLength,
    ValueChanged<String>? onChanged,
    GestureTapCallback? onTap,
    bool onTapAlwaysCalled = false,
    TapRegionCallback? onTapOutside,
    TapRegionUpCallback? onTapUpOutside,
    VoidCallback? onEditingComplete,
    ValueChanged<String>? onFieldSubmitted,
    FormFieldSetter<String>? onSaved,
    FormFieldValidator<String>? validator,
    FormFieldErrorBuilder? errorBuilder,
    List<TextInputFormatter>? inputFormatters,
    bool? enabled,
    bool? ignorePointers,
    double cursorWidth = 2.0,
    double? cursorHeight,
    Radius? cursorRadius,
    Color? cursorColor,
    Color? cursorErrorColor,
    Brightness? keyboardAppearance,
    EdgeInsets scrollPadding = const EdgeInsets.all(20.0),
    bool? enableInteractiveSelection,
    bool? selectAllOnFocus,
    TextSelectionControls? selectionControls,
    InputCounterWidgetBuilder? buildCounter,
    ScrollPhysics? scrollPhysics,
    Iterable<String>? autofillHints,
    AutovalidateMode? autovalidateMode,
    ScrollController? scrollController,
    String? restorationId,
    bool enableIMEPersonalizedLearning = true,
    MouseCursor? mouseCursor,
    EditableTextContextMenuBuilder? contextMenuBuilder,
    SpellCheckConfiguration? spellCheckConfiguration,
    TextMagnifierConfiguration? magnifierConfiguration,
    UndoHistoryController? undoController,
    AppPrivateCommandCallback? onAppPrivateCommand,
    bool? cursorOpacityAnimates,
    ui.BoxHeightStyle? selectionHeightStyle,
    ui.BoxWidthStyle? selectionWidthStyle,
    DragStartBehavior dragStartBehavior = DragStartBehavior.start,
    ContentInsertionConfiguration? contentInsertionConfiguration,
    MaterialStatesController? statesController,
    Clip clipBehavior = Clip.hardEdge,
    @Deprecated(
      'Use `stylusHandwritingEnabled` instead. '
      'This feature was deprecated after v3.27.0-0.2.pre.',
    )
    bool scribbleEnabled = true,
    bool stylusHandwritingEnabled =
        EditableText.defaultStylusHandwritingEnabled,
    bool canRequestFocus = true,
    List<Locale>? hintLocales,
  }) : super(
         key: key,
         groupId: groupId,
         controller: controller,
         initialValue: initialValue,
         focusNode: focusNode,
         forceErrorText: forceErrorText,
         decoration: decoration,
         keyboardType: keyboardType,
         textCapitalization: textCapitalization,
         textInputAction: textInputAction,
         style: style,
         strutStyle: strutStyle,
         textDirection: textDirection,
         textAlign: textAlign,
         textAlignVertical: textAlignVertical,
         autofocus: autofocus,
         readOnly: readOnly,
         toolbarOptions: toolbarOptions,
         showCursor: showCursor,
         obscuringCharacter: obscuringCharacter,
         obscureText: obscureText,
         autocorrect: autocorrect,
         smartDashesType: smartDashesType,
         smartQuotesType: smartQuotesType,
         enableSuggestions: enableSuggestions,
         maxLengthEnforcement: maxLengthEnforcement,
         maxLines: maxLines,
         minLines: minLines,
         expands: expands,
         maxLength: maxLength,
         onChanged: onChanged,
         onTap: onTap,
         onTapAlwaysCalled: onTapAlwaysCalled,
         onTapOutside: onTapOutside,
         onTapUpOutside: onTapUpOutside,
         onEditingComplete: onEditingComplete,
         onFieldSubmitted: onFieldSubmitted,
         onSaved: onSaved,
         validator: validator,
         errorBuilder: errorBuilder,
         inputFormatters: inputFormatters,
         enabled: enabled,
         ignorePointers: ignorePointers,
         cursorWidth: cursorWidth,
         cursorHeight: cursorHeight,
         cursorRadius: cursorRadius,
         cursorColor: cursorColor,
         cursorErrorColor: cursorErrorColor,
         keyboardAppearance: keyboardAppearance,
         scrollPadding: scrollPadding,
         enableInteractiveSelection: enableInteractiveSelection,
         selectAllOnFocus: selectAllOnFocus,
         selectionControls:
             selectionControls ??
             (isOhosPlatform ? ohosTextSelectionHandleControls : null),
         buildCounter: buildCounter,
         scrollPhysics: scrollPhysics,
         autofillHints: autofillHints,
         autovalidateMode: autovalidateMode,
         scrollController: scrollController,
         restorationId: restorationId,
         enableIMEPersonalizedLearning: enableIMEPersonalizedLearning,
         mouseCursor: mouseCursor,
         contextMenuBuilder:
             contextMenuBuilder ?? buildEditableTextSelectionMenu,
         spellCheckConfiguration: spellCheckConfiguration,
         magnifierConfiguration: magnifierConfiguration,
         undoController: undoController,
         onAppPrivateCommand: onAppPrivateCommand,
         cursorOpacityAnimates: cursorOpacityAnimates,
         selectionHeightStyle: selectionHeightStyle,
         selectionWidthStyle: selectionWidthStyle,
         dragStartBehavior: dragStartBehavior,
         contentInsertionConfiguration: contentInsertionConfiguration,
         statesController: statesController,
         clipBehavior: clipBehavior,
         scribbleEnabled: scribbleEnabled,
         stylusHandwritingEnabled: stylusHandwritingEnabled,
         canRequestFocus: canRequestFocus,
         hintLocales: hintLocales,
       );
}
