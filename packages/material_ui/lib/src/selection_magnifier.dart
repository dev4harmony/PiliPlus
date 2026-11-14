import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_ui/src/ohos_selection_theme.dart';
import 'package:material_ui/src/selection_platform.dart';

/// 鸿蒙（OpenHarmony）样式的手柄拖拽放大镜。
///
/// ## 与 SDK 自带镜片的差别
///
/// `TextMagnifier`（`material/magnifier.dart`）是 Android 的观感：77.37×37.9、
/// 1.25 倍、灰色蒙层、圆角 20 的方块，并且**位置规则绑在"行"上**（贴着当前行、
/// 跟手、行切换时做 70ms 位移动画）。鸿蒙的镜片是一枚 **104×68 的胶囊**（原生
/// 112×72 略收小）、1.4 倍、白色描边、中心固定在参考点上方 70vp：
///
/// - 尺寸/倍数/描边/阴影/避让距离见 [OhosSelectionTheme]，取自
///   `core/components_ng/pattern/select_overlay/magnifier.h`；
/// - 定位见 `magnifier_controller.cpp` 的 `UpdateMagnifierOffsetX/Y`：
///   **横向跟手指**（`MagnifierInfo.globalGesturePosition`，夹进屏幕），
///   纵向"中心在参考点上方 `MAGNIFIER_OFFSETY`"，贴边时压缩这段距离；
/// - 参考点离开文本控件（`IsLocalOffsetInHostRange` 失败）或落在键盘区时不再显示；
/// - 进出场 150ms 淡入淡出（本实现只有淡入，SDK 的 overlay 是被同步移除的）。
///
/// ## 横向跟手指、纵向跟光标
///
/// 原生拖手柄时横向是**跟手**的：`OnHandleMove` 把当前拖拽点（`GetLocalOffset()`，
/// 即手指位置）传给 `SetLocalOffset`，镜片横向就停在那根手指正上方；纵向则固定
/// 「参考点上方 70vp」，避免镜片盖住手指。早先版本横向也取 `caretRect.center.dx`，
/// 结果手柄球有 14vp 宽、光标在球心偏一侧时镜片会横向偏移一个字符，
/// 与手指位置对不上 —— 按产品要求改回跟手。
///
/// 纵向的"参考点"仍取 [focusOf]（`caretRect` 中心）：手柄比文字行低一整颗球的高度，
/// 拿手指的 y 会把手指下方那段空白放大。横向用 `globalGesturePosition.dx`，
/// 纵向用 `caretRect.center.dy`。
///
/// ## 镜片里不画任何额外指示
///
/// 镜片显示的就是被放大 1.4 倍的真实内容（文本、选中高亮、光标）。曾经在正中央画过
/// 一根与手柄同宽同色的竖杆，产品反馈不需要，已移除。
///
/// ## 图层顺序
///
/// 镜片必须压在选择手柄之上（`shouldDisplayHandlesInMagnifier: true` →
/// `SelectionOverlay.showMagnifier` 里 `below: null`，即插在手柄 overlay 的上面），
/// 否则拖到行尾时镜片会被手柄球盖住一角。
///
/// ## 接入方式
///
/// `SelectableText` / `TextField` 的 `magnifierConfiguration` 缺省是 null，SDK 会回落到
/// `TextMagnifier.adaptiveMagnifierConfiguration`（`selectable_text.dart:796`、
/// `text_field.dart:1941`），那是全局可变静态字段 —— 调 [installOhosTextMagnifier]
/// 换掉它即可覆盖所有输入类控件；`SelectionArea` 由本包显式传参。
///
/// ## 什么时候会出镜片
///
/// **只有拖手柄**时。这条链是上游行为：`SelectionOverlay.showMagnifier` 由各手柄的
/// 拖动回调驱动，`SelectionArea`（`SelectableRegion`）也一样。
///
/// **长按定位光标不出镜片**：那条路在
/// `TextSelectionGestureDetectorBuilder._showMagnifierIfSupportedByPlatform` 里被平台
/// switch 挡掉了（只放 android/iOS），而它是 private、没有扩展点。本包不改 SDK，
/// 所以保持"长按无镜片、拖手柄有镜片"；要补上只能改 fork（两个 switch 加 ohos 分支）
/// 或自己复刻一套长按判定并手动驱动 `selectionOverlay`。
class OhosTextMagnifier extends StatelessWidget {
  /// 创建镜片。无状态，跟随 [magnifierInfo] 重建。
  const OhosTextMagnifier({super.key, required this.magnifierInfo});

  /// SDK 每次手势更新都会写这个 notifier（`SelectionOverlay.updateMagnifier`）。
  final ValueNotifier<MagnifierInfo> magnifierInfo;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final Brightness brightness = Theme.of(context).brightness;
    final Color borderColor = brightness == Brightness.dark
        ? const Color(0xCCFFFFFF) // 暗色：白 80%
        : const Color(0x80FFFFFF); // 亮色：白 50%
    // 原生的轮廓宽是**物理像素**（3px，没有做 vp 换算），换算成逻辑像素才能对上，
    // 否则 3x 屏上会粗 3 倍。
    final double borderWidth =
        OhosSelectionTheme.magnifierBorderWidthPx /
        MediaQuery.devicePixelRatioOf(context);

    return ValueListenableBuilder<MagnifierInfo>(
      valueListenable: magnifierInfo,
      builder: (BuildContext context, MagnifierInfo info, Widget? child) {
        final Rect? rect = lensRectFor(info, screen);
        if (rect == null) {
          // 参考点（光标）离开文本控件：原生直接收起镜片，这里退化成空 widget。
          return const SizedBox.shrink();
        }
        // `RawMagnifier` 的 `focalPointOffset` 语义是「内容点 - 镜片中心」，
        // 取样点仍是光标（纵向对齐行、横向对齐手指的 x）。
        final Offset focalPoint = samplePointOf(info) - rect.center;
        return Positioned(
          left: rect.left,
          top: rect.top,
          // 镜片只是视觉，绝不能抢走正在拖手柄的那根手指的命中测试。
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: OhosSelectionTheme.magnifierFadeDuration,
              // 原生是 `Curves::FRICTION`（快速起步后收尾），decelerate 最接近。
              curve: Curves.decelerate,
              builder: (BuildContext context, double opacity, Widget? child) {
                return RawMagnifier(
                  size: rect.size,
                  magnificationScale: OhosSelectionTheme.magnifierScale,
                  focalPointOffset: focalPoint,
                  // 阴影是零偏移的，需要裁剪掉镜片内部那一半，否则会糊在镜片上。
                  clipBehavior: Clip.hardEdge,
                  decoration: MagnifierDecoration(
                    opacity: opacity,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(
                          OhosSelectionTheme.magnifierCornerRadius,
                        ),
                      ),
                    ),
                    shadows: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: OhosSelectionTheme.magnifierShadowSize,
                      ),
                    ],
                  ),
                  // 只有一圈描边，镜片内不再叠加任何指示图形（放大内容自己已经带光标）。
                  child: Opacity(
                    opacity: opacity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(
                            OhosSelectionTheme.magnifierCornerRadius,
                          ),
                        ),
                        border: Border.all(
                          color: borderColor,
                          width: borderWidth,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 计算镜片矩形（overlay 坐标）。返回 null 表示当前不该显示。
  ///
  /// `MagnifierInfo` 里的坐标已经是 **root overlay 坐标**（SDK 在
  /// `_buildMagnifier` 里做过 `overlay.globalToLocal`），而本 widget 也是插在同一个
  /// overlay 里，所以两边直接用，不要再做一次坐标转换。
  static Rect? lensRectFor(MagnifierInfo info, Size screen) {
    const double width = OhosSelectionTheme.magnifierWidth;
    const double height = OhosSelectionTheme.magnifierHeight;
    if (info.fieldBounds.isEmpty) {
      return null;
    }
    // 原生用 `IsLocalOffsetInHostRange` 判控件可见区；留一个手柄直径的余量，
    // 免得把端点拖到末行下方一点点镜片就闪断。
    final Rect allowed = info.fieldBounds.inflate(
      OhosSelectionTheme.handleOuterDiameter,
    );
    final Offset focus = focusOf(info);
    if (!allowed.contains(focus)) {
      return null;
    }
    // 横向跟手指（原生 `UpdateMagnifierOffsetX` 用的是拖拽点），不是跟选区/光标。
    final double horizontal = gestureXOf(info);
    final double left = _clamp(
      horizontal - width / 2,
      0,
      math.max(0, screen.width - width),
    );
    final double top = _clamp(
      focus.dy - OhosSelectionTheme.magnifierVerticalOffset - height / 2,
      0,
      math.max(0, screen.height - height),
    );
    return Rect.fromLTWH(left, top, width, height);
  }

  /// 镜片的纵向参考点（overlay 坐标）：光标/把柄中心，而不是手指。
  ///
  /// 依据见类头注释：拖手柄时手指按在球上，比光标低一整个手柄高度，照着手指取样会把
  /// 手指下方那段（通常已经是空白或下一行）放大。而 `MagnifierInfo.caretRect` 在拖把柄
  /// 与长按选词两条路径上都落在正确的那一行，直接取中心即可。
  static Offset focusOf(MagnifierInfo info) {
    final Rect caret = info.caretRect;
    // 注意 SelectableRegion 给的 caretRect 宽度为 0（只有 x + 行高），不能用 isEmpty。
    if (caret.height > 0 && caret.left.isFinite && caret.top.isFinite) {
      return caret.center;
    }
    return info.globalGesturePosition;
  }

  /// 镜片的横向锚点（overlay 坐标）：**手指当前位置**。
  static double gestureXOf(MagnifierInfo info) {
    final double x = info.globalGesturePosition.dx;
    if (x.isFinite) {
      return x;
    }
    return focusOf(info).dx;
  }

  /// 镜片采样的内容点（overlay 坐标）= 手指所在列 × 光标所在行。
  ///
  /// 镜片中心显示的就是这一点的内容，所以「手指横坐标」和「光标纵坐标」两件事都要。
  static Offset samplePointOf(MagnifierInfo info) {
    return Offset(gestureXOf(info), focusOf(info).dy);
  }

  static double _clamp(double value, double lower, double upper) {
    if (upper < lower) {
      upper = lower;
    }
    if (value < lower) {
      return lower;
    }
    return value > upper ? upper : value;
  }
}

/// 鸿蒙放大镜的 [TextMagnifierConfiguration]。
///
/// `shouldDisplayHandlesInMagnifier: true` —— 这个字段在
/// `SelectionOverlay.showMagnifier`（`widgets/text_selection.dart:1201-1205`）里只决定
/// overlay 的插入位置：传 true 时 `below: null`，镜片插在手柄 overlay **之上**，
/// 于是镜片盖住手柄（此前是 false，镜片被手柄球压住一角）。
///
/// 代价：手柄 overlay 进了 `BackdropFilter` 的取样范围。但镜片中心在参考点上方
/// [OhosSelectionTheme.magnifierVerticalOffset]（70vp），镜片下沿离参考点仍有 34vp，
/// 而止手柄/折叠光标的球挂在行下方，起手柄的球在行上方、热区边缘 —— 正常拖动时球
/// 只是偶尔擦到镜片底边，不会在镜片里出现一颗放大的球。真的要彻底排掉只能改 SDK
/// （让镜片的 BackdropFilter 跳过手柄 overlay 层）。
final TextMagnifierConfiguration ohosTextMagnifierConfiguration =
    TextMagnifierConfiguration(
      shouldDisplayHandlesInMagnifier: true,
      magnifierBuilder:
          (
            BuildContext context,
            MagnifierController controller,
            ValueNotifier<MagnifierInfo> magnifierInfo,
          ) {
            // 这个配置可能被手动用到非鸿蒙平台，那里保持"没有放大镜"。
            if (!isOhosPlatform) {
              return null;
            }
            return OhosTextMagnifier(magnifierInfo: magnifierInfo);
          },
    );

/// 把 SDK 的默认放大镜换成鸿蒙镜片，`runApp` 之前调一次即可。
///
/// 改的是 `TextMagnifier.adaptiveMagnifierConfiguration` 这个**可变静态字段**
/// （`material/magnifier.dart:39`）：`SelectableText.magnifierConfiguration` 为 null 时
/// SDK 用 `?? TextMagnifier.adaptiveMagnifierConfiguration`，`TextField` 同理，所以
/// 换成鸿蒙配置后所有输入类控件自动生效，不需要逐个调用点传参。
///
/// 非鸿蒙平台直接返回，不改动任何全局状态。
void installOhosTextMagnifier() {
  if (!isOhosPlatform) {
    return;
  }
  TextMagnifier.adaptiveMagnifierConfiguration = ohosTextMagnifierConfiguration;
}
