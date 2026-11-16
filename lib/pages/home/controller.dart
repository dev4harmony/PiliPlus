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
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:os_type/os_type.dart';

class HomeController extends GetxController
    with GetSingleTickerProviderStateMixin, ScrollOrRefreshMixin {
  late List<HomeTabType> tabs;
  late TabController tabController;

  /// ArkTS 发起的分类切换，跳过回发 ArkTS 以避免循环
  bool _fromArkTS = false;

  RxBool? showTopBar;
  late final bool hideTopBar;

  /// 原生顶栏是否已收起（由滚动信号同步），用于 Flutter 首页顶部安全边距
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

    setTabConfig();
    if (OS.isHarmony) {
      _initHarmonyTopBar();
    }
  }

  void setTabConfig() {
    final tabs = GStorage.setting.get(SettingBoxKey.tabBarSort) as List?;
    if (tabs != null) {
      this.tabs = tabs.map((i) => HomeTabType.values[i]).toList();
    } else {
      this.tabs = HomeTabType.values;
    }

    tabController = TabController(
      initialIndex: max(0, this.tabs.indexOf(HomeTabType.rcmd)),
      length: this.tabs.length,
      vsync: this,
    );
  }

  /// 鸿蒙顶栏：订阅原生回调 + 状态同步
  void _initHarmonyTopBar() {
    // ArkTS 分类切换 → Flutter 切换 TabController
    HarmonyChannel.onHomeTabChange = (int index) {
      // 同 index 时不置位：animateTo 对同 index 直接返回且不触发
      // listener，若置位会导致 _fromArkTS 悬挂，吞掉后续手动切换。
      if (index >= 0 && index < tabs.length && index != tabController.index) {
        // 置位后由 _onTabIndexChanged 在动画结束（indexIsChanging == false）
        // 时复位，而不是 animateTo 调用后立即复位：animateTo 是异步动画，
        // listener 在动画期间多次触发，若立即复位会把动画中途的中间
        // index 误发回 ArkTS 造成循环。
        _fromArkTS = true;
        tabController.animateTo(index);
      }
    };
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
    // Flutter 切分类 → 同步高亮到 ArkTS Tabs
    tabController.addListener(_onTabIndexChanged);
    // 下滑收起 → 同步到 ArkTS（隐藏大搜索栏，显示小搜索按钮）
    // 同时更新本地 topBarCollapsed，供 Flutter 首页顶部安全边距跟随
    if (hideTopBar) {
      final mainCtr = Get.find<MainController>();
      if (mainCtr.barOffset case final barOffset?) {
        // 滚动偏移超过顶栏一半高度视为收起
        ever(barOffset, (offset) {
          _syncCollapsed(
            mainCtr,
            collapsed: offset > Style.topBarHeight / 2,
          );
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

  /// 同步顶栏收起状态：本地 RxBool（Flutter 顶部安全边距跟随）
  /// + 通知 ArkTS 原生顶栏收起（隐藏大搜索栏）。仅在原生顶栏启用时生效。
  void _syncCollapsed(MainController mainCtr, {required bool collapsed}) {
    if (!mainCtr.useNativeTopBar.value) return;
    topBarCollapsed.value = collapsed;
    HarmonyChannel.setTopBarCollapsed(collapsed);
  }

  void _onTabIndexChanged() {
    // 动画播放期间跳过：index 中途值不参与回发。
    // 动画结束时：ArkTS 发起的切换在此复位标志并跳过回发（高亮已在
    // ArkTS 侧）；Flutter 手动切换则在此把最终 index 发回 ArkTS。
    if (tabController.indexIsChanging) return;
    if (_fromArkTS) {
      _fromArkTS = false;
      return;
    }
    if (Get.find<MainController>().useNativeTopBar.value) {
      HarmonyChannel.setHomeTabIndex(tabController.index);
    }
  }

  @override
  Future<void> onRefresh() {
    return controller.onRefresh().catchError((e) {
      if (kDebugMode) debugPrint(e.toString());
    });
  }

  @override
  Future<void> showRefresh() => controller.showRefresh();

  @override
  void dispose() {
    if (OS.isHarmony) {
      HarmonyChannel.onHomeTabChange = null;
      HarmonyChannel.onTopSearchTap = null;
      HarmonyChannel.onTopMsgTap = null;
      HarmonyChannel.onTopMineTap = null;
      tabController.removeListener(_onTabIndexChanged);
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
