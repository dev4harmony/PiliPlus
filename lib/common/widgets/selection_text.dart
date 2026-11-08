import 'package:material_ui/material_ui.dart';

/// 可选择文本的统一封装。
///
/// 内部走 [SelectableText]（EditableText/RenderEditable 路径）而非
/// [SelectionArea]：OHOS Flutter fork 上 SelectionArea 长按拖选跨行会
/// 跳变、光标无法停在行尾，且静态 Text 高度受限时无法滚动；
/// SelectableText 按字符拖选、自带内部滚动,与输入框选择行为一致。
class SelectionText extends StatelessWidget {
  const SelectionText(
    String this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.contextMenuBuilder,
  }) : textSpan = null;

  const SelectionText.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.contextMenuBuilder,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// 自定义上下文菜单；选中文本可从 [EditableTextState.textEditingValue] 读取。
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        text: data,
        children: textSpan != null ? <InlineSpan>[textSpan!] : null,
      ),
      style: style,
      textAlign: textAlign,
      // 分享/打开/站内搜索等按钮由 shim 统一加工（见 material_ui 的 selection_menu.dart），
      // 鸿蒙上 framework 自带的分享项走 Share.invoke 通道、点了没反应，所以自己插。
      contextMenuBuilder:
          contextMenuBuilder ?? buildEditableTextSelectionMenu,
    );
  }
}
