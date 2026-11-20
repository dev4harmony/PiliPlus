import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Scaffold;
import 'package:flutter/material.dart' as sdk show Scaffold;
import 'package:material_ui/src/ripple/splash_policy.dart';

/// SDK Scaffold 的包装：在整棵子树外注入带鸿蒙水波纹的 Theme。
///
/// SDK 的 Scaffold 在 build 内部自建 Material，业务侧看不见那一层；不包这层的话，
/// 直接放在 body 里的 SDK 控件（按钮/列表项/Chip）仍会从根 Theme 取到 InkRipple。
///
/// 用组合而不是继承：状态、geometry、bottom sheet 逻辑全部留在 SDK 实现里，
/// Material.of / Scaffold.of 行为不变。
///
/// key 必须落到内层 SDK Scaffold 上：GlobalKey<ScaffoldState> +
/// _scaffoldKey.currentState!.openDrawer() 是常见写法，包在外层会取到 null。
class Scaffold extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const Scaffold({
    Key? key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.floatingActionButtonAnimator,
    this.persistentFooterButtons,
    this.persistentFooterAlignment = AlignmentDirectional.centerEnd,
    this.persistentFooterDecoration,
    this.drawer,
    this.onDrawerChanged,
    this.endDrawer,
    this.onEndDrawerChanged,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.primary = true,
    this.drawerDragStartBehavior = DragStartBehavior.start,
    this.extendBody = false,
    this.drawerBarrierDismissible = true,
    this.extendBodyBehindAppBar = false,
    this.drawerScrimColor,
    this.bottomSheetScrimBuilder = _defaultBottomSheetScrimBuilder,
    this.drawerEdgeDragWidth,
    this.drawerEnableOpenDragGesture = true,
    this.endDrawerEnableOpenDragGesture = true,
    this.restorationId,
  }) : _key = key;

  final Key? _key;
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final FloatingActionButtonAnimator? floatingActionButtonAnimator;
  final List<Widget>? persistentFooterButtons;
  final AlignmentDirectional persistentFooterAlignment;
  final BoxDecoration? persistentFooterDecoration;
  final Widget? drawer;
  final DrawerCallback? onDrawerChanged;
  final Widget? endDrawer;
  final DrawerCallback? onEndDrawerChanged;
  final Color? drawerScrimColor;
  final Widget? Function(BuildContext, Animation<double>) bottomSheetScrimBuilder;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final bool? resizeToAvoidBottomInset;
  final bool primary;
  final DragStartBehavior drawerDragStartBehavior;
  final double? drawerEdgeDragWidth;
  final bool drawerEnableOpenDragGesture;
  final bool endDrawerEnableOpenDragGesture;
  final bool extendBody;
  final bool drawerBarrierDismissible;
  final bool extendBodyBehindAppBar;
  final String? restorationId;

  static ScaffoldState of(BuildContext context) => sdk.Scaffold.of(context);

  static ScaffoldState? maybeOf(BuildContext context) => sdk.Scaffold.maybeOf(context);

  static ValueListenable<ScaffoldGeometry> geometryOf(BuildContext context) =>
      sdk.Scaffold.geometryOf(context);

  static bool hasDrawer(BuildContext context, {bool registerForUpdates = true}) =>
      sdk.Scaffold.hasDrawer(context, registerForUpdates: registerForUpdates);

  // 与 SDK 默认遮罩同值（scaffold.dart 的 _kBottomSheetDominatesPercentage 等）。
  static const double _kDominates = 0.3;
  static const double _kMinScrim = 0.1;
  static const double _kMaxScrim = 0.6;

  static Widget _defaultBottomSheetScrimBuilder(
    BuildContext context,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double remaining = _kDominates * (1.0 - animation.value);
        final double visibility = remaining * _kDominates * 10;
        final double opacity = math.max(_kMinScrim, _kMaxScrim - visibility);
        return ModalBarrier(
          dismissible: false,
          color: Colors.black.withValues(alpha: opacity),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: withRippleSplash(Theme.of(context)),
      child: sdk.Scaffold(
        key: _key,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        floatingActionButtonAnimator: floatingActionButtonAnimator,
        persistentFooterButtons: persistentFooterButtons,
        persistentFooterAlignment: persistentFooterAlignment,
        persistentFooterDecoration: persistentFooterDecoration,
        drawer: drawer,
        onDrawerChanged: onDrawerChanged,
        endDrawer: endDrawer,
        onEndDrawerChanged: onEndDrawerChanged,
        bottomNavigationBar: bottomNavigationBar,
        bottomSheet: bottomSheet,
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        primary: primary,
        drawerDragStartBehavior: drawerDragStartBehavior,
        extendBody: extendBody,
        drawerBarrierDismissible: drawerBarrierDismissible,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        drawerScrimColor: drawerScrimColor,
        bottomSheetScrimBuilder: bottomSheetScrimBuilder,
        drawerEdgeDragWidth: drawerEdgeDragWidth,
        drawerEnableOpenDragGesture: drawerEnableOpenDragGesture,
        endDrawerEnableOpenDragGesture: endDrawerEnableOpenDragGesture,
        restorationId: restorationId,
      ),
    );
  }
}