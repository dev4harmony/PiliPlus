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
        TextFormField;

export 'src/selection_area.dart';

// 越界拖拽的兜底（把选区边夹回手指所在那一行），供测试与调试单独引用。
export 'src/selection_edge_clamp.dart';

// 选中菜单的分享/打开/站内搜索按钮，以及鸿蒙「杆 + 球」手柄；app 侧启动时用
// `SelectionMenuConfig` 注入实际动作（见 lib/utils/selection_menu_wiring.dart）。
export 'src/selection_menu.dart';
export 'src/selection_handle.dart';

// 平台判断（用 toString() 比较，兼容没有 TargetPlatform.ohos 的官方 SDK）。
export 'src/selection_platform.dart';

// SelectableText / TextField / TextFormField 的同名包装：把鸿蒙「杆 + 球」手柄与
// 自定义菜单作为默认值注入（详见该文件顶部说明）。
export 'src/selection_widgets.dart';
