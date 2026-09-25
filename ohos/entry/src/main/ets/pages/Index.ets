import { curves, LengthMetrics, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsAnimationMode, hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import common from '@ohos.app.ability.common';
import image from '@ohos.multimedia.image';
import window from '@ohos.window';
import { FlutterPage } from '@ohos/flutter_ohos';

let storage = LocalStorage.getShared();

const TAG = 'Index';
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS';
const EVENT_TAB_SWITCH = 'EVENT_TAB_SWITCH';
const EVENT_CHANGE_TAB = 'EVENT_CHANGE_TAB';
const EVENT_TOP_SEARCH = 'EVENT_TOP_SEARCH';
const EVENT_TOP_MSG = 'EVENT_TOP_MSG';
const EVENT_TOP_MINE = 'EVENT_TOP_MINE';

const NAV_UNSELECTED = $r('sys.color.comp_focused_primary');
const BOTTOM_NORMAL_AVOID_AREA_VALUE = 1;
const BOTTOM_SPECIAL_AVOID_AREA_VALUE = 12;
/// 顶栏内容行高度（vp）：搜索栏 / 私信按钮 / 头像
const TOP_BAR_ROW_HEIGHT = 44;
/// 顶栏内容行的上下外边距（vp）
const TOP_BAR_ROW_MARGIN = 2;
/// 顶栏内容行左右边距（vp）
const TOP_BAR_SIDE_PADDING = 14;
/// 顶栏内容行内元素间距（vp）
const TOP_BAR_ROW_SPACE = 8;
/// 顶栏内容行自身高度（vp，不含状态栏）。
/// 搜索栏 / 私信 / 头像这一行由原生绘制，分类栏与渐变模糊背景由 Flutter 绘制
/// （见 lib/pages/home/widgets/home_top_bar.dart），那边按这个值给分类栏留顶空，
/// 改这里必须同时改那边。
const TOP_BAR_CONTENT_HEIGHT = TOP_BAR_ROW_HEIGHT + TOP_BAR_ROW_MARGIN * 2 + 8;
/// API 26+ 顶栏承载盒的高度上限（vp）。沉浸式系统材质只在 Navigation 标题栏
/// （或 BarPosition.End 的底部 TabBar）内生效，这条路径必须挂进 Navigation
/// 标题栏；而 Navigation 的属性链里不能出现状态变量，高度只能写常量。
/// 实际占位由外层普通容器按「状态栏 + TOP_BAR_CONTENT_HEIGHT」裁剪，这里只要
/// 够高即可（含状态栏也不会被切）。
const TOP_BAR_NAV_HEIGHT = 120;
/// 顶栏滑动隐藏 / 展开的时长与曲线。Flutter 侧 HomeTopBar 与 NativeTopSpacer
/// 共用同一套参数：两端同时起步才不会各走各的节奏、收起过程中露出错位。
const TOP_BAR_MOTION_DURATION = 300;
const TOP_BAR_MOTION_CURVE: ICurve = curves.cubicBezierCurve(0.2, 0, 0, 1);
/// 转屏动画参数
const ROTATION_MASK_FADE_DURATION = 130;
const ROTATION_MASK_FADE_DELAY = 75;
const ROTATION_MASK_MAX_LIFETIME = 2000;

/// API 26+ 的沉浸光感材质。API 26 起 ArkUI 通用组件（Search / Stack / Image …）
/// 才支持 systemMaterial；API 23~25 只有 HDS 组件内部能拿到材质，顶栏因此分两条
/// 路径（见 homeTopBarHds / homeTopBarHost）。
function topBarMaterial(interactive: boolean): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    interactive: interactive,
    lightEffect: {}
  });
}

/// Navbar 页签类型（与 Flutter NavigationBarType.values 顺序一致）→ 符号
function navTabSymbol(typeIndex: number): Resource {
  switch (typeIndex) {
    case 0:
      return $r('sys.symbol.house_fill');
    case 1:
      return $r('sys.symbol.discover_fill');
    case 2:
      return $r('sys.symbol.person_crop_circle_fill_1');
    default:
      return $r('sys.symbol.house_fill');
  }
}

/// Navbar 页签类型 → 文案（与 Flutter NavigationBarType.label 一致）
function navTabLabel(typeIndex: number): string {
  switch (typeIndex) {
    case 0:
      return '首页';
    case 1:
      return '动态';
    case 2:
      return '我的';
    default:
      return '';
  }
}

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext;
  @LocalStorageLink('viewId') viewId: string = "";
  @StorageLink('useNativeTabs') useNativeTabs: boolean = false;
  @StorageLink('shellBarsHidden') shellBarsHidden: boolean = false;
  @StorageLink('__scrollHidden') @Watch('onScrollHiddenChanged') shellBarsScrollHidden: boolean = false;
  @StorageLink('tabSelectedColor') navSelected: string = '#3367D6';
  @StorageLink('tabSelectedSubColor') navSelectedSub: string = '#503367D6';
  @StorageLink('useNativeTopBar') useNativeTopBar: boolean = false;
  @StorageLink('topBarHidden') topBarHidden: boolean = false;
  @StorageLink('topBarCollapsed') topBarCollapsed: boolean = false;
  @StorageLink('homeHideTopBar') homeHideTopBar: boolean = false;
  @StorageLink('homeSearchText') homeSearchText: string = '';
  @StorageLink('homeUnreadCount') homeUnreadCount: string = '';
  @StorageLink('homeFaceUrl') homeFaceUrl: string = '';
  /// 底部 Navbar 页签（NavigationBarType 索引，由 Flutter 按设置内
  /// Navbar 编辑同步；默认 首页/动态/我的）
  @StorageLink('navTabs') navTabs: number[] = [0, 1, 2];
  /// 动态页签角标模式（与 Flutter DynamicBadgeMode 一致：0=隐藏 1=红点 2=数字）
  @StorageLink('dynBadgeMode') dynBadgeMode: number = 0;
  /// 动态页签角标数量（由 Flutter 按未读动态数同步）
  @StorageLink('dynBadgeCount') dynBadgeCount: number = 0;
  /// 当前选中的底部 Navbar 页签索引（自定义 tabBar 需自行区分选中态）
  @State currentNavIndex: number = 0;
  @State statusBarHeight: number = 0;
  @State winWidth: number = 0;
  @State winHeight: number = 0;
  @State bottomAvoidAreaHeight: number = 0;
  @State bgColor: ResourceColor = $r("app.color.start_window_background")

  private controller: HdsTabsController = new HdsTabsController();
  private win: window.Window | null = null;
  private sizeCallback: ((size: window.Size) => void) | null = null;
  private rectCallback: ((opts: window.RectChangeOptions) => void) | null = null;

  /// 转屏旧画面遮罩
  @State rotationMask: image.PixelMap | null = null;
  @State rotationMaskOpacity: number = 1;
  private rotationCallback: ((info: window.RotationChangeInfo) => void) | null = null;
  private rotatingCount: number = 0;
  private rotationMaskTimers: number[] = [];
  private currentOrientation: number = 0;

  private isTopBarCollapsed(): boolean {
    return this.homeHideTopBar && this.topBarCollapsed;
  }

  onScrollHiddenChanged(): void {
    if (!this.useNativeTabs || this.shellBarsHidden) {
      return;
    }
    if (this.shellBarsScrollHidden) {
      this.controller.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    } else {
      this.controller.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    }
  }

  private applySize(widthPx: number, heightPx: number): void {
    this.winWidth = px2vp(widthPx);
    this.winHeight = px2vp(heightPx);
    // 同步到 AppStorage，供 HarmonyChannel.syncTopBarWithShell
    // 按窗口宽高比分流顶栏（收起/隐藏/显示）
    AppStorage.setOrCreate('winWidth', this.winWidth);
    AppStorage.setOrCreate('winHeight', this.winHeight);
  }

  /// 屏幕旋转动画：模仿安卓CROSSFADE
  /// 旋转开始时捕获旧画面快照，新旧界面淡入淡出
  private RotatationAnimation(w: window.Window): void {
    try {
      this.rotationMask = w.snapshotSync();
      this.rotationMaskOpacity = 1;
      this.startRotationMaskFade();
    } catch (err) {
      console.error(TAG, `capture rotation mask failed: ${err}`);
      this.cleanupRotationMask();
    }
  }

  private startRotationMaskFade(): void {
    this.rotationMaskTimers.push(setTimeout(() => {
      this.rotationMaskOpacity = 0;
      this.rotationMaskTimers.push(setTimeout(() => {
        this.cleanupRotationMask();
      }, ROTATION_MASK_FADE_DURATION));
    }, ROTATION_MASK_FADE_DELAY));
    // 兜底：旋转流程异常中断时强制清理，避免遮罩残留
    this.rotationMaskTimers.push(setTimeout(() => {
      this.cleanupRotationMask();
    }, ROTATION_MASK_MAX_LIFETIME));
  }

  private cleanupRotationMask(): void {
    this.clearRotationMaskTimers();
    if (this.rotationMask !== null) {
      this.rotationMask.release();
    }
    this.rotationMask = null;
    this.rotationMaskOpacity = 1;
  }

  private clearRotationMaskTimers(): void {
    this.rotationMaskTimers.forEach((t: number) => clearTimeout(t));
    this.rotationMaskTimers = [];
  }

  aboutToAppear(): void {
    this.context.eventHub.on(EVENT_CHANGE_TAB, (index: number) => {
      this.currentNavIndex = index;
      this.controller.changeIndex(index);
    });

    window.getLastWindow(this.context).then((w: window.Window) => {
      this.win = w;
      let topAvoidArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = px2vp(topAvoidArea.topRect.height);
      w.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          this.statusBarHeight = px2vp(data.area.topRect.height);
        }
      });

      const rect = w.getWindowProperties().windowRect;
      this.applySize(rect.width, rect.height);
      this.sizeCallback = (size: window.Size) => {
        this.applySize(size.width, size.height);
      };
      w.on('windowSizeChange', this.sizeCallback);

      try {
        this.rectCallback = (opts: window.RectChangeOptions) => {
          this.applySize(opts.rect.width, opts.rect.height);
        };
        w.on('windowRectChange', this.rectCallback);
      } catch (err) {
        console.error(TAG, `windowRectChange listener failed: ${err}`);
      }

      try {
        this.rotationCallback = (info: window.RotationChangeInfo) => {
          if (info.type === window.RotationChangeType.WINDOW_WILL_ROTATE) {
            this.bgColor = Color.Black;
            this.rotatingCount++;
            if (((info.orientation+this.currentOrientation)&1) === 1 && this.rotatingCount === 1) {
              // 旋转角为 90° 或 270°，播放转屏动画
              this.RotatationAnimation(w);
            }
          } else if (info.type === window.RotationChangeType.WINDOW_DID_ROTATE) {
            this.currentOrientation = info.orientation;
            this.rotatingCount--;
            if (this.rotatingCount === 0) {
              this.bgColor = $r("app.color.start_window_background");
            }
          }
        };
        w.on('rotationChange', this.rotationCallback);
      } catch (err) {
        console.error(TAG, `rotationChange listener failed: ${err}`);
      }

      let windowBottomAvoidArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      let uiContext = this.getUIContext();
      this.bottomAvoidAreaHeight = windowBottomAvoidArea.bottomRect.height === 0
        ? BOTTOM_SPECIAL_AVOID_AREA_VALUE
        : (uiContext.px2vp(windowBottomAvoidArea.bottomRect.height) + BOTTOM_NORMAL_AVOID_AREA_VALUE);

      w.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.bottomAvoidAreaHeight = data.area.bottomRect.height === 0
            ? BOTTOM_SPECIAL_AVOID_AREA_VALUE
            : (uiContext.px2vp(data.area.bottomRect.height) + BOTTOM_NORMAL_AVOID_AREA_VALUE);
        }
      });
    }).catch((err: Object) => {
      console.error(TAG, `getLastWindow failed: ${err}`);
    });
  }

  aboutToDisappear(): void {
    if (this.win !== null) {
      try {
        if (this.sizeCallback !== null) {
          this.win.off('windowSizeChange', this.sizeCallback);
        }
        if (this.rectCallback !== null) {
          this.win.off('windowRectChange', this.rectCallback);
        }
        if (this.rotationCallback !== null) {
          this.win.off('rotationChange', this.rotationCallback);
        }
      } catch (err) {
        console.error(TAG, `off window listeners failed: ${err}`);
      }
      this.sizeCallback = null;
      this.rectCallback = null;
      this.rotationCallback = null;
    }
    this.clearRotationMaskTimers();
  }

  onPageShow(): void {
    //防止退出后台计数出错
    this.rotatingCount = 0;
    this.bgColor = $r("app.color.start_window_background");
  }

  @Builder
  navTabBuilder(typeIndex: number, index: number) {
    Column({ space: 3 }) {
      if (typeIndex === 1 && this.dynBadgeCount > 0 && this.dynBadgeMode !== 0) {
        if (this.dynBadgeMode === 1) {
          // 红点角标
          Badge({
            value: '',
            position: BadgePosition.RightTop,
            style: { badgeSize: 8, badgeColor: this.navSelected, borderColor: $r('sys.color.comp_common_contrary') }
          }) {
            SymbolGlyph(navTabSymbol(typeIndex))
              .fontSize(22)
              .fontColor(
                [this.currentNavIndex === index ? this.navSelected : NAV_UNSELECTED,
                  this.currentNavIndex === index ? this.navSelectedSub : $r('sys.color.icon_tertiary')])
              .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
              .symbolEffect(new BounceSymbolEffect(), this.currentNavIndex === index)
          }
        } else {
          // 数字角标
          Badge({
            count: this.dynBadgeCount,
            position: BadgePosition.RightTop,
            style: {
              badgeSize: 13,
              fontSize: 8,
              fontWeight: FontWeight.Medium,
              badgeColor: this.navSelected,
              borderColor: $r('sys.color.comp_common_contrary'),
              color: $r('sys.color.comp_common_contrary')
            }
          }) {
            SymbolGlyph(navTabSymbol(typeIndex))
              .fontSize(22)
              .fontColor(
                [this.currentNavIndex === index ? this.navSelected : NAV_UNSELECTED,
                  this.currentNavIndex === index ? this.navSelectedSub : $r('sys.color.icon_tertiary')])
              .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
              .symbolEffect(new BounceSymbolEffect(), this.currentNavIndex === index)
          }
        }
      } else {
        SymbolGlyph(navTabSymbol(typeIndex))
          .fontSize(22)
          .fontColor(
            [this.currentNavIndex === index ? this.navSelected : NAV_UNSELECTED,
              this.currentNavIndex === index ? this.navSelectedSub : $r('sys.color.icon_tertiary')])
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
          .symbolEffect(new BounceSymbolEffect(), this.currentNavIndex === index)
      }

      Text(navTabLabel(typeIndex))
        .fontSize(10.5)
        .fontWeight(this.currentNavIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentNavIndex === index ? this.navSelected : NAV_UNSELECTED)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  avatarButton() {
    Stack() {
      if (this.homeFaceUrl !== '') {
        Image(this.homeFaceUrl)
          .width(41)
          .height(41)
          .borderRadius(20.5)
      } else {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
          .fontSize(26)
          .width(26)
          .height(26)
          .fontColor([this.navSelected])
          .align(Alignment.Center)
      }
    }
    .width(TOP_BAR_ROW_HEIGHT)
    .height(TOP_BAR_ROW_HEIGHT)
    .borderRadius(TOP_BAR_ROW_HEIGHT / 2)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .onClick(() => {
      this.context.eventHub.emit(EVENT_TOP_MINE);
    })
  }

  /// 搜索栏页签内容：放大镜 + 默认搜索词。
  /// 由 HdsTabs 悬浮栏承载，因此整块（含文字）都绘制在沉浸光感材质之上。
  @Builder
  hdsSearchTabBuilder() {
    // HdsTabs 悬浮栏给页签内容的盒子比悬浮栏本身略矮，写死满栏高度会让整行从
    // 盒子上沿起排、整体偏下。这里只做居中、不给高度，让盒子按内容收缩，与
    // 信息按钮（单个 SymbolGlyph + align(Center)）的居中方式保持一致。
    Stack({ alignContent: Alignment.Center }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .width(16)
          .height(16)
          .fontColor([this.navSelected])
        Text(this.homeSearchText !== '' ? this.homeSearchText : '搜索')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.placeholder_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
  }

  /// 顶栏搜索栏宽度（vp）：整行宽去掉左右边距、私信按钮、头像与两处间距。
  /// HDS 悬浮栏只接受具体宽度，不吃 layoutWeight，只能自己算。
  private searchBarWidth(): number {
    const total = this.winWidth > 0 ? this.winWidth : 360;
    return Math.max(
      120,
      total - TOP_BAR_SIDE_PADDING * 2 - TOP_BAR_ROW_HEIGHT * 2 - TOP_BAR_ROW_SPACE * 2
    );
  }

  /// 沉浸光感搜索栏：由只含单个页签的 HdsTabs 悬浮栏承载。
  ///
  /// 为什么不直接用 ArkUI 的 systemMaterial：它要到 API 26 才有，而本项目顶栏
  /// 与底栏都从 API 23 起就要支持。HdsTabs 悬浮栏的 systemMaterialEffect 从
  /// API 23 起即可用，是同一套沉浸光感材质，而且栏宽/栏高/边距完全可指定
  /// （不像 HdsNavigation 标题栏有最小宽度和自带遮罩）。
  @Builder
  hdsSearchBar() {
    HdsTabs() {
      TabContent() { // empty
      }
      .tabBar(this.hdsSearchTabBuilder())
    }
    .scrollable(false)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barMode(BarMode.Fixed)
    .barHeight(TOP_BAR_ROW_HEIGHT)
    .barFloatingStyle({
      barWidth: {
        smallWidth: this.searchBarWidth(),
        mediumWidth: this.searchBarWidth(),
        largeWidth: this.searchBarWidth()
      },
      barSideMargin: 0,
      barBottomMargin: 0,
      // 唯一的例外：保留自定义渐变遮罩。底栏不设它、吃默认值，而顶栏这颗悬浮栏
      // 很短，默认遮罩（组件高 + 32vp）会露出直角块。
      // 注意不能写 Color.Transparent / 0：二者都是 falsy，HDS 会当作未设置而回退
      // 默认，主题切换后默认遮罩色未刷新就成了搜索框旁的灰块
      gradientMask: { maskColor: '#00000000', maskHeight: 1 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .onTabBarClick(() => {
      this.context.eventHub.emit(EVENT_TOP_SEARCH);
    })
    .width(this.searchBarWidth())
    .height(TOP_BAR_ROW_HEIGHT)
    // 兜底：无论 HDS 在组件范围内画了什么底/遮罩，都裁成与悬浮栏同样的胶囊
    .clipShape(new Rect({
      width: this.searchBarWidth(),
      height: TOP_BAR_ROW_HEIGHT,
      radius: TOP_BAR_ROW_HEIGHT / 2
    }))
  }

  /// API 23~25 原生顶栏：只保留沉浸光感搜索栏、沉浸光感私信按钮与头像。
  ///
  /// 分类栏与它背后的渐变模糊背景已交给 Flutter（见
  /// lib/pages/home/widgets/home_top_bar.dart）：只有 Flutter 拿得到列表的滚动
  /// 状态，分类栏才能与列表联动、并让视频从它下方透出。这里只负责列表滚不到、
  /// 也不需要跟着内容动的那一行。
  ///
  /// 这一版靠 HdsTabs 悬浮栏拿材质（API 26 起改走 [homeTopBarHost] 的
  /// systemMaterial），两条路径共用同一套几何与动画参数。
  @Builder
  homeTopBarHds() {
    Row({ space: TOP_BAR_ROW_SPACE }) {
      this.hdsSearchBar()
      this.hdsMsgButton()
      this.avatarButton()
    }
    .width('100%')
    .padding({
      left: TOP_BAR_SIDE_PADDING,
      right: TOP_BAR_SIDE_PADDING,
      top: this.statusBarHeight + TOP_BAR_ROW_MARGIN,
      bottom: TOP_BAR_ROW_MARGIN,
    })
    // 滑动隐藏：整行一起上移淡出。由滚动方向一次性触发，不跟随滚动偏移逐帧
    // 变化；Flutter 侧的分类栏同步播放同一段动画（见 HomeController）。
    .translate({
      y: this.isTopBarCollapsed() ? -(this.statusBarHeight + TOP_BAR_CONTENT_HEIGHT) : 0
    })
    .opacity(this.isTopBarCollapsed() ? 0 : 1)
    .animation({ duration: TOP_BAR_MOTION_DURATION, curve: TOP_BAR_MOTION_CURVE })
    // 收起后虽然不可见，仍会吃到点击；命中测试一并关掉
    .hitTestBehavior(this.isTopBarCollapsed() ? HitTestMode.None : HitTestMode.Default)
    .visibility(this.topBarHidden ? Visibility.None : Visibility.Visible)
    .align(Alignment.Top)
  }

  /// API 26+ 搜索栏：ArkUI 通用组件的沉浸光感材质（systemMaterial），
  /// 只能在 Navigation 标题栏内生效，见 [homeTopBarHost]。
  @Builder
  materialSearchBar() {
    Search({ value: this.homeSearchText, placeholder: '搜索' })
      .cancelButton({ style: CancelButtonStyle.INVISIBLE })
      .focusable(false)
      .enableKeyboardOnFocus(false)
      .searchIcon(new SymbolGlyphModifier($r('sys.symbol.magnifyingglass'))
        .fontColor([this.navSelected]).fontSize(16))
      .placeholderColor($r('app.color.placeholder_text'))
      .placeholderFont({ size: 16, weight: 600 })
      .fontColor($r('app.color.placeholder_text'))
      .textFont({ size: 16, weight: 600 })
      .backgroundColor(Color.Transparent)
      .borderRadius(TOP_BAR_ROW_HEIGHT / 2)
      .layoutWeight(1)
      .height(TOP_BAR_ROW_HEIGHT)
      .systemMaterial(topBarMaterial(true))
      .onClick(() => {
        this.context.eventHub.emit(EVENT_TOP_SEARCH);
      })
      .hitTestBehavior(this.isTopBarCollapsed() ? HitTestMode.None : HitTestMode.Default)
  }

  /// API 26+ 的圆形材质按钮（私信 / 头像兜底）
  @Builder
  circleIconButton(icon: Resource, size: number, iconSize: number, onClick: () => void) {
    Stack() {
      SymbolGlyph(icon)
        .fontSize(iconSize)
        .width(iconSize)
        .height(iconSize)
        .fontColor([this.navSelected])
        .align(Alignment.Center)
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .systemMaterial(topBarMaterial(true))
    .onClick(onClick)
    .hitTestBehavior(this.isTopBarCollapsed() ? HitTestMode.None : HitTestMode.Default)
  }

  @Builder
  materialMsgButton() {
    Stack() {
      this.circleIconButton($r('sys.symbol.bell'), TOP_BAR_ROW_HEIGHT, 22, () => {
        this.context.eventHub.emit(EVENT_TOP_MSG);
      })
      if (this.homeUnreadCount !== '') {
        Text(this.homeUnreadCount)
          .fontSize(9)
          .fontColor(Color.White)
          .padding({
            left: 5,
            right: 5,
            top: 1,
            bottom: 1
          })
          .backgroundColor(this.navSelected)
          .borderRadius(8)
          .offset({ x: 6, y: -8 })
      }
    }
    .hitTestBehavior(this.isTopBarCollapsed() ? HitTestMode.None : HitTestMode.Default)
    .width(TOP_BAR_ROW_HEIGHT)
    .height(TOP_BAR_ROW_HEIGHT)
  }

  @Builder
  materialAvatarButton() {
    if (this.homeFaceUrl !== '') {
      Image(this.homeFaceUrl)
        .width(41)
        .height(41)
        .borderRadius(20.5)
        .onClick(() => {
          this.context.eventHub.emit(EVENT_TOP_MINE);
        })
        .systemMaterial(topBarMaterial(true))
        .hitTestBehavior(this.isTopBarCollapsed() ? HitTestMode.None : HitTestMode.Default)
    } else {
      this.circleIconButton($r('sys.symbol.person_crop_circle_fill'), TOP_BAR_ROW_HEIGHT, 26, () => {
        this.context.eventHub.emit(EVENT_TOP_MINE);
      })
    }
  }

  /// API 26+ 顶栏内容：只保留搜索栏、私信按钮与头像（分类栏在 Flutter 侧）
  @Builder
  homeTopBarMaterial() {
    Row({ space: TOP_BAR_ROW_SPACE }) {
      this.materialSearchBar()
      this.materialMsgButton()
      this.materialAvatarButton()
    }
    .width('100%')
    .padding({
      left: TOP_BAR_SIDE_PADDING,
      right: TOP_BAR_SIDE_PADDING,
      top: this.statusBarHeight + TOP_BAR_ROW_MARGIN - 2,
      bottom: TOP_BAR_ROW_MARGIN,
    })
  }

  /// API 26+ 顶栏宿主：沉浸式系统材质只在 Navigation/NavDestination 标题栏
  /// 或 BarPosition.End 的底部 TabBar 内生效（超范围时系统打印
  /// Material inactive: out of scope 并且不画材质），所以这一版必须挂进一个
  /// 只占顶栏高度的 Navigation 标题栏，内容区留空、不遮挡下方 FlutterPage。
  ///
  /// 关键约束：Navigation 的属性链里不得出现任何状态变量。builder 作为组件
  /// 参数会被编译成闭包在宿主的 update 函数里传下去，一旦 Navigation 的 update
  /// 函数因读到脏状态而重跑，.title() 就会以新闭包再调一次，自定义标题栏整棵
  /// 子树被重建——新节点没有上一帧的值可插值，隐式 .animation() 一律退化成跳变。
  /// 因此高度写常量、显隐与收起动画一律由外层普通容器承担。
  @Builder
  homeTopBarHost() {
    Column() {
      Navigation() {
        // 空内容区：BarStyle.STACK 下被标题栏完全覆盖，不参与触摸测试
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      }
      // 宽窗口下默认的 Auto 会分栏，强制 Stack 保持单栏标题栏布局
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .hideToolBar(true)
      // 不设 menus，paddingStart/paddingEnd 才能把标题栏默认左右边距清零
      .title({ builder: this.homeTopBarMaterial, height: TOP_BAR_NAV_HEIGHT }, {
        barStyle: BarStyle.STACK,
        paddingStart: LengthMetrics.vp(0),
        paddingEnd: LengthMetrics.vp(0)
      })
      // 状态栏避让由标题栏内部的 statusBarHeight padding 负责，避免重复加一层
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height(TOP_BAR_NAV_HEIGHT)
    }
    .width('100%')
    // 实际占位按内容行算，多出来的部分裁掉——不然会盖住下方 Flutter 的分类栏，
    // 把它的点击一起吃掉
    .height(this.statusBarHeight + TOP_BAR_CONTENT_HEIGHT)
    .clip(false)
    // 收起动画与 API 23~25 那条路径完全一致
    .translate({
      y: this.isTopBarCollapsed() ? -(this.statusBarHeight + TOP_BAR_CONTENT_HEIGHT) : 0
    })
    .opacity(this.isTopBarCollapsed() ? 0 : 1)
    .animation({ duration: TOP_BAR_MOTION_DURATION, curve: TOP_BAR_MOTION_CURVE })
    .hitTestBehavior(HitTestMode.Transparent)
    .visibility(this.topBarHidden ? Visibility.None : Visibility.Visible)
    .align(Alignment.Top)
  }

  @Builder
  hdsMsgTabBuilder() {
    SymbolGlyph($r('sys.symbol.bell'))
      .fontSize(22)
      .width(22)
      .height(22)
      .fontColor([this.navSelected])
      .align(Alignment.Center)
  }

  /// 沉浸光感私信按钮：与搜索栏一样是「只含单个页签的 HdsTabs 悬浮栏」——
  /// 悬浮栏的 systemMaterialEffect 就是底栏拿沉浸光感的同一套机制，API 23 起
  /// 即可用；栏宽/栏高/边距全部可指定，几何完全可控（不像 HdsNavigation
  /// 标题栏有最小宽度和自带遮罩）。44×44 + barOverlap 使悬浮栏铺满组件，
  /// 圆角随栏高变成正圆。
  @Builder
  hdsMsgButton() {
    Stack() {
      HdsTabs() {
        TabContent() { // empty
        }
        .tabBar(this.hdsMsgTabBuilder())
      }
      .scrollable(false)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barMode(BarMode.Fixed)
      .barHeight(TOP_BAR_ROW_HEIGHT)
      .barFloatingStyle({
        barWidth: {
          smallWidth: TOP_BAR_ROW_HEIGHT,
          mediumWidth: TOP_BAR_ROW_HEIGHT,
          largeWidth: TOP_BAR_ROW_HEIGHT
        },
        barSideMargin: 0,
        barBottomMargin: 0,
        // 同搜索栏：只保留自定义渐变遮罩这一个例外
        gradientMask: { maskColor: '#00000000', maskHeight: 1 },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onTabBarClick(() => {
        this.context.eventHub.emit(EVENT_TOP_MSG);
      })
      .width(TOP_BAR_ROW_HEIGHT)
      .height(TOP_BAR_ROW_HEIGHT)
      // 兜底：无论 HDS 在组件范围内画了什么底/遮罩，都裁成与悬浮栏同样的正圆
      .clipShape(new Circle({ width: TOP_BAR_ROW_HEIGHT, height: TOP_BAR_ROW_HEIGHT }))
      if (this.homeUnreadCount !== '') {
        Text(this.homeUnreadCount)
          .fontSize(9)
          .fontColor(Color.White)
          .padding({
            left: 5,
            right: 5,
            top: 1,
            bottom: 1
          })
          .backgroundColor(this.navSelected)
          .borderRadius(8)
          .offset({ x: 6, y: -8 })
      }
    }
    .width(TOP_BAR_ROW_HEIGHT)
    .height(TOP_BAR_ROW_HEIGHT)
    // 角标可能探出按钮右缘，压在后绘制的头像之上
    .zIndex(1)
  }

  @Builder
  hdsMainTabs() {
    HdsTabs({ controller: this.controller }) {
      ForEach(this.navTabs, (typeIndex: number, index: number) => {
        TabContent() { // empty
        }
        .tabBar(this.navTabBuilder(typeIndex, index))
      }, (typeIndex: number, index: number) => index + '_' + typeIndex)
    }
    .onTabBarClick((index: number) => {
      this.currentNavIndex = index;
      this.context.eventHub.emit(EVENT_TAB_SWITCH, index);
    })
    .scrollable(false)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barHeight(56)
    .barFloatingStyle({
      barBottomMargin: this.bottomAvoidAreaHeight,
      adaptToHandedness: true,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .visibility(this.navTabs.length <= 1 || this.shellBarsHidden
      ? Visibility.None
      : Visibility.Visible)
    .align(Alignment.Bottom)
    .hitTestBehavior(HitTestMode.Transparent)
  }


  build() {
    Stack({ alignContent: Alignment.Top }) {
      FlutterPage({ viewId: this.viewId, xComponentRenderFit: RenderFit.TOP })
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      if (this.useNativeTabs && deviceInfo.sdkApiVersion >= 23) {
        this.hdsMainTabs()
      }
      // 原生顶栏分两条路径：
      // API 26+ 用 ArkUI 通用组件的沉浸光感材质（systemMaterial），需要
      //   Navigation 标题栏承载 → homeTopBarHost；
      // API 23~25 上通用组件还没有 systemMaterial，只有 HDS 组件内能拿到材质
      //   → 搜索栏/私信按钮走 HdsTabs 悬浮栏（与底栏同一套能力）→ homeTopBarHds。
      // 两条路径几何、动画参数共用，切换只影响材质实现。
      if (this.useNativeTopBar && deviceInfo.sdkApiVersion >= 23) {
        if (deviceInfo.sdkApiVersion >= 26) {
          this.homeTopBarHost()
        } else {
          this.homeTopBarHds()
        }
      }
      // 转屏遮罩
      if (this.rotationMask !== null) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor("#80000000")
          .opacity(this.rotationMaskOpacity)
          .animation({ duration: ROTATION_MASK_FADE_DURATION-30, curve: Curve.EaseOut })
        Image(this.rotationMask)
          .objectFit(ImageFit.TOP)
          .opacity(this.rotationMaskOpacity)
          .animation({ duration: ROTATION_MASK_FADE_DURATION, curve: Curve.EaseOut })
          .hitTestBehavior(HitTestMode.None)
          .syncLoad(true)
      }
    }
    .width(this.winWidth > 0 ? this.winWidth : '100%')
    .height(this.winHeight > 0 ? this.winHeight : '100%')
    .backgroundColor(this.bgColor)
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
