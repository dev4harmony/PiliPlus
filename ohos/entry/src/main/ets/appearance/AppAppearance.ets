import { common, ConfigurationConstant } from "@kit.AbilityKit";

/// 应用外观（深浅色模式 / 前景色 / 背景色）在原生侧的唯一落点，不碰窗口形态
/// （与 WindowChrome 互不引用）。由 Dart 侧统一下发，见
/// lib/harmony_adapt/appearance/appearance_sync.dart。
export const FOREGROUND_KEY: string = 'tabSelectedColor';
export const FOREGROUND_SUB_KEY: string = 'tabSelectedSubColor';
export const BACKGROUND_KEY: string = 'appBackgroundColor';

/// 前景色的次级（半透明）变体前缀：0x88 ≈ 53% 不透明。
const SUB_ALPHA_PREFIX: string = '#88';

const COLOR_MODE_MAP: Record<string, ConfigurationConstant.ColorMode> = {
  'light': ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT,
  'dark': ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
  'system': ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET,
};

export class AppAppearanceController {
  private foreground: string = '';
  private background: string = '';
  private colorMode: string = '';

  /// [colorMode] 为 light / dark / system，两色形如 '#RRGGBB'，空串表示该项跳过。
  setAppearance(colorMode: string, foreground: string, background: string): void {
    this.setColorMode(colorMode);
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

  /// 让应用上下文的深浅色模式跟随 Flutter 的选择。
  private setColorMode(colorMode: string): void {
    if (colorMode.length === 0 || this.colorMode === colorMode) {
      return;
    }
    this.colorMode = colorMode;
    try {
      const context = getContext() as common.ApplicationContext;
      context.setColorMode(COLOR_MODE_MAP[colorMode]);
    } catch (err) {
      console.error('AppAppearance', `set color mode failed: ${err}`);
    }
  }
}

export const appAppearance: AppAppearanceController = new AppAppearanceController();
