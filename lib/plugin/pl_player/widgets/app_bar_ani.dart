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
    this.fullBleedContent = false,
  });

  final Widget child;
  final AnimationController controller;
  final bool isTop;
  final bool isFullScreen;
  final bool removeSafeArea;
  final bool fullBleedContent;

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
    // 鸿蒙：窗口化全屏沿用原生装饰避让；视频详情页铺满画面后，普通全屏
    // 也只让顶部控件下移，画面本身不再预留顶部边距。
    // allowRevealedTitleBar：自由窗口全屏下鼠标唤出标题带时，顶栏跟着下移，
    // 避免被标题带盖住（弹幕不走这条，见 harmonyDecorTopInset 注释）。
    final top = harmonyDecorTopInset(
      context,
      isFullScreen: isFullScreen,
      removeSafeArea: removeSafeArea,
      fullBleedContent: fullBleedContent,
      allowRevealedTitleBar: true,
    );
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
