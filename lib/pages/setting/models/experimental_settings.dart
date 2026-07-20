import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

List<SettingsModel> experimentalSettings = [
  SwitchModel(
    title: '液态玻璃导航栏',
    subtitle: '启用液态玻璃底部导航栏\n没空适配鸿蒙导航栏\n可能有bug，将就用',
    leading: const Icon(Icons.science_outlined),
    setKey: SettingBoxKey.enableLGBar,
    defaultVal: false,
    onChanged: (_) => Get.find<MainController>().updateEnableLGBar(),
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
];
