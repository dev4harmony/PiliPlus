# 鸿蒙版视频播放体验改进

本文档说明本次针对鸿蒙版（`ohos` 基线）视频播放体验的改动，便于 review、测试和后续同步上游。

## 背景

鸿蒙版在平板、折叠屏和自由窗口下使用「左侧视频 + 右侧边栏」的横屏布局。实际使用中存在以下问题：

1. 多 P 视频位于合集内时，最后一 P 播完会继续播放合集里的其他视频；用户只想连续看完当前视频的分 P 后停止。
2. 横屏布局的视频与右侧栏宽度是固定比例，右侧评论/相关视频/播放列表空间不足，无法自行调整。
3. 拖动分栏时右侧栏宽度逐帧变化，评论图片的请求地址带 `@Nw` 尺寸后缀，导致每一帧都生成新 URL、反复下载图片。
4. `battery_plus` 已切换到带鸿蒙实现的 git 分支，但 `pubspec.lock` 和鸿蒙插件注册表仍引用旧的 `battery_plus_ohos`，会导致 HAP 构建时 ArkTS 找不到模块。

## 改动内容

### 1. 分 P 连播不再越界进入合集

- 新增设置项「自动连播合集」（设置 → 播放设置 → 播放顺序下方），默认关闭。
- 关闭时：
  - 顺序播放：当前视频的分 P 依次播放，最后一 P 结束即停止，不再进入合集。
  - 自动连播：多 P 视频播完后同样停止，不再跳到合集或相关视频。
  - 列表循环：只在当前视频的分 P 内循环。
  - 单个循环：保持原逻辑。
- 开启时：恢复旧行为，分 P 播完后继续播放合集内其他视频。
- 稍后再看/收藏夹的「播放全部」属于播放列表场景，不受此开关影响。

相关文件：

- `lib/pages/video/introduction/ugc/controller.dart`
- `lib/pages/setting/models/play_settings.dart`
- `lib/utils/storage_key.dart`
- `lib/utils/storage_pref.dart`

### 2. 横屏视频/右侧栏支持拖动调节

- 在「左视频 + 右侧栏」布局中间加入可拖动分隔条。
- 左右拖动可实时调整视频与右侧栏宽度比例；比例会持久化，下次打开视频仍生效。
- 约束：
  - 侧栏最小宽度 280；
  - 视频最小宽度约为可用宽度的 38%（上限 640）；
  - 视频高度不超过窗口可用高度，避免纵向溢出。
- 视觉与命中：
  - 视觉间距 6；
  - 线条 3 × 48，圆角 1.5；
  - 透明命中区域 28，向视频和侧栏两侧扩展，便于平板触控。
- 全屏时右侧栏隐藏，分隔条同时隐藏。

相关文件：

- `lib/pages/video/view.dart`
- `lib/utils/storage_key.dart`（`videoLandscapeSplitRatio`）
- `lib/utils/storage_pref.dart`

### 3. 稳定拖动时的评论图片请求尺寸

问题原因：`ImageGridView` 的图片请求尺寸来自侧栏当前宽度；拖动时宽度逐帧变化，`NetworkImgLayer` 生成的 `@Nw.webp` URL 也随之逐帧变化，`CachedNetworkImage` 会把每一帧都当成新图片重新请求。

改动：

- `ImageGridView` 将图片请求/解码尺寸量化到 256 的倍数（如 769~1024 都使用 1024）。
- 拖动过程中只有跨过尺寸档位才会换 URL，通常整次拖动只请求 1~3 次。
- `NetworkImgLayer` 新增可选的 `memCacheWidth` / `memCacheHeight`，允许调用方显式指定稳定尺寸。
- 网格占位图的 `cacheWidth` 同步量化，避免占位图反复解码。

代价：图片可能比当前显示宽度多请求最多 256px 的档位，以换取缓存命中和网络请求次数的大幅下降。

相关文件：

- `lib/common/widgets/image_grid/image_grid_view.dart`
- `lib/common/widgets/image/network_img_layer.dart`

### 4. 鸿蒙 HAP 构建兼容修复

- `pubspec.lock` 同步为带鸿蒙实现的 `battery_plus` git 分支。
- `GeneratedPluginRegistrant.ets` 的导入从 `battery_plus_ohos` 改为 `battery_plus`，与当前依赖解析一致。

相关文件：

- `pubspec.lock`
- `ohos/entry/src/main/ets/plugins/GeneratedPluginRegistrant.ets`

## 已知限制

- 折叠屏/平板上，竖屏视频进入竖屏全屏后退出，如果系统保持旋转锁定，窗口可能仍停在竖屏。该问题本次未修改方向恢复逻辑。
  - 临时方案：设置 → 播放设置 → 默认全屏方向，选择「不改变当前方向」或「强制横屏」。
  - 后续可单独评估「平板竖屏视频全屏保持横屏（letterbox）」方案。
- 图片请求尺寸量化会让单张图片最多多请求 256px 的档位，属于网络次数与单张体积之间的折中。

## 构建与版本

本次验证构建：

```powershell
flutter build hap --release --no-codesign --no-pub `
  --build-name=2.1.6.2.6 `
  --build-number=6339
```

产物为未签名 release HAP，安装前需使用自己的证书签名。

## 测试建议

1. 打开一个位于合集内、包含 5 个分 P 的视频：
   - 顺序播放/自动连播：播完第 5 P 应停止；
   - 打开「自动连播合集」后：应继续播放合集内其他视频；
   - 列表循环：应只在当前视频的 5 个分 P 内循环。
2. 横屏布局拖动分隔条：
   - 视频与侧栏宽度实时变化；
   - 松手后重新进入视频，比例保持；
   - 侧栏最小宽度、视频最小宽度符合预期。
3. 右侧栏切到评论区并显示图片：
   - 拖动分栏时观察网络请求，正常情况下整次拖动只出现少量图片请求；
   - 图片显示清晰度可接受。
4. 稍后再看/收藏夹「播放全部」：仍应跨视频连播。

## 提交记录

- `fix(video): 分P播完不再自动进入合集`
- `build(ohos): 修复 battery_plus 鸿蒙插件注册`
- `feat(video): 横屏左右分栏支持拖动调节`
- `fix(video): 扩大分栏拖动条命中范围并保持视觉宽度`
- `perf(image): 稳定分栏拖动时的评论图片请求尺寸`
- `fix(video): 缩窄横屏分栏右侧空隙`
