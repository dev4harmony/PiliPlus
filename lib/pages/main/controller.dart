import 'dart:async';
import 'dart:math' as math;

import 'package:PiliPlus/grpc/dyn.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliPlus/models/common/home_tab_type.dart';
import 'package:PiliPlus/models/common/msg/msg_unread_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:os_type/os_type.dart';

class MainController extends GetxController
    with GetSingleTickerProviderStateMixin, AccountMixin {
  @override
  final AccountService accountService = Get.find<AccountService>();

  List<NavigationBarType> navigationBars = <NavigationBarType>[];

  RxDouble? barOffset;
  RxBool? showBottomBar;
  late final bool hideBottomBar;
  late final barHideType = Pref.barHideType;
  bool _useBottomNav = false;
  bool get useBottomNav => _useBottomNav;
  set useBottomNav(bool value) {
    if (_useBottomNav == value) return;
    _useBottomNav = value;
    _syncNativeTopBarActive();
  }

  late dynamic controller;
  final RxInt selectedIndex = 0.obs;

  /// ArkTS 发起的页签切换，跳过回传 ArkTS 以避免循环
  bool _fromArkTS = false;

  final RxInt dynCount = 0.obs;
  late DynamicBadgeMode dynamicBadgeMode;
  late bool checkDynamic = Pref.checkDynamic;
  late int dynamicPeriod = Pref.dynamicPeriod * 60 * 1000;
  late int _lastCheckDynamicAt = 0;
  late bool hasDyn = false;
  late final dynamicController = Get.putOrFind(DynamicsController.new);

  late bool hasHome = false;
  late final homeController = Get.putOrFind(HomeController.new);

  late final disableLikeMsg = Pref.disableLikeMsg;
  late DynamicBadgeMode msgBadgeMode = Pref.msgBadgeMode;
  late Set<MsgUnReadType> msgUnReadTypes = Pref.msgUnReadTypeV2;
  late final RxnString msgUnReadCount = RxnString(null);
  late int lastCheckUnreadAt = 0;

  final enableMYBar = Pref.enableMYBar;

  /// 鸿蒙原生 HDS 底栏（API >= 23 时由原生渲染液态玻璃页签栏）
  /// 修改设置后需重启应用生效
  final RxBool useNativeTabs = false.obs;

  /// 鸿蒙原生顶部沉浸栏（与 useNativeTabs 同开关，API >= 23 时启用）
  final RxBool useNativeTopBar = false.obs;

  /// 原生顶栏在当前布局下是否真正生效：仅竖屏底栏布局由 ArkTS 渲染顶栏。
  /// 横屏 / 侧栏布局（useBottomNav == false）下 ArkTS 顶栏已被
  /// ShellBarsObserver 隐藏，此时 Flutter 必须恢复自绘分类栏并取消顶部留白，
  /// 否则分类栏消失、顶部还留下一大片空白。
  final RxBool nativeTopBarActive = false.obs;

  /// useNativeTopBar / useBottomNav 任一变化后重算顶栏是否生效
  void _syncNativeTopBarActive() {
    nativeTopBarActive.value = useNativeTopBar.value && _useBottomNav;
  }

  final floatingNavBar = Pref.floatingNavBar;
  final useSideBar = Pref.useSideBar;
  final mainTabBarView = Pref.mainTabBarView;
  late final optTabletNav = Pref.optTabletNav;

  late bool directExitOnBack = Pref.directExitOnBack;
  late bool showTrayIcon = Pref.showTrayIcon;
  late bool minimizeOnExit = Pref.minimizeOnExit;
  late bool pauseOnMinimize = Pref.pauseOnMinimize;
  late bool isPlaying = false;

  static const _period = 5 * 60 * 1000;
  late int _lastSelectTime = 0;

  @override
  void onInit() {
    super.onInit();
    if (Pref.autoUpdate) {
      Update.checkUpdate();
    }

    setNavBarConfig();

    controller = mainTabBarView
        ? TabController(
            vsync: this,
            initialIndex: selectedIndex.value,
            length: navigationBars.length,
          )
        : PageController(initialPage: selectedIndex.value);

    hideBottomBar =
        !useSideBar && navigationBars.length > 1 && Pref.hideBottomBar;
    if (hideBottomBar) {
      switch (barHideType) {
        case .instant:
          showBottomBar = RxBool(true);
        case .sync:
          barOffset ??= RxDouble(0.0);
      }
    }

    dynamicBadgeMode = Pref.dynamicBadgeMode;

    hasDyn = navigationBars.contains(NavigationBarType.dynamics);
    if (dynamicBadgeMode != DynamicBadgeMode.hidden) {
      if (hasDyn && navigationBars[selectedIndex.value] != .dynamics) {
        if (checkDynamic) {
          _lastCheckDynamicAt = DateTime.now().millisecondsSinceEpoch;
        }
        getUnreadDynamic();
      }
    }

    hasHome = navigationBars.contains(NavigationBarType.home);
    if (msgBadgeMode != DynamicBadgeMode.hidden) {
      if (hasHome) {
        lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
        queryUnreadMsg();
      }
    }

    // 鸿蒙：注册原生 HDS 底栏回调，冷启动后主动拉取配置
    if (OS.isHarmony) {
      HarmonyChannel.onShellTabSwitch = (int index) {
        if (index >= 0 && index < navigationBars.length) {
          _fromArkTS = true;
          setIndex(index);
        }
      };
      // 切换到底部非首页页签（动态/我的）时隐藏顶栏，仅首页显示。
      // 状态栏安全区由窗口沉浸全局处理（EntryAbility setWindowLayoutFullScreen
      // + 状态栏透明，保留状态栏图标），不在此操作系统状态栏，
      // 避免与播放页/直播页的 SystemChrome 显隐状态互相污染。
      // 同时同步「当前是否为首页」到 ArkTS，供 dialog 显隐时的多级分流。
      ever(selectedIndex, (index) {
        if (useNativeTopBar.value) {
          final isHome = navigationBars[index] == NavigationBarType.home;
          HarmonyChannel.setTopBarTabHidden(!isHome);
          HarmonyChannel.setTopBarIsHome(isHome);
        }
      });
      _initHdsBar();
    }
  }

  /// 鸿蒙：查询 API 版本，结合用户偏好分别计算底栏/顶栏开关，通知 ArkTS
  Future<void> _initHdsBar() async {
    if (!OS.isHarmony) {
      useNativeTabs.value = false;
      useNativeTopBar.value = false;
      return;
    }
    final sdkApiVersion =
        (await DeviceInfoPlugin().ohosInfo).sdkApiVersion ?? 0;
    // 底栏/顶栏均自 API 23（鸿蒙 6.1）起可用：ArkTS 侧 API 26+ 走 Navigation
    // 标题栏 + ArkUI systemMaterial，API 23~25 走 HdsNavigation 标题栏材质
    final useHdsBar = Pref.enableHdsBar && sdkApiVersion > 22;
    final useHdsTopBar = Pref.enableHdsTopBar && sdkApiVersion > 22;
    useNativeTabs.value = useHdsBar;
    useNativeTopBar.value = useHdsTopBar;
    _syncNativeTopBarActive();
    HarmonyChannel.setShellBars(useNativeTabs: useHdsBar);
    HarmonyChannel.setShellTopBar(useNativeTopBar: useHdsTopBar);
    // 同步 Navbar 页签数量与顺序到原生 HDS 底栏（与设置内 Navbar 编辑一致）
    if (useHdsBar) {
      HarmonyChannel.setNavBarConfig(navigationBars);
      HarmonyChannel.changeTabIndex(Pref.defaultHomePage.index);
      // 初始动态角标（数量与模式）同步到原生 HDS 底栏
      if (hasDyn) {
        HarmonyChannel.setDynamicBadge(
          count: dynCount.value,
          mode: dynamicBadgeMode.index,
        );
      }
    }
    // 首页分类标签与顶栏设置同步到原生
    if (useHdsTopBar && hasHome) {
      // 补发初始「当前是否为首页」状态：ever(selectedIndex) 只在切换时才触发，
      // 冷启动不切页签时 ArkTS 端 topBarIsHome 保持 false，导致 dialog 隐藏
      // 顶栏的宽高比分流失效。
      HarmonyChannel.setTopBarIsHome(
        navigationBars[selectedIndex.value] == NavigationBarType.home,
      );
      HarmonyChannel.setHomeTopBarData(
        tabs: homeController.tabs.map((e) => e.label).toList(),
        hideTopBar: homeController.hideTopBar,
        activeIndex: homeController.tabController.index,
      );
      // 初始头像（登录态）
      HarmonyChannel.setHomeFaceUrl(
        accountService.isLogin.value ? '${accountService.face.value}@200w_200h_10q.webp' : '',
      );
      // 初始搜索默认词（若已在异步拉取中就绪）
      if (homeController.enableSearchWord &&
          homeController.defaultSearch.value.isNotEmpty) {
        HarmonyChannel.setHomeSearchText(homeController.defaultSearch.value);
      }
    }
  }

  Future<int> _msgUnread() async {
    if (msgUnReadTypes.contains(MsgUnReadType.pm)) {
      final res = await MsgHttp.msgUnread();
      if (res case Success(:final response)) {
        return response.followUnread +
            response.unfollowUnread +
            response.bizMsgFollowUnread +
            response.bizMsgUnfollowUnread +
            response.unfollowPushMsg +
            response.customUnread;
      }
    }
    return 0;
  }

  Future<int> _msgFeedUnread() async {
    int count = 0;
    final remainTypes = Set<MsgUnReadType>.from(msgUnReadTypes)
      ..remove(MsgUnReadType.pm);
    if (remainTypes.isNotEmpty) {
      final res = await MsgHttp.msgFeedUnread();
      if (res case Success(:final response)) {
        for (final item in remainTypes) {
          switch (item) {
            case MsgUnReadType.pm:
              break;
            case MsgUnReadType.reply:
              count += response.reply;
              break;
            case MsgUnReadType.at:
              count += response.at;
              break;
            case MsgUnReadType.like:
              if (!disableLikeMsg) count += response.like;
              break;
            case MsgUnReadType.sysMsg:
              count += response.sysMsg;
              break;
          }
        }
      }
    }
    return count;
  }

  void clearUnreadMsg() {
    msgUnReadCount.value = null;
  }

  Future<void> queryUnreadMsg([bool isChangeType = false]) async {
    if (!accountService.isLogin.value ||
        !hasHome ||
        msgUnReadTypes.isEmpty ||
        msgBadgeMode == DynamicBadgeMode.hidden) {
      clearUnreadMsg();
      return;
    }

    final res = await Future.wait([_msgUnread(), _msgFeedUnread()]);

    final count = res.sum;

    final countStr = count == 0
        ? null
        : count > 99
        ? '99+'
        : count.toString();
    if (msgUnReadCount.value == countStr) {
      if (isChangeType) {
        msgUnReadCount.refresh();
      }
    } else {
      msgUnReadCount.value = countStr;
    }
    // 同步私信未读数到 ArkTS 原生顶栏红点
    if (useNativeTopBar.value) {
      HarmonyChannel.setHomeUnreadCount(countStr ?? '');
    }
  }

  void getUnreadDynamic() {
    if (!accountService.isLogin.value || !hasDyn) {
      return;
    }
    DynGrpc.dynRed().then((res) {
      if (res != null) {
        setDynCount(res);
      }
    });
  }

  void setDynCount([int count = 0]) {
    if (!hasDyn) return;
    dynCount.value = count;
    // 同步动态角标到 ArkTS HdsTabs 底栏（与 Flutter 内角标保持一致）
    if (useNativeTabs.value) {
      HarmonyChannel.setDynamicBadge(
        count: count,
        mode: dynamicBadgeMode.index,
      );
    }
  }

  void checkUnreadDynamic() {
    if (!hasDyn ||
        !accountService.isLogin.value ||
        dynamicBadgeMode == DynamicBadgeMode.hidden ||
        !checkDynamic) {
      return;
    }
    int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCheckDynamicAt >= dynamicPeriod) {
      _lastCheckDynamicAt = now;
      getUnreadDynamic();
    }
  }

  void setNavBarConfig() {
    List<int>? navBarSort =
        (GStorage.setting.get(SettingBoxKey.navBarSort) as List?)?.fromCast();
    late final List<NavigationBarType> navigationBars;
    if (navBarSort == null || navBarSort.isEmpty) {
      navigationBars = NavigationBarType.values;
    } else {
      navigationBars = navBarSort
          .map(NavigationBarType.values.elementAt)
          .toList();
    }
    this.navigationBars = navigationBars;
    final defPage = Pref.defaultHomePage;
    selectedIndex.value = math.max(0, navigationBars.indexOf(defPage));
  }

  void checkDefaultSearch([bool shouldCheck = false]) {
    if (hasHome && homeController.enableSearchWord) {
      if (shouldCheck &&
          navigationBars[selectedIndex.value] != NavigationBarType.home) {
        return;
      }
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - homeController.lateCheckSearchAt >= _period) {
        homeController
          ..lateCheckSearchAt = now
          ..querySearchDefault();
      }
    }
  }

  void checkUnread([bool shouldCheck = false]) {
    if (accountService.isLogin.value &&
        hasHome &&
        msgBadgeMode != DynamicBadgeMode.hidden) {
      if (shouldCheck &&
          navigationBars[selectedIndex.value] != NavigationBarType.home) {
        return;
      }
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCheckUnreadAt >= _period) {
        lastCheckUnreadAt = now;
        queryUnreadMsg();
      }
    }
  }

  int? _mineIndex;
  void toMinePage() {
    _mineIndex ??= navigationBars.indexOf(NavigationBarType.mine);
    if (_mineIndex != -1) {
      setIndex(_mineIndex!);
    } else {
      Get.to(
        const Material(
          child: MinePage(showBackBtn: true),
        ),
      );
    }
  }

  void setIndex(int value) {
    feedBack();

    final currentNav = navigationBars[value];
    if (value != selectedIndex.value) {
      selectedIndex.value = value;
      if (mainTabBarView) {
        controller.animateTo(value);
      } else {
        controller.jumpToPage(value);
      }
      // Flutter 发起的切换同步到 ArkTS HdsTabs
      if (!_fromArkTS) {
        HarmonyChannel.changeTabIndex(value);
      }
      if (currentNav == NavigationBarType.home) {
        checkDefaultSearch();
        checkUnread();
      } else if (currentNav == NavigationBarType.dynamics) {
        setDynCount();
      }
    } else {
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSelectTime < 500) {
        EasyThrottle.throttle(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          () {
            if (currentNav == NavigationBarType.home) {
              homeController.onRefresh();
            } else if (currentNav == NavigationBarType.dynamics) {
              dynamicController.onRefresh();
            }
          },
        );
      } else {
        if (currentNav == NavigationBarType.home) {
          homeController.toTopOrRefresh();
        } else if (currentNav == NavigationBarType.dynamics) {
          dynamicController.toTopOrRefresh();
        }
      }
      _lastSelectTime = now;
    }
    _fromArkTS = false;
  }

  void setSearchBar() {
    if (hasHome) {
      homeController.showTopBar?.value = true;
    }
  }

  bool refreshRecommendations() {
    if (navigationBars[selectedIndex.value] == NavigationBarType.home &&
        homeController.tabs[homeController.tabController.index] ==
            HomeTabType.rcmd) {
      homeController.onRefresh();
      return true;
    }
    return false;
  }

  @override
  void onClose() {
    if (OS.isHarmony) {
      HarmonyChannel.onShellTabSwitch = null;
    }
    barOffset?.close();
    controller.dispose();
    super.onClose();
  }

  @override
  void onChangeAccount(bool isLogin) {
    if (isLogin) {
      queryUnreadMsg();
      getUnreadDynamic();
    } else {
      setDynCount();
    }
    // 同步头像到 ArkTS 原生顶栏
    if (useNativeTopBar.value) {
      HarmonyChannel.setHomeFaceUrl(
        isLogin ? accountService.face.value : '',
      );
    }
  }
}
