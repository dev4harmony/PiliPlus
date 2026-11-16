# 框架核心补丁（非 Material）下游对应实现分析

分析对象：上游 `lib/scripts/*.patch`（17 个非 Material / 非 Cupertino 补丁）。
下游：`/d/github/PiliPlus`（Flutter-ohos 3.47.7，`pubspec.yaml` 声明 `flutter: ">=3.44.9"`），
**不 patch SDK**，改为 ①`lib/common/widgets/flutter/**` 内 vendored 源码，②`packages/material_ui/` shim 包，③app 侧改写。

> 下游 `lib/scripts/*.patch` 仍然存在，但没有任何 `patch.ps1` / CI 步骤引用（`.github/workflows/` 里 `git apply` 为 0 命中），
> 因此这些 patch 文件**当前不生效**，只能作为「上游想做什么」的说明文档。

## 总结表

| # | 补丁 | 目标 SDK 文件 | 行为变化（一句话） | 公开化 vs 纯行为 | 下游对应实现 | 可行性 |
|---|---|---|---|---|---|---|
| 1 | `scrollable_gesture.patch` | `material/tabs.dart`、`widgets/gesture_detector.dart`、`widgets/page_view.dart`、`widgets/scrollable.dart` | ①`PageView`/`TabBarView`/`Scrollable`/`TabBarView` 允许注入自定义横向手势识别器；②加 `NestedRawGestureDetector`/`NestedListener`，让「外」层可滚动区域在 `_shouldIgnorePointer` 时不抢指针，修复嵌套滚动 | 两者都有：新增公开参数 + 新增公开类 + 行为改动 | **部分**：`lib/common/widgets/flutter/page/scrollable.dart:93-96`、`page_view.dart:71,107`、`tabs.dart:27,40` 有 `horizontalDragGestureRecognizer`；`gallery_viewer.dart:334-344,471` 在用。**但 `NestedRawGestureDetector`/`NestedListener`/`debugLabel=='outer'` 分支下游 0 命中** | B（参数部分）；C（嵌套手势部分） |
| 2 | `scroll_view.patch` | `widgets/scrollable.dart` | 垂直拖拽在手势识别阶段就被 `isDyAllowed(dy) => viewportDimension - dy > 30` 拦掉，避免手指在列表底部 30px 内还去拖列表（上游 issue #1662「处理底部滚动事件」） | 纯行为（新增私有 `_VerticalDragGestureRecognizer`） | **无**（`isDyAllowed` 全库 0 命中；`lib/common/widgets/flutter/page/scrollable.dart:776-801` 仍用裸 `VerticalDragGestureRecognizer`） | C |
| 3 | `scroll_position.patch` | `widgets/scroll_position_with_single_context.dart` | `applyUserOffset` 只在位置真的变化时才通知 `userScrollDirection`，避免「到底了还在报 reverse/forward」导致悬浮标题/工具栏抖动 | 纯行为 | **无**（`updateUserScrollDirection` 0 命中；只有 `draggable_scrollable_sheet.dart:835`、`draggable_sheet/dyn.dart:79` 覆写 `applyUserOffset` 并 `super` 调用） | B |
| 4 | `scrollable.patch` | `widgets/scrollable.dart` | 把 `ScrollableState._shouldIgnorePointer` 公开成 `shouldIgnorePointer` | 纯公开化（getter） | **无**（`shouldIgnorePointer` 仅出现在 patch 文件；`page/scrollable.dart:754` 仍是私有 `_shouldIgnorePointer`，且未加 getter） | B |
| 5 | `selectable_region.patch` | `painting/inline_span.dart`、`placeholder_span.dart`、`text_span.dart`、`rendering/paragraph.dart`、`selection.dart`、`widgets/scrollable.dart`、`selectable_region.dart`、`selection_container.dart`、`text.dart`、`widget_span.dart` | 一整套文本选择增强：WidgetSpan 可携带 `rawText` 并入复制文本、多段选择用分隔符拼接、选区绘制按行合并并补满整行、拖拽越界夹取、`isSingle`/`fromDrag` 语义、点击空白清除选区、三击选段、桌面二次点击弹菜单 | 大量公开化 + 行为 | **部分**：`packages/material_ui/lib/src/selection_edge_clamp.dart:51,86-140`（等价 `adjustDragOffset` 夹取）、`selection_area.dart:68-84`、`selection_menu.dart:120-145`（选区文本缓存，替代 `getSelectedContent` 分隔符问题）、`selection_menu.dart:355-370`（null 安全）。`rawText`/`separator`/`isSingle`/`fromDrag` 下游 0 命中 | B/C 混合 |
| 6 | `null_safety_for_selectable_region.patch` | `widgets/selectable_region.dart` | ①`startGlyphHeight`/`endGlyphHeight` 对 `startSelectionPoint` 判空（选区端点滚出视口时 `contextMenuAnchors` 崩溃）；②监听 `ScrollEndNotification` 重新显示手柄/菜单 | 纯行为 | **有**：`packages/material_ui/lib/src/selection_menu.dart:355-370` 用 `on Object` 兜底 `selectionEndpoints`、`overlay?.lineHeightAtStart ?? 0`，注释 `selection_area.dart:24-42` 明确记录了同一崩溃栈。**②的 ScrollEndNotification 重显示部分 0 命中** | A（已实现） |
| 7 | `text_selection.patch` | `gestures/tap_and_drag.dart`、`widgets/selectable_region.dart`、`widgets/text_selection.dart` | 全平台统一用 `TapAndHorizontalDragGestureRecognizer` 做文本选择拖拽（去掉桌面端 `TapAndPan`），并让 touch 指针永不因「移动距离够」被判成横向拖拽（上游 #2106） | 纯行为（去 switch） | **部分**：`lib/common/widgets/flutter/text_field/text_selection.dart:1804-1830`（vendored 副本里整段平台 switch 被注释，`default:` 走 `TapAndHorizontalDragGestureRecognizer`，`:1845` 保留 `eagerVictoryOnDrag`）。**`tap_and_drag.dart` 那半（touch 不判 drag）下游 0 命中**，而 `SelectableRegion` 未 vendored | B（vendored 副本）；C（tap_and_drag） |
| 8 | `editable_text.patch` | `rendering/editable.dart`、`widgets/editable_text.dart` | ①选区高亮宽度默认 `tight`；②`_TextHighlightPainter` 按行合并 box 并补到整行宽（消除多行选中时右侧锯齿/缝隙）；③拖拽选字时不要每次 `_scheduleShowCaretOnScreen`（避免页面被拽着跳） | 纯行为 | **未实现**：`lib/common/widgets/flutter/text_field/editable.dart:298` `selectionWidthStyle = max`、`:3150` 仅 painter 用 tight、`:3170-3195` 仍是逐 box `drawRect` 无合并；`editable_text.dart:1708-1718` `defaultSelectionWidthStyle` 仍返回 `max`；`:5054-5056` `shouldShowCaret` 未排除 `SelectionChangedCause.drag` | B |
| 9 | `text_painter.patch` | `painting/text_painter.dart` | 公开 `TextPainter.layoutCache`（上游 `text_ellipsis/paragraph_ellipsis.dart:92` 用它判断末行为空来画省略号） | 纯公开化（getter） | **无**（`layoutCache` 下游只有 `SliverGridDelegate` 同名字段，见 `lib/utils/grid.dart:86`；`lib/common/widgets/text_ellipsis/` 整个目录下游不存在） | C |
| 10 | `text.patch` | `rendering/paragraph.dart`、`widgets/text.dart` | ①公开 `RenderParagraph.textPainter`；②给 `_OverridingTextStyleTextSpanUtils` 加公开 typedef 别名 | 纯公开化 | **部分**：`lib/common/widgets/flutter/text/paragraph.dart:125` 仍私有、**无 getter**；`text.dart:398,1300` 直接用私有名（vendored 副本内可见，不需要 typedef） | B |
| 11 | `sliver.patch` | `widgets/sliver.dart` | 给私有 `_SliverZeroFlexParentDataWidget` / `_SliverConstrainedCrossAxis` 加 typedef 别名，使 app 能 `extends` 它们做「居中约束宽度」sliver | 纯公开化 | **无**（`SliverZeroFlexParentDataWidget` / `SliverConstrainedCrossAxis_` 全库 0 命中；`lib/common/widgets/sliver/` 下无 `sliver_constrained_cross_axis.dart`）。上游消费者 `utils/waterfall.dart:21`、`chat_list_view.dart:50` 下游已改写掉：`waterfall.dart:19-31` 用 `SliverLayoutBuilder` 自行居中，`chat_list_view.dart:9,64` 改为 `BoxScrollView` + 自有 `RenderSliverChatList` | C（但已有 app 侧替代） |
| 12 | `navigator.patch` | `widgets/navigator.dart` | `_afterNavigation`（内部会 `_cancelActivePointers()`）只在 `entry.currentState == popping` 时调用，避免 push/replace 时误取消进行中的指针（上游 #1947） | 纯行为 | **无**（`afterNavigation` 0 命中；`.dart` 侧无任何替代） | C |
| 13 | `image_anim.patch` | `widgets/image.dart` | `_ImageState._isPaused` 不再理会 `MediaQuery.disableAnimations`，只跟 `TickerMode`，让「关闭动画」系统设置不再冻结 GIF/APNG（上游 #2107） | 纯行为 | **无**（`maybeDisableAnimationsOf` 全库 0 命中；无 vendored `widgets/image.dart`。`lib/common/widgets/image_viewer/image.dart:393` 是 app 自己的查看器，只读 `TickerMode`，与本补丁无关） | B |
| 14 | `layout_builder.patch` | `widgets/layout_builder.dart` | 注释掉 `_LayoutBuilderElement` 的 `BuildScope` + `_scheduleRebuild` 延迟重建机制，让 `LayoutBuilder` 在布局阶段立即同步重建（规避上游「postFrame 里 markNeedsLayout」问题） | 纯行为 | **有**：`lib/common/widgets/image_grid/image_grid_builder.dart:296-338`（vendored element 内同一段 `BuildScope get buildScope` / `_scheduleRebuild` / `_frameCallback` 被整段注释）。另有 `lib/common/widgets/cached_layout_builder.dart:8-51` 用「缓存 builder + 约束比对」从源头减少重建 | B（已实现） |
| 15 | `mouse_cursor.patch` | `widgets/widget_state.dart` | `WidgetStateMouseCursor.clickable.resolve` 在非 web 也返回 `SystemMouseCursors.click`（原来只有 web 是手型，桌面端鼠标移到按钮上不变手型，上游 #182466） | 纯行为 | **无**（无自定义 cursor 子类；`lib/common/widgets/flutter/list_tile.dart:936`、`vertical_tabs.dart:1958` 仍走 SDK `clickable`，在本 SDK 上仍是 `basic`） | B |
| 16 | `double_tap_gesture.patch` | `gestures/multitap.dart` | 让 `DoubleTapGestureRecognizer.checkUp` 拿到 `PointerUpEvent`（从而能记录第二次点击抬起的时间戳），供图片查看器区分「双击」与「双击后的单击」 | 公开化 `checkUp` + 传参 | **有**：`lib/common/widgets/gesture/image_double_tap_gesture_recognizer.dart:19-71`，不碰 SDK：`addAllowedPointer` 前先 `GestureBinding.instance.pointerRouter.addRoute` 记录 `PointerUpEvent.timeStamp`，再包一层 `onDoubleTap` 回调把时间戳写进 `timeStamp`（`:36-58`）；消费点 `gallery_viewer.dart:527-528` | A（已实现） |
| 17 | `draggable_scrollable_sheet.patch` | `widgets/draggable_scrollable_sheet.dart` | ①新增 `initialScrollOffset`；②公开 `DraggableScrollableSheetState` / `extent` / `scrollController` setter，③公开 `DraggableScrollableSheetScrollController` / `...ScrollPosition`，使 app 能继承出「带初始偏移 / 带自定义行为」的抽屉 | 公开化 + 行为 | **有**：整文件 vendored `lib/common/widgets/flutter/draggable_scrollable_sheet.dart`（1099 行）+ part `lib/common/widgets/draggable_sheet/dyn.dart`、`topic.dart`；`topic.dart:16-19` 自带 `initialScrollOffset`，`:42-43` 注入控制器，`:71` 传 `initialPixels`；`draggable_scrollable_sheet.dart:807` 暴露 `extent` | B（已实现） |
| 18 | `fab.patch`（仅 `flutter/` 部分） | `material/floating_action_button.dart` | 注释掉 `build` 里的 `Hero(tag: heroTag!)` 包装，去掉 FAB 的 Hero 飞行动画（多 FAB 同默认 tag 时还会触发 duplicate-hero 断言） | 纯行为 | **无**（`heroTag` 下游只出现在 `video_card_*` 与路由参数，与 FAB 无关；`lib/pages/blacklist/view.dart:179,184` 同一 `Column` 里两个 FAB 都用默认 `heroTag`，SDK 默认值是同一个 `const _DefaultHeroTag()` 实例 → 同 tag） | A |

## 逐补丁细节与证据

### 1. `scrollable_gesture.patch`
- 目标：`packages/flutter/lib/src/material/tabs.dart`（`TabBarView` 新增 `scrollDirection`/`hitTestBehavior`/`horizontalDragGestureRecognizer`）、`widgets/gesture_detector.dart`（`RawGestureDetectorState` 泛型化 + 新增 `NestedRawGestureDetector`/`NestedListener`/`_RenderPointerListener`）、`widgets/page_view.dart`（`PageView` → `PageView<T extends HorizontalDragGestureRecognizer>`）、`widgets/scrollable.dart`（`Scrollable<T>` + `debugLabel=='outer'` 时改用 `NestedRawGestureDetector`）。
- 用户可见问题：图片查看器里「横滑翻页」在边缘要继续把事件让给外层列表；嵌套滚动容器之间指针归属错乱。
- 公开化：`horizontalDragGestureRecognizer`（新参数）、`NestedRawGestureDetector`、`NestedListener`、`RawGestureDetectorState<T>`（泛型，破坏性签名变化）。
- 下游：
  - 参数部分已落地：`lib/common/widgets/flutter/page/scrollable.dart:83`（`class Scrollable<T extends HorizontalDragGestureRecognizer>`）、`:93-96`；`page/page_view.dart:71,107`；`page/tabs.dart:27,40`；调用点 `lib/common/widgets/image_viewer/gallery_viewer.dart:334-344`、`:471`、`:508`。
  - 嵌套手势部分**缺失**：`NestedRawGestureDetector`/`NestedListener`/`ignoring` 全库 0 命中；`page/scrollable.dart:1030-1053` 仍是原始 `_ScrollableScope(Listener(RawGestureDetector(Semantics(IgnorePointer(...)))))` 结构，没有 `debugLabel=='outer'` 分支。
- 可行性：参数部分 **B**（必须整份 vendored）；嵌套部分 **C**（`_RenderPointerListener` 继承 `RenderPointerListener`、需要 framework 内部 `_gestureDetectorKey`/`scheduleLayoutCallback` 时序）。

### 2. `scroll_view.patch`（无对照）
- 目标：`widgets/scrollable.dart`。`_isDyAllowed(dy) => position.viewportDimension - dy > 30`，在 `isPointerAllowed` 阶段算出、在 `invokeCallback` 里拦截所有回调。
- 用户可见问题：手指落在列表底部 ~30px 内（贴近底部栏/评论区入口）时，本意是点按，却被判成竖向拖拽，触发滚动或吃掉点击（上游 #1662）。
- 下游：`grep -rn "isDyAllowed" lib packages` → 仅命中 patch 文件本身。`page/scrollable.dart:776-801` 的 vertical 分支仍是裸 `VerticalDragGestureRecognizer`，`_handleDragUpdate` / `invokeCallback` 无任何前置判定。
- **结论：无下游对应实现 → 潜在回归**（下拉/上拉手势与底部按钮争抢点击的行为与上游不一致）。
- 可行性：**C**。`Scrollable` 的纵向识别器没有暴露成参数（上游只给横向开了口子），`ScrollableState` 内部用 `_gestureRecognizers` 直接构造；`invokeCallback` 的拦截发生在 `GestureRecognizer` 内部。

### 3. `scroll_position.patch`（无对照）
- 目标：`widgets/scroll_position_with_single_context.dart` 的 `applyUserOffset`。
- 用户可见问题：滑到顶/底继续拖时 `setPixels` 返回值不变，但 `userScrollDirection` 仍被翻转，依赖它的悬浮标题、`isScrollingNotifier` 逻辑会误判方向抖动。
- 下游：`grep -rn "updateUserScrollDirection"` → 0 命中。下游只有两处覆写 `applyUserOffset`（`lib/common/widgets/flutter/draggable_scrollable_sheet.dart:835`、`lib/common/widgets/draggable_sheet/dyn.dart:79`），都直接 `super.applyUserOffset(delta)`，拿到的仍是 SDK 原版语义。
- 直接受影响的下游消费者：`lib/common/widgets/sliver/sliver_floating_header.dart:85`（`updateScrollStartDirection(_position!.userScrollDirection)`）与 `:152`、`lib/pages/live_room/controller.dart:534-537`。
- **结论：无下游对应实现 → 潜在回归**。
- 可行性：**B**。`ScrollController.createScrollPosition` 可覆写，所以能在 app/shim 侧派生一个 `ScrollPositionWithSingleContext` 覆写 `applyUserOffset`，但不是 drop-in：每个滚动容器都要换成这个 controller，且 `DraggableScrollableSheet` 等内部已自带 position 的地方盖不住。

### 4. `scrollable.patch`（无对照）
- 目标：`widgets/scrollable.dart`，加 `bool get shouldIgnorePointer => _shouldIgnorePointer;`。
- 用户可见问题：需要知道「当前正在滚动」以便在滚动期间抑制点击（避免手指刚抬起就误触列表项）。
- 下游：`page/scrollable.dart:754` 定义 `bool _shouldIgnorePointer`，`:840-851` `setIgnorePointer`，`:1042-1046` 传给 `IgnorePointer`，**但没有公开 getter**。上游消费者 `lib/pages/dynamics_detail/view.dart:111`（`SelectionTapRegionSurface(isScrolling: () => _scrollable?.shouldIgnorePointer ?? false)`）所需的两个前提在下游都不存在：
  - getter：0 命中；
  - `SelectionTapRegionSurface`：`lib/common/widgets/tap_region_surface.dart` 下游**不存在**（上游有这个文件）。
- **结论：无下游对应实现 → 潜在回归**（下游 `lib/pages/dynamics_detail/view.dart` 也没有 `isScrolling` 回调，滚动期间点击防抖这层彻底缺失）。
- 可行性：**B**。下游已有 vendored `Scrollable`，补一个 getter 是一行；但它只在 vendored 副本里生效，要求调用点统一 import vendored 版本。

### 5. `selectable_region.patch`（部分对照）
- 目标：`InlineSpan`/`PlaceholderSpan`/`TextSpan`/`WidgetSpan`（`computeToPlainTextV2` + `rawText`）、`rendering/paragraph.dart`（`_SelectableFragment.placeholder` 映射、选区绘制合并、`adjustDragOffset` 早退）、`rendering/selection.dart`（`separator`、`isSingle`、`fromDrag`）、`widgets/scrollable.dart`（`separator = '\n'`）、`widgets/selectable_region.dart`（点击空白 `clearSelection`、三击选段全平台、二次点击弹菜单条件、`static _getEffectiveConsecutiveTapCount`）、`widgets/selection_container.dart`、`widgets/text.dart`、`widgets/widget_span.dart`。
- 下游等价能力（都是另一条路实现，不是 vendored 同一份）：
  - 「拖拽越界被吸附到整段首/尾」→ `packages/material_ui/lib/src/selection_edge_clamp.dart:51` 的 `EdgeClampingSelectionContainerDelegate`，在 `dispatchSelectionEventToChild` 里把 `SelectionEdgeUpdateEvent.globalPosition` 按 `selectable.boundingBoxes` 夹回当前行（`:86-140`），再 `selection_area.dart:84` 用 `EdgeClampingSelectionScope` 挂到 `SelectionArea` 子树。
  - 「多段选区拼接符 / 选中文本拿不到」→ `selection_menu.dart:120-145` 的 `SelectionMenuSelectionCache`，由 delegate 在每次事件后 `getSelectedContent()` 记下文本。
  - 「`separator` 为 `\n`」→ 只在下游遗留的 `lib/scripts/selectable_region.patch:1-20`（738 字节的极小补丁）里出现，**未生效**。
- **缺失部分**：`WidgetSpan.rawText`（下游 `grep "WidgetSpan(" -A6 | grep rawText` = 0；上游有 `lib/pages/article/widgets/opus_content.dart:63`、`lib/common/widgets/publish/...` 等 10+ 处用法）、`SelectionEdgeUpdateEvent.isSingle/fromDrag`、`fromDrag && isSingle` 的 Android 夹取、`_getEffectiveConsecutiveTapCount` 改写、点击空白 `clearSelection()`。
- 可行性：夹取/菜单属 **A**（已用公开 API 做到）；`rawText` 需要 `PlaceholderSpan` 新增字段 = **C**；`isSingle/fromDrag` 时序 = **C**。

### 6. `null_safety_for_selectable_region.patch`（已对照，前半部分）
- 目标：`widgets/selectable_region.dart`。
- 崩溃现场：长文阅读页 + 可滚动，`contextMenuAnchors` → `endGlyphHeight` → `_selectionDelegate.value.endSelectionPoint!.lineHeight` 空断言（SDK `selectable_region.dart:1796-1803`，本机 SDK 实测仍是 `!`）。
- 下游对照：`packages/material_ui/lib/src/selection_area.dart:24-42` 注释逐帧记录了同一崩溃栈；`:68-84` 用同名 `SelectionArea` 包住 SDK 版本并注入 `contextMenuBuilder: _nullSafeContextMenuBuilder`；真正的兜底在 `selection_menu.dart:355-370`：
  - `selectionEndpoints` 用 `try { ... } on Object` 兜底（`:355-360`）；
  - `lineHeightAtStart/End` 用 `overlay?.lineHeightAtStart ?? 0`（`:254`）；
  - 完全兜不住时退化到 `renderObject.localToGlobal(Offset.zero)`（`:362-366`）。
- 补丁的第二半（`ScrollEndNotification` 后 `_showHandles()` + `_showToolbar()`）：`ScrollEndNotification` 在 `packages/material_ui` 下 0 命中 → **该半无对照**。
- 可行性：**A**（已用公开 API 实现，且实现方式比打补丁更稳）。

### 7. `text_selection.patch`（部分对照）
- 目标 3 处：
  1. `gestures/tap_and_drag.dart`：`TapAndHorizontalDragGestureRecognizer._hasSufficientGlobalDistanceToAccept` 对 `PointerDeviceKind.touch` 直接返回 `false`；
  2. `widgets/selectable_region.dart`：注释 `_initMouseGestureRecognizer()`，`TapAndHorizontalDragGestureRecognizer` 去掉 `supportedDevices` 过滤；
  3. `widgets/text_selection.dart`：`defaultTargetPlatform` 的 switch 整段注释，所有平台都走 `TapAndHorizontalDragGestureRecognizer`。
- 下游对照：只有第 3 处（vendored 副本）落地——`lib/common/widgets/flutter/text_field/text_selection.dart:1804-1833`：
  ```
  switch (defaultTargetPlatform) {
    // ↓↓↓ 适配flutter 3.32.4-ohos-0.0.1
    // case TargetPlatform.android: ... iOS:
    case TargetPlatform.linux: case TargetPlatform.macOS: case TargetPlatform.windows:  // TapAndPan
    default:  // → TapAndHorizontalDragGestureRecognizer
  ```
  `:1845` 保留 `eagerVictoryOnDrag = defaultTargetPlatform != TargetPlatform.iOS`。
- **缺失**：第 1、2 处（`tap_and_drag.dart` 与 `SelectableRegion` 都没 vendored；`grep "class BaseTapAndDragGestureRecognizer" lib packages` → 只命中 patch 文件）。这会影响 `SelectionArea` 上「手指刚按下就轻微移动 → 被当成横向拖拽选字」的行为。
- 可行性：**B**（vendored 副本已存在，可继续打补丁式修改）；第 1 处 **C**（`TapAndHorizontalDragGestureRecognizer` 被 framework 的 `SelectableRegion` 内部构造）。

### 8. `editable_text.patch`（未实现）
- 目标：`rendering/editable.dart`（`selectionWidthStyle` 默认 `tight`；`_TextHighlightPainter.paint` 按 `top` 分组合并 box、本行补到 `size.width`、末尾单独补一笔；`TextSelection` 用固定 `BoxHeightStyle.max` + `BoxWidthStyle.tight`）、`widgets/editable_text.dart`（`defaultSelectionWidthStyle` → `tight`；`shouldShowCaret` 排除 `cause == SelectionChangedCause.drag`）。
- 用户可见问题：输入框多行文本被选中时，高亮块右侧逐行参差/出现 1px 缝隙；拖拽选字时视口跟着光标跳。
- 下游状态（`lib/common/widgets/flutter/text_field/`）：
  - `editable.dart:298` 构造默认值 `ui.BoxWidthStyle selectionWidthStyle = ui.BoxWidthStyle.max`（未改）；
  - `editable.dart:3150` `_selectionWidthStyle = ui.BoxWidthStyle.tight` 只是 painter 内部字段，`paint` 里仍 `getBoxesForSelection(...).toSet()` 后逐 box `drawRect`（`:3170-3195`），**没有 mergedBox 合并逻辑**；
  - `editable_text.dart:1708-1718` `defaultSelectionWidthStyle` 仍 `return ui.BoxWidthStyle.max`；
  - `editable_text.dart:5054-5056` `shouldShowCaret` 未加 `cause != SelectionChangedCause.drag`。
- **结论：无对应实现（三处全缺）→ 潜在回归**（只是视觉/体验级，不崩）。
- 可行性：**B**（两个文件都已 vendored，需在副本里重做补丁）。

### 9. `text_painter.patch`（无对照）
- 目标：`painting/text_painter.dart` 加 `_TextPainterLayoutCacheWithOffset? get layoutCache => _layoutCache;`。
- 用途：上游 `lib/common/widgets/text_ellipsis/paragraph_ellipsis.dart:92`（`textPainter.layoutCache?.lineMetrics.last.width == 0.0` 判断末行是否空行，决定要不要画 `…`）。
- 下游：`layoutCache` 仅在 `lib/utils/grid.dart:86,93-95,191-215`（`SliverGridLayout? layoutCache`，与 `TextPainter` 无关）。`lib/common/widgets/text_ellipsis/` 目录**下游不存在**（上游有 `text_ellipsis.dart` / `paragraph_ellipsis.dart` / `rich_text_ellipsis.dart`）。下游的「查看更多」是另一套：`lib/common/widgets/flutter/text/paragraph.dart:725-791`（`onShowMore` + `_morePainter` + `didOverflowHeight`）。
- **结论：无对照**（既不需要，也无法替代——两者解决的视觉问题不同：上游是「省略号被裁掉」，下游是「追加一行查看更多」）。
- 可行性：**C**（`TextPainter` 由 `RenderParagraph` 内部持有，无法从外部加 getter）。

### 10. `text.patch`（部分对照）
- 目标：`rendering/paragraph.dart` 加 `TextPainter get textPainter => _textPainter;`；`widgets/text.dart` 加 `typedef OverridingTextStyleTextSpanUtils = _OverridingTextStyleTextSpanUtils;`（避开 `@internal`）。
- 下游：`lib/common/widgets/flutter/text/paragraph.dart:125` `final TextPainter _textPainter;` **无 getter**；`lib/common/widgets/flutter/text/text.dart:398` 与 `:1300`（类声明）直接用私有名 `_OverridingTextStyleTextSpanUtils` —— 因为下游把 `text.dart` 整份 vendored 进同一个文件，不需要 typedef 那半。
- **结论：typedef 部分下游「不需要」；`textPainter` getter 部分无对照**（当前没有消费者，属未触发的缺口）。
- 可行性：**B**（vendored 副本内加一行即可）。

### 11. `sliver.patch`（无对照，但已用别的办法绕过）
- 目标：`widgets/sliver.dart` 加 `typedef SliverZeroFlexParentDataWidget = _SliverZeroFlexParentDataWidget;` 与 `typedef SliverConstrainedCrossAxis_ = _SliverConstrainedCrossAxis;`。
- 用途：上游 `lib/common/widgets/sliver/sliver_constrained_cross_axis.dart`（整个文件 76 行，`CenteredSliverConstrainedCrossAxis extends SliverConstrainedCrossAxis`，内部用 `SliverZeroFlexParentDataWidget` + 继承 `SliverConstrainedCrossAxis_` 覆写 `performLayout` 做水平居中）。
- 下游：两个符号 0 命中；`lib/common/widgets/sliver/` 只有 `sliver_floating_header.dart` 等 6 个文件，**没有 `sliver_constrained_cross_axis.dart`**。上游消费者已改写：
  - `lib/utils/waterfall.dart:19-31` 改用 `SliverLayoutBuilder` + 手动 `SliverPadding` 居中（上游同位置是 `CenteredSliverConstrainedCrossAxis`）；
  - `lib/common/widgets/flutter/chat_list_view.dart:9` 由 `class ChatListView extends ListView` 改为 `extends BoxScrollView` + 自有 `RenderSliverChatList`（`:76-120`），不再需要 `maxExtent` 参数；
  - 下游唯一 `SliverCrossAxisGroup` 用例 `lib/pages/search/view.dart:70` 与上游一致、不依赖该补丁。
- **结论：无对照，但功能上已被 app 侧改写覆盖**（不是回归）。
- 可行性：**C**（`ParentDataWidget` 子类需要 `SliverPhysicalParentData` 内部时序；`_SliverConstrainedCrossAxis` 的 render object 构造不可从外部替换）。替代方案就是当前下游做法（`SliverLayoutBuilder`）。

### 12. `navigator.patch`（无对照）
- 目标：`widgets/navigator.dart`，把 `_popEntry`（SDK 实测 `:5276`）里的 `_afterNavigation(entry.route)` 收进 `if (entry.currentState == _RouteLifecycle.popping)`。
- 用户可见问题：`_afterNavigation` 内部会 `_cancelActivePointers()`（SDK `:5311`，实现在 `:6136-6148`，会在 idle 相位置 `absorbing = true` 吸收本帧后续指针）。push/replace 时误调用 → 新页面刚推入时点击被吞一帧（上游 #1947）。
- 下游：`grep -rn "afterNavigation" lib packages` → 0 命中；无 vendored `navigator.dart`，也没有 app 侧补偿（无 `AbsorbPointer` 相关处理）。
- **结论：无下游对应实现 → 潜在回归**（表现为「刚进页面第一次点击无响应」，与上游修复前一致）。注意下游导航主用 GetX（`Get.toNamed` 232 处），会走 `Navigator` 的 push 路径，风险面更大。
- 可行性：**C**（`NavigatorState` 私有方法，无公开钩子）。

### 13. `image_anim.patch`（无对照）
- 目标：`widgets/image.dart`，`_isPaused = !TickerMode.of(context) || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)` → `_isPaused = !TickerMode.of(context)`。
- 用户可见问题：系统「减弱/关闭动画」设置下，GIF/APNG 完全不动（上游 #2107）。
- 下游：`maybeDisableAnimationsOf` / `disableAnimations` 全库 0 命中（排除 patch 文件）；无 vendored `widgets/image.dart`。`lib/common/widgets/image_viewer/image.dart:393`（app 自己的查看器 `_ImageState`）本来就只读 `TickerMode.valuesOf(context).enabled`，与本补丁无关。
- **结论：无下游对应实现 → 潜在回归**（鸿蒙系统的「减少动画」开着时，动态图会被冻结）。
- 可行性：**B**（需要 vendored 一份 `Image`，约 1200 行，且 `Image` 被 `Image.asset/.network/.file/.memory` 的 189 处调用依赖）。

### 14. `layout_builder.patch`（已对照）
- 目标：`widgets/layout_builder.dart`，注释 `_LayoutBuilderElement` 的 `buildScope` getter、`_buildScope` 字段、`_deferredCallbackScheduled` / `_scheduleRebuild()` / `_frameCallback()`。
- 用户可见问题：`LayoutBuilder` 的 builder 在 postFrame/idle 阶段被延迟重建，导致滚动中一帧的布局滞后/抖动（上游未提 issue，`patch.ps1` 注释仅写 `remove _scheduleRebuild`）。
- 下游对照：`lib/common/widgets/image_grid/image_grid_builder.dart:296-338` —— vendored 的 `_ImageGridBuilderElement` 里同一段代码被整段注释（`:296` `// BuildScope get buildScope => _buildScope;`、`:298-300` `// late final BuildScope _buildScope = BuildScope(...)`、`:302-338` `// _scheduleRebuild` / `// _frameCallback`）。
- 另有第二层：`lib/common/widgets/cached_layout_builder.dart:8-51` `CachedLayoutBuilder` 用稳定 builder 闭包 + `constraints == _previousConstraints` 缓存跳过子树重建；`lib/common/widgets/video_card/video_card_v.dart:381-405` 还有一份私有 `_CachedLayoutBuilder`。
- 可行性：**B**（已实现——但注意 vendored 只覆盖 `image_grid` 内部这一处 element，SDK 全局 `LayoutBuilder` 仍带 deferral）。

### 15. `mouse_cursor.patch`（无对照）
- 目标：`widgets/widget_state.dart`，`WidgetStateMouseCursor.clickable.resolve` 的 `return kIsWeb ? SystemMouseCursors.click : SystemMouseCursors.basic;` → `return SystemMouseCursors.click;`（本机 SDK 实测仍在 `:439`）。
- 用户可见问题：桌面/鸿蒙鼠标悬停按钮（FAB、ListTile、Tab）不变手型，只有 web 会变（上游 #182466）。
- 下游：无自定义 `MouseCursor` 子类；`lib/common/widgets/flutter/list_tile.dart:933-936`、`lib/common/widgets/flutter/vertical_tabs.dart:1954-1958` 都直接 `WidgetStateMouseCursor.clickable.resolve(...)`，拿到的是 `basic`。零星页面自己显式设了 `SystemMouseCursors.click`（`lib/pages/audio/volume_button.dart:67`、`lib/pages/member_guard/view.dart:138`、`lib/pages/member_home/widgets/live_item.dart:103` 等），但这只是逐点补救，不是补丁语义。
- **结论：无下游对应实现 → 潜在回归**（仅桌面/鼠标场景）。
- 可行性：**B**（`WidgetStateMouseCursor` 的 `resolve` 被 framework 多处内部调用，要改默认就得 vendored `widget_state.dart` 并让所有 vendored 组件 import 它；shim 里最多只能提供「显式传 cursor」的封装）。

### 16. `double_tap_gesture.patch`（已对照）
- 目标：`gestures/multitap.dart`，`_registerSecondTap(tracker)` → `_registerSecondTap(tracker, event)`，`_checkUp(int)` → `checkUp(int, PointerUpEvent)`，`checkUp` 从私有变公开。
- 用途：图片查看器需要知道「双击第二下抬起的时间戳」，才能判断紧随其后的单击是否要当成「双击后的单击」忽略。
- 下游对照：`lib/common/widgets/gesture/image_double_tap_gesture_recognizer.dart:19-71`，**完全用公开 API 复刻**：
  - 文件头注释（`:11-18`）明确写了「上游 patch SDK 暴露 `checkUp(buttons, event)`；鸿蒙 SDK 不 patch，改用 pointerroute + 包 `onDoubleTap`」；
  - `:48-56` `addAllowedPointer` 里先 `GestureBinding.instance.pointerRouter.addRoute(event.pointer, _recordPointerUp)`；
  - `:58-58+` `_recordPointerUp` 记 `_lastUpTimeStamp = event.timeStamp`；
  - `:34-44` `onDoubleTap` getter/setter 包一层，回调前 `timeStamp = _lastUpTimeStamp`。
  - 消费点：`lib/common/widgets/image_viewer/gallery_viewer.dart:527-528`（`_tapGestureRecognizer.timeStamp - _doubleTapGestureRecognizer.timeStamp < ...`）。
- 可行性：**A**（已实现，纯公开 API）。

### 17. `draggable_scrollable_sheet.patch`（已对照）
- 目标：`widgets/draggable_scrollable_sheet.dart` —— 新增 `initialScrollOffset` 字段并传给 `_DraggableScrollableSheetScrollController(initialScrollOffset:)` → `createScrollPosition(initialPixels:)`；`typedef DraggableScrollableSheetState = _DraggableScrollableSheetState;`、`typedef DraggableScrollableSheetScrollController = ...;`、`typedef DraggableScrollableSheetScrollPosition = ...;`；`_DraggableScrollableSheetState` 抽出 `initScrollController()`、加 `set scrollController`、`extent` getter。
- 用户可见问题：从外部（比如点某条消息）打开抽屉时要让它初始就滚到某个位置。
- 下游对照：**整文件 vendored**：`lib/common/widgets/flutter/draggable_scrollable_sheet.dart`（1099 行，`import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;` @ `:12`），并拆出两个 part：
  - `lib/common/widgets/draggable_sheet/topic.dart:4-19` `TopicDraggableScrollableSheet` 自带 `initialScrollOffset`（与上游补丁等价，只是做在子类上）；
  - `:30-50` 覆写 `initState` 重建 `_extent` 与控制器；
  - `:52-76` `_TopicDraggableScrollableSheetScrollController` 覆写 `initialScrollOffset` 并在 `createScrollPosition` 里传 `initialPixels: _initialScrollOffset`（`:71`）；
  - `lib/common/widgets/draggable_sheet/dyn.dart:4-45` 另一套 `DynDraggableScrollableSheet`；
  - `lib/common/widgets/flutter/draggable_scrollable_sheet.dart:554-570`（`_DraggableScrollableSheetState` 可被 part 继承）、`:807` `_DraggableSheetExtent get extent => getExtent();`、`:792-805`（`initialPixels` 已进入 position 构造）。
- 可行性：**B**（已实现，靠整份 vendored + part 子类）。

### 18. `fab.patch`（`flutter/` 部分，无对照）
- 目标：`material/floating_action_button.dart`，`build` 里 `if (heroTag != null) { result = Hero(tag: heroTag!, child: result); }` 整段注释（`patch.ps1` 注释：`remove Hero effect`）。
- 用户可见问题：FAB 在路由切换时做 Hero 飞行动画，视觉上突兀；且同页多个 FAB 用默认 tag（SDK 默认值是同一个 `const _DefaultHeroTag()` 实例，本机 SDK `floating_action_button.dart:95,140,183,225`）会命中 `heroes.dart:292` 的 `'There are multiple heroes that share the same tag within a subtree.'` 断言。
- 下游：**无对应实现**。`heroTag` 在下游只出现在视频卡片/路由参数（`lib/common/widgets/video_card/video_card_v.dart:55,72,86,141,187`、`lib/pages/audio/controller.dart:193`），与 FAB 无关；无 FAB 包装类（`grep "class .*FloatingActionButton"` → 0）。
- 具体风险点：`lib/pages/blacklist/view.dart:179` 与 `:184` 在**同一个 `Column`**（同一个 `fab:` slot）里放了两个 `FloatingActionButton`，都没传 `heroTag`（上游 `blacklist/view.dart` 同样如此，但上游靠补丁去掉了 Hero）→ 下游 debug 模式会触发 duplicate-hero 断言，release 下则是动画异常。
- 可行性：**A**。`packages/material_ui` 可以 `hide FloatingActionButton` 后导出一个同名包装类，内部固定 `heroTag: null` 转发给 SDK 版本（`.extended` / `.small` / `.large` 三个命名构造也要一并转发，共约 4 个构造）。代价是调用点的 widget 运行时类型变化。

## 需要注意的整体风险排序

1. **会崩/会断言**：`fab.patch`（`blacklist` 双 FAB 同 tag，仅 debug 断言，但下游无补救）。
2. **明确功能回归（上游已修、下游未修）**：
   - `scroll_view.patch`（底部 30px 拖拽抢点击）
   - `navigator.patch`（push 后首帧吞点击）
   - `image_anim.patch`（系统「减少动画」冻结 GIF）
   - `scroll_position.patch`（悬浮标题方向抖动）
   - `mouse_cursor.patch`（桌面/鸿蒙鼠标不变手型）
   - `scrollable.patch`（滚动期点击抑制能力缺失，连带 `SelectionTapRegionSurface` 整个机制缺失）
   - `editable_text.patch`（多行选区高亮缝隙 + 拖拽选字视口跳动）
   - `scrollable_gesture.patch` 的嵌套手势半区
   - `null_safety_...` 的 `ScrollEndNotification` 重显示半区
   - `selectable_region.patch` 的 `WidgetSpan.rawText`（复制表情会得到占位符而不是原文）
3. **已被下游等效覆盖（不算缺口）**：`double_tap_gesture`、`draggable_scrollable_sheet`、`layout_builder`、`null_safety`（前半）、`sliver`（用改写绕过）、`text.patch` 的 typedef 半区。
4. **无法在 `packages/material_ui` 内解决（C 类）**：`scroll_view`、`navigator`、`text_painter`、`sliver`、`tap_and_drag` 半区、`NestedRawGestureDetector` 半区。这几项只能靠 vendored 框架文件（B）或等鸿蒙 SDK 升级后重新 patch。
