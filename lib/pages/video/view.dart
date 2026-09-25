import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/image_viewer/hero_dialog_route.dart';
import 'package:PiliPlus/common/widgets/keep_alive_wrapper.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_behavior.dart'
    show NoOverscrollIndicator;
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show tabBarView, platformAlwaysClampingPhysics, platformClampingPhysics;
import 'package:PiliPlus/common/widgets/simple_app_bar.dart';
import 'package:PiliPlus/common/widgets/sliver/video_header.dart';
import 'package:PiliPlus/common/widgets/svg/play_icon.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/models_new/video/video_detail/section.dart';
import 'package:PiliPlus/models_new/video/video_detail/ugc_season.dart';
import 'package:PiliPlus/models_new/video/video_tag/data.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:PiliPlus/pages/episode_panel/view.dart';
import 'package:PiliPlus/pages/video/ai_conclusion/view.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/local/controller.dart';
import 'package:PiliPlus/pages/video/introduction/local/view.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/view.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/widgets/intro_detail.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/view.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/page.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/season.dart';
import 'package:PiliPlus/pages/video/member/controller.dart';
import 'package:PiliPlus/pages/video/member/view.dart';
import 'package:PiliPlus/pages/video/related/view.dart';
import 'package:PiliPlus/pages/video/reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/view.dart';
import 'package:PiliPlus/pages/video/view_point/view.dart';
import 'package:PiliPlus/pages/video/widgets/header_control.dart';
import 'package:PiliPlus/pages/video/widgets/player_focus.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart'
    show shutdownTimerService;
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/max_screen_size.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart' show kDebugMode, clampDouble;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:os_type/os_type.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

class VideoDetailPageV extends StatefulWidget {
  const VideoDetailPageV({super.key});

  @override
  State<VideoDetailPageV> createState() => _VideoDetailPageVState();
}

class _VideoDetailPageVState extends State<VideoDetailPageV>
    with RouteAware, RouteAwareMixin, WidgetsBindingObserver {
  final heroTag = Get.arguments['heroTag'];

  late final VideoDetailController videoDetailController;
  late final VideoReplyController _videoReplyController;
  PlPlayerController? plPlayerController;

  // intro ctr
  late final CommonIntroController introController =
      videoDetailController.isFileSource
      ? localIntroController
      : videoDetailController.isUgc
      ? ugcIntroController
      : pgcIntroController;
  late final UgcIntroController ugcIntroController;
  late final PgcIntroController pgcIntroController;
  late final LocalIntroController localIntroController;

  bool get autoExitFullscreen =>
      videoDetailController.plPlayerController.autoExitFullscreen;

  bool get autoPlayEnable =>
      videoDetailController.plPlayerController.autoPlayEnable;

  bool get enableVerticalExpand =>
      videoDetailController.plPlayerController.enableVerticalExpand;

  bool get pipNoDanmaku =>
      videoDetailController.plPlayerController.pipNoDanmaku;

  bool isShowing = true;

  bool get isFullScreen =>
      videoDetailController.plPlayerController.isFullScreen.value;

  /// 判断，窗口由横屏全屏旋转回竖屏：应自动退出全屏
  /// 竖屏视频全屏时窗口自始至终为竖屏：不应退出或渲染成普通布局
  bool _windowWasLandscapeInFullScreen = false;

  /// 横版视频在“竖屏窗口 + 全屏”是旋转退出全屏时的瞬态
  /// （窗口已转回竖屏、全屏状态尚未退出）。此时按普通页面布局渲染，
  /// 避免“竖屏全屏居中”一闪后跳到页面顶部播放位。
  /// 强制竖屏/不改变方向模式下竖屏全屏是稳定状态，不适用。
  /// gravity 模式进全屏时不把窗口转到视频方向（交给重力），竖着拿设备
  /// 全屏横屏视频时竖屏窗口是稳定状态而非瞬态，同样排除。
  bool get _layoutFullScreen {
    if (!isFullScreen) return false;
    /// 应用窗口是否处于受限窗口模式（分屏/自由多窗/悬浮窗等非全屏窗口）。
    /// 此模式下窗口宽高比不代表设备方向，且窗口无法旋转到全屏横屏
    /// 仍应按 isFullScreen 渲染全屏布局，
    /// 此处用于修复全屏时视频与页面没变
    final constrainedWindow =
        (OS.isHarmony && HarmonyChannel.isWindowMode) || isWindowMode;
    final invalidPortraitFullScreen =
        isPortrait &&
        // 仅确实由横屏旋转回竖屏时才退出全屏
        // 竖屏视频全屏始终为竖屏，不受isVertical竞态影响
        _windowWasLandscapeInFullScreen &&
        !constrainedWindow &&
        !videoDetailController.isVertical.value &&
        videoDetailController.plPlayerController.mode != FullScreenMode.none &&
        videoDetailController.plPlayerController.mode !=
            FullScreenMode.vertical &&
        videoDetailController.plPlayerController.mode != FullScreenMode.gravity;
    return !invalidPortraitFullScreen;
  }

  bool get _shouldShowSeasonPanel {
    if (videoDetailController.isFileSource ||
        isPortrait ||
        !videoDetailController.isUgc ||
        !videoDetailController.plPlayerController.horizontalSeasonPanel) {
      return false;
    }
    final videoDetail = ugcIntroController.videoDetail.value;
    return (videoDetail.pages?.length ?? 0) > 1 ||
        _hasRenderableSeason(videoDetail.ugcSeason?.sections);
  }

  /// 合集数据是否足以渲染播放列表面板。
  ///
  /// `ugcSeason != null` 并不足以作为判据：接口的 `sections` 是可空的，也可能是
  /// 空数组或整段没有 episodes。面板内部按下标直接取用（EpisodePanel.list 是无类型
  /// 的 List），取空即在 initState 抛出，release 下这一整列会被替换成
  /// 0xF0C0C0C0 的 ErrorWidget 灰块——这在竖屏下看不到，只有平板 / 分屏等宽屏布局
  /// 才会走到这一列。
  static bool _hasRenderableSeason(List<SectionItem>? sections) =>
      sections?.any((section) => section.episodes?.isNotEmpty == true) ?? false;

  /// seasonIndex 与 sections 不同源（前者由 SeasonPanel 查找当前集时写入），
  /// 钳位后再取下标，越界不应把整列炸成 ErrorWidget。
  bool _seasonSectionReversed(List<SectionItem> sections) {
    if (sections.isEmpty) return false;
    final index = videoDetailController.seasonIndex.value.clamp(
      0,
      sections.length - 1,
    );
    return sections[index].isReversed;
  }

  final videoReplyPanelKey = GlobalKey();
  final videoRelatedKey = GlobalKey();
  final videoIntroKey = GlobalKey();
  final _seasonPartPanelKey = GlobalKey<EpisodePanelState>();
  final _seasonPanelKey = GlobalKey<EpisodePanelState>();

  Worker? _pipModeWorker;
  Worker? _decorDarkWorker;
  Worker? _decorFullScreenWorker;

  /// 自由多窗装饰栏按钮配色是否由本页驱动。页面被覆盖（didPushNext）或
  /// 销毁后置 false：覆盖期间的滚动/主题变化不应再把按钮抢回来。
  bool _decorDarkActive = false;

  /// 装饰栏按钮（窗口右上角）下方那块区域当前是否为深色底。
  ///
  /// 深色主题下 colorScheme.surface 本身就是深色，怎么算都是深色底；
  /// 只有浅色主题需要逐布局判断：
  /// - 竖屏布局：顶栏是 SimpleAppBar 与其下的渐显工具条，随滚动由黑渐变到
  ///   colorScheme.surface，判据与 SimpleAppBar 给状态栏图标用的那套一致
  /// - 横屏布局：右上角是 MiniScaffold（surface），只有顶部那条黑色 AppBar
  ///   有高度（窗口压住状态栏，padding.top > 0）时才盖得住按钮所在的一带
  /// - 近方形布局：顶部整条都是播放器，恒为黑
  bool get _topBarIsDark {
    // 全屏：整窗都是播放器
    if (isFullScreen) return true;
    if (colorScheme.brightness == Brightness.dark) return true;
    if (_usesPortraitLayout) {
      return videoDetailController.scrollRatio.value < 0.5;
    }
    if (_usesLandscapeLayout) {
      return padding.top > 0;
    }
    return true;
  }

  /// 按顶栏实际底色同步自由多窗装饰栏按钮配色。
  void _syncDecorDark() {
    if (!_decorDarkActive) return;
    HarmonyChannel.setDecorDark(this, _topBarIsDark);
  }

  /// 交还装饰栏按钮控制权（页面被覆盖/销毁）。
  void _releaseDecorDark() {
    _decorDarkActive = false;
    HarmonyChannel.releaseDecorDark(this);
  }

  /// 当前应用生命周期状态
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  // heroTag 恒非空（兼任 GetX 控制器 tag，toVideoPage 有随机值兜底），只有
  // 真正被 Hero 包裹的卡片（首页视频卡/番剧卡）会生成带这两个前缀的稳定
  // tag。其他入口（搜索等）没有源端 Hero，不能包 Hero。
  late final _enableHero =
      Pref.enableHeroCoverAnimation &&
      heroTag is String &&
      ((heroTag as String).startsWith('video_hero_') ||
          (heroTag as String).startsWith('pgc_hero_'));

  @override
  void initState() {
    super.initState();
    PlPlayerController.setPlayCallBack(playCallBack);
    videoDetailController = Get.put(VideoDetailController(), tag: heroTag);

    if (videoDetailController.removeSafeArea) {
      hideSystemBar();
    }

    // 自由多窗的装饰栏按钮跟随顶栏实际底色：顶部是黑色播放器时切浅色
    // 风格（否则浅色模式下深色按钮不可见），顶栏随滚动渐变成 surface
    // 后再交回系统颜色模式。滚动与全屏都会改变顶栏底色，各挂一个监听。
    // 首次同步在 didChangeDependencies 里做（theme 此时才就绪）
    _decorDarkActive = true;
    _decorDarkWorker = ever(
      videoDetailController.scrollRatio,
      (_) => _syncDecorDark(),
    );
    _decorFullScreenWorker = ever(
      videoDetailController.plPlayerController.isFullScreen,
      (_) => _syncDecorDark(),
    );
    // 画中画状态翻转时强制重建：PiP 结束时若窗口尺寸恰好没变（如画中画
    // 期间从智慧多窗应用栏以小窗打开 app），没有视口变化触发重建，页面
    // 会滞留在画中画布局（黑边+播控被状态栏遮挡）。
    _pipModeWorker = ever(
      videoDetailController.plPlayerController.pipModeRx,
      (_) {
        if (mounted) setState(() {});
      },
    );

    if (videoDetailController.showReply) {
      _videoReplyController = Get.put(
        VideoReplyController(
          aid: videoDetailController.aid,
          videoType: videoDetailController.videoType,
          heroTag: heroTag,
        ),
        tag: heroTag,
      );
    }

    if (videoDetailController.isFileSource) {
      localIntroController = Get.put(LocalIntroController(), tag: heroTag);
    } else if (videoDetailController.isUgc) {
      ugcIntroController = Get.put(UgcIntroController(), tag: heroTag);
    } else {
      pgcIntroController = Get.put(PgcIntroController(), tag: heroTag);
    }

    videoSourceInit();

    addObserverMobile(this);
  }

  // 获取视频资源，初始化播放器
  void videoSourceInit() {
    videoDetailController.queryVideoUrl(autoFullScreenFlag: true);
    if (videoDetailController.autoPlay) {
      plPlayerController = videoDetailController.plPlayerController;
      plPlayerController!
        ..addStatusLister(playerListener)
        ..addPositionListener(positionListener);
    }
  }

  void positionListener(Duration position) {
    videoDetailController.playedTime = position;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    final isResume = state == .resumed;
    final ctr = videoDetailController.plPlayerController..visible = isResume;
    if (isResume) {
      if (!ctr.showDanmaku) {
        introController.startTimer();
        ctr.showDanmaku = true;
      }
    } else if (state == .paused) {
      introController.cancelTimer();
      ctr.showDanmaku = false;
    }
  }

  @override
  void handleStatusBarTap() {
    if (!Pref.enableStatusBarTapToTop) return;
    if (!isShowing) return;
    // 仅在应用处于前台（resumed）时触发
    if (_lifecycleState != AppLifecycleState.resumed) return;
    if (videoDetailController.scrollCtr.hasClients) {
      videoDetailController.animToTop();
      return;
    }

    // 横屏分栏没有 ExtendedNestedScrollView，各 tab 是自己维护的列表
    final hasIntroTab = !(videoDetailController.isVertical.value && !isPortrait);
    final tabIndex = videoDetailController.tabCtr.index;
    final replyIndex = hasIntroTab ? 1 : 0;
    final seasonIndex = replyIndex + (videoDetailController.showReply ? 1 : 0);
    if (hasIntroTab && tabIndex == 0) {
      videoDetailController.introScrollCtr?.animToTop();
    } else if (tabIndex == replyIndex && videoDetailController.showReply) {
      _videoReplyController.animateToTop();
    } else if (tabIndex == seasonIndex && _shouldShowSeasonPanel) {
      _seasonPartPanelKey.currentState?.animToTop();
      _seasonPanelKey.currentState?.animToTop();
    }
  }

  Future<void>? playCallBack() {
    if (!isShowing) {
      plPlayerController
        ?..addStatusLister(playerListener)
        ..addPositionListener(positionListener);
    }
    return plPlayerController?.play();
  }

  // 播放器状态监听
  Future<void> playerListener(PlayerStatus status) async {
    final isPlaying = status.isPlaying;
    try {
      if (videoDetailController.scrollCtr.hasClients) {
        if (isPlaying) {
          if (!videoDetailController.isExpanding &&
              videoDetailController.scrollCtr.offset != 0 &&
              !videoDetailController.animationController.isAnimating) {
            videoDetailController.isExpanding = true;
            videoDetailController.animationController.forward(
              from:
                  1 -
                  videoDetailController.scrollCtr.offset /
                      videoDetailController.videoHeight,
            );
          } else {
            videoDetailController.refreshPage();
          }
        } else {
          videoDetailController.refreshPage();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('handle player status: $e');
    }

    if (status.isCompleted) {
      try {
        if (videoDetailController
                .steinEdgeInfo
                ?.edges
                ?.questions
                ?.firstOrNull
                ?.choices
                ?.isNotEmpty ==
            true) {
          videoDetailController.showSteinEdgeInfo.value = true;
          return;
        }
      } catch (_) {}

      bool exitFlag = true;

      /// 顺序播放 列表循环
      if (shutdownTimerService.isWaiting) {
        shutdownTimerService.handleWaiting();
      } else {
        switch (plPlayerController!.playRepeat) {
          case PlayRepeat.singleCycle:
            exitFlag = false;
            plPlayerController!.play(repeat: true);
          case PlayRepeat.listOrder:
          case PlayRepeat.listCycle:
          case PlayRepeat.autoPlayRelated:
            exitFlag = !introController.nextPlay();
          case PlayRepeat.pause:
        }
      }

      if (exitFlag) {
        if (autoExitFullscreen) {
          plPlayerController!.triggerFullScreen(status: false);
          if (plPlayerController!.controlsLock.value) {
            plPlayerController!.onLockControl(false);
          }
        } else {
          // 鸿蒙/安卓走 floating 插件查询画中画状态（上游用的是 JNI AndroidHelper）
          if (plPlayerController!.controlsLock.value &&
              ((!Platform.isAndroid && !OS.isHarmony) ||
                  await Floating().pipStatus == PiPStatus.disabled)) {
            plPlayerController!.onLockControl(false);
          }
        }
      }
    }
  }

  // 继续播放或重新播放
  void continuePlay() {
    plPlayerController!.play();
  }

  /// 未开启自动播放时触发播放
  Future<void>? handlePlay() {
    if (!videoDetailController.isFileSource) {
      if (videoDetailController.isQuerying) {
        if (kDebugMode) debugPrint('handlePlay: querying');
        return null;
      }
      if (videoDetailController.videoUrl == null ||
          videoDetailController.audioUrl == null) {
        if (kDebugMode) {
          debugPrint('handlePlay: videoUrl/audioUrl not initialized');
        }
        videoDetailController.queryVideoUrl();
        return null;
      }
    }
    final plPlayerController = this.plPlayerController =
        videoDetailController.plPlayerController;
    videoDetailController.autoPlay = true;
    plPlayerController
      ..addStatusLister(playerListener)
      ..addPositionListener(positionListener);
    if (plPlayerController.preInitPlayer) {
      if (plPlayerController.autoEnterFullScreen) {
        plPlayerController.triggerFullScreen();
      }
      return plPlayerController.play();
    } else {
      return videoDetailController.playerInit(
        autoplay: true,
        autoFullScreenFlag: true,
      );
    }
  }

  @override
  void dispose() {
    _pipModeWorker?.dispose();
    _decorDarkWorker?.dispose();
    _decorFullScreenWorker?.dispose();
    _releaseDecorDark();
    plPlayerController
      ?..removeStatusLister(playerListener)
      ..removePositionListener(positionListener);

    Get.delete<HorizontalMemberPageController>(
      tag: videoDetailController.heroTag,
    );

    if (!Get.previousRoute.startsWith('/video')) {
      if ((Platform.isAndroid || OS.isHarmony) &&
          !videoDetailController.setSystemBrightness) {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      }
      PlPlayerController.setPlayCallBack(null);
    }

    if (!videoDetailController.isFileSource) {
      if (videoDetailController.isUgc) {
        ugcIntroController
          ..cancelTimer()
          ..videoDetail.close();
      } else {
        pgcIntroController.cancelTimer();
      }
    }

    if (!videoDetailController.removeSafeArea) {
      showSystemBar();
    }

    if (!videoDetailController.plPlayerController.isCloseAll) {
      videoPlayerServiceHandler?.onVideoDetailDispose(heroTag);
      if (plPlayerController != null) {
        videoDetailController.makeHeartBeat();
        unawaited(plPlayerController!.dispose());
      } else {
        PlPlayerController.updatePlayCount();
      }
    }
    removeObserverMobile(this);

    super.dispose();
  }

  @override
  // 离开当前页面时
  void didPushNext() {
    if (Get.routing.route is HeroDialogRoute) {
      videoDetailController.imageview = true;
      return;
    }

    _releaseDecorDark();
    WidgetsBinding.instance.removeObserver(this);

    if ((Platform.isAndroid || OS.isHarmony) &&
        !videoDetailController.setSystemBrightness) {
      ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
    }

    introController.cancelTimer();

    videoDetailController
      ..videoState.value = false
      ..cancelBlockListener()
      ..playerStatus = plPlayerController?.playerStatus.value
      ..brightness = plPlayerController?.brightness.value;
    if (plPlayerController != null) {
      videoDetailController.makeHeartBeat();
      plPlayerController!
        ..removeStatusLister(playerListener)
        ..removePositionListener(positionListener)
        ..pause();
    }
  }

  @override
  // 返回当前页面时
  void didPopNext() {
    super.didPopNext();

    if (videoDetailController.plPlayerController.isCloseAll) {
      return;
    }

    // 从覆盖页面返回播放页时重新进入沉浸模式：移除安全边距（页面级沉浸）
    // 或仍处于全屏（全屏沉浸）时恢复隐藏
    if (videoDetailController.removeSafeArea || isFullScreen) {
      hideSystemBar();
    }

    _decorDarkActive = true;
    _syncDecorDark();
    WidgetsBinding.instance.addObserver(this);

    plPlayerController?.isLive = false;
    if (videoDetailController.plPlayerController.playerStatus.isPlaying &&
        videoDetailController.playerStatus != PlayerStatus.playing) {
      videoDetailController.plPlayerController.pause();
    }

    PlPlayerController.setPlayCallBack(playCallBack);

    introController.startTimer();

    if (mounted &&
        (Platform.isAndroid || OS.isHarmony) &&
        !videoDetailController.setSystemBrightness) {
      if (videoDetailController.brightness != null) {
        plPlayerController?.brightness.value =
            videoDetailController.brightness!;
        if (videoDetailController.brightness != -1.0) {
          ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
            videoDetailController.brightness!,
          );
        } else {
          ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
        }
      } else {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      }
    }

    plPlayerController
      ?..addStatusLister(playerListener)
      ..addPositionListener(positionListener);
    if (videoDetailController.autoPlay) {
      videoDetailController.playerInit(
        autoplay: videoDetailController.playerStatus?.isPlaying ?? false,
      );
    } else if (videoDetailController.plPlayerController.preInitPlayer &&
        !videoDetailController.isQuerying &&
        videoDetailController.videoUrl != null) {
      videoDetailController.playerInit();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 布局/方向状态必须在这里同步计算：旋转（MediaQuery 变化）时本方法先于
    // build 执行，保证 build 读到的 isPortrait/maxWidth/maxHeight 永远是当前值。
    if (videoDetailController.removeSafeArea) {
      padding = .zero;
    } else {
      padding = MediaQuery.viewPaddingOf(context);
    }
    // 顶部间距固定为首次捕获的状态栏高度：状态栏显隐不再改变页面布局，
    // 避免旋转退出全屏时状态栏在动画末尾显现导致画面下移。
    if (padding.top > 0) {
      _fixedTopInset ??= padding.top;
    }

    final size = MediaQuery.sizeOf(context);
    maxWidth = size.width;
    maxHeight = size.height;
    isWindowMode = MaxScreenSize.isWindowMode(
      width: maxWidth * videoDetailController.uiScale,
      height: maxHeight * videoDetailController.uiScale,
    ) ||
        (OS.isHarmony && HarmonyChannel.isWindowMode);
    videoDetailController.plPlayerController.screenRatio = maxHeight / maxWidth;

    final shortestSide = size.shortestSide;
    final minVideoHeight = shortestSide / Style.aspectRatio16x9;
    final maxVideoHeight = max(size.longestSide * 0.65, shortestSide);
    videoDetailController
      ..isPortrait = isPortrait = maxHeight >= maxWidth
      ..minVideoHeight = minVideoHeight
      ..maxVideoHeight = maxVideoHeight
      ..videoHeight = videoDetailController.isVertical.value
          ? maxVideoHeight
          : minVideoHeight;

    // 跟踪本次全屏期间窗口是否曾为横屏，见定义出
    if (isFullScreen) {
      if (!isPortrait) {
        _windowWasLandscapeInFullScreen = true;
      }
    } else {
      _windowWasLandscapeInFullScreen = false;
    }

    theme = videoDetailController.plPlayerController.darkVideoPage
        ? ThemeUtils.darkTheme
        : Theme.of(context);

    // 顶栏底色还取决于方向与主题，二者变化都只经由本方法生效
    _syncDecorDark();
  }

  bool removeAppBar(bool isFullScreen) =>
      videoDetailController.removeSafeArea ||
      (OS.isHarmony && HarmonyChannel.isWindowMode && isFullScreen) ||
      (isWindowMode && isFullScreen && !isPortrait);

  Widget get childWhenDisabled {
    if (PlatformUtils.isMobile && mounted && isShowing && !isFullScreen) {
      if (videoDetailController.removeSafeArea) {
        hideSystemBar();
      }
    }
    if (PlatformUtils.isMobile) {
      // 鸿蒙自由小窗/分屏等受限窗口内窗口宽高比不代表设备方向：横屏
      // 小窗退出全屏时窗口尚未恢复竖屏尺寸，此处若按"非竖屏"自动重进
      // 全屏会形成退不出去的回环；分屏等受限窗口无法旋转到横屏，竖屏
      // 窗口同样不代表设备方向，「转回竖屏自动退全屏」会把手动全屏
      // 刚进就退。受限窗口一律跳过方向驱动的自动进/退全屏，交给手动。
      //
      // 用 controller 的恒非空单例而非本页局部 plPlayerController：未开启自动
      // 播放时局部引用为 null，横屏仍须自动进全屏（hideSystemBar 在
      // triggerFullScreen 内），否则状态栏不会被隐藏。上游通过设备方向监听器
      // 同样无条件自动进全屏（与播放器是否初始化无关），这里行为保持一致。
      final player = videoDetailController.plPlayerController;
      final aspectIsOrientation = !OS.isHarmony ||
          (!HarmonyChannel.isMiniWindow && !HarmonyChannel.isWindowMode);
      if (!isPortrait &&
          !isFullScreen &&
          aspectIsOrientation &&
          // 鸿蒙mate80开启旋转锁定后，退出全屏一段时间仍为横屏 + 非全屏，若不抑制会被自动进全屏拉回。
          !player.suppressAutoFullScreen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          player.triggerFullScreen(
            status: true,
            isManualFS: false,
          );
        });
      } else if (aspectIsOrientation &&
          isPortrait &&
          isFullScreen &&
          // 仅确实由横屏旋转回竖屏时才退出全屏
          // 竖屏视频全屏始终为竖屏，不受isVertical竞态影响
          _windowWasLandscapeInFullScreen &&
          // 鸿蒙手动进全屏（auto/ratio 等）同样跟随传感器转屏，
          // 手机转回竖屏时窗口会跟着转回，需要自动退出全屏；
          // 强制竖屏/不旋转模式除外（竖屏全屏是稳定目标状态）。
          // gravity 模式手动进全屏不把窗口转到视频方向（放开方向交给
          // 重力），竖着拿设备全屏横屏视频时竖屏窗口不代表转回竖屏，
          // 不应自动退出，否则横屏视频全屏会刚进就退。
          // 自动进全屏（倾斜手机触发）仍保留退出行为，对齐安卓。
          (!player.isManualFS ||
              (OS.isHarmony &&
                  player.mode != FullScreenMode.none &&
                  player.mode != FullScreenMode.vertical &&
                  player.mode != FullScreenMode.gravity)) &&
          !player.controlsLock.value &&
          // 竖屏视频自动进全屏后跟随设备方向：转回竖屏时保持竖屏全屏，
          // 不退出（对齐上游安卓效果）；非竖屏视频仍按原逻辑转回竖屏即退出
          !videoDetailController.isVertical.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          player.triggerFullScreen(status: false, isManualFS: false);
        });
      }
    }
    return Obx(
      () {
        final isFullScreen = this.isFullScreen;
        return SimpleScaffold(
          appBar: removeAppBar(isFullScreen)
              ? null
              : Obx(
                  () {
                    final scrollRatio = videoDetailController.scrollRatio.value;
                    final brightness = colorScheme.brightness;
                    final Brightness statusBarBrightness;
                    final Brightness statusBarIconBrightness;
                    final backgroundColor = isPortrait && scrollRatio > 0
                        ? Color.lerp(
                            Colors.black,
                            colorScheme.surface,
                            scrollRatio,
                          )!
                        : Colors.black;
                    if (isPortrait && scrollRatio >= 0.5) {
                      statusBarBrightness = brightness;
                      statusBarIconBrightness = brightness.reverse;
                    } else {
                      statusBarBrightness = .dark;
                      statusBarIconBrightness = .light;
                    }
                    return SimpleAppBar(
                      height: padding.top,
                      backgroundColor: backgroundColor,
                      brightness: brightness,
                      statusBarBrightness: statusBarBrightness,
                      statusBarIconBrightness: statusBarIconBrightness,
                    );
                  },
                ),
          body: ExtendedNestedScrollView(
            onlyOneScrollInBody: true,
            physics: platformClampingPhysics,
            key: videoDetailController.scrollKey,
            controller: videoDetailController.scrollCtr,
            scrollBehavior: const NoOverscrollIndicator(),
            pinnedHeaderSliverHeightBuilder: () {
              double pinnedHeight = this.isFullScreen || !isPortrait
                  ? maxHeight -
                        ((isWindowMode && !isPortrait) ||
                                _harmonyFullscreenNoSafeArea
                            ? 0
                            : padding.top)
                  : videoDetailController.isExpanding ||
                        videoDetailController.isCollapsing
                  ? videoDetailController.animHeight
                  : videoDetailController.isCollapsing ||
                        (plPlayerController?.playerStatus.isPlaying ?? false)
                  ? videoDetailController.minVideoHeight
                  : kToolbarHeight;
              if (videoDetailController.isExpanding &&
                  videoDetailController.animationController.value == 1) {
                videoDetailController.isExpanding = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  videoDetailController.scrollRatio.value = 0;
                  videoDetailController.refreshPage();
                });
              } else if (videoDetailController.isCollapsing &&
                  videoDetailController.animationController.value == 1) {
                videoDetailController.isCollapsing = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  videoDetailController.refreshPage();
                });
              }
              return pinnedHeight;
            },
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              final height = isFullScreen || !isPortrait
                  ? maxHeight -
                        ((isWindowMode && !isPortrait) ||
                                _harmonyFullscreenNoSafeArea
                            ? 0
                            : padding.top)
                  : videoDetailController.isExpanding ||
                        videoDetailController.isCollapsing
                  ? videoDetailController.animHeight
                  : videoDetailController.videoHeight;
              return [
                VideoHeader(
                  minExtent: kToolbarHeight,
                  maxExtent: height,
                  minVideoHeight: videoDetailController.minVideoHeight,
                  onScrollRatioChanged: videoDetailController.scrollRatio.call,
                  child: Stack(
                    clipBehavior: .none,
                    children: [
                      SizedBox(
                        width: maxWidth,
                        height: height,
                        child: videoPlayer(width: maxWidth, height: height),
                      ),
                      _buildHeaderOverlay(),
                    ],
                  ),
                ),
              ];
            },
            body: MiniScaffold(
              key: videoDetailController.childKey,
              body: Column(
                children: [
                  buildTabBar(onTap: videoDetailController.animToTop),
                  Expanded(
                    child: tabBarView(
                      hitTestBehavior: .translucent,
                      controller: videoDetailController.tabCtr,
                      children: [
                        videoIntro(isHorizontal: false, needCtr: false),
                        if (videoDetailController.showReply)
                          videoReplyPanel(isNested: true),
                        if (_shouldShowSeasonPanel) seasonPanel,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlayToolBar(double scrollRatio) {
    final IconData icon;
    final String playStat;
    if (videoDetailController.playedTime == null) {
      icon = Icons.play_arrow_rounded;
      playStat = '立即';
    } else if (plPlayerController!.isCompleted) {
      icon = CustomIcons.replay_rounded;
      playStat = '重新';
    } else {
      icon = Icons.play_arrow_rounded;
      playStat = '继续';
    }
    final playBtn = Row(
      spacing: 2,
      mainAxisSize: .min,
      children: [
        Icon(icon, color: colorScheme.primary),
        Text(
          '$playStat播放',
          style: TextStyle(color: colorScheme.primary),
        ),
      ],
    );
    return Opacity(
      opacity: videoDetailController.scrollRatio.value,
      child: Container(
        color: colorScheme.surface,
        alignment: .topCenter,
        child: SizedBox(
          height: kToolbarHeight,
          child: Stack(
            clipBehavior: .none,
            children: [
              Align(
                alignment: .centerLeft,
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    SizedBox(
                      width: 42,
                      height: 34,
                      child: IconButton(
                        tooltip: '返回',
                        icon: Icon(
                          FontAwesomeIcons.arrowLeft,
                          size: 15,
                          color: colorScheme.onSurface,
                        ),
                        onPressed: Get.back,
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      height: 34,
                      child: IconButton(
                        tooltip: '返回主页',
                        icon: Icon(
                          FontAwesomeIcons.house,
                          size: 15,
                          color: colorScheme.onSurface,
                        ),
                        onPressed:
                            videoDetailController.plPlayerController.onCloseAll,
                      ),
                    ),
                  ],
                ),
              ),
              Center(child: playBtn),
              Align(
                alignment: .centerRight,
                child: videoDetailController.playedTime == null
                    ? _moreBtn(colorScheme.onSurface)
                    : SizedBox(
                        width: 42,
                        height: 34,
                        child: IconButton(
                          tooltip: "更多设置",
                          style: const ButtonStyle(
                            padding: WidgetStatePropertyAll(EdgeInsets.zero),
                          ),
                          onPressed: () =>
                              (videoDetailController.headerCtrKey.currentState
                                      as HeaderControlState?)
                                  ?.showSettingSheet(),
                          icon: Icon(
                            Icons.more_vert_outlined,
                            size: 19,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderOverlay() {
    return Obx(
      () {
        final scrollRatio = videoDetailController.scrollRatio.value;
        if (scrollRatio == 0) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          bottom: -2,
          child: GestureDetector(
            onTap: () {
              if (!videoDetailController.isFileSource) {
                if (videoDetailController.isQuerying) {
                  if (kDebugMode) {
                    debugPrint('handlePlay: querying');
                  }
                  return;
                }
                if (videoDetailController.videoUrl == null ||
                    videoDetailController.audioUrl == null) {
                  if (kDebugMode) {
                    debugPrint('handlePlay: videoUrl/audioUrl not initialized');
                  }
                  videoDetailController.queryVideoUrl();
                  return;
                }
              }
              if (plPlayerController == null ||
                  videoDetailController.playedTime == null) {
                handlePlay();
              } else {
                plPlayerController!.onDoubleTapCenter();
              }
            },
            behavior: .opaque,
            child: _buildOverlayToolBar(scrollRatio),
          ),
        );
      },
    );
  }

  Widget get childWhenDisabledLandscape => Obx(
    () {
      final isFullScreen = this.isFullScreen;
      return SimpleScaffold(
        appBar: removeAppBar(isFullScreen)
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                automaticallyImplyLeading: false,
                toolbarHeight: isFullScreen
                    ? 0
                    : (isPortrait
                          ? (_fixedTopInset ?? padding.top)
                          : padding.top),
                primary: false,
              ),
        body: Padding(
          padding: isFullScreen
              ? EdgeInsets.zero
              : padding.copyWith(top: 0, bottom: 0),
          child: childWhenDisabledLandscapeInner(isFullScreen),
        ),
      );
    },
  );

  Widget childSplit(double ratio) {
    final double videoHeight = isFullScreen
        ? maxHeight
        : maxHeight - padding.vertical;
    final double width = videoHeight * ratio;
    final videoWidth = isFullScreen ? maxWidth : width;
    final introWidth = maxWidth - width - padding.horizontal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: videoWidth,
          height: videoHeight,
          child: videoPlayer(
            width: videoWidth,
            height: videoHeight,
          ),
        ),
        Offstage(
          offstage: isFullScreen,
          child: SizedBox(
            width: introWidth,
            height: maxHeight - padding.top,
            child: MiniScaffold(
              key: videoDetailController.childKey,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTabBar(),
                  Expanded(
                    child: tabBarView(
                      controller: videoDetailController.tabCtr,
                      children: [
                        videoIntro(
                          width: introWidth,
                          height: maxHeight,
                        ),
                        if (videoDetailController.showReply) videoReplyPanel(),
                        if (_shouldShowSeasonPanel) seasonPanel,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget childWhenDisabledLandscapeInner(bool isFullScreen) {
    if (enableVerticalExpand) {
      return Obx(() {
        if (videoDetailController.isVertical.value && !isPortrait) {
          final double videoHeight = maxHeight - padding.vertical;
          final double width = videoHeight / Style.aspectRatio16x9;
          final videoWidth = isFullScreen ? maxWidth : width;
          final introWidth = (maxWidth - padding.horizontal - width) / 2;
          final introHeight = maxHeight - padding.top;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Offstage(
                offstage: isFullScreen,
                child: SizedBox(
                  width: introWidth,
                  height: introHeight,
                  child: videoIntro(
                    width: introWidth,
                    height: introHeight,
                  ),
                ),
              ),
              SizedBox(
                width: videoWidth,
                height: videoHeight,
                child: videoPlayer(
                  width: videoWidth,
                  height: videoHeight,
                ),
              ),
              Offstage(
                offstage: isFullScreen,
                child: SizedBox(
                  width: introWidth,
                  height: introHeight,
                  child: MiniScaffold(
                    key: videoDetailController.childKey,
                    body: Column(
                      children: [
                        buildTabBar(showIntro: false),
                        Expanded(
                          child: tabBarView(
                            controller: videoDetailController.tabCtr,
                            children: [
                              if (videoDetailController.showReply)
                                videoReplyPanel(),
                              if (_shouldShowSeasonPanel) seasonPanel,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return _childWhenDisabledLandscapeInner(isFullScreen);
      });
    }
    return _childWhenDisabledLandscapeInner(isFullScreen);
  }

  Widget _childWhenDisabledLandscapeInner(bool isFullScreen) {
    double width =
        clampDouble(maxHeight / maxWidth * 1.08, 0.5, 0.7) * maxWidth;
    if (maxWidth >= 560) {
      width = maxWidth - clampDouble(maxWidth - width, 280, 425);
    }
    final videoWidth = isFullScreen ? maxWidth : width;
    final double height = width / Style.aspectRatio16x9;
    final videoHeight = isFullScreen ? maxHeight : height;
    if (height > maxHeight) {
      return childSplit(Style.aspectRatio16x9);
    }
    final introHeight = maxHeight - height - padding.top;
    final showIntro =
        videoDetailController.isUgc && videoDetailController.showRelatedVideo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: videoWidth,
              height: videoHeight,
              child: videoPlayer(
                width: videoWidth,
                height: videoHeight,
              ),
            ),
            if (!videoDetailController.isFileSource)
              Offstage(
                offstage: isFullScreen,
                child: SizedBox(
                  width: width,
                  height: introHeight,
                  child: videoIntro(
                    width: width,
                    height: introHeight,
                    needRelated: false,
                    needCtr: false,
                  ),
                ),
              ),
          ],
        ),
        Offstage(
          offstage: isFullScreen,
          child: SizedBox(
            width: maxWidth - width - padding.horizontal,
            height: maxHeight - padding.top,
            child: MiniScaffold(
              key: videoDetailController.childKey,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTabBar(
                    introText: '相关视频',
                    showIntro: videoDetailController.isFileSource
                        ? true
                        : showIntro,
                  ),
                  Expanded(
                    child: tabBarView(
                      controller: videoDetailController.tabCtr,
                      children: [
                        if (videoDetailController.isFileSource)
                          localIntroPanel()
                        else if (showIntro)
                          KeepAliveWrapper(
                            child: CustomScrollView(
                              key: const PageStorageKey(CommonIntroController),
                              controller:
                                  videoDetailController.effectiveIntroScrollCtr,
                              slivers: [
                                RelatedVideoPanel(
                                  key: videoRelatedKey,
                                  heroTag: heroTag,
                                ),
                              ],
                            ),
                          ),
                        if (videoDetailController.showReply) videoReplyPanel(),
                        if (_shouldShowSeasonPanel) seasonPanel,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget get childWhenDisabledAlmostSquare => Obx(() {
    final isFullScreen = _layoutFullScreen;
    return SimpleScaffold(
      appBar: removeAppBar(isFullScreen)
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              automaticallyImplyLeading: false,
              toolbarHeight: isFullScreen ? 0 : (_fixedTopInset ?? padding.top),
              primary: false,
            ),
      body: Padding(
        padding: isFullScreen
            ? EdgeInsets.zero
            : padding.copyWith(top: 0, bottom: 0),
        child: childWhenDisabledAlmostSquareInner(isFullScreen),
      ),
    );
  });

  Widget childWhenDisabledAlmostSquareInner(bool isFullScreen) {
    if (enableVerticalExpand) {
      return Obx(
        () {
          if (videoDetailController.isVertical.value && !isPortrait) {
            return childSplit(9 / 16);
          }

          return _childWhenDisabledAlmostSquareInner(isFullScreen);
        },
      );
    }

    return _childWhenDisabledAlmostSquareInner(isFullScreen);
  }

  Widget _childWhenDisabledAlmostSquareInner(bool isFullScreen) {
    final shouldShowSeasonPanel = _shouldShowSeasonPanel;
    final double height = maxHeight / 2.5;
    final videoHeight = isFullScreen ? maxHeight : height;
    final bottomHeight = maxHeight - height - padding.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: maxWidth,
          height: videoHeight,
          child: videoPlayer(
            width: maxWidth,
            height: videoHeight,
          ),
        ),
        Offstage(
          offstage: isFullScreen,
          child: SizedBox(
            width: maxWidth - padding.horizontal,
            height: bottomHeight,
            child: MiniScaffold(
              key: videoDetailController.childKey,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTabBar(needIndicator: false),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: videoIntro(
                            width: () {
                              double flex = 1;
                              if (videoDetailController.showReply) flex++;
                              if (shouldShowSeasonPanel) flex++;
                              return maxWidth / flex;
                            }(),
                            height: bottomHeight,
                          ),
                        ),
                        if (videoDetailController.showReply)
                          Expanded(child: videoReplyPanel()),
                        if (shouldShowSeasonPanel) Expanded(child: seasonPanel),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget manualPlayerWidget(double height) => Obx(() {
    if (!videoDetailController.autoPlay) {
      return Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: kToolbarHeight,
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 34,
                  child: IconButton(
                    tooltip: '返回',
                    icon: const Icon(
                      FontAwesomeIcons.arrowLeft,
                      size: 15,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 1.5,
                          color: Colors.black,
                        ),
                      ],
                    ),
                    onPressed: Get.back,
                  ),
                ),
                SizedBox(
                  width: 42,
                  height: 34,
                  child: IconButton(
                    tooltip: '返回主页',
                    icon: const Icon(
                      FontAwesomeIcons.house,
                      size: 15,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 1.5,
                          color: Colors.black,
                        ),
                      ],
                    ),
                    onPressed:
                        videoDetailController.plPlayerController.onCloseAll,
                  ),
                ),
                const Spacer(),
                _moreBtn(
                  Colors.white,
                  shadows: const [
                    Shadow(
                      blurRadius: 1.5,
                      color: Colors.black,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: height - 70,
            child: const PlayIcon(),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  });

  Widget _moreBtn(Color color, {List<Shadow>? shadows}) => PopupMenuButton(
    icon: Icon(
      size: 22,
      Icons.more_vert,
      color: color,
      shadows: shadows,
    ),
    itemBuilder: (BuildContext context) => <PopupMenuEntry>[
      PopupMenuItem(
        onTap: introController.viewLater,
        child: const Text('稍后再看'),
      ),
      if (videoDetailController.epId == null)
        PopupMenuItem(
          onTap: () => videoDetailController.showNoteList(context),
          child: const Text('查看笔记'),
        ),
      if (!videoDetailController.isFileSource)
        PopupMenuItem(
          onTap: () => videoDetailController.onDownload(this.context),
          child: const Text('缓存视频'),
        ),
      if (videoDetailController.cover.value.isNotEmpty)
        PopupMenuItem(
          onTap: () =>
              ImageUtils.downloadImg([videoDetailController.cover.value]),
          child: const Text('保存封面'),
        ),
      if (!videoDetailController.isFileSource && videoDetailController.isUgc)
        PopupMenuItem(
          onTap: videoDetailController.toAudioPage,
          child: const Text('听音频'),
        ),
      PopupMenuItem(
        onTap: () {
          if (!Accounts.main.isLogin) {
            SmartDialog.showToast('账号未登录');
          } else {
            PageUtils.reportVideo(videoDetailController.aid);
          }
        },
        child: const Text('举报'),
      ),
    ],
  );

  Widget plPlayer({
    required double width,
    required double height,
    bool isPipMode = false,
  }) => popScope(
    key: videoDetailController.videoPlayerKey,
    canPop:
        !isFullScreen &&
        !videoDetailController.plPlayerController.isDesktopPip &&
        (videoDetailController.horizontalScreen || isPortrait),
    onPopInvokedWithResult:
        videoDetailController.plPlayerController.onPopInvokedWithResult,
    child: Obx(
      () =>
          !videoDetailController.videoState.value ||
              !videoDetailController.autoPlay ||
              plPlayerController?.videoController == null
          ? const SizedBox.shrink()
          : PLVideoPlayer(
              maxWidth: width,
              maxHeight: height,
              plPlayerController: plPlayerController!,
              videoDetailController: videoDetailController,
              introController: introController,
              headerControl: HeaderControl(
                key: videoDetailController.headerCtrKey,
                isPortrait: isPortrait,
                controller: videoDetailController.plPlayerController,
                videoDetailCtr: videoDetailController,
                heroTag: heroTag,
              ),
              // 竖屏全屏时本页保留一条 padding.top 高的黑边（SimpleAppBar），
              // 隐藏状态栏后其高度即挖孔高度（鸿蒙见 HarmonyChannel.cutoutInsets），
              // 播放器整体已在挖孔之下，顶部控件/弹幕不再额外下移。
              danmuWidget: isPipMode && pipNoDanmaku
                  ? null
                  : Obx(
                      () => PlDanmaku(
                        key: ValueKey(videoDetailController.cid.value),
                        isPipMode: isPipMode,
                        cid: videoDetailController.cid.value,
                        playerController: plPlayerController!,
                        isFullScreen: plPlayerController!.isFullScreen.value,
                        isFileSource: videoDetailController.isFileSource,
                        size: Size(width, height),
                      ),
                    ),
              showEpisodes: showEpisodes,
              showViewPoints: showViewPoints,
            ),
    ),
  );

  late ThemeData theme;
  ColorScheme get colorScheme => theme.colorScheme;
  late bool isPortrait;
  late double maxWidth;
  late double maxHeight;
  bool isWindowMode = false;
  late EdgeInsets padding;

  /// 顶部间距固定值：首次捕获的状态栏高度（逻辑像素）。
  /// 状态栏显隐不再改变页面布局，避免旋转退出全屏时状态栏在动画末尾
  /// 显现导致画面下移。null 表示未捕获到（如移除安全边距场景），退化为 0。
  double? _fixedTopInset;

  /// 鸿蒙受限窗口（分屏/自由多窗/悬浮窗）内没有系统状态栏，但引擎仍会上报
  /// 设备状态栏高度。仅在全屏时顶部安全区应被移除（视频铺满窗口、plplayer
  /// 顶部控件/弹幕不再避让），非全屏仍按正常布局避让，故只作用于全屏路径。
  bool get _harmonyFullscreenNoSafeArea =>
      OS.isHarmony && HarmonyChannel.isWindowMode && isFullScreen;

  /// 「左视频 + 右侧栏」的横屏布局（childWhenDisabledLandscape）是否生效。
  bool get _usesLandscapeLayout =>
      videoDetailController.horizontalScreen &&
      maxWidth / maxHeight >= kScreenRatio;

  /// 「顶部视频 + 下方 Tab」的竖屏布局（childWhenDisabled）是否生效。
  /// 两者都不成立时为近方形布局（childWhenDisabledAlmostSquare）。
  /// 由 build 与 [_topBarIsDark] 共用，避免分支条件两处漂移。
  bool get _usesPortraitLayout =>
      !videoDetailController.horizontalScreen ||
      (!_usesLandscapeLayout &&
          maxWidth / Style.aspectRatio16x9 < 0.4 * maxHeight);

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (videoDetailController.plPlayerController.isPipMode) {
      child = plPlayer(width: maxWidth, height: maxHeight, isPipMode: true);
    } else if (_usesLandscapeLayout) {
      child = childWhenDisabledLandscape;
    } else if (_usesPortraitLayout) {
      child = childWhenDisabled;
    } else {
      child = childWhenDisabledAlmostSquare;
    }
    if (videoDetailController.plPlayerController.keyboardControl) {
      child = PlayerFocus(
        plPlayerController: videoDetailController.plPlayerController,
        introController: introController,
        onSendDanmaku: videoDetailController.showShootDanmakuSheet,
        canPlay: () {
          if (videoDetailController.autoPlay) {
            return true;
          }
          handlePlay();
          return false;
        },
        onSkipSegment: videoDetailController.onSkipSegment,
        child: child,
      );
    }
    Widget result = videoDetailController.plPlayerController.darkVideoPage
        ? Theme(data: theme, child: child)
        : child;
    if (_enableHero) {
      result = Hero(
        tag: heroTag,
        // Hero 动画期间，框架默认把 toHero 的 child 从树中移除（空
        // SizedBox 占位），详情页整棵子树（含播放器 State）会被 dispose。
        // 开启「提前加载播放器」时 queryVideoUrl 若在动画期间完成，
        // _initPlayerIfNeeded 因 videoPlayerKey.currentState 已卸载而跳过
        // 预初始化且不再重试，导致播放器初始化失败。用占位 Builder 保留
        // 子树（Offstage 隐藏 + 禁用 Ticker，与框架默认行为一致），让
        // 播放器 State 在动画期间保持挂载。
        placeholderBuilder: (context, size, child) => SizedBox(
          width: size.width,
          height: size.height,
          child: Offstage(
            offstage: true,
            child: TickerMode(enabled: false, child: child),
          ),
        ),
        child: RepaintBoundary(child: result),
      );
    }
    return result;
  }

  Widget buildTabBar({
    bool needIndicator = true,
    String? introText,
    bool showIntro = true,
    VoidCallback? onTap,
  }) {
    List<String> tabs = [
      if (showIntro)
        videoDetailController.isFileSource ? '离线视频' : introText ?? '简介',
      if (videoDetailController.showReply) '评论',
      if (_shouldShowSeasonPanel) '播放列表',
    ];
    if (videoDetailController.tabCtr.length != tabs.length) {
      videoDetailController.tabCtr.dispose();
      videoDetailController.tabCtr = TabController(
        vsync: videoDetailController,
        length: tabs.length,
        initialIndex: tabs.isEmpty
            ? 0
            : videoDetailController.tabCtr.index.clamp(0, tabs.length - 1),
      );
    }

    final flag = !needIndicator || tabs.length == 1;
    Widget tabBar() => TabBar(
      labelColor: flag ? colorScheme.onSurface : null,
      indicator: flag ? const BoxDecoration() : null,
      padding: EdgeInsets.zero,
      controller: videoDetailController.tabCtr,
      labelStyle:
          TabBarTheme.of(context).labelStyle?.copyWith(fontSize: 13) ??
          const TextStyle(fontSize: 13),
      labelPadding: const EdgeInsets.symmetric(horizontal: 10.0),
      dividerColor: Colors.transparent,
      dividerHeight: 0,
      onTap: (value) {
        void animToTop() {
          if (onTap != null) {
            onTap();
            return;
          }
          String text = tabs[value];
          if (videoDetailController.isFileSource ||
              text == '简介' ||
              text == '相关视频') {
            videoDetailController.introScrollCtr?.animToTop();
          } else if (text.startsWith('评论')) {
            _videoReplyController.animateToTop();
          }
        }

        if (flag) {
          animToTop();
        } else if (!videoDetailController.tabCtr.indexIsChanging) {
          animToTop();
        }
      },
      tabs: tabs.map((text) {
        if (text == '评论') {
          return Obx(() {
            final count = _videoReplyController.count.value;
            return Tab(
              text: '评论${count == -1 ? '' : ' ${NumUtils.numFormat(count)}'}',
            );
          });
        } else {
          return Tab(text: text);
        }
      }).toList(),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: SizedBox(
        height: 45,
        child: Row(
          children: [
            if (tabs.isEmpty)
              const Spacer()
            else
              Expanded(
                child: Align(
                  alignment: .centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 96.0 * tabs.length),
                    child: tabBar(),
                  ),
                ),
              ),
            SizedBox(
              height: 32,
              child: TextButton(
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(.zero),
                ),
                onPressed: videoDetailController.showShootDanmakuSheet,
                child: Text(
                  '发弹幕',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SizedBox.square(
              dimension: 38,
              child: Obx(
                () {
                  final ctr = videoDetailController.plPlayerController;
                  final enableShowDanmaku = ctr.enableShowDanmaku.value;
                  return IconButton(
                    onPressed: () {
                      final newVal = !enableShowDanmaku;
                      ctr.enableShowDanmaku.value = newVal;
                      if (!ctr.tempPlayerConf) {
                        GStorage.setting.put(
                          SettingBoxKey.enableShowDanmaku,
                          newVal,
                        );
                      }
                    },
                    icon: Icon(
                      size: 22,
                      enableShowDanmaku
                          ? CustomIcons.dm_on
                          : CustomIcons.dm_off,
                      color: enableShowDanmaku
                          ? colorScheme.secondary
                          : colorScheme.outline,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }

  Widget videoPlayer({required double width, required double height}) {
    final isFullScreen = this.isFullScreen;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            isAntiAlias: false,
          ),
        ),

        plPlayer(width: width, height: height),

        Obx(() {
          if (!videoDetailController.autoPlay) {
            return Positioned.fill(
              bottom: -1,
              child: GestureDetector(
                onTap: handlePlay,
                behavior: .opaque,
                child: Obx(
                  () => NetworkImgLayer(
                    type: .emote,
                    quality: 60,
                    src: videoDetailController.cover.value,
                    width: width,
                    height: height,
                    cacheWidth: true,
                    getPlaceHolder: () => Center(
                      child: Image.asset(Assets.loading),
                    ),
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }),
        manualPlayerWidget(height),

        if (videoDetailController.plPlayerController.enableBlock ||
            videoDetailController.continuePlayingPart)
          Positioned(
            left: 16,
            bottom: isFullScreen ? max(75, maxHeight * 0.25) : 75,
            width: MediaQuery.textScalerOf(context).scale(120),
            child: AnimatedList(
              padding: EdgeInsets.zero,
              key: videoDetailController.listKey,
              reverse: true,
              shrinkWrap: true,
              initialItemCount: videoDetailController.listData.length,
              itemBuilder: (context, index, animation) {
                return videoDetailController.buildItem(
                  videoDetailController.listData[index],
                  animation,
                );
              },
            ),
          ),

        // for debug
        // Positioned(
        //   right: 16,
        //   bottom: 75,
        //   child: FilledButton.tonal(
        //     onPressed: () {
        //       videoDetailController.onAddItem(
        //         SegmentModel(
        //           UUID: '',
        //           segmentType:
        //               SegmentType.values[Utils.random.nextInt(
        //                 SegmentType.values.length,
        //               )],
        //           segment: Pair(first: 0, second: 0),
        //           skipType: SkipType.alwaysSkip,
        //         ),
        //       );
        //     },
        //     child: const Text('skip'),
        //   ),
        // ),
        // Positioned(
        //   right: 16,
        //   bottom: 120,
        //   child: FilledButton.tonal(
        //     onPressed: () {
        //       videoDetailController.onAddItem(2);
        //     },
        //     child: const Text('index'),
        //   ),
        // ),
        Obx(
          () {
            if (videoDetailController.showSteinEdgeInfo.value) {
              try {
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: plPlayerController?.showControls.value == true
                          ? 75
                          : 16,
                    ),
                    child: Wrap(
                      spacing: 25,
                      runSpacing: 10,
                      children: videoDetailController
                          .steinEdgeInfo!
                          .edges!
                          .questions!
                          .first
                          .choices!
                          .map((item) {
                            return FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                shape: const RoundedRectangleBorder(
                                  borderRadius: .all(.circular(6)),
                                ),
                                backgroundColor: theme
                                    .colorScheme
                                    .secondaryContainer
                                    .withValues(alpha: 0.8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                ugcIntroController.onChangeEpisode(
                                  item,
                                  isStein: true,
                                );
                                videoDetailController.getSteinEdgeInfo(item.id);
                              },
                              child: Text(item.option!),
                            );
                          })
                          .toList(),
                    ),
                  ),
                );
              } catch (e) {
                if (kDebugMode) debugPrint('build stein edges: $e');
                return const SizedBox.shrink();
              }
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget localIntroPanel({
    bool needCtr = true,
  }) {
    return CustomScrollView(
      controller: needCtr
          ? videoDetailController.effectiveIntroScrollCtr
          : null,
      physics: !needCtr ? platformAlwaysClampingPhysics : null,
      key: const PageStorageKey(CommonIntroController),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 7, bottom: padding.bottom + 100),
          sliver: LocalIntroPanel(
            key: videoRelatedKey,
            heroTag: heroTag,
          ),
        ),
      ],
    );
  }

  Widget videoIntro({
    double? width,
    double? height,
    bool? isHorizontal,
    bool needRelated = true,
    bool needCtr = true,
  }) {
    if (videoDetailController.isFileSource) {
      return localIntroPanel(needCtr: needCtr);
    }
    Widget introPanel() {
      Widget child = CustomScrollView(
        key: const PageStorageKey(CommonIntroController),
        controller: needCtr
            ? videoDetailController.effectiveIntroScrollCtr
            : null,
        physics: !needCtr ? platformAlwaysClampingPhysics : null,
        slivers: [
          if (videoDetailController.isUgc) ...[
            UgcIntroPanel(
              key: videoIntroKey,
              heroTag: heroTag,
              showAiBottomSheet: showAiBottomSheet,
              showEpisodes: showEpisodes,
              onShowMemberPage: onShowMemberPage,
              isPortrait: isPortrait,
              isHorizontal: isHorizontal ?? width! / height! >= kScreenRatio,
            ),
            if (needRelated && videoDetailController.showRelatedVideo) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: Style.safeSpace,
                  ),
                  child: Divider(
                    height: 1,
                    indent: 12,
                    endIndent: 12,
                    color: colorScheme.outline.withValues(
                      alpha: 0.08,
                    ),
                  ),
                ),
              ),
              RelatedVideoPanel(key: videoRelatedKey, heroTag: heroTag),
            ],
          ] else
            PgcIntroPage(
              key: videoIntroKey,
              heroTag: heroTag,
              cid: videoDetailController.cid.value,
              showEpisodes: showEpisodes,
              showIntroDetail: showIntroDetail,
              maxWidth: width ?? maxWidth,
              isLandscape: !isPortrait,
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  (videoDetailController.isPlayAll && !isPortrait
                      ? 80
                      : Style.safeSpace) +
                  padding.bottom,
            ),
          ),
        ],
      );
      return KeepAliveWrapper(child: child);
    }

    if (videoDetailController.isPlayAll) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          introPanel(),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + padding.bottom,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => videoDetailController.showMediaListPanel(context),
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.95,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.playlist_play, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        videoDetailController.watchLaterTitle,
                        style: TextStyle(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.keyboard_arrow_up_rounded, size: 26),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return introPanel();
  }

  Widget get seasonPanel {
    final videoDetail = ugcIntroController.videoDetail.value;
    // 与 _shouldShowSeasonPanel 用同一判据，避免"入口显示了但内容取不到"
    final sections = videoDetail.ugcSeason?.sections ?? const <SectionItem>[];
    final hasSeason = _hasRenderableSeason(sections);
    return KeepAliveWrapper(
      child: Column(
        children: [
          if ((videoDetail.pages?.length ?? 0) > 1)
            if (hasSeason)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: PagesPanel(
                  heroTag: heroTag,
                  ugcIntroController: ugcIntroController,
                  bvid: ugcIntroController.bvid,
                  showEpisodes: showEpisodes,
                ),
              )
            else
              Expanded(
                child: Obx(
                  () => EpisodePanel(
                    heroTag: heroTag,
                    enableSlide: false,
                    ugcIntroController: videoDetailController.isUgc
                        ? ugcIntroController
                        : null,
                    type: EpisodeType.part,
                    list: [videoDetail.pages!],
                    cover: videoDetailController.cover.value,
                    bvid: videoDetailController.bvid,
                    aid: videoDetailController.aid,
                    cid: videoDetailController.cid.value,
                    isReversed: videoDetail.isPageReversed,
                    onChangeEpisode: videoDetailController.isUgc
                        ? ugcIntroController.onChangeEpisode
                        : pgcIntroController.onChangeEpisode,
                    showTitle: false,
                    isSupportReverse: videoDetailController.isUgc,
                    onReverse: () => onReversePlay(isSeason: false),
                    key: _seasonPartPanelKey,
                  ),
                ),
              ),
          if (hasSeason) ...[
            if ((videoDetail.pages?.length ?? 0) > 1) ...[
              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: colorScheme.outline.withValues(alpha: 0.1),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // key 必须在闭包内读取 videoDetail：SeasonPanel 的构造参数全是普通
              // 字段，闭包不读任何 Rx 时 GetX 会抛「improper use of a GetX」，
              // 而 RenderErrorBox 在高度无界的 Column 里会占满整列，表现为整个
              // 播放列表分栏变成灰块。竖屏那处（ugc/view.dart）本就是这么写的。
              // 同时合集数据换了也需要重建 State（episodes / seasonCid 有缓存）。
              child: Obx(
                () => SeasonPanel(
                  key: ValueKey(ugcIntroController.videoDetail.value),
                  heroTag: heroTag,
                  canTap: false,
                  showEpisodes: showEpisodes,
                  ugcIntroController: ugcIntroController,
                ),
              ),
            ),
            Expanded(
              child: Obx(
                () => EpisodePanel(
                  heroTag: heroTag,
                  enableSlide: false,
                  ugcIntroController: videoDetailController.isUgc
                      ? ugcIntroController
                      : null,
                  type: EpisodeType.season,
                  initialTabIndex: videoDetailController.seasonIndex.value,
                  cover: videoDetailController.cover.value,
                  seasonId: videoDetail.ugcSeason!.id,
                  list: sections,
                  bvid: videoDetailController.bvid,
                  aid: videoDetailController.aid,
                  cid: videoDetailController.seasonCid ?? 0,
                  isReversed: _seasonSectionReversed(sections),
                  onChangeEpisode: videoDetailController.isUgc
                      ? ugcIntroController.onChangeEpisode
                      : pgcIntroController.onChangeEpisode,
                  showTitle: false,
                  isSupportReverse: videoDetailController.isUgc,
                  onReverse: () => onReversePlay(isSeason: true),
                  key: _seasonPanelKey,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget videoReplyPanel({bool isNested = false}) => VideoReplyPanel(
    key: videoReplyPanelKey,
    isNested: isNested,
    heroTag: heroTag,
  );

  // ai总结
  void showAiBottomSheet() {
    videoDetailController.childKey.currentState?.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) =>
          AiConclusionPanel(item: ugcIntroController.aiConclusionResult!),
    );
  }

  void showIntroDetail(
    PgcInfoModel videoDetail,
    List<VideoTagItem>? videoTags,
  ) {
    videoDetailController.childKey.currentState?.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) => PgcIntroPanel(
        item: videoDetail,
        videoTags: videoTags,
      ),
    );
  }

  void showEpisodes([
    int? index,
    UgcSeason? season,
    List<ugc.BaseEpisodeItem>? episodes,
    String? bvid,
    int? aid,
    int? cid,
  ]) {
    assert((cid == null) == (bvid == null));
    final isFullScreen = this.isFullScreen;
    if (cid == null) {
      videoDetailController.showMediaListPanel(context);
      return;
    }
    Widget listSheetContent({bool enableSlide = true}) => EpisodePanel(
      heroTag: heroTag,
      ugcIntroController: videoDetailController.isUgc
          ? ugcIntroController
          : null,
      type: season != null
          ? EpisodeType.season
          : episodes is List<Part>
          ? EpisodeType.part
          : EpisodeType.pgc,
      cover: videoDetailController.cover.value,
      enableSlide: enableSlide,
      initialTabIndex: index ?? 0,
      bvid: bvid!,
      aid: aid,
      cid: cid,
      seasonId: season?.id,
      list: season != null ? season.sections! : [episodes],
      isReversed: !videoDetailController.isUgc
          ? null
          : season != null
          ? ugcIntroController
                .videoDetail
                .value
                .ugcSeason!
                .sections![videoDetailController.seasonIndex.value]
                .isReversed
          : ugcIntroController.videoDetail.value.isPageReversed,
      isSupportReverse: videoDetailController.isUgc,
      onChangeEpisode: videoDetailController.isUgc
          ? ugcIntroController.onChangeEpisode
          : pgcIntroController.onChangeEpisode,
      onClose: Get.back,
      onReverse: () {
        Get.back();
        onReversePlay(isSeason: season != null);
      },
    );
    if (isFullScreen || videoDetailController.showVideoSheet) {
      final child = listSheetContent(enableSlide: false);
      PageUtils.showVideoBottomSheet(
        context,
        child: videoDetailController.plPlayerController.darkVideoPage
            ? Theme(data: theme, child: child)
            : child,
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => listSheetContent(),
      );
    }
  }

  void onReversePlay({required bool isSeason}) {
    if (isSeason && videoDetailController.isPlayAll) {
      SmartDialog.showToast('当前为播放全部，合集不支持倒序');
      return;
    }

    final videoDetail = ugcIntroController.videoDetail.value;
    if (isSeason) {
      // reverse season
      final item = videoDetail
          .ugcSeason!
          .sections![videoDetailController.seasonIndex.value];
      item
        ..isReversed = !item.isReversed
        ..episodes = item.episodes!.reversed.toList();

      if (!videoDetailController.plPlayerController.reverseFromFirst) {
        // keep current episode
        videoDetailController
          ..seasonIndex.refresh()
          ..cid.refresh();
      } else {
        // switch to first episode
        final episode = ugcIntroController
            .videoDetail
            .value
            .ugcSeason!
            .sections![videoDetailController.seasonIndex.value]
            .episodes!
            .first;
        if (episode.cid != videoDetailController.cid.value) {
          ugcIntroController.onChangeEpisode(episode);
          videoDetailController.seasonCid = episode.cid;
        } else {
          videoDetailController
            ..seasonIndex.refresh()
            ..cid.refresh();
        }
      }
    } else {
      // reverse part
      videoDetail
        ..isPageReversed = !videoDetail.isPageReversed
        ..pages = videoDetail.pages!.reversed.toList();
      if (!videoDetailController.plPlayerController.reverseFromFirst) {
        // keep current episode
        videoDetailController.cid.refresh();
      } else {
        // switch to first episode
        final episode = videoDetail.pages!.first;
        if (episode.cid != videoDetailController.cid.value) {
          ugcIntroController.onChangeEpisode(episode);
        } else {
          videoDetailController.cid.refresh();
        }
      }
    }
  }

  void showViewPoints() {
    if (isFullScreen || videoDetailController.showVideoSheet) {
      final child = ViewPointsPage(
        enableSlide: false,
        videoDetailController: videoDetailController,
        plPlayerController: plPlayerController,
      );
      PageUtils.showVideoBottomSheet(
        context,
        child: videoDetailController.plPlayerController.darkVideoPage
            ? Theme(data: theme, child: child)
            : child,
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => ViewPointsPage(
          videoDetailController: videoDetailController,
          plPlayerController: plPlayerController,
        ),
      );
    }
  }

  void onShowMemberPage(int? mid) {
    videoDetailController.childKey.currentState?.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) {
        return HorizontalMemberPage(
          mid: mid,
          videoDetailController: videoDetailController,
          ugcIntroController: ugcIntroController,
        );
      },
    );
  }
}

class NoOverscrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
