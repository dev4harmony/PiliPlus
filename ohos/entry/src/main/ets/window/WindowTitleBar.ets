import { TITLE_BAR_HEIGHT, windowChrome } from './WindowChrome';

/// 指针落到「原标题带区域」后延迟放下标题带的等待时长（ms）。留一点余量，
/// 避免指针只是从窗口顶部掠过就闪一下标题带。
const REVEAL_DELAY_MS: number = 90;

/// 指针离开标题带区域后延迟收起的宽限时长（ms）。区域与放下后的标题带
/// 是同一条 40vp 带，离开即收起；宽限只用于吸收「区域 ↔ 标题带」之间
/// 一次 hover 目标切换，避免收起 / 放下抖动。
const COLLAPSE_DELAY_MS: number = 220;

/// 全屏自动收起态下鼠标离开标题带后的收起宽限（ms）。
///
/// 这种形态下标题带唤出时，播放器顶栏会整体下移一条标题带高度（见
/// WindowChrome.setTitleBarRevealed）。鼠标从标题带移到那一排按钮上时已经离开
/// 热区，必须留足宽限，用户才来得及点按钮；否则刚移下去标题带就收起、按钮又
/// 被弹回原位，等于点不到。
const AUTO_HIDE_COLLAPSE_DELAY_MS: number = 1000;

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
///
/// 自由窗口形态下「内容全屏（播放器全屏）且窗口占满显示器」时，`windowChrome`
/// 会让标题带「自动收起」：同样走 `titleBarCollapsed` 这条图形位移通道，但
/// 此时安全区不再并入 40vp（见 WindowState.readSafeArea），内容可以铺满窗口，
/// 唤出的标题带浮在内容上 —— 对齐系统标题栏在全屏下的悬停唤出行为。自动收起
/// 只响应鼠标悬停，触屏点顶部热区不唤出；窗口一旦还原成浮动窗口，或只是普通
/// 最大化而没有全屏播放，标题带都保持常驻。
@Component
export struct WindowTitleBar {
  @StorageLink('windowMaximized') maximized: boolean = false;

  /// 系统栏已隐藏（Dart 侧 `syncSystemBars(hidden:true)` 同步下来）或内容全屏
  /// 自动收起，标题带收起。
  @StorageLink('titleBarCollapsed') @Watch('onCollapsedChanged') collapsed: boolean = false;

  /// 是否「内容全屏自动收起」。与普通收起（系统栏隐藏）的区别：自动收起只响应
  /// 鼠标悬停，不响应触屏点击——全屏播放时窗口顶部不能靠点一下就唤出标题带。
  @StorageLink('titleBarAutoHide') autoHide: boolean = false;

  /// Dart 侧下发的页面背景色（'#RRGGBB'），空串表示尚未同步。
  @StorageLink('appBackgroundColor') backgroundHex: string = '';

  /// Dart 侧下发的前景色（'#RRGGBB'）。背景色未同步时用它反推深浅。
  @StorageLink('tabSelectedColor') foregroundHex: string = '';

  /// 收起态下是否已「临时放下」。仅收起态有意义：常驻态永远显示。
  @State revealed: boolean = false;

  /// 当前指针悬停的三键 key（'max' / 'min' / 'close'），空串表示没有悬停。
  @State hoveredKey: string = '';

  private revealTimer: number = -1;
  private collapseTimer: number = -1;

  aboutToDisappear(): void {
    this.clearTimers();
    this.setRevealed(false);
  }

  /// 标题带当前是否不在画面上（收起且未临时放下）。
  private isHidden(): boolean {
    return this.collapsed && !this.revealed;
  }

  /// 切换「临时放下」状态，并上报给 `windowChrome`。
  ///
  /// 全屏自动收起态下，唤出标题带需要把标题带高度并进顶部安全区，让播放器
  /// 顶部那排按钮整体下移，否则标题带会盖住它们、点不到。
  private setRevealed(value: boolean): void {
    if (this.revealed === value) {
      return;
    }
    this.revealed = value;
    windowChrome.setTitleBarRevealed(value);
  }

  /// 底色：未同步时回落资源色，须与 Index.ets 的 topBarBackground 同色。
  private titleBarColor(): ResourceColor {
    if (this.backgroundHex.length > 0) {
      return this.backgroundHex;
    }
    return $r('app.color.start_window_background');
  }

  /// 三键的悬停底色：亮色标题带上压一层淡黑、深色标题带上压一层淡白。
  ///
  /// 只做同色系透明叠加、不引入新色相，所以深浅两套标题带配色都成立
  /// （浅色底 + 8% 黑、深色底 + 12% 白），与系统标题栏的 hover 反馈观感一致。
  private hoverColor(): string {
    if (this.backgroundHex.length > 0) {
      return this.isLightColor(this.backgroundHex)
        ? '#1F000000'
        : '#1FFFFFFF';
    }
    // 背景色还没同步时用前景色反推：前景偏亮说明标题带是深色。
    if (this.foregroundHex.length > 0 && this.isLightColor(this.foregroundHex)) {
      return '#1FFFFFFF';
    }
    return '#1F000000';
  }

  /// 颜色是否偏亮（ITU-R BT.601 感知亮度 > 0.6），支持 '#RRGGBB' / '#AARRGGBB'。
  private isLightColor(color: string): boolean {
    let value = color.startsWith('#') ? color.substring(1) : color;
    if (value.length === 8) {
      value = value.substring(2);
    }
    if (value.length < 6) {
      return true;
    }
    const r = Number.parseInt(value.substring(0, 2), 16);
    const g = Number.parseInt(value.substring(2, 4), 16);
    const b = Number.parseInt(value.substring(4, 6), 16);
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6;
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
    this.setRevealed(false);
  }

  private onHoverChange(isHover: boolean): void {
    this.clearTimers();
    if (isHover) {
      if (this.collapsed && !this.revealed) {
        this.scheduleReveal();
      }
      return;
    }
    this.scheduleCollapse(
      this.autoHide ? AUTO_HIDE_COLLAPSE_DELAY_MS : COLLAPSE_DELAY_MS,
    );
  }

  private scheduleReveal(): void {
    this.revealTimer = setTimeout(() => {
      this.revealTimer = -1;
      this.setRevealed(true);
    }, REVEAL_DELAY_MS);
  }

  private scheduleCollapse(delayMs: number): void {
    if (!this.revealed) {
      return;
    }
    this.collapseTimer = setTimeout(() => {
      this.collapseTimer = -1;
      this.setRevealed(false);
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
          .fontSize(15)
          .fontColor([$r('app.color.foreground_text')])
          .align(Alignment.Center)
           
      } else if (key === 'min') {
        SymbolGlyph($r('sys.symbol.minus'))
          .fontSize(15)
          .fontColor([$r('app.color.foreground_text')])
          .align(Alignment.Center)
           
      } else {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(15)
          .fontColor([$r('app.color.foreground_text')])
          .align(Alignment.Center)
           
      }
    }
    .width(30)
    .height(30)
    // 悬停反馈：图标下面垫一块同色系半透明色块，深浅两种标题带都能看清，
    // 用户能立刻知道自己指在哪个键上。
    .borderRadius(6)
    .backgroundColor(this.hoveredKey === key ? this.hoverColor() : Color.Transparent)
    .onHover((isHover: boolean) => {
      if (isHover) {
        this.hoveredKey = key;
      } else if (this.hoveredKey === key) {
        this.hoveredKey = '';
      }
    })
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
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
           
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 16, right: 8 })
      .onTouch((event: TouchEvent) => {
        // 全屏自动收起态（窗口占满显示器 + 播放器全屏）参照系统/华为视频：
        // 拖拽标题带不移动窗口，单击空白也无动作，只有双击才还原窗口。
        // 必须跳过 startMoving：它作用在最大化窗口上会「先还原再拖动」，
        // 单击（Down/Up 无位移）就表现为窗口先缩小再弹回的抽搐动画。
        if (event.type === TouchType.Down && !this.autoHide) {
          windowChrome.startMoving();
        }
      })
      .gesture(TapGesture({ count: 2 }).onAction(() => {
        windowChrome.toggleMaximize();
      }))

      Row({ space: 6 }) {
        this.captionButton('max')
        this.captionButton('min')
        this.captionButton('close')
      }
      .height('100%')
      .padding({ right: 20 })
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
    // 避免一条看不见的 40vp 空白吞掉点击。注意这里**不能**为了扩大热区把
    // 高度撑到标题带之外：ArkUI 的点击事件只投递给最上层命中的节点，
    // 命中了没有 onClick 的这层就会把点击吞掉，下面 Flutter 的按钮就点不动。
    .hitTestBehavior(this.isHidden() ? HitTestMode.Transparent : HitTestMode.Default)
    .onHover((isHover: boolean) => {
      this.onHoverChange(isHover);
    })
    // 触屏设备没有 hover：按下即视为「滑到原区域」，同样只放下、不动布局；
    // 停下后到点自动收起，保持「临时」语义。
    //
    // 内容全屏自动收起态例外：只允许鼠标悬停唤出，触摸屏点顶部热区不唤出。
    // 全屏播放时窗口顶部是视频控件/手势区，点一下就冒出标题带会抢走点击，
    // 也不符合系统标题栏在沉浸全屏下的行为。
    .onTouch((event: TouchEvent) => {
      if (this.autoHide) {
        return;
      }
      if (event.type === TouchType.Down && this.isHidden()) {
        this.clearTimers();
        this.setRevealed(true);
        this.scheduleCollapse(TOUCH_REVEAL_HOLD_MS);
      }
    })
  }
}
