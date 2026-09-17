import 'dart:async' show unawaited;
import 'dart:io' show File, Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart' show DetailItem;
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/live/live_room_info_h5/data.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_service/audio_service.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;

Future<VideoPlayerServiceHandler> initAudioService() {
  return AudioService.init(
    builder: VideoPlayerServiceHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.piliplus.audio',
      androidNotificationChannelName: 'Audio Service ${Constants.appName}',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
      androidNotificationChannelDescription: 'Media notification channel',
      androidNotificationIcon: 'drawable/ic_notification_icon',
    ),
  );
}

class VideoPlayerServiceHandler extends BaseAudioHandler with SeekHandler {
  VideoPlayerServiceHandler({bool? enableBackgroundPlay})
    : enableBackgroundPlay = enableBackgroundPlay ?? Pref.enableBackgroundPlay;

  factory VideoPlayerServiceHandler.local() =>
      VideoPlayerServiceHandler(enableBackgroundPlay: false);

  static final List<MediaItem> _item = [];
  bool enableBackgroundPlay;

  /// 当前循环模式（同步给系统播控中心/实况窗显示与切换）
  AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none;

  /// 实况窗/播控中心切换循环模式时回调给当前播放页
  Future<void> Function(PlayRepeat repeat)? onRepeatModeChanged;

  Future<void>? Function()? onPlay;
  Future<void>? Function()? onPause;
  Future<void>? Function(Duration position)? onSeek;
  Future<bool>? Function()? onSkipToNext;
  Future<bool>? Function()? onSkipToPrevious;

  @override
  Future<void> play() {
    return onPlay?.call() ??
        PlPlayerController.playIfExists() ??
        Future.syncValue(null);
    // player.play();
  }

  @override
  Future<void> pause() {
    return onPause?.call() ?? PlPlayerController.pauseIfExists();
    // player.pause();
  }

  @override
  Future<void> seek(Duration position) {
    playbackState.add(
      playbackState.value.copyWith(
        updatePosition: position,
      ),
    );
    return (onSeek?.call(position) ??
        PlPlayerController.seekToIfExists(position, isSeek: false));
    // await player.seekTo(position);
  }

  @override
  Future<void> skipToNext() async {
    await onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onSkipToPrevious?.call();
  }

  void setMediaItem(MediaItem newMediaItem) {
    if (!enableBackgroundPlay) return;
    // if (kDebugMode) {
    //   debugPrint("此时调用栈为：");
    //   debugPrint(newMediaItem);
    //   debugPrint(newMediaItem.title);
    //   debugPrint(StackTrace.current.toString());
    // }
    if (!mediaItem.isClosed) mediaItem.add(newMediaItem);
  }

  void setPlaybackState(PlayerStatus status, bool isBuffering, bool isLive) {
    if (!enableBackgroundPlay ||
        _item.isEmpty ||
        !PlPlayerController.instanceExists()) {
      return;
    }

    final AudioProcessingState processingState;
    if (status.isCompleted) {
      processingState = AudioProcessingState.completed;
    } else if (isBuffering) {
      processingState = AudioProcessingState.buffering;
    } else {
      processingState = AudioProcessingState.ready;
    }

    final playing = status.isPlaying || isBuffering;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: isBuffering
            ? AudioProcessingState.buffering
            : processingState,
        controls: [
          if (!isLive)
            const MediaControl(
              androidIcon: 'drawable/ic_player_rewind_10s',
              label: 'Rewind',
              action: MediaAction.rewind,
            ),
          if (!isLive)
            MediaControl.skipToPrevious.copyWith(
              androidIcon: 'drawable/ic_skip_previous',
            ),
          if (playing)
            const MediaControl(
              androidIcon: 'drawable/ic_player_pause',
              label: 'Pause',
              action: MediaAction.pause,
            )
          else
            const MediaControl(
              androidIcon: 'drawable/ic_player_play',
              label: 'Play',
              action: MediaAction.play,
            ),
          if (!isLive)
            MediaControl.skipToNext.copyWith(
              androidIcon: 'drawable/ic_skip_next',
            ),
          if (!isLive)
            const MediaControl(
              androidIcon: 'drawable/ic_player_fast_forward_10s',
              label: 'Fast Forward',
              action: MediaAction.fastForward,
            ),
        ],
        repeatMode: repeatMode,
        playing: playing,
        systemActions: const {
          MediaAction.seek,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
      ),
    );
    if (Platform.isAndroid &&
        (AndroidHelper.isPipMode ||
            PlPlayerController.instance!.isAutoEnterPip)) {
      AndroidHelper.updatePipActions(
        PlatformDispatcher.instance.engineId!,
        isLive,
        playing,
      );
    }
  }

  void onStatusChange(PlayerStatus status, bool isBuffering, isLive) {
    if (!enableBackgroundPlay) return;

    if (_item.isEmpty) return;
    setPlaybackState(status, isBuffering, isLive);
  }

  void onVideoDetailChange(
    dynamic data,
    int cid,
    String herotag, {
    String? artist,
    String? cover,
  }) {
    if (!enableBackgroundPlay) return;
    // if (kDebugMode) {
    //   debugPrint('当前调用栈为：');
    //   debugPrint(StackTrace.current);
    // }
    if (!PlPlayerController.instanceExists()) return;
    if (data == null) return;
    unawaited(
      _handleVideoDetailChange(data, cid, herotag, artist: artist, cover: cover),
    );
  }

  /// 应用侧循环模式变化时同步给播控中心
  void updateRepeatMode(PlayRepeat repeat) {
    final mode = switch (repeat) {
      PlayRepeat.singleCycle => AudioServiceRepeatMode.one,
      PlayRepeat.listCycle => AudioServiceRepeatMode.all,
      _ => AudioServiceRepeatMode.none,
    };
    if (mode == repeatMode) return;
    repeatMode = mode;
    playbackState.add(playbackState.value.copyWith(repeatMode: mode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    this.repeatMode = repeatMode;
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    final repeat = switch (repeatMode) {
      AudioServiceRepeatMode.one => PlayRepeat.singleCycle,
      AudioServiceRepeatMode.all => PlayRepeat.listCycle,
      _ => PlayRepeat.listOrder,
    };
    await onRepeatModeChanged?.call(repeat);
  }

  /// 优先复用项目图片缓存（cached_network_image_ce）中的封面文件并返回
  /// file:// 本地 URI：audio_service 对 file:// 的 artUri 会直接使用本地
  /// 文件，不会再走其内置的 flutter_cache_manager（DefaultCacheManager）
  /// 重新下载并写入 libCachedImageData。仅当该封面从未被加载过时才经
  /// CE 缓存管理器下载一次，之后均命中缓存。
  ///
  /// 使用与详情页播放器封面相同的压缩率（硬编码为60）
  /// 生成 URL：两者一致才能命中同一缓存 key，复用详情页已缓存的封面文件。
  Future<Uri> _artUriFromCache(String? cover) async {
    final url = ImageUtils.thumbnailUrl(
      cover,
      60,
    );
    if (url.isEmpty) return Uri();
    try {
      final file = await CacheManager.manager.getSingleFile(url);
      return file.absolute.uri;
    } catch (_) {
      return Uri.parse(url);
    }
  }

  Future<void> _handleVideoDetailChange(
    dynamic data,
    int cid,
    String herotag, {
    String? artist,
    String? cover,
  }) async {
    late final id = '$cid$herotag';
    final MediaItem mediaItem;
    switch (data) {
      case VideoDetailData(:final pages):
        if (pages != null && pages.length > 1) {
          final current = pages.firstWhereOrNull((e) => e.cid == cid);
          mediaItem = MediaItem(
            id: id,
            title: current?.part ?? '',
            artist: data.owner?.name,
            duration: Duration(seconds: current?.duration ?? 0),
            artUri: await _artUriFromCache(data.pic),
          );
        } else {
          mediaItem = MediaItem(
            id: id,
            title: data.title ?? '',
            artist: data.owner?.name,
            duration: Duration(seconds: data.duration ?? 0),
            artUri: await _artUriFromCache(data.pic),
          );
        }
      case EpisodeItem():
        mediaItem = MediaItem(
          id: id,
          title: data.showTitle ?? data.longTitle ?? data.title ?? '',
          artist: artist,
          duration: data.from == 'pugv'
              ? Duration(seconds: data.duration ?? 0)
              : Duration(milliseconds: data.duration ?? 0),
          artUri: await _artUriFromCache(data.cover),
        );
      case RoomInfoH5Data():
        mediaItem = MediaItem(
          id: id,
          title: data.roomInfo?.title ?? '',
          artist: data.anchorInfo?.baseInfo?.uname,
          artUri: await _artUriFromCache(data.roomInfo?.cover),
          isLive: true,
          // 设置直播间时长为0，解决鸿蒙因时长为null而不显示媒体组件
          duration: Duration.zero,
        );
      case Part():
        mediaItem = MediaItem(
          id: id,
          title: data.part ?? '',
          artist: artist,
          duration: Duration(seconds: data.duration ?? 0),
          artUri: await _artUriFromCache(cover),
        );
      case DetailItem(:final arc):
        mediaItem = MediaItem(
          id: id,
          title: arc.title,
          artist: data.owner.name,
          duration: Duration(seconds: arc.duration.toInt()),
          artUri: await _artUriFromCache(arc.cover),
        );
      case BiliDownloadEntryInfo():
        final coverFile = File(
          path.join(data.entryDirPath, PathUtils.coverName),
        );
        final artUri = coverFile.existsSync()
            ? coverFile.absolute.uri
            : await _artUriFromCache(data.cover);
        mediaItem = MediaItem(
          id: id,
          title: data.showTitle,
          artist: data.ownerName,
          duration: Duration(milliseconds: data.totalTimeMilli),
          artUri: artUri,
        );
      default:
        return;
    }
    // if (kDebugMode) debugPrint("exist: ${PlPlayerController.instanceExists()}");
    if (!PlPlayerController.instanceExists()) return;
    _item.add(mediaItem);
    setMediaItem(mediaItem);
  }

  void onVideoDetailDispose(String herotag) {
    if (!enableBackgroundPlay) return;

    if (_item.isNotEmpty) {
      _item.removeWhere((item) => item.id.endsWith(herotag));
    }
    if (_item.isNotEmpty) {
      playbackState.add(
        playbackState.value.copyWith(processingState: .ready, playing: false),
      );
      setMediaItem(_item.last);
      stop();
    }
  }

  void clear() {
    if (!enableBackgroundPlay) return;
    mediaItem.add(null);
    _item.clear();
    /**
     * if (playbackState.processingState == AudioProcessingState.idle &&
            previousState?.processingState != AudioProcessingState.idle) {
          await AudioService._stop();
        }
     */
    playbackState
      ..add(PlaybackState(processingState: .completed, playing: false))
      ..add(PlaybackState(processingState: .idle, playing: false));
  }

  void onPositionChange(Duration position) {
    if (!enableBackgroundPlay ||
        _item.isEmpty ||
        !PlPlayerController.instanceExists()) {
      return;
    }

    playbackState.add(playbackState.value.copyWith(updatePosition: position));
  }
}
