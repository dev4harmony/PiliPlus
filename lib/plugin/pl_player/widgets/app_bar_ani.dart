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
  });

  final Widget child;
  final AnimationController controller;
  final bool isTop;
  final bool isFullScreen;
  final bool removeSafeArea;

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
    // 鸿蒙：窗口化全屏时原生装饰（挖孔/自绘标题带）的安全区参与避让；
    // 其余场景返回 null，行为与上游一致。
    final top = harmonyDecorTopInset(
      context,
      isFullScreen: isFullScreen,
      removeSafeArea: removeSafeArea,
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
