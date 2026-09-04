import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/top_inset_padding.dart';
import 'package:material_ui/material_ui.dart';

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

  /// 竖屏全屏时顶部控件的避让高度（页面传入的状态栏/挖孔高度），
  /// 见 [portraitFullscreenTopInset]
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
    var top = portraitFullscreenTopInset(
      isFullScreen: isFullScreen,
      isPortrait:
          MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width,
      removeSafeArea: removeSafeArea,
      topInset: topInset,
    );
    // 鸿蒙自由多窗全屏：顶部沉浸后系统三键仍悬浮在窗口右上角，顶栏得避开，
    // 否则右上角图标点不到。见 [harmonyDecorTopInset]。
    if (isTop && isFullScreen && !removeSafeArea) {
      final decorTop = harmonyDecorTopInset(context);
      if (decorTop != null && decorTop > (top ?? 0)) {
        top = decorTop;
      }
    }
    Widget result = child;
    if (!removeSafeArea) {
      result = ViewSafeArea(
        left: isFullScreen,
        right: isFullScreen,
        child: result,
      );
      // 与弹幕共用同一套顶部避让（TopInsetPadding），
      // 仅顶部栏需要，底部栏不避让
      result = TopInsetPadding(inset: isTop ? top : null, child: result);
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
