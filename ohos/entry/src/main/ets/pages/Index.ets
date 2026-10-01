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
const EVENT_HOME_TAB_CHANGE = 'EVENT_HOME_TAB_CHANGE';

const NAV_UNSELECTED = $r('sys.color.comp_focused_primary');
const BOTTOM_NORMAL_AVOID_AREA_VALUE = 1;
const BOTTOM_SPECIAL_AVOID_AREA_VALUE = 12;
const TOP_BAR_BLUR_RADIUS = 15;
const TOP_BAR_FRACTION_STOPS: [number, number][] = [[0, 0], [0.8, 0.2], [1, 0.4], [1, 1]];
const TOP_BAR_COLLAPSED_HEIGHT = 80;
const TOP_BAR_EXPANDED_HEIGHT = 144;
/// 顶栏收缩曲线：重减速的三次贝塞尔，起步轻、尾段长距离滑停，
/// 比对称的 EaseInOut 柔和。裁剪容器/内容容器/搜索行三处高度共用同一条
/// 曲线与时长，避免各自为政导致的错位；数值需与 Flutter 侧
/// NativeTopSpacer 的留白动画保持一致。
const TOP_BAR_MOTION_DURATION = 300;
const TOP_BAR_MOTION_CURVE: ICurve = curves.cubicBezierCurve(0.2, 0, 0, 1);
/// 搜索行淡出/淡入：收起时抢在高度压扁之前淡出，展开时等高度让出空间后
/// 再淡入，避免文字在被压扁的行内闪现（旧实现同时做，观感发硬）
const TOP_BAR_FADE_DURATION = 120;
const TOP_BAR_FADE_IN_DELAY = 48;
/// API 23~25 顶栏：消息按钮（单页签 HdsTabs 悬浮栏）边长，与 API 26+ 的
/// 44vp 圆形按钮一致
const HDS_MSG_BUTTON_SIZE = 44;
const CATEGORY_TABS_HEIGHT = 32;
/// 转屏动画参数
const ROTATION_MASK_FADE_DURATION = 130;
const ROTATION_MASK_FADE_DELAY = 75;
const ROTATION_MASK_MAX_LIFETIME = 2000;

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
  @StorageLink('homeTabs') homeTabs: string[] = [];
  @StorageLink('homeActiveTabIndex') @Watch('onHomeTabIndexChanged') homeActiveTabIndex: number = 0;
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
  @State categoryCurrentIndex: number = 0;
  @State winWidth: number = 0;
  @State winHeight: number = 0;
  @State bottomAvoidAreaHeight: number = 0;
  @State bgColor: ResourceColor = $r("app.color.start_window_background")
  /// HDR 平台视图模式（Dart 侧 usePlatformViewRx）期间根 Stack 必须是黑的，
  /// 见 build() 末尾。只读，由 HarmonyChannel 的 setPlatformVideoActive 写入。
  @StorageProp('platformVideoActive') platformVideoActive: boolean = false;

  private categoryController: TabsController = new TabsController();
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

  onHomeTabIndexChanged(): void {
    if (this.homeActiveTabIndex >= 0 && this.homeActiveTabIndex < this.homeTabs.length) {
      this.categoryCurrentIndex = this.homeActiveTabIndex;
      this.categoryController.changeIndex(this.homeActiveTabIndex);
    }
  }

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
  categoryTabBuilder(index: number, name: string) {
    Text(name)
      .fontSize(15)
      .fontWeight(this.categoryCurrentIndex === index ? FontWeight.Bolder : FontWeight.Medium)
      .fontColor(this.categoryCurrentIndex === index ? this.navSelected : NAV_UNSELECTED)
      .height(28)
      .margin({
        left: index === 0 ? 8 : 3,
        right: index === this.homeTabs.length - 1 ? 8 : 3
      })
      .padding({ left: 15, right: 15 })
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
  }

  @Builder
  msgButton() {
    Stack() {
      this.circleIconButton($r('sys.symbol.bell'), 44, 22, () => {
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
    .width(44)
    .height(44)
  }

  @Builder
  avatarButton() {
    if (this.homeFaceUrl !== '') {
      Image(this.homeFaceUrl)
        .width(41)
        .height(41)
        .borderRadius(20.5)
        .onClick(() => {
          this.context.eventHub.emit(EVENT_TOP_MINE);
        })
        .systemMaterial(topBarMaterial(true))
    } else {
      this.circleIconButton($r('sys.symbol.person_crop_circle_fill'), 44, 26, () => {
        this.context.eventHub.emit(EVENT_TOP_MINE);
      })
    }
  }

  /// 首页分类栏（直播/推荐/热门/分区…），API 26+ 与 API 23~25 两条顶栏路径共用
  @Builder
  categoryTabs() {
    Tabs({ barPosition: BarPosition.Start, controller: this.categoryController }) {
      ForEach(this.homeTabs, (tab: string, index: number) => {
        TabContent() { // empty
        }
        .tabBar(this.categoryTabBuilder(index, tab))
      }, (tab: string, index: number) => index + '_' + tab)
    }
    .barMode(BarMode.Scrollable)
    .fadingEdge(false)
    .scrollable(false)
    .width('100%')
    .height(CATEGORY_TABS_HEIGHT)
    .onTabBarClick((index: number) => {
      this.context.eventHub.emit(EVENT_HOME_TAB_CHANGE, index);
      this.categoryCurrentIndex = index;
    })
  }

  @Builder
  homeTopBar() {
    RelativeContainer() {
      //渐变模糊底层
      Column() {
      }
      .constraintSize({ maxHeight: TOP_BAR_EXPANDED_HEIGHT })
      .linearGradient({
          direction: GradientDirection.Bottom, // 渐变方向
          colors: [
                [$r('app.color.top_bar_mask_start'), 0],
                [$r('app.color.top_bar_mask_mid'), 0.8],
                [$r('app.color.top_bar_mask_end'), 0.95],
                [$r('app.color.top_bar_mask_end'), 1],
              ],
        })
      .linearGradientBlur(TOP_BAR_BLUR_RADIUS, {
        fractionStops: TOP_BAR_FRACTION_STOPS,
        direction: GradientDirection.Top
      })
      .alignRules({
        top: { anchor: 'topBarContent', align: VerticalAlign.Top },
        bottom: { anchor: 'topBarContent', align: VerticalAlign.Bottom },
        left: { anchor: 'topBarContent', align: HorizontalAlign.Start },
        right: { anchor: 'topBarContent', align: HorizontalAlign.End }
      })
      .id('topBarBg')
      .hitTestBehavior(HitTestMode.Transparent)
      .align(Alignment.Top)

      Column() {
        Row({ space: 8 }) {
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
            .borderRadius(22)
            .layoutWeight(1)
            .height(44)
            .systemMaterial(topBarMaterial(true))
            .onClick(() => {
              this.context.eventHub.emit(EVENT_TOP_SEARCH);
            })
          this.msgButton()
          this.avatarButton()
        }
        .width('100%')
        .padding({
          left: 14,
          right: 14,
        })
        .opacity(this.homeHideTopBar && this.topBarCollapsed ? 0 : 1)
        // .animation() 只作用于它之前、上一个 .animation() 之后的属性，
        // 故透明度与高度可以各走一套节奏
        .animation({
          duration: TOP_BAR_FADE_DURATION,
          curve: Curve.Sharp,
          delay: this.homeHideTopBar && this.topBarCollapsed ? 0 : TOP_BAR_FADE_IN_DELAY
        })
        .margin({
          top: this.homeHideTopBar && this.topBarCollapsed ? 0 : 5,
          bottom: this.homeHideTopBar && this.topBarCollapsed ? -5 : 5
        })
        .height(this.homeHideTopBar && this.topBarCollapsed ? 0 : 44)
        .animation({ duration: TOP_BAR_MOTION_DURATION, curve: TOP_BAR_MOTION_CURVE })

        if (this.homeTabs.length > 1) {
          this.categoryTabs()
        }
      }
      .width('100%')
      .padding({ top: this.statusBarHeight})
      .id('topBarContent')
      .hitTestBehavior(HitTestMode.Default)
      .align(Alignment.Top)
    }
    .height(this.topBarHeight())
    .animation({ duration: TOP_BAR_MOTION_DURATION, curve: TOP_BAR_MOTION_CURVE })
    .width('100%')
    .hitTestBehavior(HitTestMode.Default)
    .align(Alignment.Top)
  }

  /// 沉浸式系统材质仅在 Navigation/NavDestination 标题栏或 BarPosition.End 的
  /// 底部 TabBar 内生效（API 26 正式版起校验，超范围时日志打印
  /// Material inactive: out of scope），故顶栏整体挂进一个只占顶栏高度的
  /// Navigation 标题栏，内容区留空，不遮挡下方 FlutterPage。
  ///
  /// 关键约束：Navigation 的属性链里不得出现任何状态变量。builder 作为组件
  /// 参数会被编译成闭包在宿主的 update 函数里传下去（见 .tabBar 的产物形态），
  /// 一旦 Navigation 的 update 函数因读到脏状态而重跑，.title() 就会以新闭包
  /// 再调一次，自定义标题栏整棵子树被重建——新节点没有上一帧的值可插值，
  /// 隐式 .animation() 与 animateTo 一律退化成跳变。
  /// 因此收缩动画与显隐一律由外层裁剪容器承担，Navigation 保持常量属性，
  /// 标题栏内部的节点才能回到原地更新，沿用既有的 .animation() 写法。
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
      // 显式给出标题栏高度，避免自定义标题被压回默认 56vp；
      // 不设 menus，paddingStart/paddingEnd 才能把标题栏默认左右边距清零
      .title({ builder: this.homeTopBar, height: TOP_BAR_EXPANDED_HEIGHT }, {
        barStyle: BarStyle.STACK,
        paddingStart: LengthMetrics.vp(0),
        paddingEnd: LengthMetrics.vp(0)
      })
      // 状态栏避让由顶栏内部的 statusBarHeight padding 负责，避免重复加一层
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height(TOP_BAR_EXPANDED_HEIGHT)
    }
    .width('100%')
    // 收缩在这里做：普通容器高度，隐式动画正常生效；clip 让收起后露出的
    // 那段标题栏既不绘制也不参与触摸测试，触摸照常落到下方 FlutterPage
    .height(this.topBarHeight())
    .clip(true)
    .animation({ duration: TOP_BAR_MOTION_DURATION, curve: TOP_BAR_MOTION_CURVE })
    .visibility(this.topBarHidden ? Visibility.None : Visibility.Visible)
    .align(Alignment.Top)
  }

  private topBarHeight(): number {
    return this.isTopBarCollapsed()
      ? TOP_BAR_COLLAPSED_HEIGHT
      : TOP_BAR_EXPANDED_HEIGHT;
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

  /// API 23~25：消息按钮由一个只含单个页签的 HdsTabs 悬浮栏承载——悬浮栏
  /// 的 systemMaterialEffect 就是底栏在 6.1 上拿沉浸光感的同一套机制，
  /// 而且栏宽/栏高/边距全部可指定，几何完全可控（不像 HdsNavigation
  /// 标题栏有最小宽度和自带遮罩）。44×44 + barOverlap 使悬浮栏铺满组件，
  /// 圆角随栏高变成正圆。角标与 API 26+ 的 msgButton 同一画法。
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
      .barHeight(HDS_MSG_BUTTON_SIZE)
      .barFloatingStyle({
        barWidth: {
          smallWidth: HDS_MSG_BUTTON_SIZE,
          mediumWidth: HDS_MSG_BUTTON_SIZE,
          largeWidth: HDS_MSG_BUTTON_SIZE
        },
        barSideMargin: 0,
        barBottomMargin: 0,
        // 不要悬浮栏底部默认的渐变遮罩（默认高度为组件高 + 32vp，会露出直角块）。
        // 注意不能写 Color.Transparent / 0：二者都是 falsy，HDS 会当作未设置而回退默认，
        // 主题切换后默认遮罩色未刷新就成了按钮旁的灰色方块
        gradientMask: { maskColor: '#00000000', maskHeight: 1 },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          // 浅色模式下 ADAPTIVE 几乎看不出材质，按钮很小，直接用最高等级
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      })
      .barBackgroundColor('#00000000')
      .onTabBarClick(() => {
        this.context.eventHub.emit(EVENT_TOP_MSG);
      })
      .width(HDS_MSG_BUTTON_SIZE)
      .height(HDS_MSG_BUTTON_SIZE)
      // 兜底：无论 HDS 在组件范围内画了什么底/遮罩，都裁成与悬浮栏同样的正圆
      .clipShape(new Circle({ width: HDS_MSG_BUTTON_SIZE, height: HDS_MSG_BUTTON_SIZE }))
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
    .width(HDS_MSG_BUTTON_SIZE)
    .height(HDS_MSG_BUTTON_SIZE)
    // 角标可能探出按钮右缘，压在后绘制的头像之上
    .zIndex(1)
  }

  /// API 23~25（鸿蒙 6.1）顶栏。ArkUI 通用组件的 systemMaterial / uiMaterial
  /// 要到 API 26 才有，6.1 上沉浸光感只在 HDS 组件内可用：消息按钮走
  /// hdsMsgButton（HdsTabs 悬浮栏）拿材质；搜索框用组件级模糊做半透明胶囊，头像是普通圆形
  /// 图片按钮。布局、收起动画与 homeTopBar 逐项对应，仅材质相关属性不同。
  @Builder
  homeTopBarHds() {
    RelativeContainer() {
      //渐变模糊底层
      Column() {
      }
      .constraintSize({ maxHeight: TOP_BAR_EXPANDED_HEIGHT })
      .linearGradient({
          direction: GradientDirection.Bottom, // 渐变方向
          colors: [
                [$r('app.color.top_bar_mask_start'), 0],
                [$r('app.color.top_bar_mask_mid'), 0.8],
                [$r('app.color.top_bar_mask_end'), 0.95],
                [$r('app.color.top_bar_mask_end'), 1],
              ],
        })
      .linearGradientBlur(TOP_BAR_BLUR_RADIUS, {
        fractionStops: TOP_BAR_FRACTION_STOPS,
        direction: GradientDirection.Top
      })
      .alignRules({
        top: { anchor: 'topBarContent', align: VerticalAlign.Top },
        bottom: { anchor: 'topBarContent', align: VerticalAlign.Bottom },
        left: { anchor: 'topBarContent', align: HorizontalAlign.Start },
        right: { anchor: 'topBarContent', align: HorizontalAlign.End }
      })
      .id('topBarBg')
      .hitTestBehavior(HitTestMode.Transparent)
      .align(Alignment.Top)

      Column() {
        Row({ space: 8 }) {
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
            .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
            .borderRadius(22)
            .layoutWeight(1)
            .height(44)
            .onClick(() => {
              this.context.eventHub.emit(EVENT_TOP_SEARCH);
            })
          this.hdsMsgButton()
          if (this.homeFaceUrl !== '') {
            Image(this.homeFaceUrl)
              .width(41)
              .height(41)
              .borderRadius(20.5)
              .onClick(() => {
                this.context.eventHub.emit(EVENT_TOP_MINE);
              })
          } else {
            Stack() {
              SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
                .fontSize(26)
                .width(26)
                .height(26)
                .fontColor([this.navSelected])
                .align(Alignment.Center)
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
            .onClick(() => {
              this.context.eventHub.emit(EVENT_TOP_MINE);
            })
          }
        }
        .width('100%')
        .padding({
          left: 14,
          right: 14,
        })
        .opacity(this.homeHideTopBar && this.topBarCollapsed ? 0 : 1)
        .animation({
          duration: TOP_BAR_FADE_DURATION,
          curve: Curve.Sharp,
          delay: this.homeHideTopBar && this.topBarCollapsed ? 0 : TOP_BAR_FADE_IN_DELAY
        })
        .margin({
          top: this.homeHideTopBar && this.topBarCollapsed ? 0 : 5,
          bottom: this.homeHideTopBar && this.topBarCollapsed ? -5 : 5
        })
        .height(this.homeHideTopBar && this.topBarCollapsed ? 0 : 44)
        .animation({ duration: TOP_BAR_MOTION_DURATION, curve: TOP_BAR_MOTION_CURVE })

        if (this.homeTabs.length > 1) {
          this.categoryTabs()
        }
      }
      .width('100%')
      .padding({ top: this.statusBarHeight})
      .id('topBarContent')
      .hitTestBehavior(HitTestMode.Default)
      .align(Alignment.Top)
    }
    .height(this.topBarHeight())
    .animation({ duration: TOP_BAR_MOTION_DURATION, curve: TOP_BAR_MOTION_CURVE })
    .width('100%')
    .hitTestBehavior(HitTestMode.Default)
    .align(Alignment.Top)
  }

  /// API 23~25 顶栏宿主：与 API 26+ 宿主同样由外层裁剪容器承担收缩与显隐
  @Builder
  homeTopBarHdsHost() {
    Column() {
      this.homeTopBarHds()
    }
    .width('100%')
    .height(this.topBarHeight())
    .clip(true)
    .animation({ duration: TOP_BAR_MOTION_DURATION, curve: TOP_BAR_MOTION_CURVE })
    .visibility(this.topBarHidden ? Visibility.None : Visibility.Visible)
    .align(Alignment.Top)
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
      // xComponentColor 置透明：HDR 平台视图由 RenderService 合成在
      // FlutterSurface 之下，不能被 XComponent 的黑底盖住。
      // 注意上游的 RenderFit.TOP 已经让 FlutterSurface 的黑底判断恒假
      // （见 FlutterPage.ets 的 backgroundColor 三元），这里是双保险：
      // 一旦 renderFit 改回 RESIZE_FILL，仍然不会黑屏。
      FlutterPage({ viewId: this.viewId, xComponentRenderFit: RenderFit.TOP, xComponentColor: Color.Transparent })
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      if (this.useNativeTabs && deviceInfo.sdkApiVersion >= 23) {
        this.hdsMainTabs()
      }
      // API 26+：Navigation 标题栏 + ArkUI systemMaterial（全部元素带材质）
      // API 23~25：自绘顶栏，仅消息按钮（HdsTabs 悬浮栏）带 HDS 材质
      if (this.useNativeTopBar && deviceInfo.sdkApiVersion >= 26) {
        this.homeTopBarHost()
      } else if (this.useNativeTopBar && deviceInfo.sdkApiVersion >= 23) {
        this.homeTopBarHdsHost()
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
    // 平台视图（HDR）合成在 Flutter 表面之下，且只有拟合后的视频矩形那么大；
    // 该模式下 Flutter 播放器各层画透明，视频没铺满的部分（黑边）会一路透到
    // 这个根 Stack，所以此期间必须是黑的（platformVideoActive，由 Dart 同步）。
    // 不能常黑：上游 2c4e56a98 为修「一镜到底动画右侧黑块」去掉了 3s 转黑。
    // 平时沿用 bgColor（启动背景色，仅转屏期间为黑），也避免冷启动白闪。
    // rotationChange / onPageShow 只改 bgColor，不会把这里的黑色冲掉。
    .backgroundColor(this.platformVideoActive ? Color.Black : this.bgColor)
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
