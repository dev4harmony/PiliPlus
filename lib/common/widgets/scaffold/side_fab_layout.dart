part of 'simple_scaffold.dart';

enum FabSide { left, right }

/// FabSideController + 横屏门控的共享状态。
/// 横屏（且横屏适配开启）时强制回右侧并丢弃原生上报；
/// 回到竖屏自动恢复跟随。横竖判定由 SimpleScaffold.build 的重建回调写入
/// （横竖切换必然触发重建），布局层只读状态，不再自行推断。
mixin FabSideGate {
  static bool _landscapeAdapt = Pref.horizontalScreen;

  static set landscapeAdapt(bool value) {
    if (_landscapeAdapt == value) return;
    _landscapeAdapt = value;
    FabSideController.instance.recheck();
  }
}

class FabSideController extends ValueNotifier<FabSide> {
  FabSideController._() : super(FabSide.right);
  static final FabSideController instance = FabSideController._();

  static const _animDuration = Duration(milliseconds: 380);
  static const _outPhaseEnd = 0.42;
  static const _operatingHandCooldown = Duration(milliseconds: 600);

  bool _enabled = false;
  bool _landscape = false;
  AnimationController? _anim;
  DateTime _lastOperatingSwitch = DateTime.fromMillisecondsSinceEpoch(0);

  bool get enabled => _enabled;

  /// 启动时初始化。返回 true 表示当前应下发原生订阅。
  bool init({required bool enable}) {
    final changed = _enabled != enable;
    _enabled = enable;
    return changed;
  }

  /// 设置开关切换时调用：换边立即归位（不动画），并按返回值下发订阅。
  bool setEnabled(bool enable) {
    _enabled = enable;
    if (!enable && value != FabSide.right) {
      value = FabSide.right;
    }
    return enable;
  }

  /// 原生握持手/操作手推送入口。仅在启用时生效；
  /// 未握持/双手/未知不动作，保持当前侧。
  /// 操作手通道响应快但易抖动，冷却时间内忽略，防误触来回切。
  void syncFromNative({required bool isLeft, required bool fromOperatingHand}) {
    if (!_enabled || _landscape) return;
    final now = DateTime.now();
    if (fromOperatingHand &&
        now.difference(_lastOperatingSwitch) < _operatingHandCooldown) {
      return;
    }
    final next = isLeft ? FabSide.left : FabSide.right;
    if (value == next) return;
    if (fromOperatingHand) _lastOperatingSwitch = now;
    value = next;
    _startAnim();
  }

  /// 横竖屏重建回调 / 横屏适配开关变化时重算。
  /// [landscape] 为 null 时按当前门控条件重推；横屏强制回右，
  /// 期间原生上报在 [syncFromNative] 入口被丢弃，竖屏恢复跟随。
  void recheck({bool? landscape}) {
    if (landscape != null) {
      _landscape = FabSideGate._landscapeAdapt && landscape;
    } else {
      _landscape = _landscape && FabSideGate._landscapeAdapt;
    }
    if (_landscape || !_enabled) {
      if (value != FabSide.right) value = FabSide.right;
    }
  }

  void _startAnim() {
    final anim = _anim;
    if (anim != null) {
      anim.forward(from: 0);
      return;
    }
    final controller = AnimationController(
      vsync: _Vsync(),
      duration: _animDuration,
      value: 1.0,
    )
      ..addListener(() {
        for (final ro in _hooked) {
          if (ro.attached) ro.markNeedsLayout();
        }
      })
      ..forward(from: 0);
    _anim = controller;
  }

  void disposeAnim() {
    _anim?.dispose();
    _anim = null;
  }
}

class _Vsync implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

final Set<_RenderScaffoldLayout> _hooked = {};

double _sideMarginOf(RenderBox? fab) {
  RenderBox? node = fab;
  while (node != null) {
    if (node is RenderPadding) {
      final p = node.padding;
      if (p is EdgeInsets && p.right > 0) return p.right;
      if (p is EdgeInsetsDirectional && p.end > 0) return p.end;
    }
    // 沿渲染树向下找首个 RenderPadding；其余节点只在单child代理链上继续
    if (node is RenderProxyBox) {
      node = node.child;
    } else {
      return 0.0;
    }
  }
  return 0.0;
}

extension _SideFabLayout on _RenderScaffoldLayout {
  Offset sideFabOffset(BoxConstraints constraints, Size fabSize) {
    final bottom = constraints.maxHeight - fabSize.height;
    final rightX = constraints.maxWidth - fabSize.width;

    // 禁用条件：页面锁定，或控制器判定横屏（横屏适配开 + 窗口横屏）→ 一律靠右
    final controller = FabSideController.instance;
    final enabled = controller.enabled && !fabSideLocked && !controller._landscape;
    final side = controller.value;
    if (!enabled) {
      _hooked.remove(this);
      return Offset(rightX, bottom);
    }

    if (_hooked.add(this)) {
      _hooked.removeWhere((ro) => !ro.attached);
    }

    final leftX = _sideMarginOf(fab);

    final anim = controller._anim;
    final t = anim?.value ?? 1.0;
    if (t >= 1.0) {
      return Offset(side == FabSide.left ? leftX : rightX, bottom);
    }

    final fromSide = side == FabSide.left ? FabSide.right : FabSide.left;
    final fromX = fromSide == FabSide.left ? leftX : rightX;
    final toX = side == FabSide.left ? leftX : rightX;
    if (fromX == toX) return Offset(toX, bottom);

    final out = constraints.maxWidth + fabSize.width;
    final dir = (toX - fromX).sign;
    final x = t < FabSideController._outPhaseEnd
        ? fromX -
              dir *
                  out *
                  Curves.easeInCubic.transform(t / FabSideController._outPhaseEnd)
        : toX +
              dir *
                  out *
                  (1 -
                      Curves.easeOutCubic.transform(
                        (t - FabSideController._outPhaseEnd) /
                            (1 - FabSideController._outPhaseEnd),
                      ));
    return Offset(x, bottom);
  }
}
