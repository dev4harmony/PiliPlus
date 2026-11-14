# 把补丁下沉到 `packages/material_ui` 的方案

> 目标：让下游（鸿蒙 fork）与上游 `bggRGjQaUbCoE/PiliPlus` 的**源码差异尽可能小**，
> 把「因为不能改 SDK 而不得不改名/改调用点」的那部分差异，收敛到一个可删除的目录里。
>
> 结论先行：**能下沉的是「Material/Widgets 层类改写」，不是「SDK 补丁」本身。**
> `packages/material_ui` 是 `flutter/material.dart` 的映射 shim，它拿不到 SDK 私有符号，
> 所以上游那 39 个 patch 里只有一部分能以「同名 drop-in 包装」的形式搬进来；
> 剩下的必须保持现状（vendored 或 app 侧规避）。
> 但**即便是这一部分**，也能消掉下游与上游最大的一类冲突：类改名 + 49 处 `hide` 子句。

---

## 0. 先纠正三个前提（都影响方案）

在动手之前，必须先承认现状与仓库里的注释不一致：

| 项 | 仓库里的说法 | 实测 | 影响 |
|---|---|---|---|
| 鸿蒙 SDK 版本 | `packages/material_ui/pubspec.yaml` 注释称「3.41」、`packages/*/pubspec.yaml` 称「3.47 才会有 Material 拆分」；根 `pubspec.yaml` 写 `flutter: ">=3.44.9"` | **`3.47.7+ohos-0.0.1-canary`**（`flutter --version`，revision `0529879a65`） | shim 注释里的「退出方式=等升到 3.47」已经到期，但**仍然不能退出**，原因见下 |
| Material 是否还在 SDK 内 | 隐含「3.47 已拆出去」 | **仍在**：`packages/flutter/lib/material.dart` 有 181 条 `export 'src/material/...'`，`src/material/` 184 个文件；SDK **没有** `packages/material_ui` 目录 | 鸿蒙 fork 没有跟上游 3.47 的 pub 包拆分，所以 shim 仍然必要且**长期必要**（不是临时过渡） |
| 下游的 patch 是否生效 | — | **全部失效**。`lib/scripts/` 16 个 `.patch` 没有任何 `patch.ps1`，`.github/workflows/` 里 `git apply` 0 命中 | 这些是死文件，见 §5 处置建议 |

> ⚠️ 因为「鸿蒙 SDK 里 Material 没拆出去」，`packages/material_ui` 的定位**不该再写成
> 『等 3.47 就删』的临时 shim**，而应写成「永久适配层」。这直接影响 §4 的目录结构设计：
> 临时 shim 可以糙，永久适配层必须按库的规矩写（测试、lint、版本门槛）。

---

## 1. 上游 `lib/scripts` 到底在干什么

`patch.ps1` 分**三段**执行，三段改的树完全不同，这是理解一切的关键：

| 段 | 变量 | 目标树 | 条数 | 下游能否照做 |
|---|---|---|---|---|
| **A** | `$patches` | `$FLUTTER_ROOT/packages/flutter/lib/src/**`（本地 SDK） | 28 个顶层补丁（按平台增删） | ❌ 不能（改 SDK 会影响 CI 与所有项目） |
| **B** | `$patches_material` | `<pub-cache>/material_ui-*/lib/src/**` | 10 个 `material/*.patch` | ❌ 不能（下游没有真实 `material_ui` 包，只有 shim） |
| **C** | `$patches_cupertino` | `<pub-cache>/cupertino_ui-*/lib/src/**` | 1 个 `cupertino/*.patch` | ❌ 同上 |

合计 **39 个补丁文件**（28 + 10 + 1）。按「改的是什么」可分成四类：

| 类别 | 补丁 | 本质 |
|---|---|---|
| **① 暴露私有成员**（typedef / getter / 构造） | `scaffold`、`tabs`、`sliver`、`text`、`text_painter`、`scrollable`、`draggable_scrollable_sheet`、`double_tap_gesture`、`modal_barrier`(部分) | 上游想让 app 能 `extends`/访问框架私有类 |
| **② 加公开参数** | `scrollable_gesture`（`PageView`/`TabBarView`/`Scrollable` 注入识别器）、`navigation_drawer`（`flex`）、`text_field`（`selectAllOnFocus = false`） | 给框架组件加可配置项 |
| **③ 纯行为修补**（上游认为 SDK 有 bug） | `scroll_view`、`scroll_position`、`navigator`、`image_anim`、`layout_builder`、`mouse_cursor`、`editable_text`、`fab`、`refresh_indicator`、`popup_menu`、`selectable_region`、`null_safety_for_selectable_region`、`text_selection` | 改框架内部逻辑 |
| **④ app 侧代码补丁**（不是 SDK 补丁） | `geetest_ios`、`bottom_sheet_ios_piliplus` | 直接改 `lib/**`，与 SDK 无关 |

**关键判断**：只有 ②③ 里「目标类本身是公开的、且不依赖跨库私有符号」的那些，才可能以
同名包装的形式搬进 shim。① 类（typedef 私有类）**原理上做不到**——shim 无法
`typedef` 一个 SDK 里的私有符号。

---

## 2. 下游现在是怎么解决的（三种手段）

下游完全不改 SDK、不改 pub-cache，靠三招：

| 手段 | 规模 | 位置 |
|---|---|---|
| **A. vendored 整份框架源码** | 31 个文件，`+11685 / -1356` 行 | `lib/common/widgets/flutter/**`、`lib/common/widgets/scaffold/**` |
| **B. shim 包内同名/改名实现** | 10 个文件，约 3300 行 | `packages/material_ui/lib/**` |
| **C. app 侧改写规避** | 分散 | 如 `scroll_physics.dart` 用 `RawGestureDetector` 外挂识别器、`waterfall.dart` 改写 sliver |

`lib/**` 相对上游 tag `up-2.1.6.2` 的总差异：**367 文件 / +23828 / -11395**。
其中 vendored 目录独占 **31 文件 / +11685 / -1356**（约 49% 的新增行）。
去掉 vendored 目录后是 336 文件 / +12143 / -10039。

即：**vendored 框架源码是下游差异的最大单一来源**，所以它也是本方案的主战场。

### 2.1 覆盖度盘点（哪些补丁有对应、哪些是静默回归）

综合 `docs/_analysis_core_patches.md` 与 `docs/_analysis_material_patches.md`：

| 状态 | 补丁 |
|---|---|
| ✅ 已有等价实现 | `double_tap_gesture`（pointer-route 记录 `timeStamp`）、`layout_builder`（整段注释 `BuildScope`）、`draggable_scrollable_sheet`（整文件 vendored）、`null_safety_for_selectable_region`（shim 内 null 兜底）、`scrollable_gesture` 的**参数部分** |
| 🟡 有问题但换了个算法 | `refresh_indicator`（改用「固定布局+绘制期缩放」）、`selectable_region`（shim 内夹取+菜单）、`text_selection`（vendored 注释掉平台 switch） |
| ❌ **无对应实现 = 静默回归** | `scroll_view`、`scroll_position`、`scrollable`、`editable_text`、`text_painter`、`navigator`、`image_anim`、`mouse_cursor`、`fab`、`scrollable_gesture` 的**嵌套手势部分**、`text_selection` 的 `tap_and_drag` 部分 |

> ❗ 这一栏是本方案最该被重视的部分：**这些不是「换了个做法」，是能力缺失**。
> 其中 `navigator`（push 后首帧吞点击）、`scroll_position`（悬浮标题抖动）、
> `image_anim`（系统「减少动画」冻结 GIF）有明确用户可见症状，
> 而下游 `Get.toNamed` 有 232 处走 Navigator，风险面很大。

### 2.2 最致命的一类差异：**改名**

上游靠 patch 让框架**保持原名**，下游因为改不了 SDK 只能**改名**，于是：

| 上游名字（patch 后） | 下游名字 | 下游位置 |
|---|---|---|
| `TabBarView`（带 `scrollDirection`） | **`CustomTabBarView`** | `lib/common/widgets/flutter/tabs.dart:25` |
| `TabBarView`（带 recognizer 参数） | `TabBarView<T>`（同名但**必填** recognizer、**泛型**） | `lib/common/widgets/flutter/page/tabs.dart:27` |
| `PageView`（带 recognizer） | `PageView<T>` | `lib/common/widgets/flutter/page/page_view.dart:71` |
| `Scrollable`（带 recognizer） | `Scrollable<T>` | `lib/common/widgets/flutter/page/scrollable.dart:76` |
| `StandardBottomSheet` | **`_StandardBottomSheet`（降为私有）** | `lib/common/widgets/scaffold/mini_scaffold.dart:232` |
| `StandardBottomSheetState` | `_StandardBottomSheetState`（私有） | 同上 `:261` |
| `PersistentBottomSheetController` | **`MiniBottomSheetController`** | 同上 `:216` |
| `BottomSheetState` / `BottomSheetDefaultsM3` | **不存在** | — |
| `DynTabBar` | **不存在** | 退回裸 `TabBar` |
| `TabBarState`/`IndicatorPainter`/`TabBarLayoutCallback`/`TabLabelBarRenderer` | **全部不存在** | — |
| `TextField.selectAllOnFocus = false` | 无默认值（行为相反） | `packages/material_ui/lib/src/selection_widgets.dart:169` |

改名又连带出第二重差异：**49 个文件的 `material_ui` import 带 `hide` 子句**
（`hide ListTile` ×19、`hide TabBarView` ×6、`hide TextField` ×4 …）。
这些 import 行与上游永久不一致。

**这就是本方案要解决的问题**：把 vendored 实现搬进 shim 并**改回上游原名**，
让业务代码里的类名和 import 行与上游**逐字一致**。

---

## 3. 为什么不能「把补丁搬进 material_ui」

必须先把边界说清楚，否则方案会落空。

`packages/material_ui/lib/material_ui.dart` 的本质是一行 re-export：

```dart
export 'package:flutter/material.dart' hide TranslateAnimationSource, ...;
export 'src/selection_area.dart';
```

它是**普通 Dart 库**，受同样的可见性规则约束：

| 上游 patch 干的事 | shim 能否做到 | 原因 |
|---|---|---|
| `typedef BottomSheetState = _BottomSheetState;` | ❌ | shim 看不到 SDK 的 `_BottomSheetState` |
| 给 `_IndicatorPainter` 加 `get layoutCache` | ❌ | shim 不能给 SDK 私有类加成员 |
| 改 `applyUserOffset` 的 `updateUserScrollDirection` 时机 | ❌ | 要改 `ScrollPositionWithSingleContext` 内部 |
| 改 `WidgetStateMouseCursor.resolve` 返回值 | ❌ | 要改 `widget_state.dart` |
| 给**公开类**加参数、包一层同名 widget | ✅ | 这正是 `SelectionArea`/`TextField` 已经在做的事 |
| 整份复制框架文件进来（含其私有符号） | ✅ | 副本内私有符号自成一套（代价见 §3.2） |

### 3.1 结论

> **「把补丁移到 material_ui」的正确读法是：把「下游为了规避补丁而写在 `lib/` 里的
> vendored 副本」搬进 `material_ui`，并在那里恢复上游的公开名字。**
> 而不是把 SDK 补丁本身搬进去。

### 3.2 搬迁的两个硬约束

**约束一：副本的私有符号是「另一套」，会切断 SDK 的私有查找链。**

以 `Scrollable` 为例（`lib/common/widgets/flutter/page/scrollable.dart:508` 有自建
`_ScrollableScope`）。SDK 里 19 处调用 `Scrollable.of()` / `Scrollable.maybeOf()`
（`scrollbar.dart`、`reorderable_list.dart`、`sliver_floating_header.dart`、
`text_selection.dart`、`dropdown_menu.dart`、`cupertino/nav_bar.dart` …），
它们找的是 **SDK 的** `_ScrollableScope`。副本子树里若出现这些 SDK widget，
`Scrollable.of` 会**找不到** → `Scrollable.of()` 直接抛错。

> 这是**当前已存在**的隐患（不是本方案引入的），但它是「不要把 vendored 面扩大」的理由：
> 每多搬一个「会被 SDK 内部反查」的类，风险就多一层。

判定规则：**优先搬「叶子类」（自己不被 SDK 反查）**，例如
`PopupMenuItem`、`TabBar`(侧)、`DraggableScrollableSheet`、`Text`/`RichText`；
**谨慎搬「有私有 Scope / 被 SDK 反查」的类**，例如 `Scrollable`、`PageView`、`Scaffold`。

**约束二：shim 不能反向依赖 app。**

`material_ui` 是被 app `path:` 依赖的底层包。它一旦 `import 'package:PiliPlus/...'`
就是循环依赖（虽然 Dart 能编，但语义倒置，且 shim 无法独立测试）。
目前 `packages/material_ui` 的 `pubspec.yaml` 只依赖 `flutter`，必须保持。

---

## 4. 方案

### 4.1 总体策略：按「可下沉度」分三层处置

| 层 | 判据 | 处置 | 收益 |
|---|---|---|---|
| **L1 纯搬 + 改回原名** | vendored 文件 **零** `package:PiliPlus` 依赖 | 搬进 `packages/material_ui/lib/src/vendored/`，名字改回上游 | ⭐⭐⭐ 消掉改名 + `hide` |
| **L2 搬 + 拆依赖** | 有少量 app 依赖，但可参数化剥离 | 搬进 shim，app 依赖改成构造参数/静态注入（仿 `SelectionMenuConfig`） | ⭐⭐ 部分收益 |
| **L3 保持现状** | 依赖 `Pref`/业务模型/私有 Scope | **不搬**，留在 `lib/`，但补注释说明原因 | 0（但避免踩坑） |

### 4.2 L1：可整份搬进 shim 的文件（本方案主体）

判据是**「唯一的 `package:PiliPlus` 引用指向同批搬迁的兄弟文件」**——这种内部引用
搬进 shim 后改成相对 import 即可，不算 app 依赖。逐个核对过（括号内为那唯一一条引用）：

| 文件 | 行数 | 唯一 app 引用 | 搬入后应恢复的上游名字 |
|---|---|---|---|
| `lib/common/widgets/flutter/pop_scope.dart` | 77 | — | 保持（上游已有同名文件） |
| `lib/common/widgets/flutter/popup_menu.dart` | 155 | — | `CustomPopupMenuItem` → **`PopupMenuItem`**（含 `IconTheme.merge` 修正） |
| `lib/common/widgets/scaffold/bottom_sheet.dart` | 178 | — | `BottomSheet_` → **`BottomSheet`** 子类 |
| `lib/common/widgets/flutter/live_list_view.dart` | 302 | — | 保持（上游已有同名文件） |
| `lib/common/widgets/flutter/tabs.dart` | 370 | — | `CustomTabBarView` → **`TabBarView`** |
| `lib/common/widgets/flutter/page/tabs.dart` | 374 | → `page/page_view.dart` | `TabBarView<T>` → **`TabBarView`**（去泛型、参数改可选，对齐上游） |
| `lib/common/widgets/flutter/chat_list_view.dart` | 385 | — | 保持（上游已有同名文件） |
| `lib/common/widgets/scaffold/mini_scaffold.dart` | 399 | → `scaffold/bottom_sheet.dart` | `_StandardBottomSheet` → **`StandardBottomSheet`**；`MiniBottomSheetController` → **`PersistentBottomSheetController`** |
| `lib/common/widgets/flutter/page/page_view.dart` | 451 | → `page/scrollable.dart` | `PageView<T>` → **`PageView`** |
| `lib/common/widgets/flutter/page/scrollable_helpers.dart` | 208 | → `page/scrollable.dart` | 随 `scrollable.dart` 一起 |
| `lib/common/widgets/flutter/draggable_scrollable_sheet.dart` | 1099 | → 2 个 `part` 文件 | `initialScrollOffset` + 公开 `State`/`extent`/`ScrollController`/`ScrollPosition` |
| `lib/common/widgets/flutter/page/scrollable.dart` | 1857 | → `page/scrollable_helpers.dart` | `Scrollable<T>` → **`Scrollable`**（⚠️ 见约束一） |
| `lib/common/widgets/flutter/list_tile.dart` | 1952 | — | 保持 `ListTile` 同名 vendored（消掉 19 处 `hide ListTile`） |
| `lib/common/widgets/flutter/text/rich_text.dart` | 354 | → `text/paragraph.dart` | 随 `paragraph.dart` |
| `lib/common/widgets/flutter/text/paragraph.dart` | 3860 | — | 公开 `RenderParagraph.textPainter` getter |
| | **合计 12021 行（15 文件）** | | |

⚠️ **`text_field/adaptive_text_selection_toolbar.dart`（385 行）与
`text_field/cupertino/adaptive_text_selection_toolbar.dart`（256 行）不属于 L1**：
它们唯一的外部 import 是 `text_field/editable_text.dart`，而后者是 §4.4 的 L3
（引业务模型 `image_type.dart`）。二者**绑死在 vendored 的 `EditableTextState` 上**
（`:145` `editableTextState.contextMenuButtonItems`、`:146` `contextMenuAnchors`），
不能脱离 `text_field/**` 单独搬走。→ 归入 L3。

> 注意 `draggable_scrollable_sheet.dart` 的 2 个 `part` 文件
> （`lib/common/widgets/draggable_sheet/{dyn,topic}.dart`）里的 `part of` 指令也要
> 同步改成 shim 内的路径，否则搬完编译不过。

**目标目录结构**（与上游 `lib/common/widgets/flutter/` 的层级保持可对照关系）：

```
packages/material_ui/
  pubspec.yaml                 # + collection 依赖；写明"永久适配层"
  lib/
    material_ui.dart           # 扩充 hide 列表 + 新增 export
    src/
      selection_*.dart         # 现有 10 个文件不动
      arkui_scroll_physics.dart
      ohos_selection_theme.dart
      compat/                  # ← 新增：补丁等价实现（15 个文件，12021 行）
        pop_scope.dart
        popup_menu.dart               # → PopupMenuItem
        list_tile.dart                # → ListTile（同名）
        text.dart                     # → Text / RichText / RenderParagraph
        tabs.dart                     # → TabBarView（合并 page/tabs.dart，去泛型）
        page_view.dart                # → PageView + Scrollable + ScrollableHelpers
        draggable_scrollable_sheet.dart
        bottom_sheet.dart             # → BottomSheet / StandardBottomSheet / PersistentBottomSheetController
        chat_list_view.dart
        live_list_view.dart
```

`material_ui.dart` 相应扩成：

```dart
export 'package:flutter/material.dart'
    hide
        TranslateAnimationSource,
        SelectionArea, SelectionAreaState,
        SelectableText, TextField, TextFormField,
        // ↓ 新增：这些改由 src/compat/ 提供同名实现
        TabBarView, PageView, Scrollable, ScrollableState,
        DraggableScrollableSheet, PopupMenuItem, ListTile,
        Text, RichText, RenderParagraph,
        BottomSheet;
export 'src/compat/tabs.dart';
export 'src/compat/page_view.dart';
...
```

> 这样业务代码里的 `import 'package:material_ui/material_ui.dart' hide TabBarView;`
> 可以**全部删掉 `hide` 子句**，import 行与上游逐字一致。

### 4.3 L2：需要拆依赖才能搬

| 文件 | 阻塞依赖 | 拆法 |
|---|---|---|
| `flutter/vertical_slider.dart` (2686) | `os_type` | shim 加 `os_type` 依赖（第三方 pub 包，可接受） |
| `flutter/refresh_indicator.dart` (700) | `refresh_layout.dart`、`scroll_behavior.dart`、`scroll_physics.dart`、`platform_utils.dart`、`storage_pref.dart`、`extended_nested_scroll_view`、`os_type` | ⚠️ 最硬的是 **`:30` 顶层 `double _displacement = Pref.refreshDisplacement`**（库级初始化读 SharedPreferences）。必须改成构造参数注入，否则会把「用户设置」耦合进 shim。**建议本阶段先不动**。 |
| `flutter/vertical_tabs.dart` (2404) | `pages/main/controller.dart`、`get`×2 | 把 `MainController` 的用法抽成参数（`flex`/`onSelect`），中成本 |
| `scaffold/simple_scaffold.dart` (223) | `utils/extension/scroll_controller_ext.dart` | 把扩展方法内联成私有函数，低成本 |

### 4.4 L3：明确不搬（写进注释，防止后来人再试）

| 文件 | 原因 |
|---|---|
| `flutter/text_field/**`（12 文件，21116 行，含两个 `adaptive_text_selection_toolbar`） | `controller.dart:20-21` 引 `network_img_layer.dart` + 业务模型 `image_type.dart`；`editable_text.dart:29` 引 `share_utils.dart`。**业务模型进框架源码**，不可接受。两个 adaptive toolbar 绑死在 vendored `EditableTextState` 上，只能随它一起留 |
| `flutter/refresh_indicator.dart` | 顶层 `Pref.*` 初始化（见上） |
| `flutter/page/scrollable.dart` + `scrollable_helpers.dart` | 私有 `_ScrollableScope` 被 SDK 19 处反查（约束一）。**可以搬，但列为最后一步**，需单独回归 |

---

## 5. 配套动作（不做这些，方案只做了一半）

### 5.1 删掉死补丁

`lib/scripts/` 的 16 个 `.patch` 当前**不生效**，只起误导作用（读代码的人会以为打了补丁）。
建议：

- 整个 `lib/scripts/` 目录删除（`build.ps1` 下游已经删了，剩下 16 个 `.patch`）；
- 如果还要保留「上游改了什么」的可追溯性，改成 `docs/upstream-sdk-patches.md` 一张表
  （内容 = 本文 §1 + 两份 `_analysis_*.md`），比留 patch 文件有用得多。

> 删掉 16 个死文件后，`lib/scripts/` 与上游的差异从「16 个文件」变成「目录不存在」，
> 这本身也是一次差异收敛。

### 5.2 补齐静默回归（与搬迁并行，优先级更高）

§2.1 表里 ❌ 的那一栏是**功能缺失**，不是「写法不同」。按用户可见程度排：

| 优先 | 补丁 | 症状 | 做法 |
|---|---|---|---|
| P0 | `navigator` | push 后首帧点击被吞 | `_afterNavigation` 私有，只能 vendored `navigator.dart`（⚠️ 大）；或评估是否可接受 |
| P0 | `text_field`（`selectAllOnFocus`） | 桌面点输入框即全选 | **一行**：`selection_widgets.dart` 里默认 `false` |
| P1 | `scroll_position` | 到顶/到底后仍报方向，悬浮标题抖动 | vendored `ScrollPositionWithSingleContext`，或 app 侧判断 |
| P1 | `image_anim` | 系统「减少动画」冻结 GIF | vendored `widgets/image.dart` |
| P1 | `popup_menu` | 图标不跟文字色 | 4 行（在 shim 的 `PopupMenuItem` 里） |
| P2 | `scroll_view` | 列表底部 30px 内手势误判 | 需 `Scrollable` 纵向识别器开口子（C 类，难） |
| P2 | `mouse_cursor` | 桌面按钮不变手型 | 仅桌面，收益低 |

### 5.3 恢复上游调用点写法

搬完之后，把下游**为适配改名而改过的调用点**改回上游写法。这样 diff 才真正收敛：

```dart
// 现在（下游）
TabBarView<TabBarDragGestureRecognizer>(
  horizontalDragGestureRecognizer: () => TabBarDragGestureRecognizer(isDxAllowed: isDxAllowed),
  ...
)

// 目标（= 上游）
TabBarView(
  horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,   // 方法 tear-off
  ...
)
```

涉及：`episode_panel/view.dart`、`history/view.dart`、`later/view.dart`、
`video/introduction/pgc/widgets/intro_detail.dart`、`main/view.dart`、
`live_room/view.dart`、`article/view.dart`、`gallery_viewer.dart`。

配套：`CustomHorizontalDragGestureRecognizer` 的 `Type get runtimeType => HorizontalDragGestureRecognizer`
（`lib/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart:60`）这个 hack 可以退掉——
上游靠 patch 让 `Scrollable` 直接接受注入，不需要伪装 runtimeType。

---

## 6. 实施顺序与验收

### 阶段划分

| 阶段 | 内容 | 涉及文件 | 风险 | 验收 |
|---|---|---|---|---|
| **P0** 准备 | ①改 `packages/material_ui/pubspec.yaml` 注释为「永久适配层」；②补 `docs/upstream-sdk-patches.md`；③删 `lib/scripts/` 16 个死补丁 | 3 | 低 | `dart analyze` 通过 |
| **P1** 低风险搬迁 | `popup_menu.dart`、`list_tile.dart`、`text/`、`adaptive_text_selection_toolbar`、`pop_scope`、`chat_list_view`、`live_list_view` —— 都是**叶子类**，不被 SDK 反查 | 8 | 低 | 删对应 `hide`；`dart analyze` 0 error |
| **P2** 半屏状态机 | `scaffold/{bottom_sheet,mini_scaffold}.dart` 搬入 + 恢复 `StandardBottomSheet`/`StandardBottomSheetState`/`PersistentBottomSheetController`/`BottomSheetState` 原名 | 2 + 调用点 | 中 | `mini_scaffold` 引用点 10 处改回原名；弹半屏回归 |
| **P3** Tab 族 | `tabs.dart`+`page/tabs.dart` 合并成一个上游形状的 `TabBarView`（去泛型、参数可选、补 `TabBarState`/`IndicatorPainter`/`DynTabBar`） | 2 + 8 调用点 | 中高 | 4 个 `TabBarView` 调用点改回上游写法 |
| **P4** Sheet/Page | `draggable_scrollable_sheet.dart`、`page_view.dart` | 2 + 11 调用点 | 中 | 7 处 part 文件路径改；`PageView` 调用点 4 处 |
| **P5** Scrollable | `page/scrollable.dart`+`scrollable_helpers.dart`（**最后做**，约束一） | 2 | 高 | 单独回归：`Scrollbar`、`ReorderableListView`、`DropdownMenu`、文本选择在 `PageView` 子树内 |
| **P6** 静默回归 | §5.2 的 P0/P1 项 | 视项而定 | 中 | 手测对应场景 |

**增量收益**：P1–P4 完成后，`lib/common/widgets/flutter/` + `scaffold/` 下可移走
**约 10000 行** vendored 副本（14 个文件）、**10 处类改名**、**约 30 处 `hide` 子句**
（49 处带 `hide` 的 import 里，`hide ListTile`×19、`hide TabBarView`×6、
`hide TextField`×4、`hide PageView`×2、`hide DraggableScrollableSheet`×3、
`hide PopupMenuItem`×1、`hide Text/RichText`×2 等可直接删掉）。
剩下 `text_field/**`（21116 行，12 文件）是最大残留，属 L3 不动。

> ⚠️ **`DynTabBar` / `TabBarState` / `IndicatorPainter` 不在 P1–P4 收益内**：
> 它们需要 vendored 完整的 `material/tabs.dart`（2944 行，含 `_TabLabelBarRenderer`、
> `_IndicatorPainter`、`_LayoutCallback` 等私有链）。这是一次独立的大搬迁，
> 建议单列 P7 并单独评估——当前下游用裸 `TabBar` 也能工作，只是少了标签布局定制。

### 每阶段验收命令

```bash
cd /d/github/PiliPlus

# 1. 静态分析（CI 同款）
/d/github/flutter_flutter/bin/dart analyze --no-fatal-warnings

# 2. 确认 shim 没有反向依赖 app
grep -rn "package:PiliPlus" packages/ && echo "❌ shim 污染" || echo "✅ shim 干净"

# 3. 确认没有遗留的改名类
grep -rn "CustomTabBarView\|MiniBottomSheetController\|_StandardBottomSheet\b" lib packages

# 4. 统计与上游差异（对比基线 367 文件 / +23828 / -11395）
git diff --numstat up-2.1.6.2 -- lib | awk '{a+=$1;d+=$2;n++} END {print "files="n,"+="a,"-="d}'

# 5. 构建验证
/d/github/flutter_flutter/bin/flutter build hap --release --dart-define-from-file=.vscode/env.json
```

> ⚠️ CI（`.github/workflows/pr_check.yml`）用的是 **`subosito/flutter-action` 的官方
> 3.44.9**，不是鸿蒙 fork。所以 CI 里 `packages/material_ui` 的 `flutter/material.dart`
> 路径同样存在，但**没有 `TargetPlatform.ohos`**——shim 里 `selection_platform.dart`
> 已经用 `toString()` 比较规避了这个问题，搬迁新文件时要沿用这个约定。

---

## 7. 诚实的风险评估

### 7.1 这个方案能拿到什么

- ✅ 消掉**改名类**（16 处）和**`hide` 子句**（约 30 处）→ 这是同步时冲突最集中的两类。
- ✅ 把 vendored 面从「散在 `lib/` 各处」收敛到「一个可删除的包」→ 与上游合并时
  `lib/` 的冲突面显著变小，而 `packages/` 在上游根本不存在，**零冲突**。
- ✅ 让 `lib/**` 的结构与上游 `lib/common/widgets/flutter/` 对齐。

### 7.2 这个方案拿不到什么（别抱错期待）

- ❌ **不能减少总代码量**。搬进 shim 只是换位置，`+11685` 行仍然存在，
  只是从「与上游冲突的 `lib/`」挪到「与上游无冲突的 `packages/`」。
- ❌ **不能消除 L3 的差异**（`text_field/**` 21116 行、`refresh_indicator` 等）。
- ❌ **不能修好 §5.2 的静默回归**——那是独立工作，且 P0 的 `navigator` 可能需要
  vendored `navigator.dart`（约 6000 行），代价很高，需要单独决策。
- ❌ **不能让鸿蒙 SDK 摆脱 shim**。§0 已确认鸿蒙 fork 至今没做 Material 拆分，
  shim 是长期的。

### 7.3 最大的三个风险

1. **约束一（私有 Scope 断链）**：搬 `Scrollable`/`PageView` 进 shim 后，若 SDK 内部
   widget 需要 `Scrollable.of()`，会找不到。**必须**在 P5 单独做全链路回归
   （`Scrollbar`/`ReorderableListView`/`DropdownMenu`/文本选择/`RefreshIndicator`）。
   缓解：把 `Scrollable` 放最后，或干脆不搬（保留现状的 `lib/` vendored）。
2. **CI 与本地 SDK 不一致**：CI 跑 3.44.9 官方版，本地 3.47.7 鸿蒙版。
   shim 里的代码要能同时在两者下 `analyze` 通过（`TargetPlatform.ohos` 不存在、
   部分 API 缺失）。**建议**：P1 起每步都在本地跑一次 `dart analyze`，
   而不是等 CI。
3. **`up-2.1.6.2` 是移动靶**：下游落后上游（upstream HEAD `b2d6a5bef`），
   搬迁期间上游可能又改这些文件。**建议**搬迁作为一个独立分支短周期完成，
   不要在长同步分支里做。

---

## 8. 一句话总结

> 上游 39 个补丁解决的是「SDK 不给的能力」；下游改不了 SDK，只能 vendored + 改名。
> 本方案把 vendored 副本里**能脱离 app 依赖的 15 个文件**（12021 行）搬进
> `packages/material_ui` 并**恢复上游原名**，从而消掉 10 处类改名和约 30 处 `hide` 子句——
> 这是下游与上游冲突最密集的部分。`text_field/**`（21116 行）和私有 Scope 类保持现状。
> 同时必须正视 §2.1 里 9 个**静默回归**，它们与搬迁无关，但比搬迁更影响用户。

---

## 附：本次分析产出

- `docs/_analysis_core_patches.md` — 17 个非 Material 补丁的逐条分析（含 file:line 证据）
- `docs/_analysis_material_patches.md` — 12 项 Material/Cupertino 补丁的逐条分析 + 搬运阻塞清单
