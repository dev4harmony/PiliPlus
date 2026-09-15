import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

List<SettingsModel> experimentalSettings = [
  SwitchModel(
    title: '鸿蒙沉浸光感导航栏',
    subtitle: '使用鸿蒙的悬浮页签栏与沉浸光感\n仅在鸿蒙6.1及以上支持，不支持的平台会回退到传统底栏\n开启平板适配后在横屏模式下不显示',
    leading: const Icon(Icons.water_drop_outlined),
    setKey: SettingBoxKey.enableHdsBar,
    defaultVal: false,
    onChanged: (_) => SmartDialog.showToast("重启生效"),
  ),
  SwitchModel(
    title: '鸿蒙沉浸光感顶栏',
    subtitle:
        '使用鸿蒙原生沉浸光感顶栏\n仅鸿蒙6.1及以上支持，不支持则自动回退\n鸿蒙6.1仅消息按钮带光感材质，搜索框为毛玻璃效果；鸿蒙7及以上搜索框、消息与头像按钮均带光感材质',
    leading: const Icon(Icons.blur_on_outlined),
    setKey: SettingBoxKey.enableHdsTopBar,
    defaultVal: false,
    onChanged: (_) => SmartDialog.showToast("重启生效"),
  ),
  const SwitchModel(
    title: '显示实际百分比音量',
    subtitle:
        '某些系统(鸿蒙)或设备只支持整数音量级别，如0~15，对应的百分比音量只有0%、7%、···、93%和100%，不存在1%、2%和50%等实际百分比音量',
    leading: Icon(Icons.science_outlined),
    setKey: SettingBoxKey.showActualVolume,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '点击系统状态栏快速返回顶部',
    subtitle: '开启后在鸿蒙/iOS设备上，绝大部分列表点击状态栏可以快速回顶。\n关闭后除了部分原生支持的界面，均不再响应状态栏点击。',
    leading: Icon(Icons.vertical_align_top_outlined),
    setKey: SettingBoxKey.enableStatusBarTapToTop,
    defaultVal: false,
  ),
  SwitchModel(
    title: '使用内置字体',
    subtitle: '使用内置HarmonyOS Sans字体，与系统默认字体相同\n关闭后用系统字体，可能卡顿，未修改系统字体不建议关闭',
    leading: const Icon(Icons.font_download_outlined),
    setKey: SettingBoxKey.useBuiltInFont,
    defaultVal: true,
    onChanged: (_) => Get.updateMyAppTheme(),
  ),
  SwitchModel(
    title: '视频封面一镜到底动画',
    subtitle: '点击视频卡片时封面平滑展开，返回时飞回原位\n仅支持首页的部分视频卡片和番剧/影视卡片',
    leading: const Icon(Icons.motion_photos_on_outlined),
    setKey: SettingBoxKey.enableHeroCoverAnimation,
    defaultVal: false,
    onChanged: (_) => SmartDialog.showToast("建议重启以应用更改"),
  ),
  NormalModel(
    title: '应用接续',
    subtitle: '相同华为用户播放视频时可在另一个设备的Dock栏中快速流转，无缝衔接上一个设备的视频。（始终开启）',
    leading: const Icon(Icons.devices_other),
    getTrailing: (theme) => IgnorePointer(
      child: Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: Switch(
          value: true,
          onChanged: (_) {},
          thumbIcon: WidgetStateProperty.all(
            const Icon(Icons.lock_outline_rounded),
          ),
        ),
      ),
    ),
  ),
    NormalModel(
    title: '后台下载离线缓存视频',
    subtitle: '接入鸿蒙后台任务，切换至后台不中断离线缓存视频下载（始终开启）',
    leading: const Icon(Icons.downloading),
    getTrailing: (theme) => IgnorePointer(
      child: Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: Switch(
          value: true,
          onChanged: (_) {},
          thumbIcon: WidgetStateProperty.all(
            const Icon(Icons.lock_outline_rounded),
          ),
        ),
      ),
    ),
  ),
];