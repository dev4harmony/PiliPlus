/// 鸿蒙分支差异（上游原文见 `db77169b4 refa: font setting`）：
///
/// - **安卓分支已摘除**：上游走 JNI 调 `AndroidHelper.fontFamilies()`，而本分支没有
///   `jni` 依赖、`lib/utils/android/bindings.g.dart` 是手写的空实现存根。
/// - **Windows 分支已摘除**：上游用 `win32` 6.4.0 的 API（`GetDC(null)`、
///   `LPARAM(0)` 等），而本分支 `dependency_overrides` 把 win32 钉在 5.5.3
///   （鸿蒙化的插件链要求），两者 API 不兼容。哪天 win32 的 override 放开了，
///   把上游那段 `_initWindows()` / `_enumFontCallback()` 抄回来即可。
/// - Linux 的 fontconfig 分支是纯 `dart:ffi`，原样保留。
/// - **自定义字体导入**（[pickFonts] / [init] / [fontFile]）与平台无关，全部保留；
///   只是文件选择器换成鸿蒙适配 fork（`file_picker_ohos`）的
///   `FilePicker.platform.pickFiles()` 实例 API。
///
/// 鸿蒙本身没有枚举系统字体的通道，[FontUtils.getFont] 在 ohos 上返回空集合——
/// 字体设置页的系统字体列表因此为空，只剩「默认」与用户导入的自定义字体。
library;

import 'dart:ffi';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'dart:ui' show loadFontFromList;

import 'package:PiliPlus/utils/fontconfig.g.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;

typedef AppFont = ({String? fontFamily, bool isCustom});

abstract final class FontUtils {
  static final _fonts = <String>{};
  static bool _initialized = false;

  static const _kFontExts = ['ttf', 'ttc', 'otf'];

  static AppFont _appFont = _initAppFont();
  static AppFont get appFont => _appFont;
  static set appFont(AppFont value) {
    assert(value.isCustom == _isCutsomFont(value.fontFamily));
    _appFont = value;
  }

  static bool _isCutsomFont(String? fontFamily) {
    return fontFamily?.contains('/') ?? false;
  }

  static AppFont _initAppFont() {
    final String? appFont = GStorage.setting.get(SettingBoxKey.appFont);
    if (_isCutsomFont(appFont)) {
      if (fontFile.existsSync()) {
        return (fontFamily: appFont, isCustom: true);
      } else {
        GStorage.setting.delete(SettingBoxKey.appFont);
        return const (fontFamily: null, isCustom: false);
      }
    } else {
      return (fontFamily: appFont, isCustom: false);
    }
  }

  static String? get fontFamily => _appFont.fontFamily;
  static bool get isCustom => _appFont.isCustom;

  static final fontFile = File(path.join(appSupportDirPath, 'customFont.otf'));

  static Future<void>? init() {
    if (isCustom) {
      return _readAndLoad();
    }
    return null;
  }

  @pragma('vm:notify-debugger-on-exception')
  static Future<void> _readAndLoad() async {
    try {
      final bytes = await fontFile.readAsBytes();
      await _loadFont(bytes, fontFamily: fontFamily!);
    } catch (_) {}
  }

  static void removeFontIfExists() {
    if (fontFile.existsSync()) {
      fontFile.delete();
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  static Future<void> _loadFont(
    Uint8List bytes, {
    required String fontFamily,
  }) async {
    try {
      await loadFontFromList(bytes, fontFamily: fontFamily);
    } catch (_) {}
  }

  @pragma('vm:notify-debugger-on-exception')
  static Future<Map<String, Uint8List>?> pickFonts() async {
    try {
      // 鸿蒙适配 fork 仅提供 FilePicker.platform 实例方法（上游是静态的
      // FilePicker.pickFiles），返回值也仍是旧版的 FilePickerResult。
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _kFontExts,
        allowMultiple: true,
      );
      final files = result?.files;
      if (files != null && files.isNotEmpty) {
        final Map<String, Uint8List> fonts = {};
        final now = DateTime.now().millisecondsSinceEpoch.toString();
        await Future.wait(
          files.map((file) async {
            final name = '$now/${path.basenameWithoutExtension(file.name)}';
            final bytes = await file.xFile.readAsBytes();
            await _loadFont(bytes, fontFamily: name);
            fonts[name] = bytes;
          }),
        );
        return fonts;
      }
    } catch (_) {
      if (kDebugMode) rethrow;
    }
    return null;
  }

  static Set<String> getFont() {
    if (_initialized) return _fonts;
    _initialized = true;
    // 只有真正实现了枚举的平台才在失败时提示。ohos / 安卓 / Windows / ios / macos
    // 在本分支没有实现（原因见文件头），静默返回空集合即可，弹「加载失败」只会
    // 误导用户——字体页在系统字体列表为空时只显示「默认」与自定义字体。
    if (Platform.isLinux && !_initLinux()) {
      SmartDialog.showToast('加载系统字体失败');
    }
    return _fonts;
  }

  @pragma('vm:prefer-inline')
  static bool _initLinux() {
    final FontConfig fc;
    try {
      fc = FontConfig(DynamicLibrary.open('libfontconfig.so.1'));
    } catch (e) {
      if (kDebugMode) debugPrint('无法加载 Fontconfig 库: $e');
      return false;
    }

    final config = fc.FcInitLoadConfigAndFonts();
    if (config == nullptr) {
      if (kDebugMode) debugPrint('Fontconfig 初始化失败');
      return false;
    }

    final fontSet = fc.FcConfigGetFonts(config, FcSetName.FcSetSystem);
    if (fontSet == nullptr) {
      if (kDebugMode) debugPrint('无法获取系统字体集');
      fc.FcConfigDestroy(config);
      return false;
    }

    final nfont = fontSet.ref.nfont;
    final family = FC_FAMILY.toNativeUtf8().cast<Char>();
    for (int i = 0; i < nfont; i++) {
      final pattern = fontSet.ref.fonts[i];
      if (pattern == nullptr) continue;

      final outPtr = calloc<Pointer<UnsignedChar>>();

      try {
        final result = fc.FcPatternGetString(pattern, family, 0, outPtr);

        if (result == 0) {
          final strPtr = outPtr.value;
          if (strPtr != nullptr) {
            _fonts.add(strPtr.cast<Utf8>().toDartString());
          }
        }
      } finally {
        calloc.free(outPtr);
      }
    }
    calloc.free(family);
    fc.FcConfigDestroy(config);

    return true;
  }
}
