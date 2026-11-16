/// 见 pubspec.yaml 顶部说明：3.41 上把 material_ui 映射回 SDK 内置 Material。
///
/// `TranslateAnimationSource` 在 SDK 中标了 `@internal`，转导出会触发
/// invalid_export_of_internal_element，业务代码也用不到，这里隐藏掉。
///
/// `SelectionArea` 也隐藏，改用本包 `src/selection_area.dart` 的同名实现（构造签名
/// 与参数完全一致，调用点不用改）：SDK 默认的上下文菜单在选区端点滚出视口时会抛
/// `Null check operator used on a null value`，那层兜底放在本包，等鸿蒙 fork 升到
/// 3.47 删掉本目录时可一并丢弃。
library;

export 'package:flutter/material.dart'
    hide
        TranslateAnimationSource,
        SelectionArea,
        SelectionAreaState,
        // 这三个类改由 src/selection_widgets.dart 提供同名实现，构造签名与 SDK
        // 一致但不改 SDK 就让鸿蒙用上「杆 + 球」手柄。
        SelectableText,
        TextField,
        TextFormField,
        // 以下改由 src/compat/ 提供同名实现，对应 lib/scripts/*.patch：
        // navigation_drawer（flex + 水波纹）、scrollable_gesture（识别器/方向参数）。
        // NavigationDrawerDestination 必须与 compat NavigationDrawer 同源，
        // 否则它内部的 _NavigationDrawerDestinationInfo.of 会因类型错配返回
        // null（平板侧栏崩溃）。
        NavigationDrawer,
        NavigationDrawerDestination,
        PageView,
        Scrollable,
        ScrollableState,
        EdgeDraggingAutoScroller,
        TabBarView,
        DraggableScrollableSheet,
        RichText,
        RenderParagraph,
        // lib/scripts/material/scaffold.patch 的等价实现（compat/bottom_sheet.dart
        // + compat/standard_bottom_sheet.dart）。
        BottomSheet,
        PersistentBottomSheetController;

export 'src/selection_area.dart';

// 越界拖拽的兜底（把选区边夹回手指所在那一行），供测试与调试单独引用。
export 'src/selection_edge_clamp.dart';

// 选中菜单的分享/打开/站内搜索按钮，以及鸿蒙「杆 + 球」手柄；app 侧启动时用
// `SelectionMenuConfig` 注入实际动作（见 lib/utils/selection_menu_wiring.dart）。
export 'src/selection_menu.dart';
export 'src/selection_handle.dart';

// 鸿蒙文本选择体系的真实主题值（手柄/光标/选中高亮/工具栏/放大镜），
// 取自 openharmony/global_system_resources 的主题 json，来源见文件头注释。
export 'src/ohos_selection_theme.dart';

// 鸿蒙样式放大镜（104×68 胶囊、1.4 倍）与工具栏（37vp 胶囊 + 原生对齐规则 +
// 右侧溢出收起二级菜单）。放大镜需要 app 启动时调一次 `installOhosTextMagnifier()`
// 才覆盖 SelectableText / TextField 的默认配置。
export 'src/selection_magnifier.dart';
export 'src/selection_toolbar.dart';

// 平台判断（用 toString() 比较，兼容没有 TargetPlatform.ohos 的官方 SDK）。
export 'src/selection_platform.dart';

// SelectableText / TextField / TextFormField 的同名包装：把鸿蒙「杆 + 球」手柄与
// 自定义菜单作为默认值注入（详见该文件顶部说明）。
export 'src/selection_widgets.dart';

// 鸿蒙 ArkUI 列表手感（惯性 fling + EdgeEffect.Spring 回弹）的复刻，
// 平台判断与带业务语义的 physics 仍留在 app 侧（scroll_physics.dart）。
export 'src/arkui_scroll_physics.dart';

// SDK 补丁的等价实现（lib/scripts/*.patch），文件结构与上游 lib/scripts 对应。
export 'src/compat/navigation_drawer.dart';
export 'src/compat/page_view.dart';
export 'src/compat/scrollable.dart'
    hide
        ViewportBuilder,
        TwoDimensionalViewportBuilder,
        DiagonalDragBehavior,
        TwoDimensionalScrollable,
        TwoDimensionalScrollableState;
export 'src/compat/scrollable_helpers.dart';
export 'src/compat/tabs.dart';
export 'src/compat/draggable_scrollable_sheet.dart' hide DraggableScrollableController;
export 'src/compat/paragraph.dart';
export 'src/compat/rich_text.dart';
export 'src/compat/bottom_sheet.dart'
    show
        BottomSheet,
        BottomSheetState,
        BottomSheetDefaultsM3;
export 'src/compat/standard_bottom_sheet.dart';
