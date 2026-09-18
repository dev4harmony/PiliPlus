import 'dart:async' show Timer;

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/selection_text.dart';
import 'package:PiliPlus/models_new/live/live_superchat/item.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/pages/member/widget/medal_widget.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/color_utils.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

/// 超级聊天文本选中菜单。
///
/// 鸿蒙分支不打 SDK 补丁（上游把实现放在
/// `lib/utils/extension/selectable_region_ext.dart`，依赖补丁放出
/// [SelectableRegionState] 的私有成员），这里沿用本分支
/// [selectableTextContextMenuBuilder] 的做法，从 [EditableTextState]
/// 读取选中文本。
Widget scMenuBuilder(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final buttonItems = editableTextState.contextMenuButtonItems;
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

class SuperChatCard extends StatefulWidget {
  const SuperChatCard({
    super.key,
    required this.item,
    this.onRemove,
    this.persistentSC = false,
    this.onReport,
  });

  final SuperChatItem item;
  final VoidCallback? onRemove;
  final bool persistentSC;
  final VoidCallback? onReport;

  @override
  State<SuperChatCard> createState() => _SuperChatCardState();
}

class _SuperChatCardState extends State<SuperChatCard> {
  Timer? _timer;
  RxInt? _remains;

  @override
  void initState() {
    super.initState();
    if (!widget.persistentSC) {
      if (widget.item.expired) {
        _remove();
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final offset = widget.item.endTime - now;
      if (offset > 0) {
        _remains = offset.obs;
        _startTimer();
      } else {
        _remove();
      }
    }
  }

  void _remove() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 1), _onRemove);
    });
  }

  void _onRemove() {
    widget
      ..item.expired = true
      ..onRemove?.call();
  }

  void _callback(_) {
    final remains = _remains!.value;
    if (remains > 0) {
      _remains!.value = remains - 1;
    } else {
      _cancelTimer();
      _onRemove();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), _callback);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  void _showMenu(Offset offset, SuperChatItem item) {
    final flag = _timer != null;
    if (flag) {
      _cancelTimer();
    }
    showMenu(
      context: context,
      position: PageUtils.menuPosition(offset),
      items: [
        PopupMenuItem(
          height: 38,
          onTap: () => Get.toNamed('/member?mid=${item.uid}'),
          child: Text(
            '访问: ${item.userInfo.uname}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        PopupMenuItem(
          height: 38,
          onTap: () => Utils.copyText(Utils.jsonEncoder.convert(item.toJson())),
          child: const Text(
            '复制 SC 信息',
            style: TextStyle(fontSize: 13),
          ),
        ),
        PopupMenuItem(
          height: 38,
          onTap: () => _ScToImage.save(item),
          child: const Text(
            '保存为图片',
            style: TextStyle(fontSize: 13),
          ),
        ),
        PopupMenuItem(
          height: 38,
          onTap: widget.onReport,
          child: const Text(
            '举报',
            style: TextStyle(fontSize: 13),
          ),
        ),
      ],
    ).whenComplete(() {
      if (flag && mounted) {
        _startTimer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _build(item: widget.item, remains: _remains, showMenu: _showMenu);
  }
}

Widget _build({
  required SuperChatItem item,
  Function(Offset, SuperChatItem)? showMenu,
  RxInt? remains,
}) {
  final bottomColor = ColourUtils.parseColor(item.backgroundBottomColor);
  final border = BorderSide(color: bottomColor);
  void showMenu_(TapUpDetails e) => showMenu?.call(e.globalPosition, item);

  Widget name = Text(
    item.userInfo.uname,
    maxLines: 1,
    overflow: .ellipsis,
    style: TextStyle(
      color: ColourUtils.parseColor(item.userInfo.nameColor),
    ),
  );
  if (item.medalInfo case final medal?) {
    try {
      name = Row(
        spacing: 5,
        children: [
          MedalWidget.fromMedalInfo(
            medal: medal,
            padding: MedalWidget.mediumPadding,
          ),
          Flexible(child: name),
        ],
      );
    } catch (e, s) {
      if (kDebugMode) {
        Utils.reportError(e, s);
      }
    }
  }

  Widget price = Text("￥${item.price}", style: TextStyle(color: bottomColor));
  Widget? remains_;
  if (remains != null) {
    remains_ = Obx(
      () => Text(
        remains.toString(),
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
    );
  } else {
    price = Row(
      crossAxisAlignment: .end,
      mainAxisAlignment: .spaceBetween,
      children: [
        price,
        Text(
          DateFormatUtils.format(
            item.startSime,
            format: DateFormatUtils.longFormatDs,
          ),
          style: TextStyle(color: bottomColor, fontSize: 13.5),
        ),
      ],
    );
  }

  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GestureDetector(
        onTapUp: showMenu_,
        onSecondaryTapUp: PlatformUtils.isDesktop ? showMenu_ : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const .vertical(top: .circular(8)),
            color: ColourUtils.parseColor(item.backgroundColor),
            border: Border(top: border, left: border, right: border),
            image: item.backgroundImage == null
                ? null
                : DecorationImage(
                    alignment: .topRight,
                    image: CachedNetworkImageProvider(
                      ImageUtils.safeThumbnailUrl(item.backgroundImage),
                    ),
                  ),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            spacing: 12,
            children: [
              _avatar(item.userInfo.face, item.userInfo.faceFrame),
              Expanded(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [name, price],
                ),
              ),
              ?remains_,
            ],
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          borderRadius: const .vertical(bottom: .circular(8)),
          color: bottomColor,
        ),
        padding: const .all(8),
        child: TextSelectionTheme(
          data: TextSelectionThemeData(
            selectionColor: Color.lerp(bottomColor, Colors.black, .26),
            selectionHandleColor: Color.lerp(bottomColor, Colors.white, .26),
          ),
          child: SelectionText(
            item.message,
            contextMenuBuilder: scMenuBuilder,
            style: TextStyle(
              color: ColourUtils.parseColor(item.messageFontColor),
              // decoration: widget.persistentSC && item.deleted
              //     ? .lineThrough
              //     : null,
              // decorationThickness: 1.5,
              // decorationStyle: .double,
              // decorationColor: Colors.white,
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _avatar(String face, String? faceFrame) {
  const size = 45.0;
  final avatar = NetworkImgLayer(
    src: face,
    width: size,
    height: size,
    type: .avatar,
  );
  if (faceFrame != null && faceFrame.isNotEmpty) {
    const ratio = 1.16;
    const pendantSize = size * ratio;
    const offset = ((1 - ratio) * size) / 2;
    return Stack(
      clipBehavior: .none,
      alignment: .center,
      children: [
        avatar,
        Positioned(
          top: offset,
          child: NetworkImgLayer(
            type: .emote,
            width: pendantSize,
            height: pendantSize,
            src: faceFrame,
            getPlaceHolder: () => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
  return avatar;
}

class _ScToImage extends StatelessWidget {
  const _ScToImage({required this.item});

  final SuperChatItem item;

  static Future<void> save(SuperChatItem item) async {
    if (PlatformUtils.isMobile &&
        !await ImageUtils.checkPermissionDependOnSdkInt()) {
      return;
    }
    Get.key.currentState!.push(
      PublishRoute(
        transitionDuration: .zero,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => _ScToImage(item: item),
        transitionBuilder: (_, _, _, child) => child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = GlobalKey();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final byteData = await image.toByteData(format: .png);
        image.dispose();
        final pngBytes = byteData!.buffer.asUint8List();
        final picName =
            'Bili_SuperChat_${item.roomid}_${item.userInfo.uname}_￥${item.price}_${DateFormatUtils.format(item.startSime, format: DateFormat('yyyyMMddHHmmss'))}';
        final result = await ImageUtils.saveByteImg(
          bytes: pngBytes,
          fileName: picName,
          showLoading: false,
        );
        if (result?.errorMessage != null) {
          SmartDialog.showToast(result!.errorMessage!);
        }
      } catch (e) {
        if (kDebugMode) rethrow;
        SmartDialog.showToast(e.toString());
      } finally {
        Get.back();
      }
    });
    return Align(
      alignment: const Alignment(2, 2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: RepaintBoundary(
          key: key,
          child: _build(item: item),
        ),
      ),
    );
  }
}
