import 'dart:async';
import 'dart:math';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/home_tab_type.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/wbi_sign.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:os_type/os_type.dart';

class HomeController extends GetxController
    with GetSingleTickerProviderStateMixin, ScrollOrRefreshMixin {
  final List<HomeTabType> tabs = () {
    final tabs = GStorage.setting.get(SettingBoxKey.tabBarSort) as List?;
    if (tabs != null) {
      return tabs.map((i) => HomeTabType.values[i]).toList();
    } else {
      return HomeTabType.values;
    }
  }();

  late final TabController tabController = TabController(
    initialIndex: max(0, tabs.indexOf(HomeTabType.rcmd)),
    length: tabs.length,
    vsync: this,
  );

  RxBool? showTopBar;
  late final bool hideTopBar;

  /// 原生顶栏（ArkTS 的搜索行 + Flutter 的分类栏）是否已因滑动隐藏。
  /// 由 CommonPage 那条共用的滚动管线驱动（sync 模式看 barOffset，instant 模式
  /// 看 showTopBar），见 _syncCollapsed。
  final RxBool topBarCollapsed = false.obs;

  bool enableSearchWord = Pref.enableSearchWord;
  late final RxString defaultSearch = ''.obs;
  late int lateCheckSearchAt = 0;

  ScrollOrRefreshMixin get controller => tabs[tabController.index].ctr();

  @override
  ScrollController get scrollController => controller.scrollController;

  AccountService accountService = Get.find<AccountService>();

  @override
  void onInit() {
    super.onInit();

    hideTopBar = !Pref.useSideBar && Pref.hideTopBar;
    if (hideTopBar) {
      final mainCtr = Get.find<MainController>();
      switch (mainCtr.barHideType) {
        case .instant:
          showTopBar = RxBool(true);
        case .sync:
          mainCtr.barOffset ??= RxDouble(0.0);
      }
    }

    if (enableSearchWord) {
      lateCheckSearchAt = DateTime.now().millisecondsSinceEpoch;
      querySearchDefault();
    }

    if (OS.isHarmony) {
      _initHarmonyTopBar();
    }
  }

  /// 鸿蒙顶栏：订阅原生回调 + 状态同步
  void _initHarmonyTopBar() {
    // ArkTS 搜索框点击 → 打开搜索页
    HarmonyChannel.onTopSearchTap = () => Get.toNamed(
      '/search',
      parameters: enableSearchWord ? {'hintText': defaultSearch.value} : null,
    );
    // ArkTS 私信点击 → 清空未读红点（同步 ArkTS）并跳转私信页
    HarmonyChannel.onTopMsgTap = () {
      Get.find<MainController>()
        ..clearUnreadMsg()
        ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
      // 立即同步清空 ArkTS 原生顶栏红点
      HarmonyChannel.setHomeUnreadCount('');
      Get.toNamed('/whisper');
    };
    // ArkTS 头像点击 → 跳个人页
    HarmonyChannel.onTopMineTap = Get.find<MainController>().toMinePage;

    // 搜索默认词异步就绪后同步到原生 Search 组件
    ever(defaultSearch, (text) {
      if (enableSearchWord &&
          Get.find<MainController>().useNativeTopBar.value) {
        HarmonyChannel.setHomeSearchText(text);
      }
    });
    // 下滑收起 → 同步到 ArkTS（整行上移淡出）
    // 与底栏隐藏、非原生顶栏共用同一条滚动管线：sync 模式看累计的 barOffset，
    // instant 模式看 CommonPage 按滚动方向置位的 showTopBar，不另造一套判定。
    if (hideTopBar) {
      final mainCtr = Get.find<MainController>();
      if (mainCtr.barOffset case final barOffset?) {
        // 滚动偏移超过顶栏一半高度视为收起
        ever(barOffset, (offset) {
          _syncCollapsed(mainCtr, collapsed: offset > Style.topBarHeight / 2);
        });
      }
      if (showTopBar case final showTopBar?) {
        // showTopBar 显隐切换（instant 模式）直接驱动收起状态
        ever(showTopBar, (show) {
          _syncCollapsed(mainCtr, collapsed: !show);
        });
      }
    }
  }

  /// 同步顶栏收起状态：本地 RxBool（Flutter 侧悬浮层与列表留白跟随）
  /// + 通知 ArkTS 原生顶栏收起 / 放下。仅在原生顶栏启用时生效。
  ///
  /// barOffset 是逐帧变化的，状态没变就不必再发通道消息。
  void _syncCollapsed(MainController mainCtr, {required bool collapsed}) {
    if (!mainCtr.useNativeTopBar.value) return;
    if (topBarCollapsed.value == collapsed) return;
    topBarCollapsed.value = collapsed;
    HarmonyChannel.setTopBarCollapsed(collapsed);
  }

  @override
  Future<void> onRefresh() {
    return controller.onRefresh().catchError((e) {
      if (kDebugMode) debugPrint(e.toString());
    });
  }

  @override
  void dispose() {
    if (OS.isHarmony) {
      HarmonyChannel.onTopSearchTap = null;
      HarmonyChannel.onTopMsgTap = null;
      HarmonyChannel.onTopMineTap = null;
    }
    tabController.dispose();
    super.dispose();
  }

  Future<void> querySearchDefault() async {
    try {
      final res = await Request().get(
        Api.searchDefault,
        queryParameters: await WbiSign.makSign({'web_location': 333.1365}),
      );
      if (res.data['code'] == 0) {
        defaultSearch.value = res.data['data']?['name'] ?? '';
        // defaultSearch.value = res.data['data']?['show_name'] ?? '';
      }
    } catch (_) {}
  }
}
