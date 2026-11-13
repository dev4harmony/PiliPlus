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
/// 跟手、行切换时做 70ms 位移动画）。鸿蒙的镜片是一枚 **112×72、圆角 36 的胶囊**，
/// 1.4 倍、白色描边、中心固定在触点上方 80vp：
///
/// - 尺寸/倍数/描边/阴影/避让距离见 [OhosSelectionTheme]，取自
///   `core/components_ng/pattern/select_overlay/magnifier.h`；
/// - 定位见 `magnifier_controller.cpp` 的 `UpdateMagnifierOffsetX/Y`：
///   横向跟着参考点并夹进屏幕，纵向"中心在参考点上方 `MAGNIFIER_OFFSETY`(80vp)"，
///   贴边时压缩这段距离（`clamp(magnifierY, 0, MAGNIFIER_OFFSETY)`）；
/// - 参考点离开文本控件（`IsLocalOffsetInHostRange` 失败）或落在键盘区时不再显示；
/// - 进出场 150ms 淡入淡出（本实现只有淡入，SDK 的 overlay 是被同步移除的）。
///
/// ## 参考点（采样点）
///
/// 镜片对准的是**光标/把柄所在位置**，不是手指 —— 拖手柄时手指按在球上，比光标低
/// 一整个手柄高度，照着手指取样会把手指下方那段（通常已经是空白或下一行）放大。
/// 原生的传参正是这么做的：
///
/// - 拖手柄：`text/text_select_overlay.cpp` 的 `OnHandleMove` 把
///   `handleRect.GetOffset()` 加半个高度（手柄矩形中心）传给 `SetLocalOffset`；
///   `TextFieldSelectOverlay::UpdateMagnifier` 收的也是 handle rect，单把柄走
///   `SetMagnifierLocalOffsetToFloatingCaretPos`（`text_field_pattern.cpp:2969`，
///   用 `GetFloatingCaretRect().Center()`）；
/// - 长按选词：`TextPattern` 传的是手指位置，但那条路径上 `MagnifierInfo.caretRect`
///   本来就落在手指所指那一行，取它一样对。
///
/// 所以统一用 [focusOf]（`caretRect` 中心）当参考点，位置和取样点都用它。
/// `RawMagnifier` 的 `focalPointOffset` 语义是「内容点 - 镜片中心」，取
/// `参考点 - 镜片中心`（纵向恒为 +80）即可，无需像原生那样自己算 `zoomOffset`。
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
        final Offset focalPoint = focusOf(info) - rect.center;
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
    final double left = _clamp(
      focus.dx - width / 2,
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

  /// 镜片对准的参考点（overlay 坐标）：光标/把柄中心，而不是手指。
  ///
  /// 依据见类头注释：原生只在「长按选词」时用手指位置，拖手柄全程用
  /// `handleRect` 中心；而两种场景下 `MagnifierInfo.caretRect` 都已经是那条信息，
  /// 直接取它的中心即可。
  static Offset focusOf(MagnifierInfo info) {
    final Rect caret = info.caretRect;
    // 注意 SelectableRegion 给的 caretRect 宽度为 0（只有 x + 行高），不能用 isEmpty。
    if (caret.height > 0 && caret.left.isFinite && caret.top.isFinite) {
      return caret.center;
    }
    return info.globalGesturePosition;
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
/// `shouldDisplayHandlesInMagnifier: false`：原生的镜片里同样没有手柄（手柄画在
/// 浮层里、且被镜片挡在下面）。
final TextMagnifierConfiguration ohosTextMagnifierConfiguration =
    TextMagnifierConfiguration(
      shouldDisplayHandlesInMagnifier: false,
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
