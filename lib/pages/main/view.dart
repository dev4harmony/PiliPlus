import 'dart:io';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/flutter/tabs.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/main.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:os_type/os_type.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart' as kernel32;
import 'package:window_manager/window_manager.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends PopScopeState<MainApp>
    with
        RouteAware,
        RouteAwareMixin,
        WidgetsBindingObserver,
        WindowListener,
        TrayListener {
  final _mainController = Get.put(MainController());
  late final _setting = GStorage.setting;
  late EdgeInsets _padding;
  late ThemeData theme;
  Brightness? _brightness;
  Worker? _nativeTabsWorker;
  Worker? _nativeTopBarWorker;

  @override
  bool get initCanPop => false;

  @override
  void initState() {
    super.initState();
    addObserverMobile(this);
    // 监听 useNativeTabs 异步赋值（_initHdsBar 完成时触发）。
    // 首帧是按 false 构建的，此时 Flutter 底栏已经建出来了，而 _bottomNav 中
    // 的提前返回分支不读任何 Rx（不能用 Obx 包裹，否则抛 ObxError），所以必须
    // 在这里主动重建把它移除，否则会与原生 HDS 底栏重叠显示。
    _nativeTabsWorker = ever(_mainController.useNativeTabs, (useNativeTabs) {
      if (!mounted || !useNativeTabs) return;
      setState(() {});
      // 补发首帧时因 useNativeTabs 未就绪而跳过的原生底栏状态同步：
      // 横屏（侧栏布局）或已有子页面覆盖主页时，原生底栏不应显示
      MyApp.shellBarsObserver.onOrientationChanged(
        _mainController.useBottomNav,
      );
      _syncPrimaryColor();
    });
    // 仅启用沉浸光感顶栏（未启用底栏）时，也要补发主题色：
    // 顶栏的分类高亮、图标颜色均读取 tabSelectedColor。
    _nativeTopBarWorker = ever(_mainController.useNativeTopBar, (useNativeTopBar) {
      if (!mounted || !useNativeTopBar) return;
      // 同样补发首帧时因 useNativeTopBar 未就绪而跳过的顶栏显隐同步：
      // 横屏（侧栏布局）或已有子页面覆盖主页时，原生顶栏不应显示
      MyApp.shellBarsObserver.onOrientationChanged(
        _mainController.useBottomNav,
      );
      _syncPrimaryColor();
    });
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      windowManager
        ..addListener(this)
        ..setPreventClose(true);
      if (_mainController.showTrayIcon) {
        trayManager.addListener(this);
        _handleTray();
      }
    } else {
      // FlutterSmartDialog throws
      PiliScheme.init();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding = MediaQuery.viewPaddingOf(context);
    theme = Theme.of(context);
    final brightness = theme.brightness;
    NetworkImgLayer.reduce =
        NetworkImgLayer.reduceLuxColor != null && brightness.isDark;
    if (PlatformUtils.isDesktop) {
      if (_brightness != brightness) {
        _brightness = brightness;
        windowManager.setBrightness(brightness);
      }
    }
    if (!_mainController.useSideBar) {
      _mainController.useBottomNav = MediaQuery.sizeOf(context).isPortrait;
    }
    // 横竖屏切换时同步原生 HDS 沉浸底栏/顶栏显隐
    // 由 ShellBarsObserver 统一管理，避免与路由观察者冲突。
    // 顶栏与底栏是两个独立开关，只启用其一时也要通知，否则横屏下
    // ArkTS 顶栏不会隐藏。
    if (_mainController.useNativeTabs.value ||
        _mainController.useNativeTopBar.value) {
      MyApp.shellBarsObserver.onOrientationChanged(
        _mainController.useBottomNav,
      );
    }
    // 总是同步主题色到 ArkTS（底栏/顶栏共用 tabSelectedColor），
    // 不依赖 useNativeTabs：仅启用顶栏时也需加载主题色。
    _syncPrimaryColor();
  }

  @override
  void didPopNext() {
    addObserverMobile(this);
    _mainController
      ..checkUnreadDynamic()
      ..checkDefaultSearch(true)
      ..checkUnread(_mainController.useBottomNav);
    super.didPopNext();
  }

  @override
  void didPushNext() {
    removeObserverMobile(this);
    super.didPushNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _mainController
        ..checkUnreadDynamic()
        ..checkDefaultSearch(true)
        ..checkUnread(_mainController.useBottomNav);
    }
  }

  /// 将当前主题主色同步到 ArkTS（底栏选中色/顶栏高亮色共用）
  void _syncPrimaryColor() {
    final primary = theme.colorScheme.primary;
    HarmonyChannel.setTabSelectedColor(
      '#${primary.value.toRadixString(16).padLeft(8, '0').substring(2)}',
    );
  }

  @override
  void dispose() {
    _nativeTabsWorker?.dispose();
    _nativeTopBarWorker?.dispose();
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    removeObserverMobile(this);
    PiliScheme.listener?.cancel();
    GStorage.close();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyR &&
        HardwareKeyboard.instance.isMetaPressed &&
        _mainController.refreshRecommendations();
  }

  @override
  void onWindowMaximize() {
    _setting.put(SettingBoxKey.isWindowMaximized, true);
  }

  @override
  void onWindowUnmaximize() {
    _setting.put(SettingBoxKey.isWindowMaximized, false);
  }

  @override
  Future<void> onWindowMoved() async {
    if (PlPlayerController.instance?.isDesktopPip ?? false) {
      return;
    }
    final Offset offset = await windowManager.getPosition();
    _setting.put(SettingBoxKey.windowPosition, [offset.dx, offset.dy]);
  }

  @override
  Future<void> onWindowResized() async {
    if (PlPlayerController.instance?.isDesktopPip ?? false) {
      return;
    }
    final Rect bounds = await windowManager.getBounds();
    _setting.putAll({
      SettingBoxKey.windowSize: [bounds.width, bounds.height],
      SettingBoxKey.windowPosition: [bounds.left, bounds.top],
    });
  }

  @override
  void onWindowClose() {
    if (_mainController.showTrayIcon && _mainController.minimizeOnExit) {
      windowManager.hide();
      _onHideWindow();
    } else {
      _onClose();
    }
  }

  Future<void> _onClose() async {
    await GStorage.compact();
    await GStorage.close();
    await trayManager.destroy();
    if (Platform.isWindows) {
      // flutter_inappwebview
      // 6.2.0-beta.2+ https://github.com/pichillilorenzo/flutter_inappwebview/issues/2482
      // 6.1.5 https://github.com/pichillilorenzo/flutter_inappwebview/issues/2512#issuecomment-3031039587
      final hProcess = kernel32.GetCurrentProcess();
      kernel32.TerminateProcess(hProcess, 0);
    } else {
      exit(0);
    }
  }

  @override
  void onWindowMinimize() {
    _onHideWindow();
  }

  @override
  void onWindowRestore() {
    _onShowWindow();
  }

  void _onHideWindow() {
    if (_mainController.pauseOnMinimize) {
      if (PlPlayerController.instance case final player?) {
        if (_mainController.isPlaying = player.playerStatus.isPlaying) {
          player.pause();
        }
      } else {
        _mainController.isPlaying = false;
      }
    }
  }

  void _onShowWindow() {
    if (_mainController.pauseOnMinimize && _mainController.isPlaying) {
      PlPlayerController.instance?.play();
    }
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    if (await windowManager.isVisible()) {
      _onHideWindow();
      windowManager.hide();
    } else {
      _onShowWindow();
      windowManager.show();
    }
  }

  @override
  Future<void> onTrayIconRightMouseDown() async {
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
      case 'exit':
        _onClose();
    }
  }

  Future<void> _handleTray() async {
    if (Platform.isWindows) {
      await trayManager.setIcon(Assets.logoIco);
    } else {
      await trayManager.setIcon(Assets.logoLarge);
    }
    if (!Platform.isLinux) {
      await trayManager.setToolTip(Constants.appName);
    }

    Menu trayMenu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出 ${Constants.appName}'),
      ],
    );
    await trayManager.setContextMenu(trayMenu);
  }

  @pragma('vm:prefer-inline')
  static void _onBack() {
    if (OS.isHarmony) SystemNavigator.pop();
    if (Platform.isAndroid) {
      PiliAndroidHelper.back();
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (_mainController.directExitOnBack) {
      _onBack();
    } else {
      if (_mainController.selectedIndex.value != 0) {
        _mainController
          ..setIndex(0)
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
      } else {
        _onBack();
      }
    }
  }

  Widget? get _bottomNav {
    Widget? bottomNav;
    if (_mainController.navigationBars.length > 1) {
      // 开启鸿蒙沉浸光感后无需 Flutter 底栏（由原生 HDS 渲染）。
      // 这里是非响应式读取，异步就绪后的重建由 initState 中的
      // _nativeTabsWorker 触发；该提前返回分支不读 Rx，不能改成
      // Obx 包裹（会抛 ObxError）
      if (_mainController.useNativeTabs.value) {
        return null;
      }
      if (_mainController.floatingNavBar) {
        // 悬浮底栏必须拿到「松」的宽度约束才能保持自身 destinations.length * 86 的
        // 宽度。上游从 `e89241109 opt ui` 起把主页换成了自绘的 MainLayout，那里给
        // bottomNav 的是 constraints.loosen() 再手动水平居中；鸿蒙没跟进这个骨架
        // 重构（状态栏取色依赖 Scaffold 里那个零高 AppBar，换掉代价太大），而
        // Scaffold.bottomNavigationBar 下发的是 fullWidthConstraints —— 宽度是紧
        // 约束（material/scaffold.dart:1035 `looseConstraints.tighten(width:)`），
        // FloatingNavigationBar 内部的 SizedBox 会被 enforce 成整屏宽。
        //
        // 这里用 Align 吃掉紧宽度：Align 自己撑满宽度，子节点拿到松约束、按自身
        // 宽度水平居中；heightFactor: 1 让高度仍按子节点算，Scaffold 据此计算的
        // body 内边距与改动前一致。两侧空白区域 Align 不参与命中测试，点击会穿透
        // 到下面的内容，与上游 MainLayout 的表现一致。
        bottomNav = Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: Obx(
            () => FloatingNavigationBar(
              onDestinationSelected: _mainController.setIndex,
              selectedIndex: _mainController.selectedIndex.value,
              destinations: _mainController.navigationBars
                  .map(
                    (e) => FloatingNavigationDestination(
                      label: e.label,
                      icon: _buildIcon(type: e),
                      selectedIcon: _buildIcon(type: e, selected: true),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      } else if (_mainController.enableMYBar) {
        bottomNav = Obx(
          () => NavigationBar(
            maintainBottomViewPadding: true,
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => NavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        bottomNav = Obx(
          () => BottomNavigationBar(
            currentIndex: _mainController.selectedIndex.value,
            onTap: _mainController.setIndex,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: .fixed,
            items: _mainController.navigationBars
                .map(
                  (e) => BottomNavigationBarItem(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    activeIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      }

      if (_mainController.hideBottomBar) {
        if (_mainController.barOffset case final barOffset?) {
          return Obx(
            () => FractionalTranslation(
              translation: Offset(
                0.0,
                barOffset.value / Style.topBarHeight,
              ),
              child: bottomNav,
            ),
          );
        }
        if (_mainController.showBottomBar case final showBottomBar?) {
          return Obx(
            () => AnimatedSlide(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              offset: Offset(0, showBottomBar.value ? 0 : 1),
              child: bottomNav,
            ),
          );
        }
      }
    }
    return bottomNav;
  }

  Widget _sideBar(ThemeData theme) {
    final Widget sideBar = _mainController.navigationBars.length > 1
        ? context.isTablet && _mainController.optTabletNav
              ? Column(
                  children: [
                    SizedBox(
                      height: MediaQuery.paddingOf(context).top + 25,
                    ),
                    userAndSearchVertical(theme),
                    const Spacer(flex: 2),
                    Expanded(
                      flex: 5,
                      child: SizedBox(
                        width: 130,
                        child: Obx(
                          () => NavigationDrawer(
                            backgroundColor: Colors.transparent,
                            tilePadding: const .symmetric(
                              vertical: 5,
                              horizontal: 12,
                            ),
                            indicatorShape: const RoundedRectangleBorder(
                              borderRadius: .all(.circular(16)),
                            ),
                            onDestinationSelected: _mainController.setIndex,
                            selectedIndex: _mainController.selectedIndex.value,
                            children: _mainController.navigationBars
                                .map(
                                  (e) => NavigationDrawerDestination(
                                    label: Text(e.label),
                                    icon: _buildIcon(type: e),
                                    selectedIcon: _buildIcon(
                                      type: e,
                                      selected: true,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Obx(
                  () => NavigationRail(
                    groupAlignment: 0.5,
                    selectedIndex: _mainController.selectedIndex.value,
                    onDestinationSelected: _mainController.setIndex,
                    labelType: .selected,
                    leading: userAndSearchVertical(theme),
                    destinations: _mainController.navigationBars
                        .map(
                          (e) => NavigationRailDestination(
                            label: Text(e.label),
                            icon: _buildIcon(type: e),
                            selectedIcon: _buildIcon(type: e, selected: true),
                          ),
                        )
                        .toList(),
                  ),
                )
        : Container(
            width: 80,
            padding: const .only(top: 10),
            child: userAndSearchVertical(theme),
          );
    // NavigationDrawer / NavigationRail 内部各自带一层 SafeArea，会吃掉
    // padding.left；而它们上方的头像/消息/搜索列不在 SafeArea 内。鸿蒙横屏
    // 挖孔避让并入 padding 后（见 HarmonyChannel.cutoutInsets），左侧有挖孔的
    // 机型上这两组控件就一个右移一个不动，视觉错位。改为在侧栏整体上做一次
    // 左侧避让，并移除子树里的 padding.left 避免重复避让。
    final left = MediaQuery.paddingOf(context).left;
    if (left <= 0) {
      return sideBar;
    }
    return Padding(
      padding: EdgeInsets.only(left: left),
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        child: sideBar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_mainController.mainTabBarView) {
      child = CustomTabBarView(
        scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical,
        physics: const NeverScrollableScrollPhysics(),
        controller: _mainController.controller,
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    } else {
      child = PageView(
        physics: const NeverScrollableScrollPhysics(),
        controller: _mainController.controller,
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    }

    Widget? bottomNav;
    if (_mainController.useBottomNav) {
      bottomNav = _bottomNav;
      child = Row(children: [Expanded(child: child)]);
    } else {
      child = Row(
        children: [
          _sideBar(theme),
          VerticalDivider(
            width: 1,
            endIndent: _padding.bottom,
            color: theme.colorScheme.outline.withValues(alpha: 0.06),
          ),
          Expanded(child: child),
        ],
      );
    }

    // Flutter 在鸿蒙平台上的状态栏颜色依赖于AppBar设置的backgroundColor进行取色，因此需要写这个神人代码保证取色能力正常
    final backgroundColor =
        MediaQuery.platformBrightnessOf(context) == Brightness.light
        ? const Color.fromARGB(0, 255, 255, 255)
        : const Color.fromARGB(0, 0, 0, 0);

    child = Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true, // 扩展安全区
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: backgroundColor,
      ),
      body: Padding(
        padding: EdgeInsets.only(
          left: _mainController.useBottomNav ? _padding.left : 0.0,
          right: _padding.right,
        ),
        child: child,
      ),
      bottomNavigationBar: bottomNav,
    );

    if (PlatformUtils.isMobile) {
      child = AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: theme.brightness.reverse,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    final icon = selected ? type.selectIcon : type.icon;
    return type == .dynamics
        ? Obx(
            () {
              final dynCount = _mainController.dynCount.value;
              return Badge(
                isLabelVisible: dynCount > 0,
                label: _mainController.dynamicBadgeMode == .number
                    ? Text(dynCount.toString())
                    : null,
                padding: const .symmetric(horizontal: 6),
                child: icon,
              );
            },
          )
        : icon;
  }

  Widget userAndSearchVertical(ThemeData theme) {
    return Column(
      children: [
        userAvatar(theme: theme, mainController: _mainController),
        const SizedBox(height: 8),
        msgBadge(_mainController),
        IconButton(
          tooltip: '搜索',
          icon: const Icon(
            Icons.search_outlined,
            semanticLabel: '搜索',
          ),
          onPressed: () => Get.toNamed('/search'),
        ),
      ],
    );
  }
}
