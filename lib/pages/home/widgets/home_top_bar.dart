import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:get/get.dart';
import 'package:inspire_blur/inspire_blur.dart';
import 'package:material_ui/material_ui.dart';

/// 首页原生顶栏启用时的「渐变模糊 + 分类栏」悬浮层。
///
/// 原生顶栏（ArkTS）只保留沉浸光感搜索栏、沉浸光感私信按钮与头像（见
/// Index.ets 的 homeTopBar）；分类栏与它背后的渐变模糊搬到这里，因为只有
/// Flutter 拿得到列表的滚动状态，分类栏才能与列表联动。
///
/// 布局要点：
/// - 它是**悬浮**在列表之上的固定层，不占列表空间：视频卡片从屏幕顶部（含状态
///   栏区域）开始渲染，从分类栏下方透出。首屏内容不被遮住靠 [NativeTopSpacer]
///   在列表内注入的顶部留白，两者高度必须一致。
/// - 顶部留空 = 状态栏 + 原生搜索行高度，给 ArkTS 那一行让位；数值须与
///   Index.ets 的 TOP_BAR_CONTENT_HEIGHT 对齐。
/// - 模糊用 [Inspire.backdropBlur]（模糊**身后**的内容），叠在列表之上、分类栏
///   之下；分类栏自身没有底色，滑动时能透出被模糊过的视频。
/// - 滑动隐藏时**只收起 ArkTS 的搜索行**，分类栏保留并上移到状态栏下方，
///   悬浮层高度（含模糊带）跟着缩短。
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key});

  /// ArkTS 顶栏内容行高度（vp，不含状态栏）：搜索栏 / 私信 / 头像 + 上下外边距。
  /// 与 Index.ets 的 TOP_BAR_CONTENT_HEIGHT 一一对应，改一处必须改另一处。
  static const double contentHeight = 49;

  /// 分类栏区域高度（vp）：整块高度（页签文字约 28vp，其余是上下留白），
  /// 与未启用原生顶栏时 Flutter 自绘的分类栏观感保持一致
  static const double tabsHeight = 46;

  /// 悬浮层展开时的总高度（vp，不含状态栏）
  static const double height = contentHeight + tabsHeight;

  /// 模糊强度（sigma），与原生顶栏过去那条 linearGradientBlur 的观感对齐
  static const double blurSigma = 12;

  /// 模糊过渡的作用范围（相对悬浮层高度）。
  /// 取大于 1 的值让过渡延伸到悬浮层之外，模糊一直有效到分类栏那一段；
  /// 取 1.0 时刚好在悬浮层底边衰减到 0，分类栏那一段几乎看不到模糊。
  static const double blurExtent = 0.9;

  /// 背景色叠加的不透明度与作用范围。
  /// 作用范围与 [blurExtent] 相同：底色跟着模糊一起延伸到分类栏，两层的梯度
  /// 才不会在分类栏那一段脱节。
  static const double tintOpacity = 0.92;
  static const double tintExtent = blurExtent;

  /// 下滑隐藏 / 上滑展开的时长与曲线，与 Index.ets 的
  /// TOP_BAR_MOTION_DURATION / TOP_BAR_MOTION_CURVE 同源：
  /// 原生搜索行与这里的分类栏同时起步，才不会在收起过程中露出错位。
  static const Duration motionDuration = Duration(milliseconds: 300);
  static const Cubic motionCurve = Cubic(0.2, 0, 0, 1);

  @override
  Widget build(BuildContext context) {
    final homeController = Get.find<HomeController>();
    if (homeController.tabs.length <= 1) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final statusTop = MediaQuery.paddingOf(context).top;
    // 分类栏固定在悬浮层底部，与补间进度无关：作为 child 传进去，逐帧重建时
    // 复用同一个实例，页签子树不会跟着重建
    final tabBar = SizedBox(
      height: tabsHeight,
      // 撑满整宽：TabBar 的 tabAlignment: center 要按整行居中，
      // 否则列会按字面宽度收缩、整排页签跑到中间
      width: double.infinity,
      // 上下各留 4vp：指示器画在内容区最下沿，这 4vp 就是它到槽位底边的距离；
      // 页签文字与指示器的距离由每个页签自己的下边距决定（见 tabLabelBottomGap）
      child: TabBar(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        controller: homeController.tabController,
        // 页签内容在槽位里是整体垂直居中的（_TabBar 用 Center(heightFactor: 1.0)
        // 包住），所以给内容补一段下边距就能把文字顶上去：底部指示器画在内容区
        // 最下沿不动，文字到指示器的距离增加「下边距的一半」，上边距同步减少
        // 同样的量——即「单个页签加高」而槽位总高不变。
        tabs: homeController.tabs
            .map(
              (e) => Tab(
                child: Text(e.label),
              ),
            )
            .toList(),
        isScrollable: true,
        // 背景透明：透出下方视频
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        // 未选中页签用纯黑/纯白：底下是模糊过的视频，主题默认的灰在两种模式下
        // 都不够实。选中色仍走主题默认（ColorScheme.primary），与底部指示器
        // 一起表达选中态。
        unselectedLabelColor: theme.brightness == Brightness.dark
            ? Colors.white
            : Colors.black,
        // 去掉 MD3 点击页签时的扩散（水波纹）动画
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        tabAlignment: TabAlignment.center,
        onTap: (_) {
          feedBack();
          if (!homeController.tabController.indexIsChanging) {
            homeController.animateToTop();
          }
        },
      ),
    );
    return Obx(() {
      // 注意先读 Rx 再参与判断：写成 homeController.hideTopBar && xxx.value 时，
      // 关闭「滑动隐藏」会让 && 短路，Obx 一个 observable 都收不到，GetX 直接
      // 抛错（Obx 要求 builder 至少订阅一个 Rx）。
      final collapsed = homeController.topBarCollapsed.value;
      final hidden = homeController.hideTopBar && collapsed;
      // 自己驱动补间而不是用 AnimatedContainer：逐帧拿到进度，才能在每一帧上
      // 给模糊层换一个 layoutInvalidationKey（见 _BandBlur）
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: hidden ? 1.0 : 0.0),
        duration: motionDuration,
        curve: motionCurve,
        child: tabBar,
        builder: (context, t, tabBar) {
          final searchRowHeight = (1 - t) * contentHeight;
          return SizedBox(
            height: statusTop + searchRowHeight + tabsHeight,
            child: Stack(
              children: [
                // 渐变模糊：模糊身后的列表，随本层高度一起收缩
                Positioned.fill(child: _BandBlur(progress: t)),
                // 背景色叠加：用主题底色压一层，模糊过渡更自然
                Positioned.fill(
                  child: Inspire.tint.topToBottom(
                    color: theme.colorScheme.surface,
                    opacity: tintOpacity,
                    extent: tintExtent,
                    curve: Curves.easeOutSine,
                  ),
                ),
                Column(
                  children: [
                    SizedBox(height: statusTop),
                    // ArkTS 的搜索行那一格：收起时让它整行滑走，分类栏顺势上移
                    SizedBox(height: searchRowHeight),
                    tabBar!,
                  ],
                ),
              ],
            ),
          );
        },
      );
    });
  }
}

/// 悬浮层里的渐变模糊。
///
/// 单独抽出来，只为了逐帧喂 `layoutInvalidationKey`——inspire_blur 会把模糊
/// 作用区间的**屏幕矩形**烘进 shader，而它自己只在两种情况下重算：
/// 1. 画布矩阵变化（`_RenderPaintMatrixInterceptor`）；
/// 2. 所在路由的 `ModalRoute.animation` 走动。
///
/// 这两条正好漏掉顶栏会动的两种场景：
/// - 收起/放下只改高度，矩阵不变 → 矩形一直停在展开时的高度，模糊错乱；
/// - Cupertino 过场里本页是被推出的那一页，自己的 `animation` 恒为 1，
///   走的是 `secondaryAnimation` → 矩形停在过场中途，返回后只剩半边模糊。
///
/// 所以这里把「补间进度 + 路由两个动画的当前值」组合成 key：任一动画走动时
/// key 每帧都变，逼包重新测一次屏幕矩形。没有动画时 key 恒定，不会白重建。
class _BandBlur extends StatelessWidget {
  const _BandBlur({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([route?.animation, route?.secondaryAnimation]),
      builder: (context, _) => Inspire.backdropBlur(
        config: InspireBlurConfig.topToBottom(
          sigma: HomeTopBar.blurSigma,
          extent: HomeTopBar.blurExtent,
          fadeCurve: Curves.easeOutQuad,
        ),
        useRepaintBoundary: true,
        clipBehavior: Clip.none,
        layoutInvalidationKey: (
          progress,
          route?.animation?.value,
          route?.secondaryAnimation?.value,
        ),
      ),
    );
  }
}
