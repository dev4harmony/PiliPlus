import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/harmony_adapt/harmony_volume.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/ua_type.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/media_kit_adapt/media_kit_adapt.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/audio_normalization.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/models/common/super_resolution_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/user/danmaku_rule.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/video/video_shot/data.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/bottom_progress_behavior.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/plugin/pl_player/models/double_tap_type.dart';
import 'package:PiliPlus/plugin/pl_player/models/duration.dart';
import 'package:PiliPlus/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliPlus/plugin/pl_player/models/heart_beat_type.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension/box_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart' show PageUtils;
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:archive/archive.dart' show getCrc32;
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:dio/dio.dart' show Options;
import 'package:easy_debounce/easy_throttle.dart';
import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

class PlPlayerController {
  Player? _videoPlayerController;
  VideoController? _videoController;

  // 添加一个私有静态变量来保存实例
  static PlPlayerController? _instance;

  // 流事件  监听播放状态变化
  // StreamSubscription? _playerEventSubs;

  /// [playerStatus] has a [status] observable
  final playerStatus = PlPlayerStatus(PlayerStatus.playing);

  ///
  final PlPlayerDataStatus dataStatus = PlPlayerDataStatus();

  // bool controlsEnabled = false;

  /// 响应数据
  /// 带有Seconds的变量只在秒数更新时更新，以避免频繁触发重绘
  // 播放位置
  final Rx<Duration> position = Rx(Duration.zero);
  final RxInt positionSeconds = 0.obs;

  /// 进度条位置
  final Rx<Duration> sliderPosition = Rx(Duration.zero);
  final RxInt sliderPositionSeconds = 0.obs;
  // 展示使用
  final Rx<Duration> sliderTempPosition = Rx(Duration.zero);

  /// 视频时长
  final Rx<Duration> duration = Rx(Duration.zero);
  final Rx<Duration> durationSeconds = Duration.zero.obs;

  /// 视频缓冲
  final Rx<Duration> buffered = Rx(Duration.zero);
  final RxInt bufferedSeconds = 0.obs;

  int _playerCount = 0;

  late double lastPlaybackSpeed = 1.0;
  final RxDouble _playbackSpeed = Pref.playSpeedDefault.obs;
  late final RxDouble _longPressSpeed = Pref.longPressSpeedDefault.obs;

  /// 音量控制条
  final RxDouble volume = RxDouble(
    PlatformUtils.isDesktop ? Pref.desktopVolume : 1.0,
  );
  final setSystemBrightness = Pref.setSystemBrightness;

  /// 亮度控制条
  final RxDouble brightness = (-1.0).obs;

  /// 是否展示控制条
  final RxBool showControls = false.obs;

  /// 音量控制条展示/隐藏
  final RxBool showVolumeStatus = false.obs;

  /// 亮度控制条展示/隐藏
  final RxBool showBrightnessStatus = false.obs;

  /// 是否长按倍速
  final RxBool longPressStatus = false.obs;

  /// 屏幕锁 为true时，关闭控制栏
  final RxBool controlsLock = false.obs;

  /// 全屏状态
  final RxBool isFullScreen = false.obs;
  // 默认投稿视频格式
  bool isLive = false;

  bool _isVertical = false;

  /// 视频比例
  final Rx<VideoFitType> videoFit = Rx(VideoFitType.contain);

  StreamSubscription<DataStatus>? _dataListenerForVideoFit;
  StreamSubscription<DataStatus>? _dataListenerForEnterFullScreen;

  void _stopListenerForVideoFit() {
    _dataListenerForVideoFit?.cancel();
    _dataListenerForVideoFit = null;
  }

  void _stopListenerForEnterFullScreen() {
    _dataListenerForEnterFullScreen?.cancel();
    _dataListenerForEnterFullScreen = null;
  }

  /// 后台播放
  late final RxBool continuePlayInBackground =
      Pref.continuePlayInBackground.obs;

  ///
  final RxBool isSliderMoving = false.obs;

  /// 是否循环
  PlaylistMode _looping = PlaylistMode.none;
  bool _autoPlay = false;

  // 记录历史记录
  int? _aid;
  String? _bvid;
  int? cid;
  int? _epid;
  int? _seasonId;
  int? _pgcType;
  VideoType _videoType = VideoType.ugc;
  int _heartDuration = 0;
  int? width;
  int? height;

  late final tryLook = !Accounts.get(AccountType.video).isLogin && Pref.p1080;

  late DataSource dataSource;

  Timer? _timer;
  Timer? _timerForSeek;
  Timer? _timerForShowingVolume;

  Box setting = GStorage.setting;

  // final Durations durations;

  String get bvid => _bvid!;

  /// 视频播放速度
  double get playbackSpeed => _playbackSpeed.value;

  // 长按倍速
  double get longPressSpeed => _longPressSpeed.value;

  /// [videoPlayerController] instance of Player
  Player? get videoPlayerController => _videoPlayerController;

  /// [videoController] instance of Player
  VideoController? get videoController => _videoController;

  bool isMuted = false;

  /// 听视频
  late final RxBool onlyPlayAudio = false.obs;

  /// 镜像
  late final RxBool flipX = false.obs;

  late final RxBool flipY = false.obs;

  final RxBool isBuffering = true.obs;

  /// 全屏方向
  bool get isVertical => _isVertical;

  /// 弹幕开关
  late final RxBool _enableShowDanmaku = Pref.enableShowDanmaku.obs;
  late final RxBool _enableShowLiveDanmaku = Pref.enableShowLiveDanmaku.obs;
  RxBool get enableShowDanmaku =>
      isLive ? _enableShowLiveDanmaku : _enableShowDanmaku;

  late final bool autoPiP = Pref.autoPiP;
  bool get isPipMode =>
      ((Platform.isAndroid || PlatformUtils.isHarmony) &&
          Floating().isPipMode) ||
      (PlatformUtils.isDesktop && isDesktopPip);
  late bool isDesktopPip = false;
  late Rect _lastWindowBounds;

  late final RxBool isAlwaysOnTop = false.obs;
  Future<void> setAlwaysOnTop(bool value) {
    isAlwaysOnTop.value = value;
    return windowManager.setAlwaysOnTop(value);
  }

  Offset initialFocalPoint = Offset.zero;

  Future<void> exitDesktopPip() {
    isDesktopPip = false;
    return Future.wait([
      windowManager.setTitleBarStyle(TitleBarStyle.normal),
      windowManager.setMinimumSize(const Size(400, 700)),
      windowManager.setBounds(_lastWindowBounds),
      setAlwaysOnTop(false),
      windowManager.setAspectRatio(0),
    ]);
  }

  Future<void> enterDesktopPip() async {
    if (isFullScreen.value) return;

    isDesktopPip = true;

    _lastWindowBounds = await windowManager.getBounds();

    windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    late final Size size;
    final state = videoController!.player.state;
    final width = state.width ?? this.width ?? 16;
    final height = state.height ?? this.height ?? 9;
    if (height > width) {
      size = Size(280.0, 280.0 * height / width);
    } else {
      size = Size(280.0 * width / height, 280.0);
    }

    await windowManager.setMinimumSize(size);
    setAlwaysOnTop(true);
    windowManager
      ..setSize(size)
      ..setAspectRatio(width / height);
  }

  void toggleDesktopPip() {
    if (isDesktopPip) {
      exitDesktopPip();
    } else {
      enterDesktopPip();
    }
  }

  late bool _shouldSetPip = false;

  bool get _isCurrVideoPage {
    final currentRoute = Get.currentRoute;
    return currentRoute.startsWith('/video') ||
        currentRoute.startsWith('/liveRoom');
  }

  bool get _isPreviousVideoPage {
    final previousRoute = Get.previousRoute;
    return previousRoute.startsWith('/video') ||
        previousRoute.startsWith('/liveRoom');
  }

  void enterPip({bool isAuto = false}) {
    if (videoController != null) {
      final state = videoController!.player.state;
      PageUtils.enterPip(
        isAuto: isAuto,
        width: state.width ?? width,
        height: state.height ?? height,
      );
    }
  }

  void disableAutoEnterPipIfNeeded() {
    if (!_isPreviousVideoPage) {
      disableAutoEnterPip();
    }
  }

  void disableAutoEnterPip() {
    if (_shouldSetPip) {
      if (PlatformUtils.isHarmony) {
        Floating().setAutoPip(false);
      } else {
        Utils.channel.invokeMethod('setPipAutoEnterEnabled', {
          'autoEnable': false,
        });
      }
    }
  }

  // 弹幕相关配置
  late final enableTapDm = PlatformUtils.isMobile && Pref.enableTapDm;
  late RuleFilter filters = Pref.danmakuFilterRule;
  // 关联弹幕控制器
  DanmakuController<DanmakuExtra>? danmakuController;
  bool showDanmaku = true;
  Set<int> dmState = <int>{};
  late final mergeDanmaku = Pref.mergeDanmaku;
  late final String midHash = getCrc32(
    ascii.encode(Accounts.main.mid.toString()),
    0,
  ).toRadixString(16);
  late final RxDouble danmakuOpacity = Pref.danmakuOpacity.obs;

  late List<double> speedList = Pref.speedList;
  late bool enableAutoLongPressSpeed = Pref.enableAutoLongPressSpeed;
  late final showControlDuration = Pref.enableLongShowControl
      ? const Duration(seconds: 30)
      : const Duration(seconds: 3);
  // 字幕
  late double subtitleFontScale = Pref.subtitleFontScale;
  late double subtitleFontScaleFS = Pref.subtitleFontScaleFS;
  late int subtitlePaddingH = Pref.subtitlePaddingH;
  late int subtitlePaddingB = Pref.subtitlePaddingB;
  late double subtitleBgOpacity = Pref.subtitleBgOpacity;
  final bool showVipDanmaku = Pref.showVipDanmaku; // loop unswitching
  late double subtitleStrokeWidth = Pref.subtitleStrokeWidth;
  late int subtitleFontWeight = Pref.subtitleFontWeight;

  late final pgcSkipType = Pref.pgcSkipType;
  late final enablePgcSkip = Pref.pgcSkipType != SkipType.disable;
  // sponsor block
  late final bool enableSponsorBlock = Pref.enableSponsorBlock;
  late final bool enableBlock = enableSponsorBlock || enablePgcSkip;
  late final double blockLimit = Pref.blockLimit;
  late final blockSettings = Pref.blockSettings;
  late final List<Color> blockColor = Pref.blockColor;
  late final Set<String> enableList = blockSettings
      .where((item) => item.second != SkipType.disable)
      .map((item) => item.first.name)
      .toSet();

  // settings
  late final showFSActionItem = Pref.showFSActionItem;
  late final enableShrinkVideoSize = Pref.enableShrinkVideoSize;
  late final darkVideoPage = Pref.darkVideoPage;
  late final enableSlideVolumeBrightness = Pref.enableSlideVolumeBrightness;
  late final enableSlideFS = Pref.enableSlideFS;
  late final enableDragSubtitle = Pref.enableDragSubtitle;
  late final fastForBackwardDuration = Duration(
    seconds: Pref.fastForBackwardDuration,
  );

  late final horizontalSeasonPanel = Pref.horizontalSeasonPanel;
  late final preInitPlayer = Pref.preInitPlayer;
  late final showRelatedVideo = Pref.showRelatedVideo;
  late final showVideoReply = Pref.showVideoReply;
  late final showBangumiReply = Pref.showBangumiReply;
  late final reverseFromFirst = Pref.reverseFromFirst;
  late final horizontalPreview = Pref.horizontalPreview;
  late final showDmChart = Pref.showDmChart;
  late final showViewPoints = Pref.showViewPoints;
  late final showFsScreenshotBtn = Pref.showFsScreenshotBtn;
  late final showFsLockBtn = Pref.showFsLockBtn;
  late final keyboardControl = Pref.keyboardControl;

  late final bool autoExitFullscreen = Pref.autoExitFullscreen;
  late final bool autoPlayEnable = Pref.autoPlayEnable;
  late final bool enableVerticalExpand = Pref.enableVerticalExpand;
  late final bool pipNoDanmaku = Pref.pipNoDanmaku;

  late final bool tempPlayerConf = Pref.tempPlayerConf;

  late int? cacheVideoQa = PlatformUtils.isMobile ? null : Pref.defaultVideoQa;
  late int cacheAudioQa = Pref.defaultAudioQa;
  bool enableHeart = true;

  late final bool enableHA = Pref.enableHA;
  late final String hwdec = Pref.hardwareDecoding;

  late final progressType =
      BtmProgressBehavior.values[Pref.btmProgressBehavior];
  late final enableQuickDouble = Pref.enableQuickDouble;
  late final fullScreenGestureReverse = Pref.fullScreenGestureReverse;

  late final isRelative = Pref.useRelativeSlide;
  late final offset = isRelative
      ? Pref.sliderDuration / 100
      : Pref.sliderDuration * 1000;

  num get sliderScale =>
      isRelative ? duration.value.inMilliseconds * offset : offset;

  // 播放顺序相关
  late PlayRepeat playRepeat = PlayRepeat.values[Pref.playRepeat];

  TextStyle get subTitleStyle => TextStyle(
    height: 1.5,
    fontSize:
        16 * (isFullScreen.value ? subtitleFontScaleFS : subtitleFontScale),
    letterSpacing: 0.1,
    wordSpacing: 0.1,
    color: Colors.white,
    fontWeight: FontWeight.values[subtitleFontWeight],
    backgroundColor: subtitleBgOpacity == 0
        ? null
        : Colors.black.withValues(alpha: subtitleBgOpacity),
  );

  late final Rx<SubtitleViewConfiguration> subtitleConfig = _getSubConfig.obs;

  SubtitleViewConfiguration get _getSubConfig {
    final subTitleStyle = this.subTitleStyle;
    return SubtitleViewConfiguration(
      style: subTitleStyle,
      // TODO 鸿蒙待适配 strokeStyle media_kit
      // strokeStyle: subtitleBgOpacity == 0
      //     ? subTitleStyle.copyWith(
      //         color: null,
      //         background: null,
      //         backgroundColor: null,
      //         foreground: Paint()
      //           ..color = Colors.black
      //           ..style = PaintingStyle.stroke
      //           ..strokeWidth = subtitleStrokeWidth,
      //       )
      //     : null,
      padding: EdgeInsets.only(
        left: subtitlePaddingH.toDouble(),
        right: subtitlePaddingH.toDouble(),
        bottom: subtitlePaddingB.toDouble(),
      ),
      textScaler: TextScaler.noScaling,
    );
  }

  void updateSubtitleStyle() {
    subtitleConfig.value = _getSubConfig;
  }

  void onUpdatePadding(EdgeInsets padding) {
    subtitlePaddingB = padding.bottom.round().clamp(0, 200);
    putSubtitleSettings();
  }

  void updateSliderPositionSecond() {
    int newSecond = sliderPosition.value.inSeconds;
    if (sliderPositionSeconds.value != newSecond) {
      sliderPositionSeconds.value = newSecond;
    }
  }

  void updatePositionSecond() {
    int newSecond = position.value.inSeconds;
    if (positionSeconds.value != newSecond) {
      positionSeconds.value = newSecond;
    }
  }

  void updateDurationSecond() {
    if (durationSeconds.value != duration.value) {
      durationSeconds.value = duration.value;
    }
  }

  void updateBufferedSecond() {
    int newSecond = buffered.value.inSeconds;
    if (bufferedSeconds.value != newSecond) {
      bufferedSeconds.value = newSecond;
    }
  }

  static PlPlayerController? get instance => _instance;

  static bool instanceExists() {
    return _instance != null;
  }

  static void setPlayCallBack(Function? playCallBack) {
    _playCallBack = playCallBack;
  }

  static Function? _playCallBack;

  static void playIfExists({bool repeat = false, bool hideControls = true}) {
    // await _instance?.play(repeat: repeat, hideControls: hideControls);
    _playCallBack?.call();
  }

  // try to get PlayerStatus
  static PlayerStatus? getPlayerStatusIfExists() {
    return _instance?.playerStatus.value;
  }

  static Future<void> pauseIfExists({
    bool notify = true,
    bool isInterrupt = false,
  }) async {
    if (_instance?.playerStatus.value == PlayerStatus.playing) {
      await _instance?.pause(notify: notify, isInterrupt: isInterrupt);
    }
  }

  static Future<void> seekToIfExists(
    Duration position, {
    bool isSeek = true,
  }) async {
    await _instance?.seekTo(position, isSeek: isSeek);
  }

  static double? getVolumeIfExists() {
    return _instance?.volume.value;
  }

  static Future<void> setVolumeIfExists(double volumeNew) async {
    await _instance?.setVolume(volumeNew);
  }

  Box video = GStorage.video;

  // 添加一个私有构造函数
  PlPlayerController._() {
    if (!Accounts.heartbeat.isLogin || Pref.historyPause) {
      enableHeart = false;
    }

    if (autoPiP) {
      if (Platform.isAndroid) {
        Utils.sdkInt.then((sdkInt) {
          if (sdkInt < 31) {
            Utils.channel.setMethodCallHandler((call) async {
              if (call.method == 'onUserLeaveHint') {
                if (playerStatus.playing && _isCurrVideoPage) {
                  enterPip();
                }
              }
            });
          } else {
            _shouldSetPip = true;
          }
        });
      } else if (PlatformUtils.isHarmony) {
        _shouldSetPip = true;
      }
    }
  }

  // 获取实例 传参
  static PlPlayerController getInstance({bool isLive = false}) {
    // 如果实例尚未创建，则创建一个新实例
    _instance ??= PlPlayerController._();
    _instance!
      ..isLive = isLive
      .._playerCount += 1;
    return _instance!;
  }

  bool _processing = false;
  bool get processing => _processing;

  // offline
  bool isFileSource = false;
  String? dirPath;
  String? typeTag;
  int? mediaType;

  // 初始化资源
  Future<void> setDataSource(
    DataSource dataSource, {
    bool isLive = false,
    bool autoplay = true,
    // 默认不循环
    PlaylistMode looping = PlaylistMode.none,
    // 初始化播放位置
    Duration? seekTo,
    // 初始化播放速度
    double speed = 1.0,
    int? width,
    int? height,
    Duration? duration,
    // 方向
    bool? isVertical,
    // 记录历史记录
    int? aid,
    String? bvid,
    int? cid,
    int? epid,
    int? seasonId,
    int? pgcType,
    VideoType? videoType,
    VoidCallback? onInit,
    Volume? volume,
    String? dirPath,
    String? typeTag,
    int? mediaType,
  }) async {
    try {
      this.dirPath = dirPath;
      this.typeTag = typeTag;
      this.mediaType = mediaType;
      isFileSource = dataSource.type == DataSourceType.file;
      _processing = true;
      this.isLive = isLive;
      _videoType = videoType ?? VideoType.ugc;
      this.width = width;
      this.height = height;
      this.dataSource = dataSource;
      _autoPlay = autoplay;
      _looping = looping;
      // 初始化视频倍速
      // _playbackSpeed.value = speed;
      // 初始化数据加载状态
      dataStatus.status.value = DataStatus.loading;
      // 初始化全屏方向
      _isVertical = isVertical ?? false;
      _aid = aid;
      _bvid = bvid;
      this.cid = cid;
      _epid = epid;
      _seasonId = seasonId;
      _pgcType = pgcType;

      if (showSeekPreview) {
        _clearPreview();
      }
      cancelLongPressTimer();
      if (_videoPlayerController != null &&
          _videoPlayerController!.state.playing) {
        await pause(notify: false);
      }

      if (_playerCount == 0) {
        return;
      }
      // 配置Player 音轨、字幕等等
      _videoPlayerController = await _createVideoController(
        dataSource,
        _looping,
        seekTo,
        volume,
      );
      // 获取视频时长 00:00
      this.duration.value = duration ?? _videoPlayerController!.state.duration;
      position.value = buffered.value = sliderPosition.value =
          seekTo ?? Duration.zero;
      updateDurationSecond();
      updatePositionSecond();
      updateSliderPositionSecond();
      updateBufferedSecond();
      // 数据加载完成
      dataStatus.status.value = DataStatus.loaded;

      // listen the video player events
      startListeners();
      await _initializePlayer();
      onInit?.call();
    } catch (err, stackTrace) {
      dataStatus.status.value = DataStatus.error;
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
        debugPrint('plPlayer err:  $err');
      }
    } finally {
      _processing = false;
    }
  }

  String? shadersDirPath;
  Future<String> get copyShadersToExternalDirectory async {
    if (shadersDirPath != null) {
      return shadersDirPath!;
    }

    final dir = Directory(path.join(appSupportDirPath, 'anime_shaders'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final shaderFilesPath =
        (Constants.mpvAnime4KShaders + Constants.mpvAnime4KShadersLite)
            .map((e) => 'assets/shaders/$e')
            .toList();

    for (final filePath in shaderFilesPath) {
      final fileName = filePath.split('/').last;
      final targetFile = File(path.join(dir.path, fileName));
      if (targetFile.existsSync()) {
        continue;
      }

      try {
        final data = await rootBundle.load(filePath);
        final List<int> bytes = data.buffer.asUint8List();
        await targetFile.writeAsBytes(bytes);
      } catch (e) {
        if (kDebugMode) debugPrint('$e');
      }
    }
    return shadersDirPath = dir.path;
  }

  late final isAnim = _pgcType == 1 || _pgcType == 4;
  late final Rx<SuperResolutionType> superResolutionType =
      (isAnim ? Pref.superResolutionType : SuperResolutionType.disable).obs;
  Future<void> setShader([SuperResolutionType? type, NativePlayer? pp]) async {
    if (type == null) {
      type = superResolutionType.value;
    } else {
      superResolutionType.value = type;
      if (isAnim && !tempPlayerConf) {
        setting.put(SettingBoxKey.superResolutionType, type.index);
      }
    }
    pp ??= _videoPlayerController!.platform!.maybeAsNativePlayer;
    await pp.waitForPlayerInitialization;
    await pp.waitForVideoControllerInitializationIfAttached;
    switch (type) {
      case SuperResolutionType.disable:
        return pp.command(['change-list', 'glsl-shaders', 'clr', '']);
      case SuperResolutionType.efficiency:
        return pp.command([
          'change-list',
          'glsl-shaders',
          'set',
          PathUtils.buildShadersAbsolutePath(
            await copyShadersToExternalDirectory,
            Constants.mpvAnime4KShadersLite,
          ),
        ]);
      case SuperResolutionType.quality:
        return pp.command([
          'change-list',
          'glsl-shaders',
          'set',
          PathUtils.buildShadersAbsolutePath(
            await copyShadersToExternalDirectory,
            Constants.mpvAnime4KShaders,
          ),
        ]);
    }
  }

  static final loudnormRegExp = RegExp('loudnorm=([^,]+)');

  // 配置播放器
  Future<Player> _createVideoController(
    DataSource dataSource,
    PlaylistMode looping,
    Duration? seekTo,
    Volume? volume,
  ) async {
    // 每次配置时先移除监听
    removeListeners();
    isBuffering.value = false;
    buffered.value = Duration.zero;
    _heartDuration = 0;
    position.value = Duration.zero;
    // 初始化时清空弹幕，防止上次重叠
    danmakuController?.clear();

    Player player =
        _videoPlayerController ??
        Player(
          configuration: PlayerConfiguration(
            // 默认缓冲 4M 大小
            bufferSize: Pref.expandBuffer
                ? (isLive ? 64 * 1024 * 1024 : 32 * 1024 * 1024)
                : (isLive ? 16 * 1024 * 1024 : 4 * 1024 * 1024),
            logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
          ),
        );
    final pp = player.platform!.maybeAsNativePlayer;
    if (_videoPlayerController == null) {
      if (PlatformUtils.isDesktop) {
        pp.setVolume(this.volume.value * 100);
      }
      if (isAnim) {
        setShader(superResolutionType.value, pp);
      }
      await pp.setProperty("af", "scaletempo2=max-speed=8");
      if (Platform.isAndroid) {
        await pp.setProperty("volume-max", "100");
        String ao = Pref.useOpenSLES
            ? "opensles,audiotrack"
            : "audiotrack,opensles";
        await pp.setProperty("ao", ao);
      }
      // video-sync=display-resample
      await pp.setProperty("video-sync", Pref.videoSync);
      // vo=gpu-next & gpu-context=android & gpu-api=opengl
      // await pp.setProperty("vo", "gpu-next");
      // await pp.setProperty("gpu-context", "android");
      // await pp.setProperty("gpu-api", "opengl");
      await player.setAudioTrack(AudioTrack.auto());
      if (Pref.enableSystemProxy) {
        final systemProxyHost = Pref.systemProxyHost;
        final systemProxyPort = int.tryParse(Pref.systemProxyPort);
        if (systemProxyPort != null && systemProxyHost.isNotEmpty) {
          await pp.setProperty(
            "http-proxy",
            'http://$systemProxyHost:$systemProxyPort',
          );
        }
      }
    }

    // 音轨
    late final String audioUri;
    if (isFileSource) {
      audioUri = onlyPlayAudio.value || mediaType == 1
          ? ''
          : path.join(dirPath!, typeTag!, PathUtils.audioNameType2);
    } else if (dataSource.audioSource?.isNotEmpty == true) {
      audioUri = Platform.isWindows
          ? dataSource.audioSource!.replaceAll(';', '\\;')
          : dataSource.audioSource!.replaceAll(':', '\\:');
    } else {
      audioUri = '';
    }
    await pp.setProperty('audio-files', audioUri);

    _videoController ??= VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: enableHA,
        androidAttachSurfaceAfterVideoParameters: false,
        hwdec: enableHA ? hwdec : null,
      ),
    );

    player.setPlaylistMode(looping);

    final Map<String, String>? filters;
    if (Platform.isAndroid) {
      String audioNormalization = AudioNormalization.getParamFromConfig(
        Pref.audioNormalization,
      );
      if (volume != null && volume.isNotEmpty) {
        audioNormalization = audioNormalization.replaceFirstMapped(
          loudnormRegExp,
          (i) =>
              'loudnorm=${volume.format(
                Map.fromEntries(
                  i.group(1)!.split(':').map((item) {
                    final parts = item.split('=');
                    return MapEntry(parts[0].toLowerCase(), num.parse(parts[1]));
                  }),
                ),
              )}',
        );
      } else {
        audioNormalization = audioNormalization.replaceFirst(
          loudnormRegExp,
          AudioNormalization.getParamFromConfig(Pref.fallbackNormalization),
        );
      }
      filters = audioNormalization.isEmpty
          ? null
          : {'lavfi-complex': '"[aid1] $audioNormalization [ao]"'};
    } else {
      filters = null;
    }

    // if (kDebugMode) debugPrint(filters.toString());

    late final String videoUri;
    if (isFileSource) {
      videoUri = path.join(
        dirPath!,
        typeTag!,
        mediaType == 1
            ? PathUtils.videoNameType1
            : onlyPlayAudio.value
            ? PathUtils.audioNameType2
            : PathUtils.videoNameType2,
      );
    } else {
      videoUri = dataSource.videoSource!;
    }
    await player.open(
      Media(
        videoUri,
        httpHeaders: dataSource.httpHeaders,
        start: seekTo,
        extras: filters,
      ),
      play: false,
    );

    return player;
  }

  Future<bool> refreshPlayer() async {
    if (isFileSource) {
      return true;
    }
    if (_videoPlayerController == null) {
      // SmartDialog.showToast('视频播放器为空，请重新进入本页面');
      return false;
    }
    if (dataSource.videoSource.isNullOrEmpty) {
      SmartDialog.showToast('视频源为空，请重新进入本页面');
      return false;
    }
    if (!isLive) {
      if (dataSource.audioSource.isNullOrEmpty) {
        SmartDialog.showToast('音频源为空');
      } else {
        await (_videoPlayerController!.platform!).maybeAsNativePlayer
            .setProperty(
              'audio-files',
              Platform.isWindows
                  ? dataSource.audioSource!.replaceAll(';', '\\;')
                  : dataSource.audioSource!.replaceAll(':', '\\:'),
            );
      }
    }
    await _videoPlayerController!.open(
      Media(
        dataSource.videoSource!,
        httpHeaders: dataSource.httpHeaders,
        start: position.value,
      ),
      play: true,
    );
    return true;
    // seekTo(currentPos);
  }

  // 开始播放
  Future<void> _initializePlayer() async {
    if (_instance == null) return;
    // 设置倍速
    if (isLive) {
      await setPlaybackSpeed(1.0);
    } else {
      if (_videoPlayerController?.state.rate != _playbackSpeed.value) {
        await setPlaybackSpeed(_playbackSpeed.value);
      }
    }
    getVideoFit();
    // if (_looping) {
    //   await setLooping(_looping);
    // }

    // 跳转播放
    // if (seekTo != Duration.zero) {
    //   await this.seekTo(seekTo);
    // }

    // 自动播放
    if (_autoPlay) {
      playIfExists();
      // await play(duration: duration);
    }
  }

  late final bool enableAutoEnter = Pref.enableAutoEnter;
  Future<void> autoEnterFullscreen() async {
    if (enableAutoEnter) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (dataStatus.status.value != DataStatus.loaded) {
          _stopListenerForEnterFullScreen();
          _dataListenerForEnterFullScreen = dataStatus.status.listen((status) {
            if (status == DataStatus.loaded) {
              _stopListenerForEnterFullScreen();
              triggerFullScreen(status: true);
            }
          });
        } else {
          triggerFullScreen(status: true);
        }
      });
    }
  }

  Set<StreamSubscription> subscriptions = {};
  final Set<Function(Duration position)> _positionListeners = {};
  final Set<Function(PlayerStatus status)> _statusListeners = {};

  /// 播放事件监听
  void startListeners() {
    final controllerStream = videoPlayerController!.stream;
    subscriptions = {
      controllerStream.playing.listen((event) {
        WakelockPlus.toggle(enable: event);
        if (event) {
          if (_shouldSetPip) {
            if (_isCurrVideoPage) {
              enterPip(isAuto: true);
            } else {
              disableAutoEnterPip();
            }
          }
          playerStatus.value = PlayerStatus.playing;
        } else {
          disableAutoEnterPip();
          playerStatus.value = PlayerStatus.paused;
        }
        videoPlayerServiceHandler?.onStatusChange(
          playerStatus.value,
          isBuffering.value,
          isLive,
        );

        /// 触发回调事件
        for (final element in _statusListeners) {
          element(event ? PlayerStatus.playing : PlayerStatus.paused);
        }
        if (videoPlayerController!.state.position.inSeconds != 0) {
          makeHeartBeat(positionSeconds.value, type: HeartBeatType.status);
        }
      }),
      controllerStream.completed.listen((event) {
        if (event) {
          playerStatus.value = PlayerStatus.completed;

          /// 触发回调事件
          for (final element in _statusListeners) {
            element(PlayerStatus.completed);
          }
        } else {
          // playerStatus.value = PlayerStatus.playing;
        }
        makeHeartBeat(positionSeconds.value, type: HeartBeatType.completed);
      }),
      controllerStream.position.listen((event) {
        position.value = event;
        updatePositionSecond();
        if (!isSliderMoving.value) {
          sliderPosition.value = event;
          updateSliderPositionSecond();
        }

        /// 触发回调事件
        for (final element in _positionListeners) {
          element(event);
        }
        makeHeartBeat(event.inSeconds);
      }),
      controllerStream.duration.listen((Duration event) {
        duration.value = event;
      }),
      controllerStream.buffer.listen((Duration event) {
        buffered.value = event;
        updateBufferedSecond();
      }),
      controllerStream.buffering.listen((bool event) {
        isBuffering.value = event;
        videoPlayerServiceHandler?.onStatusChange(
          playerStatus.value,
          event,
          isLive,
        );
      }),
      if (kDebugMode)
        controllerStream.log.listen(((PlayerLog log) {
          if (log.level == 'error' || log.level == 'fatal') {
            Utils.reportError('${log.prefix}: ${log.text}', null);
          } else {
            debugPrint(log.toString());
          }
        })),
      controllerStream.error.listen((String event) {
        if (isFileSource && event.startsWith("Failed to open file")) {
          return;
        }
        if (isLive) {
          if (event.startsWith('tcp: ffurl_read returned ') ||
              event.startsWith("Failed to open https://") ||
              event.startsWith("Can not open external file https://")) {
            Future.delayed(const Duration(milliseconds: 3000), refreshPlayer);
          }
          return;
        }
        if (event.startsWith("Failed to open https://") ||
            event.startsWith("Can not open external file https://") ||
            //tcp: ffurl_read returned 0xdfb9b0bb
            //tcp: ffurl_read returned 0xffffff99
            event.startsWith('tcp: ffurl_read returned ')) {
          EasyThrottle.throttle(
            'controllerStream.error.listen',
            const Duration(milliseconds: 10000),
            () {
              Future.delayed(const Duration(milliseconds: 3000), () async {
                // if (kDebugMode) {
                //   debugPrint("isBuffering.value: ${isBuffering.value}");
                // }
                // if (kDebugMode) {
                //   debugPrint("_buffered.value: ${_buffered.value}");
                // }
                if (isBuffering.value && buffered.value == Duration.zero) {
                  SmartDialog.showToast(
                    '视频链接打开失败，重试中',
                    displayTime: const Duration(milliseconds: 500),
                  );
                  if (!await refreshPlayer()) {
                    if (kDebugMode) debugPrint("failed");
                  }
                }
              });
            },
          );
        } else if (event.startsWith('Could not open codec')) {
          SmartDialog.showToast('无法加载解码器, $event，可能会切换至软解');
        } else if (!onlyPlayAudio.value) {
          if (event.startsWith("error running") ||
              event.startsWith("Failed to open .") ||
              event.startsWith("Cannot open") ||
              event.startsWith("Can not open")) {
            return;
          }
          SmartDialog.showToast('视频加载错误, $event');
        }
      }),
      // controllerStream.volume.listen((event) {
      //   if (!mute.value && _volumeBeforeMute != event) {
      //     _volumeBeforeMute = event / 100;
      //   }
      // }),
      // 媒体通知监听
      if (videoPlayerServiceHandler != null) ...[
        playerStatus.listen((PlayerStatus event) {
          videoPlayerServiceHandler!.onStatusChange(
            event,
            isBuffering.value,
            isLive,
          );
        }),
        position.listen((Duration event) {
          EasyThrottle.throttle(
            'mediaServicePosition',
            const Duration(seconds: 1),
            () => videoPlayerServiceHandler!.onPositionChange(event),
          );
        }),
      ],
    };
  }

  /// 移除事件监听
  Future<void> removeListeners() {
    return Future.wait(subscriptions.map((e) => e.cancel()));
  }

  /// 跳转至指定位置
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {
    // if (position >= duration.value) {
    //   position = duration.value - const Duration(milliseconds: 100);
    // }
    if (_playerCount == 0) {
      return;
    }
    if (position < Duration.zero) {
      position = Duration.zero;
    }
    this.position.value = position;
    updatePositionSecond();
    _heartDuration = position.inSeconds;
    if (duration.value.inSeconds != 0) {
      if (isSeek) {
        /// 拖动进度条调节时，不等待第一帧，防止抖动
        await _videoPlayerController?.stream.buffer.first;
      }
      danmakuController?.clear();
      try {
        await _videoPlayerController?.seek(position);
      } catch (e) {
        if (kDebugMode) debugPrint('seek failed: $e');
      }
      // if (playerStatus.stopped) {
      //   play();
      // }
    } else {
      // if (kDebugMode) debugPrint('seek duration else');
      _timerForSeek?.cancel();
      _timerForSeek = Timer.periodic(const Duration(milliseconds: 200), (
        Timer t,
      ) async {
        //_timerForSeek = null;
        if (_playerCount == 0) {
          _timerForSeek?.cancel();
          _timerForSeek = null;
        } else if (duration.value.inSeconds != 0) {
          try {
            await _videoPlayerController?.stream.buffer.first;
            danmakuController?.clear();
            await _videoPlayerController?.seek(position);
          } catch (e) {
            if (kDebugMode) debugPrint('seek failed: $e');
          }
          // if (playerStatus.value == PlayerStatus.paused) {
          //   play();
          // }
          t.cancel();
          _timerForSeek = null;
        }
      });
    }
  }

  /// 设置倍速
  Future<void> setPlaybackSpeed(double speed) async {
    lastPlaybackSpeed = playbackSpeed;

    if (speed == _videoPlayerController?.state.rate) {
      return;
    }

    await _videoPlayerController?.setRate(speed);
    _playbackSpeed.value = speed;
    if (danmakuController != null) {
      try {
        DanmakuOption currentOption = danmakuController!.option;
        double defaultDuration = currentOption.duration * lastPlaybackSpeed;
        double defaultStaticDuration =
            currentOption.staticDuration * lastPlaybackSpeed;
        DanmakuOption updatedOption = currentOption.copyWith(
          duration: defaultDuration / speed,
          staticDuration: defaultStaticDuration / speed,
        );
        danmakuController!.updateOption(updatedOption);
      } catch (_) {}
    }
  }

  // 还原默认速度
  double playSpeedDefault = Pref.playSpeedDefault;
  Future<void> setDefaultSpeed() async {
    await _videoPlayerController?.setRate(playSpeedDefault);
    _playbackSpeed.value = playSpeedDefault;
  }

  /// 播放视频
  Future<void> play({bool repeat = false, bool hideControls = true}) async {
    if (_playerCount == 0) return;
    // 播放时自动隐藏控制条
    controls = !hideControls;
    // repeat为true，将从头播放
    if (repeat) {
      // await seekTo(Duration.zero);
      await seekTo(Duration.zero, isSeek: false);
    }

    await _videoPlayerController?.play();

    audioSessionHandler?.setActive(true);

    playerStatus.value = PlayerStatus.playing;
    // screenManager.setOverlays(false);
  }

  /// 暂停播放
  Future<void> pause({bool notify = true, bool isInterrupt = false}) async {
    await _videoPlayerController?.pause();
    playerStatus.value = PlayerStatus.paused;

    // 主动暂停时让出音频焦点
    if (!isInterrupt) {
      audioSessionHandler?.setActive(false);
    }
  }

  bool tripling = false;

  /// 隐藏控制条
  void hideTaskControls() {
    _timer?.cancel();
    _timer = Timer(showControlDuration, () {
      if (!isSliderMoving.value && !tripling) {
        controls = false;
      }
      _timer = null;
    });
  }

  /// 调整播放时间
  void onChangedSlider(double v) {
    sliderPosition.value = Duration(seconds: v.floor());
    updateSliderPositionSecond();
  }

  void onChangedSliderStart([Duration? value]) {
    if (value != null) {
      sliderTempPosition.value = value;
    }
    isSliderMoving.value = true;
  }

  bool? cancelSeek;
  bool? hasToast;

  void onUpdatedSliderProgress(Duration value) {
    sliderTempPosition.value = value;
    sliderPosition.value = value;
    updateSliderPositionSecond();
  }

  void onChangedSliderEnd() {
    if (cancelSeek != true) {
      feedBack();
    }
    cancelSeek = null;
    hasToast = null;
    isSliderMoving.value = false;
    hideTaskControls();
  }

  final RxBool volumeIndicator = false.obs;
  Timer? volumeTimer;
  final RxBool volumeInterceptEventStream = false.obs;

  static final double maxVolume = PlatformUtils.isDesktop ? 2.0 : 1.0;
  Future<void> setVolume(double volume) async {
    if (this.volume.value != volume) {
      this.volume.value = volume;
      try {
        if (PlatformUtils.isDesktop) {
          _videoPlayerController!.setVolume(volume * 100);
        } else if (PlatformUtils.isHarmony) {
          // 否则如果是鸿蒙手机和平板，按系统音量设置
          HarmonyVolumeView.cntlr.setVolume(volume);
        } else {
          FlutterVolumeController.updateShowSystemUI(false);
          await FlutterVolumeController.setVolume(volume);
        }
      } catch (err) {
        if (kDebugMode) debugPrint(err.toString());
      }
    }
    volumeIndicator.value = true;
    volumeInterceptEventStream.value = true;
    volumeTimer?.cancel();
    volumeTimer = Timer(const Duration(milliseconds: 200), () {
      volumeIndicator.value = false;
      volumeInterceptEventStream.value = false;
      if (PlatformUtils.isDesktop) {
        setting.put(SettingBoxKey.desktopVolume, volume.toPrecision(3));
      }
    });
  }

  void volumeUpdated() {
    if (PlatformUtils.isHarmony) {
      volumeIndicator.value = true;
      volumeTimer?.cancel();
      volumeTimer = Timer(const Duration(seconds: 1), () {
        volumeIndicator.value = false;
      });
      return;
    }
    showVolumeStatus.value = true;
    _timerForShowingVolume?.cancel();
    _timerForShowingVolume = Timer(const Duration(seconds: 1), () {
      showVolumeStatus.value = false;
    });
  }

  /// Toggle Change the videofit accordingly
  void toggleVideoFit(VideoFitType value) {
    videoFit.value = value;
    video.put(VideoBoxKey.cacheVideoFit, value.index);
  }

  /// 读取fit
  int fitValue = Pref.cacheVideoFit;
  Future<void> getVideoFit() async {
    var attr = VideoFitType.values[fitValue];
    // 由于none与scaleDown涉及视频原始尺寸，需要等待视频加载后再设置，否则尺寸会变为0，出现错误;
    if (attr == VideoFitType.none || attr == VideoFitType.scaleDown) {
      if (buffered.value == Duration.zero) {
        attr = VideoFitType.contain;
        _stopListenerForVideoFit();
        _dataListenerForVideoFit = dataStatus.status.listen((status) {
          if (status == DataStatus.loaded) {
            _stopListenerForVideoFit();
            final attr = VideoFitType.values[fitValue];
            if (attr == VideoFitType.none || attr == VideoFitType.scaleDown) {
              videoFit.value = attr;
            }
          }
        });
      }
      // fill不应该在竖屏视频生效
    } else if (attr == VideoFitType.fill && isVertical) {
      attr = VideoFitType.contain;
    }
    videoFit.value = attr;
  }

  /// 设置后台播放
  void setBackgroundPlay(bool val) {
    videoPlayerServiceHandler?.enableBackgroundPlay = val;
    if (!tempPlayerConf) {
      setting.put(SettingBoxKey.enableBackgroundPlay, val);
    }
  }

  set controls(bool visible) {
    showControls.value = visible;
    _timer?.cancel();
    if (visible) {
      hideTaskControls();
    }
  }

  Timer? longPressTimer;
  void cancelLongPressTimer() {
    longPressTimer?.cancel();
    longPressTimer = null;
  }

  /// 设置长按倍速状态 live模式下禁用
  Future<void> setLongPressStatus(bool val) async {
    if (isLive) {
      return;
    }
    if (controlsLock.value) {
      return;
    }
    if (longPressStatus.value == val) {
      return;
    }
    if (val) {
      if (playerStatus.value == PlayerStatus.playing) {
        longPressStatus.value = val;
        HapticFeedback.lightImpact();
        await setPlaybackSpeed(
          enableAutoLongPressSpeed ? playbackSpeed * 2 : longPressSpeed,
        );
      }
    } else {
      // if (kDebugMode) debugPrint('$playbackSpeed');
      longPressStatus.value = val;
      await setPlaybackSpeed(lastPlaybackSpeed);
    }
  }

  bool get _isCompleted =>
      videoPlayerController!.state.completed ||
      (duration.value - position.value).inMilliseconds <= 50;

  // 双击播放、暂停
  Future<void> onDoubleTapCenter() async {
    if (!isLive && _isCompleted) {
      await videoPlayerController!.seek(Duration.zero);
      videoPlayerController!.play();
    } else {
      videoPlayerController!.playOrPause();
    }
  }

  final RxBool mountSeekBackwardButton = false.obs;
  final RxBool mountSeekForwardButton = false.obs;

  void onDoubleTapSeekBackward() {
    mountSeekBackwardButton.value = true;
  }

  void onDoubleTapSeekForward() {
    mountSeekForwardButton.value = true;
  }

  void onForward(Duration duration) {
    onForwardBackward(position.value + duration);
  }

  void onBackward(Duration duration) {
    onForwardBackward(position.value - duration);
  }

  void onForwardBackward(Duration duration) {
    seekTo(
      duration.clamp(Duration.zero, videoPlayerController!.state.duration),
      isSeek: false,
    ).whenComplete(play);
  }

  void doubleTapFuc(DoubleTapType type) {
    if (!enableQuickDouble) {
      onDoubleTapCenter();
      return;
    }
    switch (type) {
      case DoubleTapType.left:
        // 双击左边区域 👈
        onDoubleTapSeekBackward();
        break;
      case DoubleTapType.center:
        onDoubleTapCenter();
        break;
      case DoubleTapType.right:
        // 双击右边区域 👈
        onDoubleTapSeekForward();
        break;
    }
  }

  /// 关闭控制栏
  void onLockControl(bool val) {
    feedBack();
    controlsLock.value = val;
    if (!val && showControls.value) {
      showControls.refresh();
    }
    controls = !val;
  }

  void toggleFullScreen(bool val) {
    isFullScreen.value = val;
    updateSubtitleStyle();
    if (!PlatformUtils.isHarmony) return;
    // 鸿蒙小窗适配方向

    if (val) {
      // 横向全屏需设置小窗横屏
      if (!isVertical) HarmonyChannel.setMiniWindowLandscape(true);
    } else {
      // 退出全屏取消鸿蒙小窗横屏
      HarmonyChannel.setMiniWindowLandscape(false);
    }
  }

  late bool isManualFS = true;
  late final FullScreenMode mode = FullScreenMode.values[Pref.fullScreenMode];
  late final horizontalScreen = Pref.horizontalScreen;

  // 全屏
  bool fsProcessing = false;
  Future<void> triggerFullScreen({
    bool status = true,
    bool inAppFullScreen = false,
    bool isManualFS = true,
    FullScreenMode? mode,
  }) async {
    if (isDesktopPip) return;
    if (isFullScreen.value == status) return;

    if (fsProcessing) {
      return;
    }
    fsProcessing = true;
    try {
      mode ??= this.mode;
      this.isManualFS = isManualFS;

      if (status) {
        if (PlatformUtils.isMobile) {
          hideStatusBar();
          if (mode == FullScreenMode.none) {
            return;
          }
          if (mode == FullScreenMode.gravity) {
            await fullAutoModeForceSensor();
            return;
          }
          late final size = MediaQuery.sizeOf(Get.context!);
          if ((mode == FullScreenMode.vertical ||
              (mode == FullScreenMode.auto && isVertical) ||
              (mode == FullScreenMode.ratio &&
                  (isVertical || size.height / size.width < kScreenRatio)))) {
            await verticalScreenForTwoSeconds();
          } else {
            await landscape();
          }
        } else {
          await enterDesktopFullscreen(inAppFullScreen: inAppFullScreen);
        }
      } else {
        if (PlatformUtils.isMobile) {
          showStatusBar();
          if (mode == FullScreenMode.none) {
            return;
          }
          if (!horizontalScreen) {
            await verticalScreenForTwoSeconds();
          } else {
            await autoScreen();
          }
        } else {
          await exitDesktopFullscreen();
        }
      }
    } finally {
      toggleFullScreen(status);
      fsProcessing = false;
    }
  }

  void addPositionListener(Function(Duration position) listener) =>
      _positionListeners.add(listener);
  void removePositionListener(Function(Duration position) listener) =>
      _positionListeners.remove(listener);
  void addStatusLister(Function(PlayerStatus status) listener) =>
      _statusListeners.add(listener);
  void removeStatusLister(Function(PlayerStatus status) listener) =>
      _statusListeners.remove(listener);

  /// 截屏
  Future<Uint8List?> screenshot() async {
    final Uint8List? screenshot = await _videoPlayerController!.screenshot(
      format: 'image/png',
    );
    return screenshot;
  }

  // 记录播放记录
  Future<void> makeHeartBeat(
    int progress, {
    HeartBeatType type = HeartBeatType.playing,
    bool isManual = false,
    dynamic aid,
    dynamic bvid,
    dynamic cid,
    dynamic epid,
    dynamic seasonId,
    dynamic pgcType,
    VideoType? videoType,
  }) async {
    if (isLive) {
      return;
    }
    if (!enableHeart || MineController.anonymity.value || progress == 0) {
      return;
    } else if (playerStatus.value == PlayerStatus.paused) {
      if (!isManual) {
        return;
      }
    }
    bool isComplete =
        playerStatus.value == PlayerStatus.completed ||
        type == HeartBeatType.completed;
    if ((durationSeconds.value - position.value).inMilliseconds > 1000) {
      isComplete = false;
    }
    // 播放状态变化时，更新

    if (type == HeartBeatType.status || type == HeartBeatType.completed) {
      await VideoHttp.heartBeat(
        aid: aid ?? _aid,
        bvid: bvid ?? _bvid,
        cid: cid ?? this.cid,
        progress: isComplete ? -1 : progress,
        epid: epid ?? _epid,
        seasonId: seasonId ?? _seasonId,
        subType: pgcType ?? _pgcType,
        videoType: videoType ?? _videoType,
      );
      return;
    }
    // 正常播放时，间隔5秒更新一次
    else if (progress - _heartDuration >= 5) {
      _heartDuration = progress;
      await VideoHttp.heartBeat(
        aid: aid ?? _aid,
        bvid: bvid ?? _bvid,
        cid: cid ?? this.cid,
        progress: progress,
        epid: epid ?? _epid,
        seasonId: seasonId ?? _seasonId,
        subType: pgcType ?? _pgcType,
        videoType: videoType ?? _videoType,
      );
    }
  }

  void setPlayRepeat(PlayRepeat type) {
    playRepeat = type;
    video.put(VideoBoxKey.playRepeat, type.index);
  }

  void putSubtitleSettings() {
    setting.putAllNE({
      SettingBoxKey.subtitleFontScale: subtitleFontScale,
      SettingBoxKey.subtitleFontScaleFS: subtitleFontScaleFS,
      SettingBoxKey.subtitlePaddingH: subtitlePaddingH,
      SettingBoxKey.subtitlePaddingB: subtitlePaddingB,
      SettingBoxKey.subtitleBgOpacity: subtitleBgOpacity,
      SettingBoxKey.subtitleStrokeWidth: subtitleStrokeWidth,
      SettingBoxKey.subtitleFontWeight: subtitleFontWeight,
    });
  }

  bool isCloseAll = false;
  Future<void> dispose() async {
    // 每次减1，最后销毁
    cancelLongPressTimer();
    if (!isCloseAll && _playerCount > 1) {
      _playerCount -= 1;
      _heartDuration = 0;
      if (!_isPreviousVideoPage) {
        pause();
      }
      return;
    }

    _playerCount = 0;
    danmakuController = null;
    _stopListenerForVideoFit();
    _stopListenerForEnterFullScreen();
    disableAutoEnterPip();
    setPlayCallBack(null);
    dmState.clear();
    if (showSeekPreview) {
      _clearPreview();
    }
    Utils.channel.setMethodCallHandler(null);
    _timer?.cancel();
    _timerForSeek?.cancel();
    _timerForShowingVolume?.cancel();
    // _position.close();
    // _playerEventSubs?.cancel();
    // _sliderPosition.close();
    // _sliderTempPosition.close();
    // _isSliderMoving.close();
    // _duration.close();
    // _buffered.close();
    // _showControls.close();
    // _controlsLock.close();

    // playerStatus.close();
    // dataStatus.status.close();

    if (PlatformUtils.isDesktop && isAlwaysOnTop.value) {
      windowManager.setAlwaysOnTop(false);
    }

    await removeListeners();
    subscriptions.clear();
    _positionListeners.clear();
    _statusListeners.clear();
    if (playerStatus.playing) {
      WakelockPlus.disable();
    }
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _videoController = null;
    _instance = null;
    videoPlayerServiceHandler?.clear();
  }

  static void updatePlayCount() {
    if (_instance?._playerCount == 1) {
      _instance?.dispose();
    } else {
      _instance?._playerCount -= 1;
    }
  }

  void setContinuePlayInBackground() {
    continuePlayInBackground.value = !continuePlayInBackground.value;
    if (!tempPlayerConf) {
      setting.put(
        SettingBoxKey.continuePlayInBackground,
        continuePlayInBackground.value,
      );
    }
  }

  void setOnlyPlayAudio() {
    onlyPlayAudio.value = !onlyPlayAudio.value;
    videoPlayerController?.setVideoTrack(
      onlyPlayAudio.value ? VideoTrack.no() : VideoTrack.auto(),
    );
  }

  late final Map<String, ui.Image?> previewCache = {};
  LoadingState<VideoShotData>? videoShot;
  late final RxBool showPreview = false.obs;
  late final showSeekPreview = Pref.showSeekPreview;
  late final previewIndex = RxnInt();

  void updatePreviewIndex(int seconds) {
    if (videoShot == null) {
      videoShot = LoadingState.loading();
      getVideoShot();
      return;
    }
    if (videoShot case Success(:final response)) {
      if (!showPreview.value) {
        showPreview.value = true;
      }
      previewIndex.value = max(
        0,
        (response.index.where((item) => item <= seconds).length - 2),
      );
    }
  }

  void _clearPreview() {
    showPreview.value = false;
    previewIndex.value = null;
    videoShot = null;
    for (final i in previewCache.values) {
      i?.dispose();
    }
    previewCache.clear();
  }

  Future<void> getVideoShot() async {
    try {
      final res = await Request().get(
        '/x/player/videoshot',
        queryParameters: {
          // 'aid': IdUtils.bv2av(_bvid),
          'bvid': _bvid,
          'cid': cid,
          'index': 1,
        },
        options: Options(
          headers: {
            'user-agent': UaType.pc.ua,
            'referer': 'https://www.bilibili.com/video/$bvid',
          },
        ),
      );
      if (res.data['code'] == 0) {
        final data = VideoShotData.fromJson(res.data['data']);
        if (data.index.isNotEmpty) {
          videoShot = Success(data);
          return;
        }
      }
      videoShot = const Error(null);
    } catch (e) {
      videoShot = const Error(null);
      if (kDebugMode) debugPrint('getVideoShot: $e');
    }
  }

  void takeScreenshot() {
    SmartDialog.showToast('截图中');
    videoPlayerController?.screenshot(format: 'image/png').then((value) {
      if (value != null) {
        SmartDialog.showToast('点击弹窗保存截图');
        showDialog(
          context: Get.context!,
          builder: (context) => GestureDetector(
            onTap: () {
              Get.back();
              ImageUtils.saveByteImg(
                bytes: value,
                fileName: 'screenshot_${ImageUtils.time}',
              );
            },
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: min(Get.width / 3, 350),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        width: 5,
                        color: Get.theme.colorScheme.surface,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Image.memory(value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        SmartDialog.showToast('截图失败');
      }
    });
  }
}
