import { BusinessError } from '@kit.BasicServicesKit';
import display from '@ohos.display';
import window from '@ohos.window';

/// 系统栏下发失败后的退避重试间隔（ms）与次数上限。旋转瞬间系统窗口可能尚未
/// 就绪，setSpecificSystemBarEnabled 会以 801 拒绝，稍后重试即可。
const RETRY_DELAY_MS: number = 150;
const MAX_RETRY: number = 4;

/// 方向变化后等待窗口尺寸稳定再重放系统栏（ms）。旋转过程中 windowSizeChange
/// 会连续触发多次，合帧成一次，避免系统栏在动画中间反复显隐。
const REPLAY_DELAY_MS: number = 60;

/// 系统栏 apply 完成回调：`hidden` 是本次落地的期望值。
export type SystemBarsAppliedListener = (hidden: boolean) => void;

/// 系统栏显隐的窗口级状态机（与「装饰栏 / 标题带」无关）。
///
/// 为什么独立成类：系统栏属于**窗口**，不属于自由窗口的标题栏——手机全屏播放、
/// 桌面内容全屏、平板分屏都会用到它；任何需要「隐藏/显示状态栏与导航栏」的
/// 模块（WindowState、视频 Surface 等）都只依赖这个类，
/// 不必经过 WindowChromeController。
///
/// 真源在 Dart `SystemBars`，本类缓存一份镜像（[hidden]）：
/// - `sync()` 接收 Dart 下发的新状态（带 revision / epoch 去重）；
/// - `replay()` 按镜像无条件重放，用于旋转后系统把系统栏悄悄恢复显示的场景。
///
/// 线程模型（ArkTS 单线程，但 await 会交错）：apply 串行化，同一时刻只跑一轮；
/// 期间到达的期望只置 dirty，循环结束取最新值，旧期望晚到的 await 不会覆盖新期望。
export class SystemBarsController {
  private win: window.Window | null = null;
  /// 期望状态（Dart 侧真源的镜像）。
  private hidden: boolean = false;
  /// Dart 侧单调递增的同步版本，用于丢弃乱序到达的旧同步。
  private revision: number = -1;
  /// Dart 会话号：hot restart 后 revision 从 0 重新开始，新会话首个同步无条件接受。
  private epoch: number = -1;
  /// 是否有待下发的期望：apply 期间到达的同步只置位，循环结束取最新值。
  private dirty: boolean = false;
  /// apply 串行化标志。
  private applying: boolean = false;
  /// 连续下发失败次数（退避重试，避免旋转瞬间一次 801 就永久失配）。
  private failures: number = 0;
  private retryTimer: number = -1;
  /// 方向变化后的重放合帧定时器。
  private replayTimer: number = -1;
  /// 上一次观察到的方向（true = 横屏），null = 尚未初始化。
  private landscape: boolean | null = null;
  /// 上一次观察到的屏幕旋转角（`display.Rotation`），-1 = 尚未初始化。
  /// 相比宽高比，它能区分 90° ↔ 270° 这种「同是横屏但方向翻转」的旋转。
  private rotation: number = -1;
  /// 窗口所在屏的 displayId，用于在多屏环境下挑对那个 display 的旋转值。
  private displayId: number = -1;
  private appliedListener: SystemBarsAppliedListener | null = null;

  /// 窗口尺寸变化：方向翻转或旋转角变化时安排一次重放。
  ///
  /// 系统栏自身显隐也会改变窗口可用尺寸（返回键/手势条占位），但既不翻转
  /// 宽高关系、也不改 rotation，因此不会触发重放——避免 apply → sizeChange →
  /// apply 的自激回环。
  private sizeCallback = (size: window.Size): void => {
    let rotated = false;
    // 兜底：display 'change' 偶发丢失时（或 90° ↔ 270° 这类同为横屏的翻转），
    // 在窗口尺寸回调里回读一次旋转角，避免旋转后系统栏停留在旧状态。
    try {
      const rotation = display.getDefaultDisplaySync().rotation;
      if (rotation !== this.rotation) {
        this.rotation = rotation;
        rotated = true;
      }
    } catch (err) {
      const e = err as BusinessError;
      console.error('SystemBars', `read rotation failed: ${e.code} ${e.message}`);
    }
    const landscape = size.width > size.height;
    if (this.landscape === null) {
      // 首帧（或 attach 时读不到窗口尺寸）：只记基线，不重放——此时
      // loadContent 尚未完成，系统栏接口会静默失败并吃掉重试次数。
      this.landscape = landscape;
      return;
    }
    const flipped = this.landscape !== landscape;
    this.landscape = landscape;
    if (flipped || rotated) {
      this.scheduleReplay();
    }
  };

  /// 屏幕旋转：display 'change' 回调只给变化的 displayId，回读其 rotation。
  /// 与 [sizeCallback] 互补——固定尺寸自由窗口旋转时窗口尺寸可能不变，但旋转角会变。
  private displayCallback = (changedDisplayId: number): void => {
    const rotation = this.readRotation(changedDisplayId);
    if (rotation === null || rotation === this.rotation) {
      return;
    }
    this.rotation = rotation;
    this.scheduleReplay();
  };

  /// 登记窗口并开始监听方向变化。幂等：重复调用只替换窗口引用。
  attach(win: window.Window): void {
    this.detach();
    this.win = win;
    try {
      this.landscape = this.readLandscape(win);
      win.on('windowSizeChange', this.sizeCallback);
    } catch (err) {
      const e = err as BusinessError;
      console.error('SystemBars', `window size listener failed: ${e.code} ${e.message}`);
    }
    try {
      this.displayId = win.getWindowProperties().displayId ?? -1;
      this.rotation = display.getDefaultDisplaySync().rotation;
      display.on('change', this.displayCallback);
    } catch (err) {
      const e = err as BusinessError;
      console.error('SystemBars', `display listener failed: ${e.code} ${e.message}`);
    }
  }

  /// 解除监听并复位瞬时状态（期望值保留，供下一次 attach 后重放）。
  detach(): void {
    this.clearTimers();
    if (this.win === null) {
      this.applying = false;
      this.dirty = false;
      this.failures = 0;
      return;
    }
    try {
      this.win.off('windowSizeChange', this.sizeCallback);
    } catch (err) {
      console.error('SystemBars', `window listener detach failed: ${err}`);
    }
    try {
      display.off('change', this.displayCallback);
    } catch (err) {
      console.error('SystemBars', `display listener detach failed: ${err}`);
    }
    this.win = null;
    this.applying = false;
    this.dirty = false;
    this.failures = 0;
    this.landscape = null;
    this.rotation = -1;
    this.displayId = -1;
  }

  /// 当前期望是否隐藏（供需要读状态的模块查询，例如标题带收起）。
  isHidden(): boolean {
    return this.hidden;
  }

  /// 登记 apply 完成回调（WindowState 重推安全区、标题带收起等）。
  onApplied(listener: SystemBarsAppliedListener): void {
    this.appliedListener = listener;
  }

  /// 窗口内容已加载（官方要求窗口接口在 loadContent 之后才生效）：
  /// Dart 可能早在首帧前就同步过「需要隐藏」，这里按镜像重放一次。
  onContentLoaded(): void {
    this.replay();
  }

  /// 接收 Dart 下发的期望状态（真源在 Dart）。
  ///
  /// 顺序保护两层：`epoch` 变即视为新 Dart 会话，revision 从 0 重新计数；
  /// 同会话内 `revision` 必须单调递增，乱序到达的旧同步直接丢弃。
  async sync(hidden: boolean, revision: number, epoch: number): Promise<void> {
    if (epoch !== this.epoch) {
      this.epoch = epoch;
      this.revision = -1;
    }
    if (revision <= this.revision) {
      return;
    }
    this.revision = revision;
    this.hidden = hidden;
    this.failures = 0;
    await this.requestApply();
  }

  /// 按缓存的镜像无条件重放一次（绕开 revision 去重）。
  ///
  /// 用于系统在旋转 / 重建窗口后把系统栏悄悄恢复显示的情况——期望没变，
  /// 但实际状态丢了，所以必须强制执行。下发本身幂等（显式 true / false）。
  replay(): void {
    // 清失败计数：这是一次新的对齐机会，不应被上一轮旋转中的 801 卡住。
    this.failures = 0;
    this.requestApply();
  }

  /// 置脏并驱动一轮串行 apply。
  private requestApply(): Promise<void> {
    this.dirty = true;
    return this.drive().catch((err: BusinessError) => {
      console.error('SystemBars', `apply failed: ${err.code} ${err.message}`);
    });
  }

  /// 串行 apply：同一时刻只跑一轮；期间新到的期望只置 dirty，由循环重新取
  /// 最新值，因此不会出现「旧期望的 await 晚到后把新期望覆盖掉」。
  private async drive(): Promise<void> {
    if (this.applying) {
      return;
    }
    this.applying = true;
    try {
      while (this.dirty) {
        this.dirty = false;
        const ok = await this.applyBars(this.hidden);
        if (!ok) {
          this.scheduleRetry();
          break;
        }
      }
    } finally {
      this.applying = false;
    }
  }

  /// 幂等下发一次系统栏显隐。重复调用无副作用（系统接口本身幂等）。
  private async applyBars(hidden: boolean): Promise<boolean> {
    const w = this.win;
    if (w === null) {
      // 窗口未登记（已 detach 或尚未 attach）：不自旋，交给 onContentLoaded 重放；
      // 返回 true 让 drive 循环正常退出，避免 dirty 永远为真造成死循环。
      return true;
    }
    try {
      await w.setSpecificSystemBarEnabled("status", !hidden, false);
      await w.setSpecificSystemBarEnabled("navigation", !hidden, false);
      await w.setSpecificSystemBarEnabled("navigationIndicator", !hidden, false);
    } catch (err) {
      const e = err as BusinessError;
      console.warn('SystemBars', `setSpecificSystemBarEnabled failed: ${e.code} ${e.message}`);
      return false;
    }
    this.appliedListener?.(hidden);
    return true;
  }

  /// 下发失败后的退避重试：旋转瞬间窗口可能尚未就绪（801），重试几次即可，
  /// 不能让一次失败把系统栏永久留在错误状态。
  private scheduleRetry(): void {
    if (this.retryTimer >= 0 || this.failures >= MAX_RETRY) {
      return;
    }
    this.failures++;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      this.dirty = true;
      this.drive();
    }, RETRY_DELAY_MS);
  }

  /// 方向变化后合帧重放：窗口尺寸会连续触发多次，只在稳定后落一次，
  /// 避免系统栏在旋转动画中间反复闪。
  private scheduleReplay(): void {
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer);
    }
    this.replayTimer = setTimeout(() => {
      this.replayTimer = -1;
      this.replay();
    }, REPLAY_DELAY_MS);
  }

  private clearTimers(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer);
      this.replayTimer = -1;
    }
  }

  /// 当前窗口是否横屏；读取失败返回 null（不做方向重放，等下一次尺寸事件）。
  private readLandscape(w: window.Window): boolean | null {
    try {
      const rect = w.getWindowProperties().windowRect;
      return rect.width > rect.height;
    } catch (err) {
      return null;
    }
  }

  /// 读取变化屏的旋转角。只关心窗口所在屏：副屏旋转不应触发主屏的系统栏重放。
  private readRotation(displayId: number): number | null {
    if (this.displayId >= 0 && displayId !== this.displayId) {
      return null;
    }
    try {
      return display.getDisplayByIdSync(displayId).rotation;
    } catch (err) {
      return null;
    }
  }
}
