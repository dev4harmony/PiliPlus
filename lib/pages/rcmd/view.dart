import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/native_top_spacer.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:os_type/os_type.dart';

class RcmdPage extends StatefulWidget {
  const RcmdPage({super.key});

  @override
  State<RcmdPage> createState() => _RcmdPageState();
}

class _RcmdPageState extends State<RcmdPage>
    with AutomaticKeepAliveClientMixin {
  final RcmdController controller = Get.put(RcmdController());

  Worker? _fillWorker;

  @override
  void initState() {
    super.initState();
    controller.scrollController.addListener(_onScroll);
    // 大屏多列下一页数据可能填不满视口：此时列表不可滚动，_onScroll 永远不会
    // 触发，页面就一直空着下半屏，只有手动下拉刷新才会变多。每次数据变化后
    // 补一次判断，不可滚动就继续拉下一页，直到出现可滚动区域。
    _fillWorker = ever(controller.loadingState, (_) => _fillViewport());
  }

  void _fillViewport() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller.isLoading) return;
      // 只在已有数据时续拉：错误态下列表同样不可滚动，重试交给 HttpError
      if (controller.loadingState.value.dataOrNull?.isNotEmpty != true) return;
      final scrollController = controller.scrollController;
      if (scrollController.hasClients &&
          scrollController.position.maxScrollExtent <= 0) {
        controller.onLoadMore();
      }
    });
  }

  void _onScroll() {
    if (!controller.scrollController.hasClients || controller.isLoading) return;
    final position = controller.scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 1000) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => controller.onLoadMore(),
      );
    }
  }

  @override
  void dispose() {
    _fillWorker?.dispose();
    controller.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);
    return Container(
      clipBehavior: OS.isHarmony ? Clip.none : Clip.hardEdge,
      margin: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(borderRadius: Style.mdRadius),
      child: NativeTopRefreshIndicator(
        onRefresh: controller.onRefresh,
        child: CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          cacheExtent: 800,
          slivers: [
            // 原生顶栏启用时顶部的可滚动留白（内容可滑入顶栏下方重合）
            const NativeTopSpacer(),
            SliverPadding(
              padding: const .only(top: Style.cardSpace, bottom: 100),
              sliver: Obx(
                () => _buildBody(colorScheme, controller.loadingState.value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Pref.recommendCardWidth,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
  );

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<dynamic>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => _buildSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  if (controller.lastRefreshAt != null) {
                    if (controller.lastRefreshAt == index) {
                      return GestureDetector(
                        onTap: () => controller
                          ..animateToTop()
                          ..onRefresh(),
                        child: Card(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const .symmetric(horizontal: 10),
                            child: Text(
                              '上次看到这里\n点击刷新',
                              textAlign: .center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final actualIndex = index > controller.lastRefreshAt!
                        ? index - 1
                        : index;
                    final item = response[actualIndex];
                    return VideoCardV(
                      key: ValueKey(
                        '${item.goto}_${item.bvid ?? item.param ?? item.uri}',
                      ),
                      videoItem: item,
                      onRemove: () {
                        if (controller.lastRefreshAt != null &&
                            actualIndex < controller.lastRefreshAt!) {
                          controller.lastRefreshAt =
                              controller.lastRefreshAt! - 1;
                        }
                        controller.loadingState
                          ..value.data!.remove(item)
                          ..refresh();
                      },
                    );
                  } else {
                    final item = response[index];
                    return VideoCardV(
                      key: ValueKey(
                        '${item.goto}_${item.bvid ?? item.param ?? item.uri}',
                      ),
                      videoItem: item,
                      onRemove: () => controller.loadingState
                        ..value.data!.remove(item)
                        ..refresh(),
                    );
                  }
                },
                itemCount: controller.lastRefreshAt != null
                    ? response.length + 1
                    : response.length,
              )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  /// 骨架数量按视口实际能放下的格子数算：固定 10 个在大屏多列下只能占到
  /// 页面上半部分，加载中看着像“只加载了半页”。
  Widget get _buildSkeleton => SliverLayoutBuilder(
    builder: (context, constraints) => SliverGrid(
      gridDelegate: gridDelegate,
      delegate: SliverSingleChildDelegate(
        count:
            gridDelegate
                .getLayout(constraints)
                .getMaxChildIndexForScrollOffset(
                  constraints.remainingPaintExtent,
                ) +
            1,
        child: const VideoCardVSkeleton(),
      ),
    ),
  );
}
