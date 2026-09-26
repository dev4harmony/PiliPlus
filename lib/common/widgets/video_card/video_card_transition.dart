import 'dart:async' show Completer;

import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const double _cardRadius = 12;

const double _scrimOpacity = 0.35;

const double _horizontalAspect = 1.35;

bool _isHorizontalFlight(Size card, Size viewport) =>
    card.width >= card.height * _horizontalAspect ||
    viewport.width > viewport.height;

const double _veilFadeEnd = 0.37;
const Curve _veilFadeCurve = Interval(
  0,
  _veilFadeEnd,
  curve: Curves.easeInOut,
);

const Curve _openCurve = Cubic(0.22, 0.77, 0.08, 1.0);

const Curve _openPortraitCurve = Cubic(0.28, 0.70, 0.12, 1.0);

Curve _openCurveFor(bool horizontal) =>
    horizontal ? _openCurve : _openPortraitCurve;

const Curve _closeCurve = Cubic(0.54, 0.15, 0.68, 0.95);

/// 卡片占位：进入时先显后隐、返回时后显
const Curve _cardFadeCurve = Interval(0.3, 1, curve: Curves.easeIn);

/// 入场进度到此值即认为页面已就位，播放页据此开始取流（0.5 ≈ 175ms）
const double _entryContentReadyAt = 0.5;

const Duration videoPageTransitionDuration = Duration(milliseconds: 350);
const Duration videoPageReverseTransitionDuration = Duration(milliseconds: 240);

const double _paintEpsilon = 0.02;

const bool _freezePageWhileFlying = true;

/// 播放页整页快照开关：置 false 即退回实时绘制（用于二分定位闪退）
const bool _snapshotVideoPage = true;

/// 快照分辨率上限：快照是一次性全屏光栅化，成本与 dpr² 成正比，
/// 故按 min(设备 dpr, 该值) 封顶（0 = 不限制）。
/// 快照只在转场期间显示，略微降采样换来的省时很划算。
const double _snapshotMaxPixelRatio = 1.6;

/// 同时允许存在的整屏快照总数。快照很吃 GPU 表面/缓冲，
/// 连点叠加时会同时存在多个（首页 + 退场页 + 进场页），
/// 名额用完的后来者直接退化为实时绘制。
const int _maxSnapshots = 3;

int _activeSnapshots = 0;

bool _acquireSnapshotSlot() {
  if (_activeSnapshots >= _maxSnapshots) return false;
  _activeSnapshots++;
  return true;
}

void _releaseSnapshotSlot() {
  if (_activeSnapshots > 0) _activeSnapshots--;
}

/// 新页面压上来时下层页面（首页）下沉的缩放幅度
const double _belowPageSinkScale = 0.07;

typedef _PendingVideoTransition = ({Object tag, RenderBox box});

_PendingVideoTransition? _pendingVideoTransition;
final _enteringVideoPages = <Object, Completer<bool>>{};

/// 卡片已被移出树（滚走/列表重建）时丢弃待用的矩形
void clearPendingVideoCardTransition(Object tag) {
  if (_pendingVideoTransition?.tag == tag) {
    _pendingVideoTransition = null;
  }
}

Future<bool> waitForVideoPageEntry(Object? tag) async {
  final entry = _enteringVideoPages[tag];
  if (entry == null) return true;
  return entry.future.timeout(
    const Duration(milliseconds: 1800),
    onTimeout: () => true,
  );
}

Color transitionBackgroundOf(BuildContext context) {
  Color? result;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    final Color? color = switch (widget) {
      Material(:final type, :final color)
          when type != MaterialType.transparency =>
        color ?? Theme.of(element).canvasColor,
      ColoredBox(:final color) => color,
      DecoratedBox(decoration: BoxDecoration(:final color)) => color,
      _ => null,
    };
    if (color != null && color.a == 1) {
      result = color;
      return false;
    }
    return true;
  });
  return result ?? Theme.of(context).scaffoldBackgroundColor;
}

bool hasPendingVideoCardTransition(Object tag) =>
    _pendingVideoTransition?.tag == tag;

/// 该 tag 的播放页是否仍在世（含正在退场）。
///
/// 用来避免"刚返回又立刻进入同一张卡片"时新页面复用同一个 GetX 控制器：
/// 旧路由 dispose 会按 key 删掉该控制器，新页面便会拿到已关闭的实例。
bool isVideoPageTransitionActive(Object tag) =>
    _enteringVideoPages.containsKey(tag);

/// 由卡片在 `onTap` 里调用，记录本次点击的卡片矩形
void prepareVideoCardTransition(Object tag, BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    _pendingVideoTransition = (tag: tag, box: box);
  }
}

/// 用自定义转场推入 `/videoV`；页面构造器取路由表，避免 utils 反向依赖 pages
Future<void>? pushVideoPageTransition({
  required Map arguments,
  bool off = false,
}) {
  final navigator = Get.key.currentState;
  final builder = Get.routeTree.matchRoute('/videoV').route?.page;
  if (navigator == null || builder == null) return null;
  final route = VideoPageTransitionRoute<void>(
    settings: RouteSettings(name: '/videoV', arguments: arguments),
    builder: (_) => builder(),
  );
  return off
      ? navigator.pushReplacement<void, void>(route)
      : navigator.push<void>(route);
}

class VideoPageTransitionRoute<T> extends GetPageRoute<T> {
  VideoPageTransitionRoute({required WidgetBuilder builder, super.settings})
    : super(page: () => Builder(builder: builder));

  bool _gestureCommitted = false;
  AnimationStatusListener? _gestureCompletion;
  final _entryReady = Completer<bool>();
  Object? get _entryTag => (settings.arguments as Map?)?['heroTag'];

  @override
  void install() {
    super.install();
    if (_entryTag case final tag?) _enteringVideoPages[tag] = _entryReady;
    controller
      ?..addStatusListener(_entryStatus)
      ..addListener(_entryProgress);
  }

  void _entryProgress() {
    final animationController = controller;
    if (animationController?.status == AnimationStatus.forward &&
        animationController!.value >= _entryContentReadyAt) {
      _finishEntry(true);
    }
  }

  void _entryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finishEntry(true);
  }

  void _finishEntry(bool entered) {
    if (!_entryReady.isCompleted) _entryReady.complete(entered);
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) _finishEntry(false);
    return popped;
  }

  @override
  void handleStartBackGesture({double progress = 0.0}) {
    _gestureCommitted = false;
    super.handleStartBackGesture(progress: progress);
  }

  @override
  void handleCommitBackGesture() {
    if (_gestureCommitted || !popGestureInProgress) return;
    _gestureCommitted = true;
    final owner = navigator;
    if (isCurrent) owner?.pop();
    final animationController = controller;
    void finish() {
      if (_gestureCompletion case final listener?) {
        animationController?.removeStatusListener(listener);
        _gestureCompletion = null;
      }
      if (owner?.userGestureInProgress == true) owner!.didStopUserGesture();
    }

    if (animationController?.isAnimating ?? false) {
      _gestureCompletion = (status) {
        if (status == AnimationStatus.dismissed ||
            status == AnimationStatus.completed) {
          finish();
        }
      };
      animationController!.addStatusListener(_gestureCompletion!);
    } else {
      finish();
    }
  }

  @override
  void dispose() {
    _finishEntry(false);
    controller
      ?..removeStatusListener(_entryStatus)
      ..removeListener(_entryProgress);
    if (identical(_enteringVideoPages[_entryTag], _entryReady)) {
      _enteringVideoPages.remove(_entryTag);
    }
    if (_gestureCompletion case final listener?) {
      controller?.removeStatusListener(listener);
    }
    super.dispose();
  }

  @override
  Duration get transitionDuration => videoPageTransitionDuration;

  @override
  Duration get reverseTransitionDuration => videoPageReverseTransitionDuration;

  /// 返回时窗口尺寸变了（旋转/折叠/分屏/小窗）：放弃一镜到底，
  /// 播放页改走默认的页面切换动画，下层也不再缩放
  bool heroDisabled = false;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _sinkBelowPage;

  /// 接管下层路由（首页）的出场过渡：带曲线地小幅缩小 = 下沉，反向即浮起。
  /// 注意用 [secondaryAnimation]（被本路由驱动），不是下层自己的 [animation]。
  Widget? _sinkBelowPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (child == null) return null;
    // 下层也是播放页（退场中又被点开新页面）时不加下沉：否则正在退场的
    // 播放页会被多套一层整屏快照 + 缩放
    if (ModalRoute.of(context)?.settings.name == '/videoV') return child;
    return _BelowPageSink(
      route: this,
      animation: secondaryAnimation,
      allowSnapshotting: allowSnapshotting,
      child: child,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => heroDisabled
      ? super.buildTransitions(context, animation, secondaryAnimation, child)
      : child;
}

/// 用受限于 [_snapshotMaxPixelRatio] 的像素比包一层快照。
///
/// 只改快照自身的栅格化 dpr，子树再还原成设备的真实 dpr
/// （否则会影响取图尺寸等）。
Widget _cappedSnapshot(
  BuildContext context,
  SnapshotController controller,
  Widget child,
) {
  final mediaQuery = MediaQuery.of(context);
  final dpr = mediaQuery.devicePixelRatio;
  final ratio = _snapshotMaxPixelRatio > 0 && dpr > _snapshotMaxPixelRatio
      ? _snapshotMaxPixelRatio
      : dpr;
  return MediaQuery(
    data: mediaQuery.copyWith(devicePixelRatio: ratio),
    child: SnapshotWidget(
      controller: controller,
      mode: SnapshotMode.permissive,
      autoresize: true,
      child: MediaQuery(data: mediaQuery, child: child),
    ),
  );
}

/// 下层页面（首页）的下沉 / 浮起。
///
/// 页面在飞行期间被 TickerMode 冻结、内容几乎不变，所以整页只栅格化一次：
/// 进入时生成，退出时直接复用，退场动画结束后随本 widget 一起释放。
class _BelowPageSink extends StatefulWidget {
  const _BelowPageSink({
    required this.route,
    required this.animation,
    required this.allowSnapshotting,
    required this.child,
  });

  /// 用于读取 [VideoPageTransitionRoute.heroDisabled]（放弃一镜到底时不再缩放）
  final VideoPageTransitionRoute route;

  final Animation<double> animation;
  final bool allowSnapshotting;
  final Widget child;

  @override
  State<_BelowPageSink> createState() => _BelowPageSinkState();
}

class _BelowPageSinkState extends State<_BelowPageSink> {
  final SnapshotController _controller = SnapshotController();
  bool _slotHeld = false;

  @override
  void initState() {
    super.initState();
    // 挂载即开、整个"播放页驻留期"都不关：
    // 进入时生成一次，退出时复用同一张，退场动画结束后本 widget 被卸载才释放
    _slotHeld = _acquireSnapshotSlot();
    _controller.allowSnapshotting = _slotHeld && widget.allowSnapshotting;
  }

  @override
  void didUpdateWidget(covariant _BelowPageSink oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.allowSnapshotting = _slotHeld && widget.allowSnapshotting;
  }

  @override
  void dispose() {
    if (_slotHeld) _releaseSnapshotSlot();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      // child 实例跨帧不变，且下面返回的包装结构恒定：
      // 结构一变（哪怕只是多套一层），下层页面的整棵 Element 会被重建
      child: widget.child,
      builder: (context, child) {
        final value = widget.animation.value;
        final t = value <= 0.001
            ? 0.0
            : (widget.animation.status == AnimationStatus.reverse
                  ? Curves.easeInCubic.transform(value)
                  : Curves.easeOutCubic.transform(value));
        return Transform.scale(
          scale: widget.route.heroDisabled ? 1 : 1 - _belowPageSinkScale * t,
          child: _cappedSnapshot(context, _controller, child!),
        );
      },
    );
  }
}

class VideoCardHero extends StatefulWidget {
  const VideoCardHero({
    super.key,
    required this.tag,
    required this.surfaceColor,
    required this.child,
    this.cornerRadius = _cardRadius,
  });

  final Object tag;

  final Color surfaceColor;
  final Widget child;

  final double cornerRadius;

  @override
  State<VideoCardHero> createState() => _VideoCardHeroState();
}

class _VideoCardHeroState extends State<VideoCardHero> {
  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.tag,
      curve: Curves.linear,
      reverseCurve: Curves.linear,
      transitionOnUserGestures: true,
      flightShuttleBuilder: _buildFlightShuttle,
      // 飞行期间原位显示卡片副本：进入时淡出、返回时淡入
      placeholderBuilder: _buildCardPlaceholder,
      child: _CardSurface(
        radius: widget.cornerRadius,
        cardColor: widget.surfaceColor,
        child: widget.child,
      ),
    );
  }

  static Widget _buildCardPlaceholder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    final animation = ModalRoute.of(context)?.secondaryAnimation;
    if (animation == null) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => Opacity(
        opacity: _cardFadeCurve.transform(1 - animation.value),
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    clearPendingVideoCardTransition(widget.tag);
    super.dispose();
  }
}

class VideoPageHeroTarget extends StatefulWidget {
  const VideoPageHeroTarget({
    super.key,
    required this.tag,
    required this.child,
  });

  final Object tag;
  final Widget child;

  @override
  State<VideoPageHeroTarget> createState() => _VideoPageHeroTargetState();
}

class _VideoPageHeroTargetState extends State<VideoPageHeroTarget> {
  ModalRoute<dynamic>? _route;
  Animation<double>? _routeAnimation;
  RenderBox? _sourceBox;
  Rect? _sourceRect;
  bool _entryCompleted = false;

  /// 进入时的视口尺寸：返回时若窗口尺寸变了（旋转/折叠/分屏/小窗），放弃动画
  Size? _sourceViewport;

  /// 飞行期间把整页内容栅格化成一张图，只缩放这张图
  final SnapshotController _snapshotController = SnapshotController();
  bool _snapshotOn = false;
  bool _snapshotSlotHeld = false;

  @override
  void initState() {
    super.initState();
    if (hasPendingVideoCardTransition(widget.tag)) {
      final box = _pendingVideoTransition!.box;
      // 取 cid 等异步流程期间卡片可能已被移出树，此时退化为普通进入
      if (box.attached && box.hasSize) {
        _sourceBox = box;
        _sourceRect = box.localToGlobal(Offset.zero) & box.size;
      }
      _pendingVideoTransition = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sourceRect == null) return;
    _route = ModalRoute.of(context);
    final animation = _route?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_handleAnimationStatus);
    _routeAnimation = animation;
    animation?.addStatusListener(_handleAnimationStatus);
    if (animation != null) _handleAnimationStatus(animation.status);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    // 只在飞行期间开快照；落地后恢复实时绘制（这时页面才需要被重绘）
    _setSnapshotting(_snapshotVideoPage && status.isAnimating);
    if (status == AnimationStatus.completed && _route?.offstage == false) {
      _entryCompleted = true;
    }
    final box = _sourceBox;
    if (status == AnimationStatus.reverse &&
        box != null &&
        box.attached &&
        box.hasSize) {
      _sourceRect = box.localToGlobal(Offset.zero) & box.size;
    }
  }

  /// 开/关整页快照；名额用完时退化为实时绘制（本次调用直接放弃）
  void _setSnapshotting(bool on) {
    if (on == _snapshotOn) return;
    if (on) {
      if (!_snapshotSlotHeld) {
        _snapshotSlotHeld = _acquireSnapshotSlot();
        if (!_snapshotSlotHeld) return;
      }
    } else if (_snapshotSlotHeld) {
      _releaseSnapshotSlot();
      _snapshotSlotHeld = false;
    }
    _snapshotOn = on;
    _snapshotController.allowSnapshotting = on;
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleAnimationStatus);
    if (_snapshotSlotHeld) _releaseSnapshotSlot();
    _snapshotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = _routeAnimation;
    if (_sourceRect == null || animation == null) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // 退化情况：视口为 0 时缩放比会变成 NaN
        if (size.isEmpty) return widget.child;
        final viewport = Offset.zero & size;
        // 每帧都要用到的原点在布局期算一次即可（本帧内不会变）
        final box = context.findRenderObject();
        final origin = box is RenderBox && box.hasSize
            ? box.localToGlobal(Offset.zero)
            : Offset.zero;
        final pageContent = SizedBox.fromSize(
          size: size,
          child: RepaintBoundary(child: widget.child),
        );
        // 进入时的视口尺寸：返回时用它判断窗口是否变过
        final sourceViewport = _sourceViewport ??= size;
        return AnimatedBuilder(
          animation: animation,
          child: pageContent,
          builder: (context, child) {
            final reversing =
                animation.status == AnimationStatus.reverse ||
                (_route?.popGestureInProgress ?? false);
            final returning = reversing && _entryCompleted;
            final source = _sourceRect!.shift(-origin);
            final horizontal = _isHorizontalFlight(_sourceRect!.size, size);
            final openCurve = _openCurveFor(horizontal);
            final expansion = openCurve.transform(animation.value);
            final contraction = _closeCurve.transform(1 - animation.value);
            // 页面矩形即唯一的转场载体：进入时从卡片展开，返回时收回卡片
            final pageRect = returning
                ? Rect.lerp(viewport, source, contraction)!
                : Rect.lerp(source, viewport, expansion)!;
            // 返回时窗口尺寸和进入时不一致（旋转/折叠/分屏/小窗）：卡片矩形
            // 已失真，放弃几何动画，交给路由的默认页面切换动画
            final fallback = returning && sourceViewport != size;
            if (fallback) {
              final route = _route;
              if (route is VideoPageTransitionRoute) route.heroDisabled = true;
            }
            final visualRect = fallback ? viewport : pageRect;
            final scrimAlpha = _scrimOpacity * expansion;
            // 全屏纯色压暗（比挖洞 Path 便宜）。动画结束后页面铺满视口，
            // 此时必须透明，否则会从页面圆角缺口透出黑边；
            // 走默认转场时也不需要它（否则黑罩会跟着转场一起动）
            final scrimVisible =
                !fallback &&
                animation.status != AnimationStatus.completed &&
                scrimAlpha > _paintEpsilon;
            final ticking =
                !_freezePageWhileFlying ||
                animation.status == AnimationStatus.completed;
            final pageContentChild = TickerMode(
              enabled: ticking,
              child: child!,
            );
            // 页面内容按视口尺寸静态布局，每帧只更新变换与裁剪；
            // 缩放比等价于 FittedBox(BoxFit.cover, topCenter)
            final scaleX = visualRect.width / size.width;
            final scaleY = visualRect.height / size.height;
            final pageScale = scaleX > scaleY ? scaleX : scaleY;
            // 平移 + 缩放合成一个矩阵，省掉一层 Transform
            final pageTransform = Matrix4.diagonal3Values(pageScale, pageScale, 1)
              ..setTranslationRaw(
                visualRect.left +
                    (visualRect.width - size.width * pageScale) / 2,
                visualRect.top,
                0,
              );
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  key: const ValueKey('video-transition-scrim'),
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: scrimVisible ? scrimAlpha : 0,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  key: const ValueKey('video-transition-page-position'),
                  child: ClipPath(
                    key: const ValueKey('video-transition-page-container'),
                    clipBehavior: Clip.hardEdge,
                    clipper: _PageRectClipper(visualRect),
                    // 快照按 1:1 栅格化，缩放只作用于纹理
                    child: Transform(
                      transform: pageTransform,
                      child: _cappedSnapshot(
                        context,
                        _snapshotController,
                        pageContentChild,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  key: const ValueKey('video-transition-hero-position'),
                  child: IgnorePointer(
                    child: Hero(
                      tag: widget.tag,
                      curve: Curves.linear,
                      reverseCurve: Curves.linear,
                      transitionOnUserGestures: true,
                      flightShuttleBuilder: _buildFlightShuttle,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 把整页内容裁到当前页面矩形（直角），使页面子树可以静态布局
class _PageRectClipper extends CustomClipper<Path> {
  const _PageRectClipper(this.rect);

  final Rect rect;

  @override
  Path getClip(Size size) => Path()..addRect(rect);

  @override
  bool shouldReclip(_PageRectClipper oldClipper) => oldClipper.rect != rect;
}

/// 卡片侧 Hero 的类型标记（[_buildFlightShuttle] 靠它识别），并携带飞行层的底色与圆角。
/// 不自己裁剪：卡片本体的 `Card(clipBehavior: Clip.hardEdge)` 已经裁过圆角。
class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.child,
    required this.cardColor,
    this.radius = _cardRadius,
  });

  final Widget child;
  final double radius;

  final Color cardColor;

  @override
  Widget build(BuildContext context) => child;
}

Offset _flightBoxOrigin(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero)
      : Offset.zero;
}

Widget _buildFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final returning = direction == HeroFlightDirection.pop;
  final cardContext = returning ? toHeroContext : fromHeroContext;
  final pageContext = returning ? fromHeroContext : toHeroContext;
  final cardHero = cardContext.widget;
  if (cardHero is! Hero || cardHero.child is! _CardSurface) {
    return const SizedBox.shrink();
  }
  final cardSurface = cardHero.child as _CardSurface;
  final cardBox = cardContext.findRenderObject();
  final pageBox = pageContext.findRenderObject();
  if (cardBox is! RenderBox || !cardBox.hasSize || cardBox.size.isEmpty) {
    return const SizedBox.shrink();
  }
  if (pageBox is! RenderBox || !pageBox.hasSize || pageBox.size.isEmpty) {
    return const SizedBox.shrink();
  }
  return _FlightCardLayer(
    animation: ModalRoute.of(pageContext)?.animation ?? animation,
    flightContext: flightContext,
    returning: returning,
    cardRect: cardBox.localToGlobal(Offset.zero) & cardBox.size,
    viewportRect: pageBox.localToGlobal(Offset.zero) & pageBox.size,
    cardColor: cardSurface.cardColor,
    radius: cardSurface.radius,
  );
}

class _FlightCardLayer extends StatefulWidget {
  const _FlightCardLayer({
    required this.animation,
    required this.flightContext,
    required this.returning,
    required this.cardRect,
    required this.viewportRect,
    required this.cardColor,
    required this.radius,
  });

  final Animation<double> animation;
  final BuildContext flightContext;

  final bool returning;

  final Rect cardRect;

  final Rect viewportRect;

  final Color cardColor;

  final double radius;

  @override
  State<_FlightCardLayer> createState() => _FlightCardLayerState();
}

class _FlightCardLayerState extends State<_FlightCardLayer> {
  late final BorderRadius _radius = BorderRadius.all(
    Radius.circular(widget.radius),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) {
        final progress = widget.animation.value;
        final horizontal = _isHorizontalFlight(
          widget.cardRect.size,
          widget.viewportRect.size,
        );
        // 只保留一层纯色面：进入时盖住卡片位置，避免页面被压缩进小矩形时穿帮
        final veilAlpha = widget.returning
            ? 0.0
            : 1 - _veilFadeCurve.transform(progress);
        if (veilAlpha <= _paintEpsilon) {
          return const SizedBox.shrink();
        }
        final openProgress = _openCurveFor(horizontal).transform(progress);
        final rect = Rect.lerp(
          widget.cardRect,
          widget.viewportRect,
          openProgress,
        )!;
        final flightOrigin = horizontal
            ? rect.topLeft
            : _flightBoxOrigin(widget.flightContext);
        final localRect = rect.shift(-flightOrigin);
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              key: const ValueKey('video-transition-card-layer'),
              rect: localRect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.cardColor.withValues(alpha: veilAlpha),
                  borderRadius: _radius,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
