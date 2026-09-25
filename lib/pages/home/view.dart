import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/custom_height_widget.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/home/widgets/home_top_bar.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends CommonPageState<HomePage>
    with AutomaticKeepAliveClientMixin {
  final _homeController = Get.putOrFind(HomeController.new);
  final _mainController = Get.find<MainController>();
  Worker? _nativeTopBarWorker;

  /// 是否需要对滚动做「顶栏位移补偿」（见 CommonPage.onNotificationType2）。
  ///
  /// 原生顶栏生效时必须关掉：那条补偿是用来抵消 Flutter 自绘顶栏（customAppBar）
  /// 随 barOffset 收缩的位移的，原生顶栏下根本没有这层自绘顶栏，补偿出来的位移无
  /// 处抵消，累计下来会把列表一直往顶栏方向推，表现为上滑时列表直接回顶。
  /// 收起信号本身仍然走共用管线：barOffset 照常累计，只是不做这条补偿
  /// （见 HomeController._syncCollapsed）。
  @override
  bool get needsCorrection =>
      _homeController.hideTopBar && !_mainController.nativeTopBarActive.value;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 鸿蒙顶栏异步就绪 / 横竖屏切换后重建，显示或隐藏 Flutter 顶栏、分类栏。
    // 状态栏安全区移除由窗口沉浸实现（EntryAbility 设置
    // setWindowLayoutFullScreen(true) + 状态栏背景透明），保留系统状态栏
    // 图标；此处仅负责按顶栏是否生效重建 UI 布局，不操作系统状态栏。
    _nativeTopBarWorker = ever(_mainController.nativeTopBarActive, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nativeTopBarWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    // 鸿蒙原生顶栏生效时：ArkTS 只画搜索行/私信/头像，分类栏与渐变模糊在这里
    // （见 HomeTopBar）。分类栏是**悬浮**在列表之上的，视频从状态栏区域开始
    // 渲染、从分类栏下方透出；列表首屏不被遮住靠 NativeTopSpacer 的顶部留白。
    final useNativeTopBar = _mainController.nativeTopBarActive.value;
    if (useNativeTopBar) {
      return Stack(
        children: [
          Positioned.fill(child: onBuild(_buildTabBarView())),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: HomeTopBar(),
          ),
        ],
      );
    }
    // 横屏/侧栏布局下 ArkTS 顶栏是隐藏的，此处恢复 Flutter 自绘的顶栏与分类栏
    Widget tabBar;
    if (_homeController.tabs.length > 1) {
      tabBar = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          height: 42,
          width: double.infinity,
          child: TabBar(
            controller: _homeController.tabController,
            tabs: _homeController.tabs.map((e) => Tab(text: e.label)).toList(),
            isScrollable: true,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            splashBorderRadius: Style.mdRadius,
            tabAlignment: TabAlignment.center,
            onTap: (_) {
              feedBack();
              if (!_homeController.tabController.indexIsChanging) {
                _homeController.animateToTop();
              }
            },
          ),
        ),
      );
      if (_homeController.hideTopBar &&
          _mainController.barHideType == .instant) {
        tabBar = Material(
          color: theme.colorScheme.surface,
          child: tabBar,
        );
      }
    } else {
      tabBar = const SizedBox(height: 6);
    }
    return Column(
      children: [
        if (!_mainController.useSideBar &&
            MediaQuery.sizeOf(context).isPortrait)
          customAppBar(theme)
        else
          SizedBox(height: MediaQuery.of(context).padding.top),
        tabBar,
        Expanded(child: onBuild(_buildTabBarView())),
      ],
    );
  }

  Widget _buildTabBarView() {
    return tabBarView(
      controller: _homeController.tabController,
      children: _homeController.tabs.map((e) => e.page).toList(),
    );
  }

  Widget customAppBar(ThemeData theme) {
    const padding = EdgeInsets.fromLTRB(14, 6, 14, 0);
    final child = Row(
      children: [
        searchBar(theme),
        const SizedBox(width: 4),
        msgBadge(_mainController),
        const SizedBox(width: 8),
        userAvatar(theme: theme, mainController: _mainController),
      ],
    );
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    if (_homeController.hideTopBar) {
      if (_mainController.barOffset case final barOffset?) {
        return Obx(
          () {
            final offset = barOffset.value;
            return SizedBox(
              height: statusBarHeight + Style.topBarHeight - offset,
              child: Stack(
                // 移除顶部安全区之后，在同步收起顶栏模式下需要保证顶栏有正确的遮挡关系。
                children: [
                  Positioned(
                    // 必须同时指定 left/right：只指定 top 时 Stack 会给子组件
                    // 无界宽度约束（Positioned 未指定宽度时 child 收到
                    // unconstrained），CustomHeightWidget 会把 constraints.maxWidth
                    // （Infinity）直接作为自身宽度，导致 size 为
                    // Size(Infinity, ...)，Stack 计算其偏移时产生 NaN 坐标，
                    // 内容不显示、滑动无法命中。
                    top: statusBarHeight,
                    left: 0,
                    right: 0,
                    child: CustomHeightWidget(
                      offset: Offset(0, -offset),
                      height: Style.topBarHeight - offset,
                      child: Padding(
                        padding: padding,
                        child: child,
                      ),
                    ),
                  ),
                  Container(
                    height: statusBarHeight,
                    color: theme.colorScheme.surface,
                  ),
                ],
              ),
            );
          },
        );
      }
      if (_homeController.showTopBar case final showTopBar?) {
        return Obx(() {
          final showSearchBar = showTopBar.value;
          return Container(
            padding: EdgeInsets.only(
              top: statusBarHeight
            ),
            child: AnimatedOpacity(
              opacity: showSearchBar ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: AnimatedContainer(
                curve: Curves.easeInOutCubicEmphasized,
                duration: const Duration(milliseconds: 500),
                height: showSearchBar ? Style.topBarHeight : 0,
                padding: padding,
                child: child,
              ),
            ),
          );
        });
      }
    }
    final paddingWithSafeArea = EdgeInsets.fromLTRB(
      14,
      6 + statusBarHeight,
      14,
      0,
    );
    return Container(
      height: Style.topBarHeight + statusBarHeight,
      padding: paddingWithSafeArea,
      child: child,
    );
  }

  Widget searchBar(ThemeData theme) {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    return Expanded(
      child: SizedBox(
        height: 44,
        child: Material(
          borderRadius: borderRadius,
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.05),
          child: InkWell(
            borderRadius: borderRadius,
            splashColor: theme.colorScheme.primaryContainer.withValues(
              alpha: 0.3,
            ),
            onTap: () => Get.toNamed(
              '/search',
              parameters: _homeController.enableSearchWord
                  ? {'hintText': _homeController.defaultSearch.value}
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                  semanticLabel: '搜索',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Obx(
                    () => Text(
                      _homeController.defaultSearch.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget userAvatar({
  required ThemeData theme,
  required MainController mainController,
}) {
  return Semantics(
    label: "我的",
    child: Obx(
      () {
        if (mainController.accountService.isLogin.value) {
          return Stack(
            clipBehavior: .none,
            children: [
              NetworkImgLayer(
                type: .avatar,
                width: 34,
                height: 34,
                src: mainController.accountService.face.value,
              ),
              Positioned.fill(
                child: Material(
                  type: .transparency,
                  child: InkWell(
                    onTap: mainController.toMinePage,
                    splashColor: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    customBorder: const CircleBorder(),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Obx(
                  () => MineController.anonymity.value
                      ? IgnorePointer(
                          child: Container(
                            padding: const .all(2),
                            decoration: BoxDecoration(
                              shape: .circle,
                              color: theme.colorScheme.secondaryContainer,
                            ),
                            child: Icon(
                              size: 14,
                              MdiIcons.incognito,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        }
        return SizedBox(
          width: 38,
          height: 38,
          child: IconButton(
            tooltip: '点击登录',
            style: IconButton.styleFrom(
              padding: .zero,
              backgroundColor: theme.colorScheme.onInverseSurface,
            ),
            onPressed: mainController.toMinePage,
            icon: Icon(
              Icons.person_rounded,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
        );
      },
    ),
  );
}

Widget msgBadge(MainController mainController) {
  return Obx(
    () {
      if (mainController.accountService.isLogin.value) {
        final count = mainController.msgUnReadCount.value;
        final isNumBadge = mainController.msgBadgeMode == .number;
        return IconButton(
          tooltip: '消息',
          onPressed: () {
            mainController
              ..clearUnreadMsg()
              ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
            Get.toNamed('/whisper');
          },
          icon: Badge(
            isLabelVisible:
                mainController.msgBadgeMode != .hidden && count != null,
            alignment: isNumBadge
                ? const Alignment(0.0, -0.85)
                : const Alignment(1.0, -0.85),
            label: isNumBadge && count != null ? Text(count) : null,
            child: const Icon(Icons.notifications_none),
          ),
        );
      }
      return const SizedBox.shrink();
    },
  );
}