/// 应用外观（主题色）在原生侧的唯一落点，只管颜色，不碰窗口形态（与
/// WindowChrome 互不引用）。颜色由 Dart 侧成对下发，见
/// lib/harmony_adapt/appearance/appearance_sync.dart。
export const FOREGROUND_KEY: string = 'tabSelectedColor';
export const FOREGROUND_SUB_KEY: string = 'tabSelectedSubColor';
export const BACKGROUND_KEY: string = 'appBackgroundColor';

/// 前景色的次级（半透明）变体前缀：0x88 ≈ 53% 不透明。
const SUB_ALPHA_PREFIX: string = '#88';

export class AppAppearanceController {
  private foreground: string = '';
  private background: string = '';

  /// 入参形如 '#RRGGBB'。两色同进同出：任一为空整对丢弃，避免只换一半色板。
  setColors(foreground: string, background: string): void {
    if (foreground.length === 0 || background.length === 0) {
      return;
    }
    if (this.foreground === foreground && this.background === background) {
      return;
    }
    this.foreground = foreground;
    this.background = background;
    AppStorage.setOrCreate(FOREGROUND_KEY, foreground);
    AppStorage.setOrCreate(FOREGROUND_SUB_KEY, SUB_ALPHA_PREFIX + foreground.substring(1));
    AppStorage.setOrCreate(BACKGROUND_KEY, background);
  }
}

export const appAppearance: AppAppearanceController = new AppAppearanceController();
