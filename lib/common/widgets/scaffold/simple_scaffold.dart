import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/rendering.dart'
    show
        BoxParentData,
        BoxHitTestResult,
        ChildLayoutHelper,
        HitTestResult,
        RenderMetaData,
        RenderPadding,
        RenderProxyBox;
import 'package:flutter/scheduler.dart'
    show Ticker, TickerCallback, TickerProvider;
import 'package:material_ui/material_ui.dart';

part 'side_fab_layout.dart';

class SimpleScaffold extends StatefulWidget {
  const SimpleScaffold({
    super.key,
    this.backgroundColor,
    this.fab,
    this.appBar,
    required this.body,
    this.fabSideLocked = false,
  });

  final Color? backgroundColor;
  final Widget? fab;
  final Widget? appBar;
  final Widget body;

  /// 锁定 FAB 恒在右侧（禁用智感握姿换边），用于 fab 自带左右位移动画的页面
  final bool fabSideLocked;

  @override
  State<SimpleScaffold> createState() => _SimpleScaffoldState();
}

class _SimpleScaffoldState extends State<SimpleScaffold>
    with WidgetsBindingObserver {
  final _statusBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void handleStatusBarTap() {
    super.handleStatusBarTap();
    if (!_hitTestableAtOrigin()) return;
    final primaryScrollController = PrimaryScrollController.maybeOf(context);
    if (primaryScrollController?.hasClients == true) {
      primaryScrollController!.animToTop();
    }
  }

  bool _hitTestableAtOrigin() {
    final element = _statusBarKey.currentContext as Element?;
    if (element == null) return false;
    final renderObject = element.renderObject;
    if (renderObject is! RenderMetaData) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      Offset.zero,
      View.of(context).viewId,
    );
    return result.path.any((entry) => entry.target == renderObject);
  }

  @override
  Widget build(BuildContext context) {
    // 判定是否为横屏状态，禁用智感握姿
    final view = View.of(context);
    FabSideController.instance.recheck(
      landscape: view.physicalSize.width > view.physicalSize.height,
    );
    return Material(
      color: widget.backgroundColor,
      child: ScaffoldLayout(
        statusBar: MetaData(
          key: _statusBarKey,
          behavior: HitTestBehavior.translucent,
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.paddingOf(context).top,
          ),
        ),
        fab: widget.fab,
        fabSideLocked: widget.fabSideLocked,
        appBar: widget.appBar,
        body: widget.body,
      ),
    );
  }
}

enum ScaffoldType { statusBar, fab, appBar, body }

class ScaffoldLayout
    extends SlottedMultiChildRenderObjectWidget<ScaffoldType, RenderBox> {
  const ScaffoldLayout({
    super.key,
    this.statusBar,
    this.fab,
    this.appBar,
    required this.body,
    this.fabSideLocked = false,
  });

  final Widget? statusBar;
  final Widget? fab;
  final Widget? appBar;
  final Widget body;
  final bool fabSideLocked;

  @override
  Iterable<ScaffoldType> get slots => ScaffoldType.values;

  @override
  Widget? childForSlot(slot) => switch (slot) {
    .statusBar => statusBar,
    .fab => fab,
    .appBar => appBar,
    .body => body,
  };

  @override
  SlottedContainerRenderObjectMixin<ScaffoldType, RenderBox> createRenderObject(
    BuildContext context,
  ) {
    return _RenderScaffoldLayout()..fabSideLocked = fabSideLocked;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant SlottedContainerRenderObjectMixin<ScaffoldType, RenderBox>
    renderObject,
  ) {
    (renderObject as _RenderScaffoldLayout).fabSideLocked = fabSideLocked;
  }
}

class _RenderScaffoldLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<ScaffoldType, RenderBox> {
  RenderBox? get fab => childForSlot(.fab);
  RenderBox? get appBar => childForSlot(.appBar);
  RenderBox? get statusBar => childForSlot(.statusBar);
  RenderBox get body => childForSlot(.body)!;

  bool fabSideLocked = false;

  Offset _getOffset(RenderBox child) {
    return (child.parentData as BoxParentData).offset;
  }

  void _setOffset(RenderBox child, Offset offset) {
    (child.parentData as BoxParentData).offset = offset;
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    size = constraints.biggest;

    final statusBar = this.statusBar;
    if (statusBar != null) {
      ChildLayoutHelper.layoutChild(
        statusBar,
        BoxConstraints.tightFor(width: constraints.maxWidth),
      );
      _setOffset(statusBar, .zero);
    }

    final Offset bodyOffset;
    final BoxConstraints bodyConstraints;

    final appBar = this.appBar;
    if (appBar != null) {
      final appBarHeight = ChildLayoutHelper.layoutChild(
        appBar,
        BoxConstraints.tightFor(width: constraints.maxWidth),
      ).height;
      _setOffset(appBar, .zero);

      bodyOffset = Offset(0, appBarHeight);
      bodyConstraints = BoxConstraints.tightFor(
        width: constraints.maxWidth,
        height: constraints.maxHeight - appBarHeight,
      );
    } else {
      bodyOffset = .zero;
      bodyConstraints = constraints;
    }

    final body = this.body..layout(bodyConstraints);
    _setOffset(body, bodyOffset);

    final fab = this.fab;
    if (fab != null) {
      final fabSize = ChildLayoutHelper.layoutChild(fab, constraints.loosen());
      _setOffset(fab, sideFabOffset(constraints, fabSize));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    void doPaint(RenderBox? child) {
      if (child != null) {
        context.paintChild(child, _getOffset(child) + offset);
      }
    }

    doPaint(appBar);
    doPaint(body);
    doPaint(fab);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final type in ScaffoldType.values) {
      final child = childForSlot(type);
      if (child == null) continue;
      final bool isHit = result.addWithPaintOffset(
        offset: _getOffset(child),
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          return child.hitTest(result, position: transformed);
        },
      );
      if (isHit) {
        return true;
      }
    }
    return false;
  }
}
