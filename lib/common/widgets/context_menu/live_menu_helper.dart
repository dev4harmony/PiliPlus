part of 'package:PiliPlus/pages/live_room/superchat/superchat_card.dart';

Widget scMenuBuilder(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final buttonItems = ensureSelectionMenuButtons(
    editableTextState.contextMenuButtonItems,
    selectedTextOf: () =>
        editableTextState.textEditingValue.selection.isValid &&
            !editableTextState.textEditingValue.selection.isCollapsed
        ? editableTextState.textEditingValue.selection.textInside(
            editableTextState.textEditingValue.text,
          )
        : null,
    hideToolbar: editableTextState.hideToolbar,
  );
  final selection = editableTextState.textEditingValue.selection;
  final String? text = selection.isValid && !selection.isCollapsed
      ? selection.textInside(editableTextState.textEditingValue.text)
      : null;
  if (text != null && text.isNotEmpty) {
    buttonItems
      ..insertOrAdd(
        3,
        ContextMenuButtonItem(
          label: '视频',
          onPressed: () {
            editableTextState.hideToolbar();
            PiliScheme.videoPush(null, text);
          },
        ),
      )
      ..insertOrAdd(
        4,
        ContextMenuButtonItem(
          label: '搜索',
          onPressed: () {
            editableTextState.hideToolbar();
            Get.toNamed('/searchResult', parameters: {'keyword': text});
          },
        ),
      );
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: buttonItems,
    anchors: editableTextState.contextMenuAnchors,
  );
}
