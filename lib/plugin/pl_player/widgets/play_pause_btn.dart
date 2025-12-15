import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
  late final Worker _statusWorker;

  @override
  void initState() {
    super.initState();
    final isPlaying = widget.plPlayerController.playerStatus.value == PlayerStatus.playing;
    controller = AnimationController(
      vsync: this,
      value: isPlaying ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    
    // Listen to player status changes using GetX
    _statusWorker = ever(widget.plPlayerController.playerStatus, (PlayerStatus status) {
      if (status == PlayerStatus.playing) {
        controller.forward();
      } else {
        controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _statusWorker.dispose();
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
          child: Obx(() {
            final isPlaying = widget.plPlayerController.playerStatus.value == PlayerStatus.playing;
            return AnimatedIcon(
              semanticLabel: isPlaying ? '暂停' : '播放',
              progress: controller,
              icon: AnimatedIcons.play_pause,
              color: Colors.white,
              size: 20,
            );
          }),
        ),
      ),
    );
  }
}
