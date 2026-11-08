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
    hide TranslateAnimationSource, SelectionArea, SelectionAreaState;

export 'src/selection_area.dart';
