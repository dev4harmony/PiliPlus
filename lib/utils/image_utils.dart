import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/permission_handler.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:dio/dio.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:live_photo_maker/live_photo_maker.dart';
import 'package:os_type/os_type.dart';
import 'package:path/path.dart' as path;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

abstract final class ImageUtils {
  static bool silentDownImg = Pref.silentDownImg;
  static final _albumPath = Platform.isAndroid
      ? 'Pictures/${Constants.appName}'
      : Constants.appName;

  static String? imageSavePath = _initImageSavePath();
  static String? _initImageSavePath() {
    final path = Pref.imageSavePath;
    if (path != null) {
      if (Directory(path).existsSync()) {
        return path;
      } else {
        GStorage.setting.delete(SettingBoxKey.imageSavePath);
      }
    }
    return null;
  }

  // 图片分享
  static Future<void> onShareImg(String url) async {
    try {
      SmartDialog.showLoading();
      final res = await CacheManager.manager.getSingleFile(
        url.http2https,
      );
      SmartDialog.dismiss();
      await Share.shareXFiles(
        [XFile(res.path)],
        sharePositionOrigin: await ShareUtils.sharePositionOrigin,
      );
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }

  // 获取存储权限
  static Future<bool> requestPer() async {
    final status = Platform.isAndroid
        ? await Permission.storage.request()
        : await Permission.photos.request();
    if (status == PermissionStatus.denied ||
        status == PermissionStatus.permanentlyDenied) {
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text('存储权限未授权'),
          actions: [
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                openAppSettings();
              },
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      return false;
    } else {
      return true;
    }
  }

  static FutureOr<bool> checkPermissionDependOnSdkInt() {
    if (OS.isHarmony) return true; // 鸿蒙图片保存权限由插件后续请求
    if (Platform.isAndroid) {
      if (DeviceUtils.sdkInt < 29) {
        return requestPer();
      } else {
        return true;
      }
    }
    return requestPer();
  }

  static Future<bool> downloadLivePhoto({
    required String url,
    required String liveUrl,
    required int width,
    required int height,
  }) async {
    try {
      if (PlatformUtils.isMobile && !await checkPermissionDependOnSdkInt()) {
        return false;
      }
      if (!silentDownImg) SmartDialog.showLoading(msg: '正在下载');

      String videoName = "video_${Utils.getFileName(liveUrl)}";
      String videoPath = '$tmpDirPath/$videoName';

      final res = await Request().downloadFile(liveUrl.http2https, videoPath);
      if (res.statusCode != 200) throw '${res.statusCode}';

      if (Platform.isIOS) {
        final imageFile = await CacheManager.manager.getSingleFile(
          url.http2https,
        );
        if (!silentDownImg) SmartDialog.showLoading(msg: '正在保存');
        bool success = await LivePhotoMaker.create(
          coverImage: imageFile.path,
          imagePath: null,
          voicePath: videoPath,
          width: width,
          height: height,
        ).whenComplete(File(videoPath).tryDel);
        if (success) {
          SmartDialog.showToast(' 已保存 ');
        } else {
          SmartDialog.showToast('保存失败');
          return false;
        }
      } else {
        if (!silentDownImg) SmartDialog.showLoading(msg: '正在保存');
        await saveFileImg(
          filePath: videoPath,
          fileName: videoName,
          type: FileType.video,
          needToast: true,
        );
      }
      return true;
    } catch (err) {
      SmartDialog.showToast(err.toString());
      return false;
    } finally {
      if (!silentDownImg) SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  static Future<bool> downloadImg(List<String> imgList) async {
    if (PlatformUtils.isMobile && !await checkPermissionDependOnSdkInt()) {
      return false;
    }
    CancelToken? cancelToken;
    if (!silentDownImg) {
      cancelToken = CancelToken();
      SmartDialog.showLoading(
        msg: '正在下载原图',
        clickMaskDismiss: true,
        onDismiss: cancelToken.cancel,
      );
    }
    try {
      final futures = imgList.map((url) async {
        final name = Utils.getFileName(url);

        final file = await CacheManager.manager.getSingleFile(
          url.http2https,
        );
        return (filePath: file.path, name: name, statusCode: 200);
      });
      final result = await Future.wait(futures, eagerError: true);
      bool success = true;
      SaveResult? saveRes;
      if (PlatformUtils.isMobile) {
        final saveList = <SaveFileData>[];
        for (final i in result) {
          if (i.statusCode == 200) {
            saveList.add(
              SaveFileData(
                filePath: i.filePath,
                fileName: i.name,
                androidRelativePath: _albumPath,
              ),
            );
          } else {
            success = false;
          }
        }
        saveRes = await SaverGallery.saveFiles(saveList, skipIfExists: false);
      } else {
        for (final res in result) {
          if (res.statusCode == 200) {
            await saveFileImg(filePath: res.filePath, fileName: res.name);
          } else {
            success = false;
          }
        }
      }
      if (cancelToken?.isCancelled == true) {
        SmartDialog.showToast('已取消下载');
        return false;
      } else {
        SmartDialog.showToast(success && saveRes?.isSuccess==true ? ' 已保存 ' : '保存失败');
      }
      return success;
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        SmartDialog.showToast('已取消下载');
      } else {
        SmartDialog.showToast(e.toString());
      }
      return false;
    } finally {
      if (!silentDownImg) SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  static final _suffixRegex = RegExp(
    r'\.(jpg|jpeg|png|webp|gif|avif)$',
    caseSensitive: false,
  );
  static String safeThumbnailUrl(String? src) {
    if (src != null && _suffixRegex.hasMatch(src)) {
      return thumbnailUrl(src);
    }
    return src.http2https;
  }

  static final _thumbRegex = RegExp(
    r'(@(\d+[a-z]_?)*)(\..*)?$',
    caseSensitive: false,
  );
  static String thumbnailUrl(String? src, [int maxQuality = 1]) {
    if (src != null && maxQuality != 100) {
      maxQuality = math.max(maxQuality, GlobalData().imgQuality);
      bool hasMatch = false;
      src = src.splitMapJoin(
        _thumbRegex,
        onMatch: (match) {
          hasMatch = true;
          String suffix = match.group(3) ?? '.webp';
          return '${match.group(1)}_${maxQuality}q$suffix';
        },
        onNonMatch: (String str) {
          return str;
        },
      );
      if (!hasMatch) {
        src += '@${maxQuality}q.webp';
      }
    }
    return src.http2https;
  }

  static String thumbnailUrlWithSize(
    String? src,
    int? expectedWidth,
    int? expectedHeight, [
    int maxQuality = 1,
  ]) {
    if (src != null &&
        (expectedWidth != null ||
            expectedHeight != null ||
            maxQuality != 100)) {
      // 确定质量
      int finalQuality = maxQuality;
      if (maxQuality != 100) {
        finalQuality = math.max(maxQuality, GlobalData().imgQuality);
      }
      // 构建参数字符串
      List<String> params = [];
      if (expectedWidth != null) params.add('${expectedWidth}w');
      if (expectedHeight != null) params.add('${expectedHeight}h');
      if (maxQuality != 100) params.add('${finalQuality}q');
      String paramsStr = params.join('_'); // 可能为空，但如果进入处理块则至少有一个参数

      bool hasMatch = false;
      src = src.splitMapJoin(
        _thumbRegex,
        onMatch: (match) {
          hasMatch = true;
          String suffix = match.group(3) ?? '.webp';
          return '@$paramsStr$suffix';
        },
        onNonMatch: (str) => str,
      );
      if (!hasMatch) {
        src += '@$paramsStr.webp';
      }
    }
    return src.http2https;
  }

  static Future<SaveResult?> saveByteImg({
    required Uint8List bytes,
    required String fileName,
    String ext = 'png',
  }) async {
    SaveResult? res;
    fileName += '.$ext';
    if (PlatformUtils.isMobile || OS.isHarmony) {
      SmartDialog.showLoading(msg: '正在保存');
      res = await SaverGallery.saveImage(
        bytes,
        fileName: fileName,
        androidRelativePath: _albumPath,
        skipIfExists: false,
      );
      SmartDialog.dismiss();
      if (res.isSuccess) {
        SmartDialog.showToast(' 已保存 ');
      } else {
        SmartDialog.showToast('保存失败，${res.errorMessage}');
      }
    } else {
      SmartDialog.dismiss();
      final String? savePath;
      if (imageSavePath != null) {
        savePath = path.join(imageSavePath!, fileName);
      } else {
        savePath = await FilePicker.platform.saveFile(
          type: FileType.image,
          fileName: fileName,
          bytes: Uint8List(0),
        );
        if (savePath == null) {
          SmartDialog.showToast("取消保存");
          return null;
        }
      }
      await File(savePath).writeAsBytes(bytes);
      SmartDialog.showToast(' 已保存 ');
      res = SaveResult(true, null);
    }
    return res;
  }

  static Future<void> saveFileImg({
    required String filePath,
    required String fileName,
    FileType type = FileType.image,
    bool needToast = false,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      SmartDialog.showToast("文件不存在");
      return;
    }
    SaveResult? res;
    if (PlatformUtils.isMobile || OS.isHarmony) {
      res = await SaverGallery.saveFile(
        filePath: filePath,
        fileName: fileName,
        androidRelativePath: _albumPath,
        skipIfExists: false,
      );
    } else {
      final String? savePath;
      if (imageSavePath != null) {
        savePath = path.join(imageSavePath!, fileName);
      } else {
        savePath = await FilePicker.platform.saveFile(
          type: type,
          fileName: fileName,
          bytes: Uint8List(0),
        );
        if (savePath == null) {
          SmartDialog.showToast("取消保存");
          return;
        }
      }
      await file.copy(savePath);
      res = SaveResult(true, null);
    }
    if (needToast) {
      if (res.isSuccess) {
        SmartDialog.showToast(' 已保存 ');
      } else {
        SmartDialog.showToast('保存失败，${res.errorMessage}');
      }
    }
  }
}
