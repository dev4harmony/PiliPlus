part of 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';

void showReplyCopyDialog(
  BuildContext context,
  String message,
  Map<String, Emote> emotes,
) {
  var showEmote = false;
  showDialog(
    context: context,
    builder: (context) => Dialog(
      constraints: const BoxConstraints.tightFor(width: 380),
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 16),
        child: StatefulBuilder(
            builder: (context, setState) => SelectionText.rich(
            showEmote
                ? TextSpan(
                    children: emotes.entries.mapIndexed((index, entry) {
                      final emote = entry.value;
                      final size = emote.size.toInt() * 25.0;
                      return TextSpan(
                        children: [
                          if (index != 0) const TextSpan(text: '\n\n'),
                          WidgetSpan(
                            child: NetworkImgLayer(
                              src: emote.url,
                              type: .emote,
                              width: size,
                              height: size,
                            ),
                          ),
                          TextSpan(text: '\n${entry.key}\n${emote.url}'),
                        ],
                      );
                    }).toList(),
                  )
                : TextSpan(text: message),
            style: const TextStyle(fontSize: 15, height: 1.7),
            contextMenuBuilder: (_, state) {
            String? selectedText() {
              final value = state.textEditingValue;
              final selection = value.selection;
              if (!selection.isValid || selection.isCollapsed) return null;
              return selection.textInside(value.text);
            }

            final items = ensureSelectionMenuButtons(
              state.contextMenuButtonItems,
              selectedTextOf: selectedText,
              hideToolbar: state.hideToolbar,
            );
            if (emotes.isNotEmpty) {
              items.insertOrAdd(
                3,
                ContextMenuButtonItem(
                  label: showEmote ? '文本' : '表情',
                  onPressed: () {
                    state.hideToolbar();
                    setState(() => showEmote = !showEmote);
                  },
                ),
              );
            }
            final selected = selectedText();
            if (selected != null && selected.isNotEmpty) {
              items.add(
                ContextMenuButtonItem(
                  onPressed: () {
                    state.hideToolbar();
                    final escapedText = RegExp.escape(selected);
                    final filterText = ReplyGrpc.enableFilter
                        ? '|$escapedText'
                        : escapedText;
                    showConfirmDialog(
                      context: context,
                      title: const Text('是否确认评论过滤的变更：'),
                      content: Text.rich(
                        TextSpan(
                          text: ReplyGrpc.replyRegExp.pattern,
                          children: [
                            TextSpan(
                              text: filterText,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: .bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      onConfirm: () {
                        final filter = ReplyGrpc.replyRegExp.pattern + filterText;
                        ReplyGrpc.replyRegExp = RegExp(
                          filter,
                          caseSensitive: true,
                        );
                        ReplyGrpc.enableFilter = true;
                        GStorage.setting.put(
                          SettingBoxKey.banWordForReply,
                          filter,
                        );
                        SmartDialog.showToast('已保存');
                      },
                    );
                  },
                  label: '加入过滤',
                ),
              );
            }
            return AdaptiveTextSelectionToolbar.buttonItems(
              buttonItems: items,
              anchors: state.contextMenuAnchors,
            );
            },
          ),
        ),
      ),
    ),
  );
}
