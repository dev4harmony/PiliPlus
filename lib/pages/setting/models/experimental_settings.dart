import 'package:PiliPlus/harmony_adapt/harmony_channel.dart';
import 'package:PiliPlus/models/common/harmony/hds_material_level.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:os_type/os_type.dart';

List<SettingsModel> experimentalSettings = [
  if (OS.isHarmony)
    const SwitchModel(
      title: '允许和其他应用同时播放',
      subtitle: '语音输入等场景下尽量不中断视频和直播；重新播放后生效\n通话等系统强制中断不受此设置影响',
      leading: Icon(Icons.multitrack_audio_outlined),
      setKey: SettingBoxKey.allowConcurrentPlayback,
      defaultVal: false,
    ),
  SwitchModel(
    title: '鸿蒙沉浸光感导航栏',
    subtitle: '仅鸿蒙6.1及以上支持，侧边栏下不显示',
    leading: const Icon(Icons.water_drop_outlined),
    setKey: SettingBoxKey.enableHdsBar,
    defaultVal: false,
    onChanged: (_) => SmartDialog.showToast("重启生效"),
  ),
  if (OS.isHarmony)
    PopupModel(
      title: '沉浸光感导航栏材质',
      leading: const Icon(Icons.water_drop_outlined),
      value: () => Pref.hdsTabMaterialLevel,
      items: HdsMaterialLevel.values,
      onSelected: (value, setState) {
        GStorage.setting
            .put(SettingBoxKey.hdsTabMaterialLevel, value.index)
            .whenComplete(() {
          setState();
          HarmonyChannel.setTabMaterialLevel(value);
        });
      },
    ),
  SwitchModel(
    title: '鸿蒙沉浸光感顶栏',
    subtitle: '鸿蒙6.1以上支持，鸿蒙7以上完整效果\n侧边栏下不显示，不支持调节强度',
    leading: const Icon(Icons.blur_on_outlined),
    setKey: SettingBoxKey.enableHdsTopBar,
    defaultVal: false,
    onChanged: (_) => SmartDialog.showToast("重启生效"),
  ),
  const SwitchModel(
    title: '显示实际百分比音量',
    subtitle: '适配鸿蒙音量调节步进',
    leading: Icon(Icons.science_outlined),
    setKey: SettingBoxKey.showActualVolume,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '点击状态栏快速回顶',
    subtitle: '关闭后除部分原生支持界面，不再响应状态栏点击',
    leading: Icon(Icons.vertical_align_top_outlined),
    setKey: SettingBoxKey.enableStatusBarTapToTop,
    defaultVal: false,
  ),
  SwitchModel(
    title: '首页一镜到底动画',
    subtitle: '仅支持首页的视频卡片',
    leading: const Icon(Icons.motion_photos_on_outlined),
    setKey: SettingBoxKey.enableHeroCoverAnimation,
    defaultVal: false,
    onChanged: (_) => SmartDialog.showToast("建议重启以应用更改"),
  ),
  NormalModel(
    title: '应用接续',
    subtitle: '相同华为用户播放视频可在不同设备中快速流转视频。（始终开启）',
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