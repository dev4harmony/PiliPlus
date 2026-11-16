# Material / Cupertino 层补丁分析：上游 vs 鸿蒙下游

> 范围：`/d/github/piliplus-upstream/PiliPlus/lib/scripts/` 下 material / cupertino / app 级补丁，
> 对照 `/d/github/PiliPlus`（Flutter-ohos 3.44.9，不 patch SDK、不 patch pub-cache）。
>
> 结论先行：**本层几乎所有补丁在下游都没有等价实现**。下游只覆盖了「能靠公开 API 重写」的
> 3 处（bottom sheet 拖拽手势、TabBarView 的 scrollDirection、bottom sheet 状态机），
> 其余 12 处（iOS 手势返回关闭半屏、菜单遮罩抬起即关闭、图标随文字色、桌面鼠标手型、
> selectAllOnFocus、NavigationDrawer ripple、TabBar 布局钩子）处于**能力缺失**状态，
> 而非「换了个写法」。

---

## 0. patch 分发方式（先决背景）

`lib/scripts/patch.ps1` 分三段执行，三段的目标树完全不同：

| 段 | 变量 | 目标 | 说明 |
|---|---|---|---|
| A | `$patches`（patch.ps1:125-135） | `$env:FLUTTER_ROOT/packages/flutter/lib/src/**` | 直接改本地 Flutter SDK。下游做不到。 |
| B | `$patches_material`（patch.ps1:212-227） | `<pub-cache>/material_ui-*/lib/src/**`（patch.ps1:237-268） | 改 pub-cache 里的 material 包。下游同样不做。 |
| C | `$patches_cupertino`（patch.ps1:276-290） | `<pub-cache>/cupertino_ui-*/lib/src/**`（patch.ps1:294-313） | 同上。 |

平台条件：`bottom_sheet_android.patch` 只在 `android` 分支加（patch.ps1:135-137），
`bottom_sheet_ios_flutter.patch` 只在 `ios` 分支加（patch.ps1:143-145）。
material/cupertino 段用同样条件（patch.ps1:219-224、281-283）。

下游 `lib/scripts/` 里只剩 11 个 patch 文件、**没有 patch.ps1、没有 CI 步骤**
（`.github/workflows/` 只有 `pr_check.yml` / `release.yml`），因此这些补丁全部是死文件。

---

## 1. 汇总表

图例：✅ = 有等价实现；🟡 = 有替代但行为不等价 / 名字不同；❌ = 下游完全没有；⛔ = 需访问框架私有成员。

| # | 补丁 | 上游行为改动（一句话） | 下游机制 | 上游同名兼容？ | 阻塞点 |
|---|---|---|---|---|---|
| 1 | `material/bottom_sheet_android.patch`<br>`bottom_sheet_android.patch` | 半屏 `_BottomSheetGestureDetector` 的竖直拖拽识别器接 `MediaQuery.maybeGestureSettingsOf`，让 touchSlop 跟随系统 | 🟡 只对 MiniScaffold 生效：自写 `BottomSheet_` 用 `Listener` + 自建识别器（`scaffold/bottom_sheet.dart:61`）。SDK `showModalBottomSheet` 路径未覆盖 | ✋ widget 名 `BottomSheet_` 保留了，但基类从 `BottomSheet` 变成 `StatefulWidget` | 无（纯公开 API） |
| 2 | `material/bottom_sheet_ios_flutter_material.patch`<br>`bottom_sheet_ios_flutter.patch`<br>`cupertino/bottom_sheet_ios_flutter.patch`<br>`bottom_sheet_ios_piliplus.patch` | iOS 侧滑返回可关闭非持久半屏；并让「本地历史条目」在手势 pop 时整体出栈而不是只摘一层 | ❌ 无。`grep popGestureEnabled / gesturePop` 全仓 0 命中；`mini_scaffold.dart:102` 的 `LocalHistoryEntry` 不带参数；`common_slide_page.dart:150` 的 `SlideDragGestureRecognizer` 无 `gestureSettings` 覆写 | — | ⛔ 需改 `LocalHistoryEntry` 构造、`LocalHistoryRoute.didPop`、`ModalRoute.popGestureEnabled`，全是框架私有/内部状态 |
| 3 | `material/fab.patch`<br>`fab.patch` | 注释掉 FAB 内部自动 `Hero(tag: heroTag)` 包裹，默认 `heroTag` 不再参与转场 | ❌ 无代码等价物。只有 3 处调用点显式写 `heroTag: null`（`common_dyn_page.dart:338`、`main_reply/view.dart:98`、`video/reply/view.dart:130`），其余 FAB 仍带默认 tag | — | ⛔ 需改 `FloatingActionButton.build`（SDK 内部） |
| 4 | `material/modal_barrier_material.patch`<br>`modal_barrier.patch` | 弹窗菜单遮罩改为 **pointer-down 即关闭**（原本 up 才关），修「点菜单项被遮罩先吃掉」；配 `ModalRoute.isMenu` 显式开关 | ❌ 无。`grep isMenu` 全仓 0 命中；`showMenu` 调用点十余处（`image_grid_view.dart:152`、`gallery_viewer.dart:609`、`live_room/superchat/superchat_card.dart:106` 等）全走 SDK 原行为；`PublishRoute extends PopupRoute`（`publish_route.dart:4`）无法 opt-in | — | ⛔ 需改 `ModalBarrier`、`_AnyTapGestureRecognizer`、`_PopupMenuRoute`、`ModalRoute`，四层全私有 |
| 5 | `material/navigation_drawer.patch`<br>`navigation_drawer.patch` | ① `NavigationDrawer` 新增 `flex` 参数（可调列表区占高）；② 目的地 `inkWell` 外包一层 `Material(type: transparency)` 修水波纹不显示/错位 | 🟡 `flex` 用外层 `Spacer(flex:2)` + `Expanded(flex:5)` 硬编码替代（`pages/main/view.dart:445-447`）；**ripple 那半完全没有** | 🟡 用 SDK 原名 `NavigationDrawer`，但 `flex`/`header` 参数不存在 → 参数级不兼容 | ⛔ ripple 修复点在 `_NavigationDestinationBuilder`（私有类） |
| 6 | `material/popup_menu.patch`<br>`popup_menu.patch` | `PopupMenuItemState` 在非 disabled 时用 `IconTheme.merge(color: style.color)` 包 icon，让图标跟随文字色 | 🟡 只有 token 层（`fontSize:13`），无图标色；vendored `flutter/popup_menu.dart` 内 `grep IconTheme` 0 命中 | ✋ 类名 `CustomPopupMenuItem` / `CustomPopupMenuItemState` 与上游一致，但实现被精简，行为缺失 | 无（但需重写，见第 6 节） |
| 7 | `material/refresh_indicator.patch`<br>`refresh_indicator.patch` | `_RefreshProgressIndicatorPainter.paint` 加 `if (size == .zero) return;`，修「背景圆已消失但弧还在画」 | 🟡 换思路：不冻结布局尺寸，改用固定布局 + 绘制期缩放（`flutter/refresh_indicator.dart:523-528` 注释 + `refresh_layout.dart:137` `tightFor` + `refresh_layout.dart:161` 的 `scaleFactor > 0` 守卫） | — | 无（纯公开 API），但**内层用的仍是 SDK `RefreshProgressIndicator`**（`refresh_indicator.dart:537`），零尺寸绘制隐患未在框架层消除 |
| 8 | `material/scaffold.patch`<br>`scaffold.patch` | 把 `_BottomSheetState` / `_StandardBottomSheet(State)` / `_BottomSheetDefaultsM3` / `PersistentBottomSheetController` 转成公开可继承：typedef 别名、公开 `childKey`、`handleDrag*`、`.widget`/`.completer` getter、公开 const 构造 | 🟡 **整段重写**：`scaffold/bottom_sheet.dart:17` `BottomSheet_`（StatefulWidget）+ `scaffold/mini_scaffold.dart:232` `_StandardBottomSheet` + `:216` `MiniBottomSheetController` | ❌ **类被改名且降为私有**：`StandardBottomSheet`→`_StandardBottomSheet`、`StandardBottomSheetState`→`_StandardBottomSheetState`、`PersistentBottomSheetController`→`MiniBottomSheetController`、`BottomSheetState`→无 | ⛔ 上游是「把私有类 typedef 出来」，下游无法 typedef 私有类 |
| 9 | `material/tabs.patch`<br>（app 级 `tabs.patch` 已不存在，见 §2.9） | ① `TabBarView` 加 `scrollDirection` / `hitTestBehavior` / `horizontalDragGestureRecognizer`；② `TabBar` 暴露 `TabBarState`、`buildIndicator`、`buildTabLabelBar`、`applyFillAlignment` 与 `IndicatorPainter`/`TabBarLayoutCallback` typedef，供子类改标签布局；③ 跳过 `_debugTabAlignmentIsValid` 断言 | 🟡 **两套分叉**：<br>① `flutter/tabs.dart:25` `CustomTabBarView` 只补 `scrollDirection`（`:37/:74/:359`）<br>② `flutter/page/tabs.dart:27` `TabBarView<T>` 全量 vendored，带 `horizontalDragGestureRecognizer`（`:40/:43/:369`）+ `hitTestBehavior`<br>③ TabBar 侧 **完全无对应**，`DynTabBar` 下游不存在 | ❌ `CustomTabBarView` 是改名；`page/tabs.dart` 的 `TabBarView` 参数与上游同名但需显式传 recognizer，调用点无法直接复用 | ⛔ 第②③项要 `_IndicatorPainter`、`_TabLabelBarRenderer`、`_LayoutCallback` 等私有类型 |
| 10 | `material/text_field.patch`<br>`text_field.patch` | `TextFormField`/`TextField.selectAllOnFocus` 默认改 `false`，修桌面端点输入框即全选 | ❌ **反向**：vendored `text_field/text_field.dart:327` 仍是 `this.selectAllOnFocus,`（无默认值），`editable_text.dart:1736-1748` 仍按平台给桌面 `true`；shim `selection_widgets.dart:169` 直接 `super.selectAllOnFocus`（null） | — | 无（纯公开 API，属最易补的一项） |
| 11 | `mouse_cursor.patch` | `WidgetStateMouseCursor.resolve` 在非 web 也返回 `SystemMouseCursors.click`，桌面/鸿蒙上按钮指针变手型（原为箭头） | ❌ 无。下游全靠零散 `SystemMouseCursors.click` 硬写（`audio/volume_button.dart:67`、`member_guard/view.dart:138`、`member_home/widgets/live_item.dart:103`、`search_panel/all/widgets/user.dart:155`）；框架级 `WidgetStateMouseCursor.clickable`（`flutter/list_tile.dart:936`、`vertical_slider.dart:956`、`vertical_tabs.dart:1958`）仍解析成箭头 | — | ⛔ 需改 `packages/flutter/lib/src/widgets/widget_state.dart` |

---

## 2. 逐补丁详情

### 2.1 `material/bottom_sheet_android.patch` + `bottom_sheet_android.patch`

- **目标**：`material_ui/lib/src/bottom_sheet.dart` 私有 `_BottomSheetGestureDetector.build`（material 版 hunk @1412）；
  SDK 版同一类，hunk @1412。两边 hunk 内容完全一致，只差文件前缀。
- **改动**：给 `RawGestureDetector` 里的 `VerticalDragGestureRecognizer` 补一行
  `..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)`。
- **用户可见问题**：Android/harmony 上系统手势阈值（`DeviceGestureSettings.touchSlop`，通常
  8-18vp）被无视，半屏拖拽永远按 Flutter 默认常量判定，表现为「手指没怎么动就跟着走」或
  「要拖很久才有反应」，与系统其它面板手感不一致。
- **私有成员**：不需要。`_BottomSheetGestureDetector` 虽是私有类，但改动只碰公开的
  `RawGestureDetector`/识别器属性，**属于可移植改动**。
- **下游**：🟡 半覆盖。
  - `lib/common/widgets/scaffold/bottom_sheet.dart:61` `..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)`
    完全照抄了这一行；
  - 但它是**另一条代码路径**：下游没有继承 SDK `BottomSheet`，而是把整个 widget 重写成
    `BottomSheet_ extends StatefulWidget`（`bottom_sheet.dart:17`），用 `Listener(onPointerDown:)`
    + 自建 `_VerticalDragGestureRecognizer`（`:165`）驱动拖拽；
  - 因此该修复**只对 `MiniScaffold` 里弹出的半屏生效**，全仓几十处 `showModalBottomSheet`
    （`article/view.dart:445`、`audio/view.dart:204`、`dyn/common_dyn_page.dart` 等）走的仍是
    SDK 内部 `_BottomSheetGestureDetector`，手感问题依旧。
- **同名兼容性**：widget 名 `BottomSheet_` 与上游一致（上游也是 `class BottomSheet_ extends BottomSheet`），
  **但基类不同**（上游 `:6` 是 `extends BottomSheet`，下游 `:17` 是 `extends StatefulWidget`）。
  任何以 `BottomSheet` 类型接收它的地方会编译失败。
- **imports**：`flutter/gestures.dart`（`:1`）、`material_ui/material_ui.dart`（`:2`）。
  **无 app-only 依赖，可直接搬进 `packages/material_ui`。**

### 2.2 iOS 侧滑返回关闭半屏（4 个补丁联动，下游 0 覆盖）

四个文件必须一起看，缺一不可：

| 文件 | 目标 | 改动 |
|---|---|---|
| `cupertino/bottom_sheet_ios_flutter.patch` | `cupertino_ui/lib/src/route.dart` | `_startPopGesture` 断言放宽为 `route.popGestureEnabled \|\| route.popGestureEnabled_`；给 `_CupertinoBackGestureDetector` 加 `popGestureEnabled_` 回调；新增私有 `_HorizontalDragGestureRecognizer`（stop 时把 `gestureSettings` 复位 null）；`_handlePointerDown` 里对「仅历史条目可 pop」的分支压到 `touchSlop: 28`；`navigator.pop()` → `navigator.pop(gesturePop)` |
| `bottom_sheet_ios_flutter.patch` | 同上（SDK 路径）+ `material/scaffold.dart` + `widgets/routes.dart` | 与上表同一份 cupertino 改动；`ScaffoldState.showBottomSheet` 的 `LocalHistoryEntry` 加 `popGestureEnabled: true`；`routes.dart` 新增 `LocalHistoryEntry.popGestureEnabled`、`LocalHistoryRoute.popGestureEnabled_`、`gesturePop` 哨兵、`didPop` 里遇到 `gesturePop` 就清空整条本地历史 |
| `bottom_sheet_ios_piliplus.patch` | **app 代码** | `pages/common/slide/common_slide_page.dart` 给 `SlideDragGestureRecognizer` 覆写 `gestureSettings => DeviceGestureSettings(touchSlop: 5.0)`（侧滑返回更灵敏）；`common/widgets/scaffold/mini_scaffold.dart` 的 `LocalHistoryEntry` 加 `popGestureEnabled: true` |

- **用户可见问题**：iOS 上从屏幕左缘右滑，期望「关掉当前半屏」，实际要么完全没反应
  （半屏不是路由，`Navigator` 不认），要么把**整个页面** pop 掉。上游让半屏注册的
  `LocalHistoryEntry` 声明「我可以被手势 pop」，并在手势命中时用 `gesturePop` 哨兵一次性
  清空本地历史再 `super.didPop`，从而手势只弹半屏。
- **私有成员**：⛔ 重度依赖。`_CupertinoBackGestureDetector`/`_CupertinoBackGestureController`
  是私有类；`LocalHistoryRoute._localHistory` 是私有字段；`_localHistory` 的 `didPop` 改写
  直接在 mixin 里操作私有列表。**下游无法用扩展/子类实现**，哪怕愿意 fork
  `local_history` 也不行——因为 `ModalRoute` 混入的是 SDK 里的那份 mixin。
- **下游**：❌ 无对应。
  - `grep -rn "popGestureEnabled|gesturePop" lib packages` → 0 命中；
  - `scaffold/mini_scaffold.dart:102` 的 `LocalHistoryEntry(onRemove: ...)` 只有 `onRemove`，
    没有也不可能传 `popGestureEnabled`；
  - `pages/common/slide/common_slide_page.dart:150` 的 `SlideDragGestureRecognizer` 只有
    `isPointerAllowed`，**缺少上游 piliplus 补丁加的那 4 行 `gestureSettings` 覆写**
    → 即便底层能 pop，灵敏度也没调；
  - `lib/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart:42` 里有 `touchSlopH`
    这套机制（`Pref.touchSlopH`，`storage_pref.dart:1066`，默认 12.0），但它是给
    `TabBarDragGestureRecognizer` 用的，**与半屏返回无关**。
- **替代可行性**：只能用「在 MiniScaffold 里自己 `Listener` 判左缘滑动手势 + 手动 close」重做，
  代价是绕过 `Navigator` 的返回仲裁（与系统返回键、`PopScope` 冲突）。
  **建议判定为「鸿蒙/iOS 侧永久缺失」，不要试图搬进 shim。**

### 2.3 `material/fab.patch` + `fab.patch`

- **目标**：`material_ui/lib/src/floating_action_button.dart` `FloatingActionButton.build`（两版 hunk 内容一致）。
- **改动**：把 `if (heroTag != null) { result = Hero(tag: heroTag!, child: result); }` 整段注释掉。
- **用户可见问题**：FAB 默认 `heroTag` 是同一个 `const _DefaultHeroTag()`。同屏出现 2 个以上
  FAB（`blacklist/view.dart:179` 与 `:184` 就并排两个）时，一旦跨路由转场，Flutter 会抛
  「There are multiple heroes that share the same tag」并中断转场动画。
- **私有成员**：不需要（虽然 `_DefaultHeroTag` 是私有，改动只删逻辑）。
- **下游**：❌ 无。`git show 204715266`（commit 名 `remove FAB hero`）**只新增了 patch 文件本身**，
  没有任何代码改动，正是「vestigial」的典型。
  - 仅 3 处调用点显式 `heroTag: null`：`pages/common/dyn/common_dyn_page.dart:338`、
    `pages/main_reply/view.dart:98`、`pages/video/reply/view.dart:130`——上游同样有这 3 处，
    说明它们是**业务层规避**，不是本补丁的替代。
  - 风险点举例：`lib/pages/blacklist/view.dart:179`/`:184` 两个 FAB 都未传 `heroTag`
    → 同一 `Column` 内两个默认 tag，从该页 push 详情页时仍有概率触发重复 tag。
- **替代可行性**：⚠️ 可以，且成本最低——业务侧给每个 FAB 传唯一 `heroTag`，或干脆统一传
  `heroTag: null`。**不需要动框架**。建议列为「可用代码约定替代」。

### 2.4 `material/modal_barrier_material.patch` + `modal_barrier.patch`

- **目标**：
  - material 版：只有 `material_ui/lib/src/popup_menu.dart` 里的 `_PopupMenuRoute`（hunk @1023），加 `bool get isMenu => true;`
  - SDK 版：三文件联动——
    - `material/popup_menu.dart` `_PopupMenuRoute.isMenu => true`（hunk @1014）
    - `widgets/modal_barrier.dart`：`ModalBarrier`/`AnimatedModalBarrier` 新增 `isMenu`；
      `_ModalBarrierGestureDetector` 把单一 `onDismiss` 拆成 `onAnyTapUp` / `onAnyTapDown`；
      `_AnyTapGestureRecognizer` 新增 `onAnyTapDown` 并在 `handleTapDown` 里 invoke
      （原实现是故意 `// Do nothing.`）
    - `widgets/routes.dart` `ModalRoute`：新增 `bool get isMenu => false;` 并透传给两种 barrier
- **用户可见问题**：弹出菜单（`showMenu`）时，「点空白处关闭」原本要等**抬手**才触发。用户
  按下即决定要关，手指一抬却被菜单项抢先响应，出现「想关菜单结果误点到某一项」
  （长按视频卡片的菜单尤其容易误触）。
- **私有成员**：⛔ 需要。`_PopupMenuRoute`、`_AnyTapGestureRecognizer`、
  `_AnyTapGestureRecognizerFactory`、`_ModalBarrierGestureDetector` 全是私有类；
  `ModalRoute.buildModalBarrier` 是框架内部构建点。
- **下游**：❌ 无。`grep -rn "isMenu" lib packages` → **0 命中**。
  - 十余处 `showMenu` 全部裸用 SDK（`image_grid/image_grid_view.dart:152`、
    `image_viewer/gallery_viewer.dart:609`、`download/download_action_mixin.dart:113`、
    `live_room/superchat/superchat_card.dart:106`、`video_popup_menu.dart:325` 等）；
  - 下游唯一自定义 `PopupRoute` 是 `pages/common/publish/publish_route.dart:4`
    `PublishRoute<T> extends PopupRoute<T>`，**没有 `isMenu` 可覆写**，天然无法参与；
  - `lib/harmony_adapt/shell_bars_observer.dart:51` 的注释明确把
    「dialog/bottomSheet/popupmenu」当 `PopupRoute` 统一处理——说明下游是**观测**层
    popup，而不是改它的 barrier 语义。
- **替代可行性**：❌ 不可。没有公开的 barrier 定制入口（`PopupRoute` 的 barrier 由
  `ModalRoute` 内部无条件构造，`barrierDismissible` 只能开/关不能改时机）。
  只能整条自写 `showMenu` 替身（复制 `_PopupMenuRoute` + `_PopupMenuRouteLayout`），
  工程量 ≈ 重写 `popup_menu.dart` 全文件。

### 2.5 `material/navigation_drawer.patch` + `navigation_drawer.patch`

- **目标**：`navigation_drawer.dart`，两版 hunk 相同（material 版行号 @73/198/416，SDK 版 @67/192/410）。
- **改动**（两件事被打包进一个补丁）：
  1. `NavigationDrawer` 新增 `final int flex`（默认 1），传给内部 `Expanded(flex: flex)`；
  2. 私有 `_NavigationDestinationBuilder` 里 `child: inkWell` → `child: Material(type: MaterialType.transparency, child: inkWell)`。
- **用户可见问题**：① 平板/横屏侧边抽屉里，头部区（头像+搜索）和页签列表的高度比例写死，
  无法按屏幕自适应；② 页签的 `InkWell` 缺少 `Material` 祖先时，水波纹要么不画，
  要么画在错误的坐标系里（选中的圆角指示器外溢/被裁）。
- **私有成员**：① 不需要；② ⛔ 需要（`_NavigationDestinationBuilder` 是私有类）。
- **下游**：🟡 半点覆盖，且是**换机制**。
  - `flex` 那半：`lib/pages/main/view.dart:445-447` 用 `const Spacer(flex: 2)` +
    `Expanded(flex: 5, child: SizedBox(width: 130, child: Obx(() => NavigationDrawer(...))))`
    手工拼出同一个 2:5 比例，**没有用 `NavigationDrawer.flex`**（该参数在 3.44.9 SDK 里不存在）。
    同文件 `:451` 就是 `NavigationDrawer(` 的调用点。
  - ripple 那半：❌ **完全没有**。全仓 `grep -n "MaterialType.transparency"` 的 20+ 处
    都是业务卡片/列表项自己包的，没有一处针对 `NavigationDrawerDestination`。
  - 额外差异：上游 `:451` 之后用 `header: Expanded(flex: 4, child: userAndSearchVertical())`
    把头部塞进抽屉；下游没有 `header` 参数，改成在 `Column` 里自己排（`:443-447` 之前）。
- **同名兼容性**：用了 SDK 原名 `NavigationDrawer`，看起来「没改」，但 `flex` / `header`
  两个构造参数在下游**不存在**——从上游同步任何给 `NavigationDrawer` 传这两个参数的代码
  会直接编译失败。这是「名字兼容、参数不兼容」的隐蔽型冲突。
- **替代可行性**：ripple 那半可用「自定义 `NavigationDrawerDestination` 包装」绕过
  （下游已有 `lib/common/widgets/floating_navigation_bar.dart:140` `FloatingNavigationDestination` 这种先例），
  但会引入第二套 destination 类型。建议保持现状 + 文档标注。

### 2.6 `material/popup_menu.patch` + `popup_menu.patch`

- **目标**：`popup_menu.dart` 的公开类 `PopupMenuItemState.build`（material 版 @454，SDK 版 @446）。
- **改动**：在 `if (states.contains(WidgetState.disabled)) { … }` 之后补 `else` 分支，
  用 `IconTheme.merge(data: IconThemeData(color: style.color), child: item)` 包一层。
- **用户可见问题**：菜单项里如果放的是 `Icon`（而非带 `TextStyle` 的 `Text`），图标不会跟随
  菜单项的 `labelTextStyle.color`——深色主题下出现「文字是白的、图标还是主题蓝/黑」，
  或禁用态图标色与文字不对齐。
- **私有成员**：不需要（`PopupMenuItemState` 是公开类，`style`/`states` 都是局部变量）。
  **这是本层里少数「一行 hunk、零私有依赖」的补丁。**
- **下游**：🟡 有替代文件、无替代行为。
  - `lib/common/widgets/flutter/popup_menu.dart:9` `CustomPopupMenuItem`、
    `:31` `CustomPopupMenuItemState`——类名与上游 `flutter/popup_menu.dart` **完全一致**；
  - 但 `:34` 的 `build` 是一份精简重写：`ListTileTheme.merge` → `AnimatedDefaultTextStyle`
    → `ConstrainedBox` → `Padding` → `Align`，**没有任何 `IconTheme`**（该文件 `grep IconTheme` = 0）；
  - 也就是说：上游补丁修的那个 icon 色问题，在下游这份自写实现里**依旧存在**；
  - 使用范围极小：只有 `pages/live_room/widgets/chat_panel.dart:342` 一处用
    `CustomPopupMenuItem`（配 `:346` 的 `CustomPopupMenuDivider`）。
- **下游与上游该文件的唯一差异**：`diff` 显示只有 `contentPadding: .zero` →
  `EdgeInsetsGeometry.zero`（`:43`）这一处格式化差异，即上游 vendored 文件的补丁内容
  **没有同步过来**。
- **替代可行性**：✅ 极易。在 `CustomPopupMenuItemState.build` 里补 4 行 `IconTheme.merge`
  即可，**可以搬进 `packages/material_ui`**（见第 4 节）。

### 2.7 `material/refresh_indicator.patch` + `refresh_indicator.patch`

- **目标**：`progress_indicator.dart` 私有 `_RefreshProgressIndicatorPainter.paint`
  （material 版 @1309，SDK 版 @1279）。
- **改动**：`paint` 开头加 `if (size == .zero) return;`。
- **用户可见问题**：下拉刷新收起的瞬间，指示器的**背景圆已经缩到 0**，但弧线仍按
  `arrowheadScale`/旧 `size` 画一帧，出现「圆形背景消失了、弧还飘在那里」的闪烁拖影。
- **私有成员**：不需要（`_RefreshProgressIndicatorPainter` 私有，但改动只加一行早退）。
- **下游**：🟡 换思路，且**未真正消除**。
  - `lib/common/widgets/flutter/refresh_indicator.dart` 是完整 vendored 副本（含
    `RefreshIndicatorState` 公开类 `:220`）。它的做法是**不缩小布局尺寸**：
    把 `scale:` 从 `_scaleFactor` 换成 `_layoutScale`（`:525-528`，注释解释「布局尺寸固定，
    缩放交给绘制期的 ScaleTransition」），并新增 `edgeOffset`（`:147`）。
  - 承接的 `lib/common/widgets/refresh_layout.dart:137` 用
    `BoxConstraints.tightFor(width: scaleSize, height: scaleSize)`，
    `:161` 用 `if (indicator != null && heightFactor > 0 && scaleFactor > 0)` 挡住绘制。
  - 但 `refresh_indicator.dart:537` 里内层用的**仍是 SDK 的 `RefreshProgressIndicator`**，
    其 painter 未被 patch。所以「零尺寸仍 paint」的**根因没消除**，只是下游用自己的布局
    保证不去触发它。任何走 SDK `RefreshIndicator`（非下游这份 vendored 版）的路径无保护。
- **替代可行性**：✅ 若愿意搬，整份 `flutter/refresh_indicator.dart` 需要先剥离 6 个 app 依赖，
  见第 4 节（**重度阻塞**）。

### 2.8 `material/scaffold.patch` + `scaffold.patch`（半屏状态机的「公开化」）

这是本层改动面最大、对下游影响最深的一组。

- **目标 / 改动**（material 版与 SDK 版内容一致，只差泛型与行号）：

| 目标类 | 改动 | 用途 |
|---|---|---|
| `_BottomSheetState` | 加 `typedef BottomSheetState = _BottomSheetState;`；加 `GlobalKey get childKey`；`_handleDragStart/Update/End` 去下划线改公开 | 让 app 能继承 SDK 半屏状态，只替换「拖拽入口」而不复制整套逻辑 |
| `_BottomSheetDefaultsM3` | 加 `typedef BottomSheetDefaultsM3 = _BottomSheetDefaultsM3;` | 让 app 读到 M3 默认 `constraints` |
| `ScaffoldFeatureController` | 加 `T get widget => _widget;` 和 `Completer<U> get completer => _completer;` | 让 app 能比较/等待当前半屏 |
| `_StandardBottomSheet` | `typedef StandardBottomSheet = _StandardBottomSheet;` | 让 app 能 `extends StandardBottomSheet` |
| `_StandardBottomSheetState` | `typedef StandardBottomSheetState = …`；`_handleDragStart/End` 公开；`didUpdateWidget` 放宽 | 让 app 覆盖动画曲线 |
| `PersistentBottomSheetController` | 加一个**公开 const 构造**（转发 `super.widget` 等）+ `bool get isLocalHistoryEntry` | 让 app 能自己 new 控制器 |

  material 版额外把 `_StandardBottomSheetState<T extends _StandardBottomSheet>`
  泛型化（`scaffold.patch` 的 SDK 版没有泛型）。**两版不等价**，material 版更新。

- **用户可见问题**：`MiniScaffold`（自定义迷你脚手架）需要「在指定高度带内可拖拽」的半屏。
  SDK 把状态类全设为私有 → app 只能整段复制。上游用 typedef 把私有类「假装公开」，
  再靠公开的 `handleDragStart/Update/End` + `childKey` 只换拖拽入口。
- **私有成员**：⛔ **这个补丁的本质就是「给私有类开洞」**。所有 6 个 typedef 别名指向
  `_` 开头的 privates。下游无法做同样的事——Dart 的 typedef 不能引用库外私有符号。
- **下游**：
  - `lib/common/widgets/scaffold/bottom_sheet.dart:17` `BottomSheet_ extends StatefulWidget`
    ——**不是** `extends BottomSheet`，因为它无法继承私有 `_BottomSheetState`；
    整套 `_childHeight` / `_dismissUnderway` / fling 阈值（`_minFlingVelocity = 700.0`、
    `_closeProgressThreshold = 0.5`，`:5-6`）都是手抄 SDK 常量。
  - `lib/common/widgets/scaffold/mini_scaffold.dart:232` `_StandardBottomSheet`（**私有**）、
    `:261` `_StandardBottomSheetState`（**私有**）——上游是公开的 `StandardBottomSheet`。
  - `lib/common/widgets/scaffold/mini_scaffold.dart:216` `MiniBottomSheetController`
    ——替代上游 `PersistentBottomSheetController`，字段 `widget`/`completer`/`close`/
    `setState`/`isLocalHistoryEntry` 都在，但类型是 `_StandardBottomSheet`（私有）。
  - 文件头注释（`mini_scaffold.dart:3-7`）明确写了这是 port：
    「Port of the Flutter framework's private `_StandardBottomSheet` / `PersistentBottomSheetController`
    internals, which are not public in the HarmonyOS Flutter SDK.」
  - 上游对应位置的写法见 `piliplus-upstream/.../mini_scaffold.dart:56-57`
    （`GlobalKey<StandardBottomSheetState>` / `late StandardBottomSheet bottomSheet`）与
    `:175` `class _StandardBottomSheet extends StandardBottomSheet`。
- **同名兼容性**：❌ **全面改名 + 降级**。下游所有相关文件内部自洽（自己用自己），
  但从上游同步时，任何出现 `StandardBottomSheet` / `StandardBottomSheetState` /
  `PersistentBottomSheetController` / `BottomSheetState` / `BottomSheetDefaultsM3` 的代码
  在下游**全部无法解析**。`MiniBottomSheetController` 这个名字在上游**不存在**。
- **替代可行性**：⚠️ 已是最优解（重写），但可以**搬进 `packages/material_ui` 并把名字改回上游名**
  ——`mini_scaffold.dart` + `bottom_sheet.dart` 两个文件的 import 里没有 app-only 依赖
  （见第 4 节），搬过去后可以把 `_StandardBottomSheet` 复活成公开 `StandardBottomSheet`，
  从而恢复同名兼容。

### 2.9 `material/tabs.patch`（app 级 `tabs.patch` 已消失）

> ⚠️ **注意**：任务清单里列的 app 级 `lib/scripts/tabs.patch` **在现存上游仓库里已不存在**。
> `git log --all -- 'lib/scripts/tabs.patch'` 显示它在 commit `1ded09f24`（"opt scrollable gesture"）
> 被删除，删前内容只有一件事：给 SDK `TabBarView` 加 `scrollDirection`（`git show 1ded09f24^:lib/scripts/tabs.patch`）。
> 该能力后来并入 `material/tabs.patch`。所以「app 级 tabs.patch」的实际对应物 = 下文 material 版。

`material/tabs.patch` 一个文件里塞了 3 组互不相干的改动：

**① `TabBarView` 三个新参数（公开 API，零私有依赖）**
- 构造函数（patch @2338）新增：`scrollDirection`（默认 horizontal）、`hitTestBehavior`
  （默认 `HitTestBehavior.opaque`）、`horizontalDragGestureRecognizer`
  （默认 `HorizontalDragGestureRecognizer.new`）。
- `_TabBarViewState.build`（@2650）把它们透传给 `PageView`。
  > 注意 `hitTestBehavior` 和 `horizontalDragGestureRecognizer` 实际是 `PageView` 的参数，
  > 上游同时也 patch 了 `Scrollable`/`PageView`（`scrollable_gesture.patch`、`scrollable.patch`），
  > 三者必须同时生效，tabs 这里只是转发。
- **用户可见问题**：`TabBarView` 无法竖直（底部导航做侧栏时按页切换）、无法替换水平拖拽
  识别器（自定义 touchSlop/角度判定）、无法调命中测试行为。

**② `TabBar` 子类化钩子（⛔ 强私有依赖）**
- typedef：`TabBarLayoutCallback = _LayoutCallback`、`TabLabelBarRenderer = _TabLabelBarRenderer`、
  `IndicatorPainterNotifier = _IndicatorPainterNotifier`、`IndicatorPainter = _IndicatorPainter`、
  `TabBarState = _TabBarState`。
- `_IndicatorPainter._` 改名 `_IndicatorPainter.builder`（供子类 `super.builder(...)`）。
- `_TabBarState` 新增 3 个可覆写方法：`buildIndicator(...)`、`applyFillAlignment(...)`、
  `buildTabLabelBar(...)`；`_initIndicatorPainter` 改调 `buildIndicator`；
  build 里两处内联逻辑改为调用钩子。
- `_debugTabAlignmentIsValid` 首行直接 `return true;`（跳过 `assert`）。
- **用户可见问题**：见 `dyn_tab_bar.dart` 场景——3 个固定页签要**均匀铺满整行**且
  **指示器不能偏向最后一格**。SDK 做不到，只能改框架。
- **私有成员**：⛔ 全部。`_IndicatorPainter`、`_TabLabelBarRenderer`、`_LayoutCallback`、
  `_TabBarState` 都是私有。

**③ 断言放宽**：`_debugTabAlignmentIsValid` → `return true`，同样私有。

- **下游**：🟡 分叉成两套，**且 TabBar 侧完全空白**。
  1. `lib/common/widgets/flutter/tabs.dart:25` `CustomTabBarView extends StatefulWidget`
     ——**改名**的 `TabBarView` 副本，只加了 `scrollDirection`（构造 `:37`、字段 `:74`、
     透传 `:359`），**没有** `hitTestBehavior` / `horizontalDragGestureRecognizer`。
     唯一使用点：`lib/pages/main/view.dart:531`
     （`scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical`）。
     这个文件**在上游没有对应物**（上游 `lib/common/widgets/flutter/` 下无 `tabs.dart`），
     属于下游纯自建 → 每次同步都是潜在冲突点。
  2. `lib/common/widgets/flutter/page/tabs.dart:27`
     `TabBarView<T extends HorizontalDragGestureRecognizer>` ——**全量 vendored 的完整
     `TabBarView`**（374 行），带 `horizontalDragGestureRecognizer`（构造 `:40`、字段 `:43`、
     透传 `:369`）与 `hitTestBehavior`。它与 `page/page_view.dart`（`PageView<T>`）、
     `page/scrollable.dart`（`Scrollable<T>`/`ScrollableState<T>`）、
     `page/scrollable_helpers.dart` 构成一个自洽的 4 文件闭包。
     使用点：`pages/episode_panel/view.dart:8`、`pages/history/view.dart:2`、
     `pages/later/view.dart:2`、`pages/video/introduction/pgc/widgets/intro_detail.dart:1`。
  3. `lib/common/widgets/scroll_physics.dart:8` 的 `tabBarView()` 辅助函数：因为 SDK
     `TabBarView` 没有 recognizer 参数，下游用 **`RawGestureDetector` 外挂一层**
     （`:12`，`:18-21`）把 `CustomHorizontalDragGestureRecognizer` 塞进去，
     注释（`:14-17`）解释了为何 key 必须写成 `HorizontalDragGestureRecognizer`
     （因为下游把 `runtimeType` 覆写成了基类名，`RawGestureDetector` 会断言）。
     **这是「参数化能力」变成「外挂手势」的典型降级**，调用点从 14 处
     （`blacklist/view.dart:81`、`bubble/view.dart:165`、`contact/view.dart:73`、
     `danmaku_block/view.dart:62`、`dynamics/view.dart:127`、`dynamics_detail/view.dart:347`、
     `emote/view.dart:55`、`fav/view.dart:156`、`follow/view.dart:215` …）全都要走这个 helper，
     而不能直接用 `TabBarView(horizontalDragGestureRecognizer: …)`。
  4. **TabBar 侧（②③）❌ 完全无对应**：
     - `lib/common/widgets/flutter/dyn_tab_bar.dart`（上游 `:9` `class DynTabBar extends TabBar`，
       `:48` `_DynTabBarState extends TabBarState`，`:68` `buildIndicator`，`:83` `_IndicatorPainter(...)`）
       **在下游不存在**（`grep -rn DynTabBar lib` → 0）。
     - 下游 `lib/pages/dynamics_detail/view.dart:281` 直接 `TabBar(`，且用
       `isScrollable: true` + `tabAlignment: .start`（`:283`、`:285`）；
       上游同一位置是 `DynTabBar(` 且 `// isScrollable: true,` **被注释掉**
       （上游 `dynamics_detail/view.dart:292`、`:294`）。
     - 后果：上游那套「3 页签铺满 + 指示器索引修正（`_correctTabIndex` 对最后一格 +1）」
       在下游**消失了**，页签是滚动式左对齐，指示器在最后一格偏窄问题未处理。
- **同名兼容性**：❌ 三处都不兼容。
  `TabBarView(scrollDirection:)` → 下游得改叫 `CustomTabBarView` 或
  `page/tabs.dart` 的 `TabBarView`（需额外必填 `horizontalDragGestureRecognizer`）；
  `DynTabBar` → 不存在。
- **替代可行性**：
  - ①（TabBarView 参数）→ 已用 vendored 副本实现，**但可搬进 shim**（`page/*` 四文件
    只互相引用，见第 4 节）；
  - ②（TabBar 钩子）→ ❌ 只能靠 vendored 一份完整 `TabBar` + `_IndicatorPainter`，
    即把整个 2400 行 `tabs.dart` 复制成 `CustomTabBar`，成本高且与上游永久分叉。

### 2.10 `material/text_field.patch` + `text_field.patch`

- **目标**：`text_field.dart` 的 `TextFormField` 构造参数（material 版 @320，SDK 版 @301）。
- **改动**：`this.selectAllOnFocus,` → `this.selectAllOnFocus = false,`。
- **用户可见问题**：桌面上点一下输入框（回复框、搜索框），内容**立刻被全选**，
  用户再输入就把原本的内容整段替换掉了。移动端默认本来就是 false，只有桌面受影响。
- **私有成员**：不需要。**一行 hunk、零依赖、纯公开 API**——理论上最该被搬进 shim 的一项。
- **下游**：❌ **且方向相反**。
  - vendored `lib/common/widgets/flutter/text_field/text_field.dart:327`
    仍是 `this.selectAllOnFocus,`（无默认值），与上游同一行 `:300` 的 `= false` **不一致**；
  - 其依赖的 vendored `lib/common/widgets/flutter/text_field/editable_text.dart:1736-1748`
    保留了平台 switch：`linux/macOS/windows => true`，兜底 `_ => PlatformUtils.isDesktop`；
  - shim 侧 `packages/material_ui/lib/src/selection_widgets.dart:169`
    `super.selectAllOnFocus,` 一路透传 null → 最终仍由 SDK 的
    `_defaultSelectAllOnFocus` 决定，桌面为 true；
  - 因此**鸿蒙桌面/平板上「点输入框即全选」的问题未修复**。
- **替代可行性**：✅ 成本最低。在 `packages/material_ui/lib/src/selection_widgets.dart`
  的 `TextField`/`TextFormField` 包装里把默认值改成 `false`（`const TextFormField` 里改
  `bool? selectAllOnFocus` → `bool? selectAllOnFocus = false` 再透传），
  或直接在下游 vendored `text_field.dart:327` 补 `= false`。

### 2.11 `mouse_cursor.patch`

- **目标**：**不是 material 层**，是 `packages/flutter/lib/src/widgets/widget_state.dart`
  里 `WidgetStateMouseCursor.resolve`（hunk @448）。
- **改动**：`return kIsWeb ? SystemMouseCursors.click : SystemMouseCursors.basic;` →
  `return SystemMouseCursors.click;`
- **用户可见问题**：非 web 平台（Windows/macOS/Linux **以及鸿蒙 PC 模式**）上，
  所有用 `WidgetStateMouseCursor.clickable` 的控件（`ListTile`、按钮、Tab）鼠标悬停时
  是**箭头**而不是**手型**，桌面上完全看不出「这里可以点」。
- **私有成员**：不需要（纯公开 API，一处三元式）。
- **下游**：❌ 无，只能靠业务侧零散硬写。
  - 框架级默认仍在：`lib/common/widgets/flutter/list_tile.dart:936`
    `WidgetStateMouseCursor.clickable.resolve(mouseStates)`、
    `flutter/vertical_slider.dart:956`、`flutter/vertical_tabs.dart:1958` ——
    这三处拿到的仍是 `basic`（箭头）。
  - 业务侧补丁式写法（不覆盖框架默认，只覆盖个别控件）：
    `lib/pages/audio/volume_button.dart:67`、`lib/pages/member_guard/view.dart:138`、
    `lib/pages/member_home/widgets/live_item.dart:103`
    （`MouseCursor get cursor => SystemMouseCursors.click;`）、
    `lib/pages/search_panel/all/widgets/user.dart:155`、
    `lib/common/widgets/progress_bar/audio_video_progress_bar.dart:817`。
  - 没有自定义 `MouseCursor` 子类（`grep "class .*MouseCursor"` → 0）。
- **替代可行性**：🟡 中等。可以在 shim 里导出一个替换版 `WidgetStateMouseCursor`？
  **不行**——它是 SDK 的 `MouseCursor` 实现类，`ListTile` 等内部直接引用，
  shim 无法拦截。唯一可行路径：下游 vendored 的 `list_tile.dart` 已经是自己的一份，
  可以在这份里把 `:936` 换成 `WidgetStateMouseCursor.clickable` 的包装
  （自定义 `MouseCursor` 在 `getCursor` 里对非 disabled 一律返回 `SystemMouseCursors.click`）。
  但这只覆盖 `ListTile`，覆盖不了按钮/Tab。

---

## 3. 关键差异：**改名类**清单（同步时最致命的部分）

上游用「框架原名」，下游因为不能 patch 只能改名，导致**同名同步必炸**：

| 上游名字 | 下游名字 / 状态 | 下游位置 | 说明 |
|---|---|---|---|
| `TabBarView`（带 `scrollDirection`） | `CustomTabBarView` | `flutter/tabs.dart:25` | 纯改名；调用点 `main/view.dart:531` |
| `TabBarView<T>`（带 recognizer） | `TabBarView<T>`（同名的 vendored 副本） | `flutter/page/tabs.dart:27` | 名字相同但**必须传 `horizontalDragGestureRecognizer`**；两套 `TabBarView` 并存 |
| `DynTabBar` | **不存在** | — | 上游 `flutter/dyn_tab_bar.dart`；下游退回裸 `TabBar`（`dynamics_detail/view.dart:281`） |
| `StandardBottomSheet` | `_StandardBottomSheet`（私有！） | `scaffold/mini_scaffold.dart:232` | 公开 → 私有 |
| `StandardBottomSheetState` | `_StandardBottomSheetState`（私有！） | `scaffold/mini_scaffold.dart:261` | 同上 |
| `PersistentBottomSheetController` | `MiniBottomSheetController` | `scaffold/mini_scaffold.dart:216` | 改名 |
| `BottomSheetState` | **不存在** | — | 上游靠 typedef 暴露私有 `_BottomSheetState` |
| `BottomSheetDefaultsM3` | **不存在** | — | 上游靠 typedef 暴露私有 `_BottomSheetDefaultsM3` |
| `BottomSheet_ extends BottomSheet` | `BottomSheet_ extends StatefulWidget` | `scaffold/bottom_sheet.dart:17` | 同名但**基类不同** |
| `TabBarState` / `IndicatorPainter` / `TabBarLayoutCallback` / `TabLabelBarRenderer` | **全部不存在** | — | `material/tabs.patch` 的公开化产物 |
| `CustomPopupMenuItem` / `CustomPopupMenuState` | 同名 | `flutter/popup_menu.dart:9/:31` | 名字兼容，但**实现是简化的**，含补丁行为缺失 |
| `RefreshIndicator` / `RefreshIndicatorState` | 同名 vendored 副本 | `flutter/refresh_indicator.dart:134/:220` | 名字兼容，另加 `RefreshIndicator_`（`common/widgets/refresh_indicator.dart:5`）作为轻量版 |
| `NavigationDrawer`（带 `flex`/`header`） | SDK 原名，无这两个参数 | `pages/main/view.dart:451` | 名字兼容、**参数不兼容** |
| `TextFormField.selectAllOnFocus = false` | 回调默认 null | `packages/material_ui/.../selection_widgets.dart:169` | 行为相反 |
| `ModalBarrier.isMenu` / `ModalRoute.isMenu` | **不存在** | — | 全仓 0 命中 |
| `LocalHistoryEntry.popGestureEnabled` / `gesturePop` | **不存在** | — | 全仓 0 命中 |

---

## 4. 下游 vendored 文件的 import 清单与「可否搬进 packages/material_ui」

### 4.1 与本次 material/cupertino 补丁直接相关的文件

| 文件 | import 行 | app-only 依赖 | 搬进 shim？ |
|---|---|---|---|
| `flutter/popup_menu.dart` | `:7` `package:material_ui/material_ui.dart` | **无** | ✅ 可（唯一 import 是 shim 自己） |
| `flutter/tabs.dart`（`CustomTabBarView`） | `:5` `dart:ui`、`:7` `flutter/foundation.dart`、`:8` `flutter/gestures.dart`、`:9` `material_ui/material_ui.dart` | **无** | ✅ 可，但建议改名回 `TabBarView` 再搬 |
| `flutter/page/tabs.dart` | `:7` `package:PiliPlus/common/widgets/flutter/page/page_view.dart`、`:8` `flutter/foundation.dart`、`:9` `flutter/gestures.dart`、`:11` `material_ui/material_ui.dart` (`hide TabBarView, PageView`) | 仅 1 条 **包内相对引用** | ✅ 可（四文件整体搬，`package:PiliPlus/...` 改相对路径） |
| `flutter/page/page_view.dart` | `:5` `package:PiliPlus/.../page/scrollable.dart`、`:6` `flutter/gestures.dart`、`:8` `material_ui/material_ui.dart` (`hide PageView, Scrollable, ScrollableState`)、`:10` `flutter/rendering.dart` | 仅包内相对引用 | ✅ 可 |
| `flutter/page/scrollable.dart` | `:10` `package:PiliPlus/.../page/scrollable_helpers.dart`、`:11` `flutter/foundation.dart`、`:12` `flutter/gestures.dart`、`:13` `material_ui/material_ui.dart` (`hide Scrollable, ScrollableState, EdgeDraggingAutoScroller`)、`:15` `flutter/rendering.dart`、`:16` `flutter/scheduler.dart`、`:17` `flutter/services.dart` | 仅包内相对引用 | ✅ 可 |
| `flutter/page/scrollable_helpers.dart` | `:14` `package:PiliPlus/.../page/scrollable.dart`、`:15` `flutter/foundation.dart`、`:16` `material_ui/material_ui.dart` | 仅包内相对引用 | ✅ 可 |
| `scaffold/bottom_sheet.dart` | `:1` `flutter/gestures.dart`、`:2` `material_ui/material_ui.dart` | **无** | ✅ 可 |
| `scaffold/mini_scaffold.dart` | `:8` `package:PiliPlus/common/widgets/scaffold/bottom_sheet.dart`、`:9` `material_ui/material_ui.dart`、`:10-11` `flutter/rendering.dart` (`RenderStack, BoxHitTestResult, StackParentData`) | 仅 1 条包内相对引用 | ✅ 可（与 `bottom_sheet.dart` 成对搬） |
| `flutter/list_tile.dart` | `:21` `dart:math`、`:23` `flutter/rendering.dart`、`:24` `material_ui/material_ui.dart` (`hide ListTile`) | **无** | ✅ 可（顺带可解 `mouse_cursor.patch` 在 `ListTile` 上的缺失） |
| `flutter/refresh_indicator.dart` | `:5` `dart:async`、`:7` `package:PiliPlus/common/widgets/refresh_layout.dart`、`:8` `package:PiliPlus/common/widgets/scroll_behavior.dart`、`:9-10` `package:PiliPlus/common/widgets/scroll_physics.dart` (`BouncingScrollPhysicsExt, ClampingBoundaryMixin`)、`:11` `package:PiliPlus/utils/platform_utils.dart`、`:12` `package:PiliPlus/utils/storage_pref.dart`、`:13` `package:extended_nested_scroll_view/refresh.dart`、`:14` `flutter/foundation.dart`、`:15` `material_ui/material_ui.dart` (`hide RefreshIndicator`)、`:16` `package:os_type/os_type.dart` | ❌ **6 条**（见下） | ❌ **重度阻塞** |
| `flutter/vertical_tabs.dart` | `:7` `dart:math`、`:8` `dart:ui`、`:10` `package:PiliPlus/pages/main/controller.dart`、`:11` `flutter/foundation.dart`、`:12` `flutter/gestures.dart`、`:13` `material_ui/material_ui.dart`、`:14` `flutter/rendering.dart`、`:15-16` `package:get/get_core`、`package:get/get_instance` | ❌ **3 条**（`MainController`、`get`×2） | ❌ |
| `flutter/vertical_slider.dart` | `:9` `package:cupertino_ui/cupertino_ui.dart`、`:10` `flutter/foundation.dart`、`:11` `flutter/gestures.dart`、`:12` `material_ui/material_ui.dart` (`hide Slider`)、`:13` `flutter/rendering.dart`、`:14` `flutter/scheduler.dart`、`:15` `flutter/services.dart`、`:16` `package:os_type/os_type.dart` | ⚠️ `os_type`（第三方 pub 包，非 app 内部） | ⚠️ 需给 shim 加 `os_type` 依赖 |
| `scaffold/simple_scaffold.dart` | `:1` `package:PiliPlus/utils/extension/scroll_controller_ext.dart`、`:2` `material_ui/material_ui.dart`、`:3-6` `flutter/rendering.dart` | ❌ 1 条（app 扩展方法） | ❌（但与本层补丁无关，是 `ScaffoldLayout`） |
| `flutter/text_field/*`（13 文件） | 见 4.2 | ❌ 大面积 | ❌ |
| `flutter/text/*`（3 文件） | `paragraph.dart` `:27`/`rich_text.dart`/`text.dart` 均只用 flutter + material_ui | 无 | ✅ 可（与本层补丁无关） |

### 4.2 `flutter/refresh_indicator.dart` 的 6 个阻塞项（详细）

| import | 用途 | 剥离难度 |
|---|---|---|
| `:7` `PiliPlus/common/widgets/refresh_layout.dart` | `RefreshLayout`（下游自写的布局 render object，承载 `scale`/`position`/`edgeOffset`） | ❌ 这是下游整套刷新布局的核心，必须一起搬（还牵出 `RefreshLayout` 的其它依赖） |
| `:8` `PiliPlus/common/widgets/scroll_behavior.dart` | `CustomScrollBehavior`（`:631` `class RefreshScrollBehavior extends CustomScrollBehavior`） | ⚠️ 可搬到 shim |
| `:9` `PiliPlus/common/widgets/scroll_physics.dart` | `BouncingScrollPhysicsExt`、`ClampingBoundaryMixin`（`:644` `RefreshScrollPhysics extends ClampingScrollPhysics`、`:660` `RefreshScrollPhysicsIOS extends BouncingScrollPhysicsExt`、`:683` `RefreshScrollPhysicsArkui extends ArkuiScrollPhysics`） | ❌ `scroll_physics.dart` 自己又 import `horizontal_drag_gesture_recognizer.dart`（`Pref.touchSlopH`）+ `platform_utils.dart` + `os_type`，形成二阶依赖链 |
| `:11` `PiliPlus/utils/platform_utils.dart` | `PlatformUtils.isDarwin`（`:549` 分支判断） | ❌ 读 `OS.isPCOS`（`platform_utils.dart:8`） |
| `:12` `PiliPlus/utils/storage_pref.dart` | `Pref.refreshDisplacement`（`:30` `double _displacement = Pref.refreshDisplacement;` 顶层变量！） | ❌ **致命**：这是**库级初始化时**读 SharedPreferences 的顶层可变全局，shim 是无状态库，必须先改成参数注入 |
| `:16` `package:os_type/os_type.dart` | `OS.isHarmony`（`:550`） | ⚠️ 需给 shim 加依赖，且与 `platform_utils` 的 `isPCOS` 语义重叠 |
| `:13` `package:extended_nested_scroll_view/refresh.dart` | 第三方包 | ⚠️ 需给 shim 加依赖 |

> `:30` 那个顶层 `Pref.*` 是本层最硬的阻塞点：`packages/material_ui` 的 `pubspec.yaml`
> 目前只依赖 `flutter`（见该文件 `dependencies:` 段），任何引入 `Pref` 的搬迁都会
> 把「用户设置」耦合进 shim 包，违背它「只做 API 映射」的定位。

### 4.3 `flutter/text_field/*` 的阻塞项（与本层 §2.10 相关）

`flutter/text_field/` 共 13 个文件，互相引用之外还有：

- `controller.dart:20-21` `package:PiliPlus/common/widgets/image/network_img_layer.dart`、
  `package:PiliPlus/models/common/image_type.dart` ← **业务模型进框架源码**，最硬的阻塞
- `editable_text.dart:28` `package:PiliPlus/utils/platform_utils.dart`
- `editable_text.dart:29` `package:PiliPlus/utils/share_utils.dart`（分享逻辑！）
- `editable_text.dart:43` `package:os_type/os_type.dart`
- `cupertino/text_field.dart:11` `.../text_field/controller.dart`（连带上面两条）

→ **不可能整体搬**。若只想修 §2.10 的 `selectAllOnFocus`，走 `packages/material_ui` 的
`selection_widgets.dart` 包装（`TextField:118` / `TextFormField:205`）**一行改默认值**即可，
不必动 vendored 副本。

### 4.4 `scaffold/*` 的可搬性（对应 §2.8）

`scaffold/bottom_sheet.dart` + `scaffold/mini_scaffold.dart` 这对文件是本层**最值得搬**的：

- `bottom_sheet.dart`：**零 app 依赖**（`flutter/gestures.dart` + `material_ui`）；
- `mini_scaffold.dart`：仅 1 条包内引用（`bottom_sheet.dart`）+ `flutter/rendering.dart`；
- 搬过去后可做两件事：
  1. 把 `_StandardBottomSheet` / `_StandardBottomSheetState` 恢复成**公开** `StandardBottomSheet` /
     `StandardBottomSheetState`（因为不再受「不能引用库外私有符号」限制）；
  2. 把 `MiniBottomSheetController` 恢复成 `PersistentBottomSheetController`。
- 从而让 `MiniScaffold` 一类代码**重新与上游同名**，把 §3 里最大的三个改名冲突消掉。
- 剩下的 `scaffold/simple_scaffold.dart` 因 `scroll_controller_ext.dart`（app 扩展）
  不能搬 —— 但它是 `ScaffoldLayout`，与本层补丁无关。

---

## 5. 行动建议（按性价比排序）

| 优先级 | 项 | 做法 | 成本 |
|---|---|---|---|
| P0 | §2.10 `selectAllOnFocus` | `packages/material_ui/lib/src/selection_widgets.dart` 的 `TextField`/`TextFormField` 包装里默认 `false` | 1 行 ×2 |
| P0 | §2.6 popup icon 色 | `flutter/popup_menu.dart:34` 的 `build` 补 `IconTheme.merge(color: style.color)` | 4 行 |
| P1 | §2.8 半屏状态机 | 把 `scaffold/{bottom_sheet,mini_scaffold}.dart` 搬进 `packages/material_ui` 并恢复上游公开名 | 中（2 文件 + 改名） |
| P1 | §2.9① TabBarView 参数 | 把 `flutter/page/*` 四文件搬进 shim，命名回 `TabBarView`/`PageView`/`Scrollable` | 中（4 文件 + 去掉 `PiliPlus` 前缀） |
| P2 | §2.11 鼠标手型 | 只能在 vendored `list_tile.dart:936` 里包一层自定义 `MouseCursor`（覆盖 `ListTile` 而已） | 低但收益有限 |
| P3 | §2.3 FAB hero | 业务侧给 FAB 传唯一 `heroTag`，不动框架 | 低 |
| ❌ | §2.2 iOS 手势关半屏、§2.4 菜单遮罩时机、§2.9②③ TabBar 钩子 | **无法移植**（框架私有状态 + `LocalHistoryRoute` mixin） | — |
| ❌ | §2.7 refresh 零尺寸绘制 | 根因在 SDK painter；下游只能用「不触发」规避，现状可接受 | — |

---

## 附：核查命令

```bash
# 下游本层行为缺失确认（应为 0 命中）
grep -rn "popGestureEnabled\|gesturePop\|isMenu" /d/github/PiliPlus/lib /d/github/PiliPlus/packages
grep -rn "IconTheme" /d/github/PiliPlus/lib/common/widgets/flutter/popup_menu.dart
grep -rn "DynTabBar\|StandardBottomSheet\|BottomSheetDefaultsM3\|TabBarState" /d/github/PiliPlus/lib

# app 级 tabs.patch 已不存在
cd /d/github/piliplus-upstream/PiliPlus && git log --all --oneline -- 'lib/scripts/tabs.patch'
# → 1ded09f24 (删除) / e89241109 (加入)
```

> 全部行号基于 2026-11-14 工作区状态：
> upstream HEAD `b2d6a5bef`（flutter 3.47.7），downstream 工作区（Flutter-ohos 3.44.9）。
