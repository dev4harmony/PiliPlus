part of 'package:PiliPlus/pages/dynamics/widgets/content_panel.dart';

Widget dynTextMenuBuilder(
  EditableTextState state,
  String text,
  ModuleDynamicModel? moduleDynamic,
) {
  final buttonItems = ensureSelectionMenuButtons(
    state.contextMenuButtonItems,
    selectedTextOf: () {
      final value = state.textEditingValue;
      final selection = value.selection;
      if (!selection.isValid || selection.isCollapsed) return null;
      return selection.textInside(value.text);
    },
    hideToolbar: state.hideToolbar,
  )
    ..insertOrAdd(
      3,
      ContextMenuButtonItem(
        label: '文本',
        onPressed: () {
          state.hideToolbar();
          _showTextDialog(text);
        },
      ),
    )
    ..insertOrAdd(
      4,
      ContextMenuButtonItem(
        label: '表情',
        onPressed: () {
          state.hideToolbar();
          _showEmoteDialog(moduleDynamic);
        },
      ),
    );
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: buttonItems,
    anchors: state.contextMenuAnchors,
  );
}

void _showEmoteDialog(ModuleDynamicModel? moduleDynamic) {
  if (moduleDynamic == null) return;
  final richTextNodes =
      moduleDynamic.desc?.richTextNodes ??
      moduleDynamic.major?.opus?.summary?.richTextNodes;
  if (richTextNodes == null || richTextNodes.isEmpty) return;
  final emotes = <String, Emoji>{};
  for (final node in richTextNodes) {
    final text = node.origText;
    final emoji = node.emoji;
    if (node.type == 'RICH_TEXT_NODE_TYPE_EMOJI' &&
        text != null &&
        emoji?.url != null) {
      emotes.putIfAbsent(text, () => emoji!);
    }
  }
  if (emotes.isEmpty) return;
  final spans = <InlineSpan>[];
  for (final entry in emotes.entries) {
    if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n\n'));
    final emoji = entry.value;
    final size = emoji.size * 25.0;
    spans
      ..add(
        WidgetSpan(
          child: NetworkImgLayer(
            src: emoji.url!,
            type: .emote,
            width: size,
            height: size,
          ),
        ),
      )
      ..add(TextSpan(text: '\n${entry.key}\n${emoji.url}'));
  }
  showDialog(
    context: Get.context!,
    builder: (context) => Dialog(
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 16),
        child: SingleChildScrollView(
          child: SelectionText.rich(
            TextSpan(children: spans),
            style: const TextStyle(fontSize: 15, height: 1.7),
          ),
        ),
      ),
    ),
  );
}

void _showTextDialog(String text) {
  showDialog(
    context: Get.context!,
    builder: (context) => Dialog(
      constraints: const BoxConstraints.tightFor(width: 380),
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 16),
        child: SelectionText(
          text,
          style: const TextStyle(fontSize: 15, height: 1.7),
        ),
      ),
    ),
  );
}
