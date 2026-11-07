import { TITLE_BAR_HEIGHT, windowChrome } from './WindowChrome';

/// 指针落到「原标题带区域」后延迟放下标题带的等待时长（ms）。留一点余量，
/// 避免指针只是从窗口顶部掠过就闪一下标题带。
const REVEAL_DELAY_MS: number = 90;

/// 指针离开标题带区域后延迟收起的宽限时长（ms）。区域与放下后的标题带
/// 是同一条 40vp 带，离开即收起；宽限只用于吸收「区域 ↔ 标题带」之间
/// 一次 hover 目标切换，避免收起 / 放下抖动。
const COLLAPSE_DELAY_MS: number = 220;

/// 触屏放下后的停留时长（ms）。触屏没有 hover，不会有「指针离开」事件
/// 把它收回去，故放下后自动收起，保证「临时」放下。
const TOUCH_REVEAL_HOLD_MS: number = 3000;

/// 收起时长：离开视线，走加速曲线（先快后慢地滑出去）
const COLLAPSE_DURATION_MS: number = 160;

/// 临时放下时长：进入视线并在终点稳定，走减速曲线
const REVEAL_DURATION_MS: number = 200;

/// 自绘窗口标题带：左侧应用图标 + 标题，右侧「最大化 / 最小化 / 关闭」三键。
/// 自由窗口形态下常驻（由 WindowChrome 决定），高度固定 [TITLE_BAR_HEIGHT]。
///
/// 取色：底色读 AppStorage `appBackgroundColor`（Dart 侧下发，见
/// appearance/AppAppearance.ets），前景走 ColoringStrategy.INVERT（底色反色）。
/// INVERT 要求组件自身设置 backgroundColor，且同一节点只能有一个
/// foregroundColor，故容器定底色、子节点各自取反色。
///
/// 收起：Dart 同步「系统栏隐藏」状态（播放器等进入沉浸）时，
/// `windowChrome` 只写 AppStorage `titleBarCollapsed`，**不动**
/// `titleBarVisible` / `titleBarHeight`。因此这里收起标题带时也只做图形变换
/// （translate），不改任何布局信息：原生安全区照旧把 40vp 并进顶部 inset，
/// Dart 侧布局与滚动位置纹丝不动，收起 / 放下只发生在绘制层。
/// 指针滑回原标题带区域时临时放下（浮在内容之上，不推挤任何内容），
/// 离开后再收起。
@Component
export struct WindowTitleBar {
  @StorageLink('windowMaximized') maximized: boolean = false;

  /// 系统栏已隐藏（Dart 侧 `syncSystemBars(hidden:true)` 同步下来），标题带收起。
  @StorageLink('titleBarCollapsed') @Watch('onCollapsedChanged') collapsed: boolean = false;

  /// Dart 侧下发的页面背景色（'#RRGGBB'），空串表示尚未同步。
  @StorageLink('appBackgroundColor') backgroundHex: string = '';

  /// 收起态下是否已「临时放下」。仅收起态有意义：常驻态永远显示。
  @State revealed: boolean = false;

  private revealTimer: number = -1;
  private collapseTimer: number = -1;

  aboutToDisappear(): void {
    this.clearTimers();
  }

  /// 标题带当前是否不在画面上（收起且未临时放下）。
  private isHidden(): boolean {
    return this.collapsed && !this.revealed;
  }

  /// 底色：未同步时回落资源色，须与 Index.ets 的 topBarBackground 同色。
  private titleBarColor(): ResourceColor {
    if (this.backgroundHex.length > 0) {
      return this.backgroundHex;
    }
    return $r('app.color.start_window_background');
  }

  private clearTimers(): void {
    if (this.revealTimer >= 0) {
      clearTimeout(this.revealTimer);
      this.revealTimer = -1;
    }
    if (this.collapseTimer >= 0) {
      clearTimeout(this.collapseTimer);
      this.collapseTimer = -1;
    }
  }

  /// 收起 / 恢复切换时归位：进入收起立即滑出，恢复常驻时回到稳态。
  private onCollapsedChanged(): void {
    this.clearTimers();
    this.revealed = false;
  }

  private onHoverChange(isHover: boolean): void {
    this.clearTimers();
    if (isHover) {
      if (this.collapsed && !this.revealed) {
        this.scheduleReveal();
      }
      return;
    }
    this.scheduleCollapse(COLLAPSE_DELAY_MS);
  }

  private scheduleReveal(): void {
    this.revealTimer = setTimeout(() => {
      this.revealTimer = -1;
      this.revealed = true;
    }, REVEAL_DELAY_MS);
  }

  private scheduleCollapse(delayMs: number): void {
    if (!this.revealed) {
      return;
    }
    this.collapseTimer = setTimeout(() => {
      this.collapseTimer = -1;
      this.revealed = false;
    }, delayMs);
  }

  /// 三键。顺序与系统标题栏一致：最大化（还原）、最小化、关闭；
  /// 最大化图标随窗口状态在「最大化 / 还原」两个 Symbol 间切换。
  @Builder
  captionButton(key: string) {
    Stack() {
      if (key === 'max') {
        SymbolGlyph($r(this.maximized
          ? 'sys.symbol.exit_full_screen'
          : 'sys.symbol.full_screen'))
          .fontSize(14)
          .align(Alignment.Center)
           
      } else if (key === 'min') {
        SymbolGlyph($r('sys.symbol.minus'))
          .fontSize(14)
          .align(Alignment.Center)
           
      } else {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .align(Alignment.Center)
           
      }
    }
    .width(28)
    .height(28)
    .onClick(() => {
      if (key === 'max') {
        windowChrome.toggleMaximize();
      } else if (key === 'min') {
        windowChrome.minimize();
      } else {
        windowChrome.close();
      }
    })
  }

  @Builder
  titleBand() {
    Row() {
      // 拖拽区：按下即发起移动，双击切换最大化
      Row({ space: 10 }) {
        Image($r('app.media.foreground'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .draggable(false)
        Text($r('app.string.EntryAbility_label'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
           
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 16, right: 8 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          windowChrome.startMoving();
        }
      })
      .gesture(TapGesture({ count: 2 }).onAction(() => {
        windowChrome.toggleMaximize();
      }))

      Row({ space: 4 }) {
        this.captionButton('max')
        this.captionButton('min')
        this.captionButton('close')
      }
      .height('100%')
      .padding({ right: 18 })
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    .backgroundColor(this.titleBarColor())
    // 只做图形变换：收起时整条滑出窗口顶部，不留任何布局痕迹（父容器仍是
    // 同一条 40vp 带，热区与安全区都不变）。
    .translate({ y: this.isHidden() ? -TITLE_BAR_HEIGHT : 0 })
    .animation({
      duration: this.isHidden() ? COLLAPSE_DURATION_MS : REVEAL_DURATION_MS,
      curve: this.isHidden() ? Curve.EaseIn : Curve.EaseOut,
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.titleBand()
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    // 收起态这层只剩「热区」职责：让指针 / 触摸事件穿透给下层内容，
    // 避免一条看不见的 40vp 空白吞掉点击。
    .hitTestBehavior(this.isHidden() ? HitTestMode.Transparent : HitTestMode.Default)
    .onHover((isHover: boolean) => {
      this.onHoverChange(isHover);
    })
    // 触屏设备没有 hover：按下即视为「滑到原区域」，同样只放下、不动布局；
    // 停下后到点自动收起，保持「临时」语义。
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && this.isHidden()) {
        this.clearTimers();
        this.revealed = true;
        this.scheduleCollapse(TOUCH_REVEAL_HOLD_MS);
      }
    })
  }
}
