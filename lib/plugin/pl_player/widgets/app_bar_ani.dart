import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:flutter/material.dart';

class AppBarAni extends StatelessWidget {
  const AppBarAni({
    super.key,
    required this.child,
    required this.controller,
    required this.isTop,
    required this.isFullScreen,
    required this.removeSafeArea,
    this.topInset,
  });

  final Widget child;
  final AnimationController controller;
  final bool isTop;
  final bool isFullScreen;
  final bool removeSafeArea;

  /// 竖屏全屏时顶部控件的固定避让高度（进全屏前捕获的状态栏/挖孔高度）
  final double? topInset;

  static final _topPos = Tween<Offset>(
    begin: const Offset(0.0, -1.0),
    end: Offset.zero,
  );

  static const _topDecoration = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0xBF000000),
    ],
    tileMode: TileMode.mirror,
  );

  static final _bottomPos = Tween<Offset>(
    begin: const Offset(0, 1.2),
    end: Offset.zero,
  );

  static const _bottomDecoration = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0xBF000000),
    ],
    tileMode: TileMode.mirror,
  );

  @override
  Widget build(BuildContext context) {
    final top = portraitFullscreenTopInset(
      isFullScreen: isFullScreen,
      isPortrait:
          MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width,
      removeSafeArea: removeSafeArea,
      topInset: topInset,
    );
    Widget result = child;
    if (!removeSafeArea) {
      result = ViewSafeArea(
        left: isFullScreen,
        right: isFullScreen,
        child: result,
      );
      // 竖屏全屏时用进全屏前捕获的固定高度避让挖孔/状态栏，
      // 不依赖全屏下已归零的 MediaQuery padding
      if (isTop && top != null) {
        result = Padding(
          padding: EdgeInsets.only(top: top),
          child: result,
        );
      }
    }
    return SlideTransition(
      position: controller.drive(isTop ? _topPos : _bottomPos),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isTop ? _topDecoration : _bottomDecoration,
        ),
        child: result,
      ),
    );
  }
}
