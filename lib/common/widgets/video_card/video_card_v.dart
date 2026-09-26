import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_transition.dart';
import 'package:PiliPlus/common/widgets/video_popup_menu.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/dimension_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:intl/intl.dart';

// 视频卡片 - 垂直布局
class VideoCardV extends StatefulWidget {
  final BaseRcmdVideoItemModel videoItem;
  final VoidCallback? onRemove;

  /// 是否作为「一镜到底」转场的源卡片（仅首页推荐位开启）
  final bool enableHeroTransition;

  const VideoCardV({
    super.key,
    required this.videoItem,
    this.onRemove,
    this.enableHeroTransition = false,
  });

  static final shortFormat = DateFormat('M-d');
  static final longFormat = DateFormat('yy-M-d');

  @override
  State<VideoCardV> createState() => _VideoCardVState();
}

class _VideoCardVState extends State<VideoCardV> {
  BaseRcmdVideoItemModel get videoItem => widget.videoItem;
  VoidCallback? get onRemove => widget.onRemove;

  /// 转场标识：[Utils.makeHeroTag] 带随机后缀，必须只算一次并全程复用，
  /// 否则卡片与详情页的 tag 对不上，动画不会触发。
  String? _heroTag;

  /// 取详情页时的底色：只在依赖变化时算一次（原来每帧 build 都要走一遍祖先链）
  Color? _surfaceColor;

  /// `av` 分支要先异步取 cid，期间重复点击会 push 两个播放页
  bool _pushing = false;

  bool get _enableHero =>
      widget.enableHeroTransition && Pref.enableHeroCoverAnimation;

  String _makeHeroTag() =>
      Utils.makeHeroTag(videoItem.cid ?? videoItem.bvid ?? videoItem.aid);

  @override
  void initState() {
    super.initState();
    if (_enableHero) _heroTag = _makeHeroTag();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_heroTag != null) _surfaceColor = transitionBackgroundOf(context);
  }

  @override
  void didUpdateWidget(covariant VideoCardV oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableHeroTransition != oldWidget.enableHeroTransition ||
        !identical(oldWidget.videoItem, videoItem)) {
      _heroTag = _enableHero ? _makeHeroTag() : null;
    }
  }

  Future<void> onPushDetail() async {
    if (_pushing) return;
    _pushing = true;
    // 同 tag 的播放页还在世（刚返回、动画未结束）时不再共用这个 tag：
    // 否则两个页面共享同一个 GetX 控制器，旧页销毁会把新页的控制器一起删掉
    final tag = _heroTag;
    final useHero = tag != null && !isVideoPageTransitionActive(tag);
    // 记下本卡片的矩形供转场使用（替代卡片上的 onPointerDown Listener）
    if (useHero) prepareVideoCardTransition(tag, context);
    try {
      await _pushDetail(useHero: useHero);
    } finally {
      // 转场期间页面矩形之外仍可能漏进触摸，等动画结束再解锁
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _pushing = false;
      });
    }
  }

  Future<void> _pushDetail({required bool useHero}) async {
    switch (videoItem.goto) {
      case 'bangumi':
        PageUtils.viewPgc(epId: videoItem.param!);
        break;
      case 'av':
        var bvid = videoItem.bvid ?? IdUtils.av2bv(videoItem.aid!);
        var cid = videoItem.cid;
        bool isVertical = false;
        Dimension? dimension;
        if (videoItem is RcmdVideoItemAppModel) {
          if (videoItem.uri case final uri?) {
            isVertical = uri.isVerticalFromUri;
          }
        }
        if (cid == null) {
          if (await SearchHttp.ab2cWithDimension(aid: videoItem.aid, bvid: bvid)
              case final res?) {
            cid = res.cid;
            dimension = res.dimension;
          }
        }
        if (cid != null) {
          PageUtils.toVideoPage(
            aid: videoItem.aid,
            bvid: bvid,
            cid: cid,
            cover: videoItem.cover,
            title: videoItem.title,
            isVertical: isVertical,
            dimension: dimension,
            // 退化成普通进入时会由 toVideoPage 生成新的随机 tag
            heroTag: useHero ? _heroTag : null,
          );
        }
        break;
      // 动态
      case 'picture':
        try {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        } catch (err) {
          SmartDialog.showToast(err.toString());
        }
        break;
      default:
        if (videoItem.uri?.isNotEmpty == true) {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
    );
    Widget card = Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onPushDetail,
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverBuilder(
              cover: videoItem.cover,
              duration: videoItem.duration,
            ),
            content(context),
          ],
        ),
      ),
    );
    if (_heroTag case final heroTag?) {
      card = VideoCardHero(
        tag: heroTag,
        surfaceColor: _surfaceColor ??= transitionBackgroundOf(context),
        child: card,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        if (videoItem.goto == 'av')
          Positioned(
            right: -5,
            bottom: -2,
            width: 29,
            height: 29,
            child: VideoPopupMenu(
              iconSize: 17,
              videoItem: videoItem,
              onRemove: onRemove,
            ),
          ),
      ],
    );
  }

  Widget content(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                "${videoItem.title}\n",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  height: 1.38,
                ),
              ),
            ),
            videoStat(context, theme),
            Row(
              spacing: 2,
              children: [
                if (videoItem.goto == 'bangumi')
                  PBadge(
                    text: videoItem.pgcBadge,
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (videoItem.rcmdReason != null)
                  PBadge(
                    text: videoItem.rcmdReason,
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                if (videoItem.goto == 'picture')
                  const PBadge(
                    text: '动态',
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (videoItem.isFollowed)
                  const PBadge(
                    text: '已关注',
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                Expanded(
                  flex: 1,
                  child: Text(
                    videoItem.owner.name.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    semanticsLabel: 'UP：${videoItem.owner.name}',
                    style: TextStyle(
                      height: 1.5,
                      fontSize: theme.textTheme.labelMedium!.fontSize,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (videoItem.goto == 'av') const SizedBox(width: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget videoStat(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        StatWidget(
          type: StatType.play,
          value: videoItem.stat.view,
        ),
        if (videoItem.goto != 'picture') ...[
          const SizedBox(width: 4),
          StatWidget(
            type: StatType.danmaku,
            value: videoItem.stat.danmu,
          ),
        ],
        if (videoItem is RcmdVideoItemModel) ...[
          const Spacer(),
          Text(
            DateFormatUtils.dateFormat(
              videoItem.pubdate,
              short: VideoCardV.shortFormat,
              long: VideoCardV.longFormat,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: theme.textTheme.labelSmall!.fontSize,
              color: theme.colorScheme.outline.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 2),
        ],
        // deprecated
        //  else if (videoItem is RcmdVideoItemAppModel &&
        //     videoItem.desc != null &&
        //     videoItem.desc!.contains(' · ')) ...[
        //   const Spacer(),
        //   Text.rich(
        //     maxLines: 1,
        //     TextSpan(
        //         style: TextStyle(
        //           fontSize: theme.textTheme.labelSmall!.fontSize,
        //           color: theme.colorScheme.outline.withValues(alpha: 0.8),
        //         ),
        //         text: Utils.shortenChineseDateString(
        //             videoItem.desc!.split(' · ').last)),
        //   ),
        //   const SizedBox(width: 2),
        // ]
      ],
    );
  }
}

class _CoverBuilder extends StatelessWidget {
  const _CoverBuilder({
    required this.cover,
    required this.duration,
  });

  final String? cover;
  final int duration;

  // 缓存 builder 闭包，避免每次 rebuild 产生新实例触发 scheduleLayoutCallback
  static Widget _buildCover(
    BuildContext context,
    BoxConstraints constraints,
    String? cover,
    int duration,
  ) {
    final double maxWidth = constraints.maxWidth;
    final double maxHeight = constraints.maxHeight;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NetworkImgLayer(
          src: cover,
          width: maxWidth,
          height: maxHeight,
          borderRadius: BorderRadius.zero,
        ),
        if (duration > 0)
          PBadge(
            bottom: 6,
            right: 7,
            size: PBadgeSize.small,
            type: PBadgeType.gray,
            text: DurationUtils.formatDuration(duration),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CachedLayoutBuilder(
      cover: cover,
      duration: duration,
    );
  }
}

class _CachedLayoutBuilder extends StatefulWidget {
  const _CachedLayoutBuilder({
    required this.cover,
    required this.duration,
  });

  final String? cover;
  final int duration;

  @override
  State<_CachedLayoutBuilder> createState() => _CachedLayoutBuilderState();
}

class _CachedLayoutBuilderState extends State<_CachedLayoutBuilder> {
  BoxConstraints? _previousConstraints;
  Widget? _cachedChild;

  // 稳定的闭包实例，不会因父 rebuild 而改变
  late final Widget Function(BuildContext, BoxConstraints) _builder = _build;

  Widget _build(BuildContext context, BoxConstraints constraints) {
    // 约束未变时直接返回缓存，跳过子树重建
    if (_cachedChild != null && constraints == _previousConstraints) {
      return _cachedChild!;
    }
    _previousConstraints = constraints;
    _cachedChild = _CoverBuilder._buildCover(
      context,
      constraints,
      widget.cover,
      widget.duration,
    );
    return _cachedChild!;
  }

  @override
  void didUpdateWidget(_CachedLayoutBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据源变化时清除缓存，强制下次重建
    if (oldWidget.cover != widget.cover ||
        oldWidget.duration != widget.duration) {
      _cachedChild = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: Style.aspectRatio,
      child: LayoutBuilder(builder: _builder),
    );
  }
}
