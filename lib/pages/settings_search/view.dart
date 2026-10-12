import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/pages/search/controller.dart' show DebounceStreamState;
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/pages/setting/models/experimental_settings.dart';
import 'package:PiliPlus/pages/setting/models/extra_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart';
import 'package:PiliPlus/pages/setting/models/privacy_settings.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/style_settings.dart';
import 'package:PiliPlus/pages/setting/models/video_settings.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState
    extends DebounceStreamState<SettingsSearchPage, String> {
  /// 与主搜索共用 historyWord 盒子，另起 key 互不干扰
  static const String _historyKey = 'settingsSearchWord';
  static const int _maxHistory = 20;

  final _textEditingController = TextEditingController();
  final RxList<SettingsModel> _list = <SettingsModel>[].obs;
  final RxString _keyword = ''.obs;
  late final RxList<String> _history = RxList<String>.from(
    GStorage.historyWord.get(_historyKey) ?? const <String>[],
  );
  late final _settings = [
    ...extraSettings,
    ...privacySettings,
    ...recommendSettings,
    ...videoSettings,
    ...playSettings,
    ...styleSettings,
    ...experimentalSettings,
  ];

  @override
  void onValueChanged(String value) {
    _keyword.value = value;
    if (value.isEmpty) {
      _list.clear();
    } else {
      value = value.toLowerCase();
      _list.value = _settings
          .where(
            (item) =>
                item.effectiveTitle.toLowerCase().contains(value) ||
                item.effectiveSubtitle?.toLowerCase().contains(value) == true,
          )
          .toList();
    }
  }

  /// 设置搜索是输入即过滤、没有「提交搜索」这一步，故只在离开页面、清空输入
  /// 和按下回车时记录当次的最终关键词——逐次输入都记会把中间前缀（「弹」
  /// 「弹幕」…）全存进去。
  void _saveHistory([String? word]) {
    final text = (word ?? _textEditingController.text).trim();
    if (text.isEmpty) return;
    _history
      ..remove(text)
      ..insert(0, text);
    if (_history.length > _maxHistory) {
      _history.removeRange(_maxHistory, _history.length);
    }
    GStorage.historyWord.put(_historyKey, _history);
  }

  void _onTapHistory(String word) {
    _textEditingController
      ..text = word
      ..selection = TextSelection.collapsed(offset: word.length);
    // 直接过滤，不等防抖
    onValueChanged(word);
  }

  void _onLongPressHistory(String word) {
    _history.remove(word);
    GStorage.historyWord.put(_historyKey, _history);
  }

  void _onClearHistory() {
    showConfirmDialog(
      context: context,
      title: const Text('确定清空搜索历史？'),
      onConfirm: () {
        _history.clear();
        GStorage.historyWord.delete(_historyKey);
      },
    );
  }

  @override
  void dispose() {
    _saveHistory();
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () {
              if (_textEditingController.text.isNotEmpty) {
                _saveHistory();
                _textEditingController.clear();
                _list.clear();
                _keyword.value = '';
              } else {
                Get.back();
              }
            },
            icon: const Icon(Icons.clear),
          ),
          const SizedBox(width: 10),
        ],
        title: TextField(
          autofocus: true,
          controller: _textEditingController,
          textAlignVertical: TextAlignVertical.center,
          onChanged: ctr!.add,
          onSubmitted: _saveHistory,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '搜索',
            visualDensity: VisualDensity.standard,
            border: InputBorder.none,
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          ViewSliverSafeArea(
            sliver: Obx(() {
              if (_list.isNotEmpty) {
                return SliverMasonryGrid(
                  gridDelegate: gridDelegate,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _list[index].widget,
                    childCount: _list.length,
                  ),
                );
              }
              // 关键词为空时展示历史；有关键词却没结果才是「无结果」
              return _keyword.value.isEmpty
                  ? _buildHistory(theme)
                  : const HttpError();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory(ThemeData theme) {
    if (_history.isEmpty) {
      return const SliverToBoxAdapter();
    }
    final secondary = theme.colorScheme.secondary;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 25),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Row(
              children: [
                Text(
                  '搜索历史',
                  strutStyle: const StrutStyle(leading: 0, height: 1),
                  style: theme.textTheme.titleMedium!.copyWith(
                    height: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                  onPressed: _onClearHistory,
                  icon: Icon(
                    Icons.clear_all_outlined,
                    size: 18,
                    color: secondary,
                  ),
                  label: Text(
                    '清空',
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _history
                    .map(
                      (item) => SearchText(
                        text: item,
                        fontSize: 14,
                        height: 1,
                        onTap: _onTapHistory,
                        onLongPress: _onLongPressHistory,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  late final gridDelegate = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
    maxCrossAxisExtent: Grid.smallCardWidth * 2,
  );
}
