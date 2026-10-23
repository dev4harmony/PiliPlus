import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

abstract final class StorageUtils {
  static Future<void> saveBytes2File({
    required String name,
    required Uint8List bytes,
    required List<String> allowedExtensions,
    FileType type = FileType.custom,
  }) async {
    try {
      // 鸿蒙适配 fork（br_v10.2.0_ohos）仅提供 FilePicker.platform 实例方法
      final path = await FilePicker.platform.saveFile(
        allowedExtensions: allowedExtensions,
        type: type,
        fileName: name,
        bytes: PlatformUtils.isDesktop ? null : bytes,
      );
      if (path == null) {
        SmartDialog.showToast("取消保存");
        return;
      }
      if (PlatformUtils.isDesktop) {
        await File(path).writeAsBytes(bytes);
      }
      SmartDialog.showToast("已保存");
    } catch (e) {
      SmartDialog.showToast("保存失败: $e");
    }
  }
}
