import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 把 shim 包里的选区菜单动作接到 app 实现上。
///
/// `packages/material_ui` 是被 app 依赖的底层包，不能反过来 import `PiliPlus/...`，
/// 所以「分享 / 打开链接 / 站内搜索」三个动作由这里注入一次：
///
/// - 分享：[SelectionMenuConfig.shareText]，由 shim 的兼容
///   `AdaptiveTextSelectionToolbar` 在渲染前补按钮；
/// - 打开 / 站内搜索：上游的 `SelectableRegionStateExt.addLaunchMenuIfNeeded`
///   已经把逻辑搬到了 shim（等价 `lib/scripts/selectable_region.patch`），
///   这里注入它需要的两个路由动作。
///
/// 调用点：`lib/main.dart` 的 `main()`，`runApp` 之前。
void configureSelectionMenu() {
  SelectionMenuConfig.shareText = ShareUtils.shareText;
  // 注意签名差异：`handleWebview` 是 `Future<void>` 且带可选参数，
  // 这里用闭包抹平，不要直接赋 method tear-off。
  SelectionMenuConfig.openLink = PageUtils.handleWebview;
  SelectionMenuConfig.searchText = (String keyword) => Get.offOrToNamed(
    '/searchResult',
    parameters: {'keyword': keyword},
    // 选区常出现在对话框/底部面板里，这类路由不是 PageRoute，
    // 直接 off 掉，避免搜索结果压在浮层上面。
    off: Get.routing.route is! PageRoute,
  );
  // 放大镜：SelectableText / TextField 的默认值来自 SDK 的
  // `TextMagnifier.adaptiveMagnifierConfiguration`（Material 77×38），
  // 在鸿蒙上换成原生 112×72 胶囊镜片；非鸿蒙平台此调用无副作用。
  installOhosTextMagnifier();
}
