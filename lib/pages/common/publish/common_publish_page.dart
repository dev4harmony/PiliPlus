import 'dart:async';
import 'dart:io';
import 'dart:math' show max;

import 'package:PiliPlus/models/common/publish_panel_type.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:chat_bottom_container/chat_bottom_container.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

abstract class CommonPublishPage<T> extends StatefulWidget {
  const CommonPublishPage({
    super.key,
    this.initialValue,
    this.imageLengthLimit,
    this.onSave,
    this.autofocus = true,
  });

  final String? initialValue;
  final int? imageLengthLimit;
  final ValueChanged<T>? onSave;
  final bool autofocus;
}

abstract class CommonPublishPageState<T extends CommonPublishPage>
    extends State<T>
    with WidgetsBindingObserver {
  late bool _paused = false;
  late final FocusNode focusNode;
  late final controller = ChatBottomPanelContainerController<PanelType>(
    uiScale: Pref.uiScale,
  );
  TextEditingController get editController;

  final Rx<PanelType> panelType = PanelType.none.obs;
  late final RxBool readOnly = false.obs;
  late final RxBool enablePublish = false.obs;

  bool isPublishing = false;

  bool hasPub = false;
  void initPubState();

  bool get handleKeyboard => Platform.isAndroid && widget.autofocus;

  late ThemeData theme;

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode()..addListener(_onFocusChanged);

    if (handleKeyboard) {
      WidgetsBinding.instance.addObserver(this);
    }

    initPubState();

    if (widget.autofocus) {
      _requestFocus(duration: const Duration(milliseconds: 300));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    initTheme();
  }

  void initTheme() {
    theme = Theme.of(context);
  }

  void _onFocusChanged() {
    if (focusNode.hasFocus && readOnly.value) {
      updatePanelType(.keyboard);
    }
  }

  @override
  void dispose() {
    focusNode.removeListener(_onFocusChanged);
    if (!hasPub) {
      onSave();
    }
    focusNode.dispose();
    editController.dispose();
    if (handleKeyboard) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  void _safeRequestFocus() {
    if (mounted) {
      focusNode.requestFocus();
    }
  }

  void _requestFocus({Duration duration = const Duration(microseconds: 200)}) {
    Timer(duration, _safeRequestFocus);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == .resumed) {
      if (_paused) {
        _paused = false;
        final panelType = this.panelType.value;
        if (panelType == .keyboard || panelType == .none) {
          // 鸿蒙适配：恢复被 keepChatPanel 冻结的面板高度，避免回前台后面板错位
          controller.restoreChatPanel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (focusNode.hasFocus) {
              focusNode.unfocus();
              _requestFocus();
            } else {
              _requestFocus();
            }
          });
        }
      }
    } else if (state == .paused) {
      _paused = true;
      // 鸿蒙适配：退到后台时冻结面板，避免键盘收起导致面板高度被重置
      controller.keepChatPanel();
      if (focusNode.hasFocus) {
        focusNode.unfocus();
      }
    }
  }

  void updatePanelType(PanelType type) {
    final isSwitchToKeyboard = PanelType.keyboard == type;
    bool isUpdated = false;
    switch (type) {
      case PanelType.keyboard:
        updateInputView(isReadOnly: false);
        break;
      case PanelType.emoji || PanelType.more:
        isUpdated = updateInputView(isReadOnly: true);
        break;
      default:
        break;
    }

    void updatePanelTypeFunc() {
      controller.updatePanelType(
        isSwitchToKeyboard
            ? ChatBottomPanelType.keyboard
            : ChatBottomPanelType.other,
        data: type,
        forceHandleFocus: isSwitchToKeyboard
            ? ChatBottomHandleFocus.requestFocus
            : ChatBottomHandleFocus.unfocus,
      );
    }

    if (isUpdated) {
      // Waiting for the input view to update.
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        updatePanelTypeFunc();
      });
    } else {
      updatePanelTypeFunc();
    }
  }

  Future<void> hidePanel([_]) async {
    if (focusNode.hasFocus) {
      // TODO(ohos): 上游用 Future.pause（Dart 3.13+），鸿蒙 Dart SDK(3.12) 暂不支持，先用 Future.delayed 等价替换
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      focusNode.unfocus();
    }
    updateInputView(isReadOnly: false);
    if (ChatBottomPanelType.none == controller.currentPanelType) return;
    controller.updatePanelType(ChatBottomPanelType.none);
  }

  bool updateInputView({
    required bool isReadOnly,
  }) {
    if (readOnly.value != isReadOnly) {
      readOnly.value = isReadOnly;
      return true;
    }
    return false;
  }

  Widget buildEmojiPickerPanel() {
    double height = ContextExtensions(context).isTablet ? 300 : 170;
    final keyboardHeight = controller.keyboardHeight;
    if (keyboardHeight != 0) {
      height = max(height, keyboardHeight);
    }
    return SizedBox(
      height: height,
      child: customPanel,
    );
  }

  Widget buildMorePanel() => throw UnimplementedError();

  Widget buildPanelContainer([Color? panelBgColor]) {
    return ChatBottomPanelContainer<PanelType>(
      controller: controller,
      inputFocusNode: focusNode,
      otherPanelWidget: (type) {
        if (type == null) return const SizedBox.shrink();
        switch (type) {
          case PanelType.emoji:
            return buildEmojiPickerPanel();
          case PanelType.more:
            return buildMorePanel();
          default:
            return const SizedBox.shrink();
        }
      },
      onPanelTypeChange: (panelType, data) {
        switch (panelType) {
          case ChatBottomPanelType.none:
            this.panelType.value = PanelType.none;
            break;
          case ChatBottomPanelType.keyboard:
            this.panelType.value = PanelType.keyboard;
            break;
          case ChatBottomPanelType.other:
            if (data == null) return;
            this.panelType.value = data;
            break;
        }
      },
      panelBgColor: panelBgColor ?? theme.colorScheme.surface,
    );
  }

  void onSubmitted(String value) {
    if (enablePublish.value) {
      onPublishThrottle();
    }
  }

  void onPublishThrottle() {
    if (isPublishing) return;
    isPublishing = true;
    onPublish().whenComplete(() => isPublishing = false);
  }

  Future<void> onPublish();

  Future<void> onCustomPublish({List? pictures});

  Widget? get customPanel => null;

  void onChanged(String value) {
    enablePublish.value = value.trim().isNotEmpty;
  }

  void onSave();
}
