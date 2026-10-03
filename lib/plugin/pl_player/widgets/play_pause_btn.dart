import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PlayOrPauseButton extends StatefulWidget {
  final PlPlayerController plPlayerController;

  const PlayOrPauseButton({
    super.key,
    required this.plPlayerController,
  });

  @override
  PlayOrPauseButtonState createState() => PlayOrPauseButtonState();
}

class PlayOrPauseButtonState extends State<PlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      value: widget.plPlayerController.playerStatus.isPlaying ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    // 不要缓存 Player 实例：HDR / SDR 之间切换画质会整体重建播放器，缓存下来
    // 的 Player 连同它的 stream 一起失效，按钮就永久停在切换前的状态。
    // playerStatus 由 _startListeners 重新绑定到新播放器，因此这里改为订阅
    // controller 自己的状态回调（用回调而非 Obx：forward/reverse 是副作用，
    // 不应该写在 build 闭包里）。
    widget.plPlayerController.addStatusLister(_onStatusChanged);
  }

  void _onStatusChanged(PlayerStatus status) {
    if (status.isPlaying) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.plPlayerController.removeStatusLister(_onStatusChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 34,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.plPlayerController.onDoubleTapCenter,
        child: Center(
          child: Obx(
            () => AnimatedIcon(
              semanticLabel: widget.plPlayerController.playerStatus.isPlaying
                  ? '暂停'
                  : '播放',
              progress: controller,
              icon: AnimatedIcons.play_pause,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
