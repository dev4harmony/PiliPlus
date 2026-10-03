# 鸿蒙 HDR 输出

全屏播放 HDR 片源（HDR10 / HDR Vivid / 杜比视界）时让系统真正进入 HDR 模式：面板拉起峰值亮度，按 BT.2020 PQ 显示。

## 为什么纹理做不到

libmpv 在鸿蒙上已经会把 NativeWindow 切到 BT.2020 PQ / HLG，并挂上 HDR 元数据。问题出在上屏：视频原本渲染进 Flutter 纹理，引擎会把纹理重采样进自己的 SDR 合成层，色域和 HDR 元数据都在这一步丢失（#72）。

## 方案

| 播放场景 | 渲染路径 | 输出 |
| --- | --- | --- |
| 全屏，且片源是 HDR | XComponent 平台视图（Flutter 3.44 自带的 HCPP 合成），直接交给 RenderService | HDR |
| 内嵌、画中画，或 SDR 片源 | 原来的 Flutter 纹理 | `--ohos-hdr-mode=no`，由 mpv 色调映射到 SDR |

- 内嵌播放不走平台视图，是因为平台视图要求视频上方的每一层 Flutter 都透明，在内嵌布局里做不到。
- 画中画是另一块 XComponent，平台视图跟不过去。
- 渲染路径和 HDR 信令都在创建 Player 时确定，所以进出全屏、进出画中画都会重建播放器，并保留进度、播放状态和倍速。重建与 `setDataSource` 共用一条串行队列（`PlayerRebuildQueue`）。

## 依赖

上游库的 HDR 改动目前都在以下 fork 的 `feat-ohos-hdr` 分支，后续计划提交给 cnoim：

| 仓库 | 内容 |
| --- | --- |
| [p1nbored/media-kit](https://github.com/p1nbored/media-kit) | 基于 cnoim `feat-ohos`（含 762fdc63）。`VideoControllerConfiguration` 新增 `usePlatformView` / `ohosHdrMode` / `ohosHdrTargetPeak`；XComponent 平台视图；固定下载下面这份 libmpv |
| [p1nbored/mpv](https://github.com/p1nbored/mpv) | 上报 HDR Vivid 类型，新增 `--ohos-hdr-mode`；把 Vivid 动态峰值接入 libplacebo 色调映射；设置缓冲区尺寸 |
| [p1nbored/FFmpeg](https://github.com/p1nbored/FFmpeg) | 鸿蒙硬解路径解析前缀 SEI 中的动态 HDR 元数据 |
| [p1nbored/libmpv-ohos-build](https://github.com/p1nbored/libmpv-ohos-build) | 用上面两个分支编译；发布为 [`20260831-hdr`](https://github.com/p1nbored/libmpv-ohos-build/releases/tag/20260831-hdr) |

`pubspec.yaml` 中 `media_kit`、`media_kit_video`、`media_kit_libs_video`、`media_kit_libs_ohos` 指向 p1nbored/media-kit。构建时 `media_kit_libs_ohos` 会自动下载并校验这份 libmpv。

这份 libmpv 早于 cnoim/libmpv-ohos-build 的 0253df1（编译优化选项），其余与 cnoim 当前的构建一致（FLAC 解码器同样保留）。

## 设置

- **启用 HDR 视频**：默认关闭。关闭或面板明确不支持 HDR 时，HDR 片源也按 SDR 输出。
- **HDR 峰值亮度**：色调映射的目标峰值，默认 1600 nit，可在 200–10000 之间修改。鸿蒙没有查询面板峰值亮度的接口，只能由用户按屏幕参数填写；修改后从下一次创建播放器起生效。

## 信令

| 片源 | qn | `--ohos-hdr-mode` | `--target-peak` |
| --- | --- | --- | --- |
| HDR Vivid | 129 | `vivid`（面板明确不支持 Vivid 时为 `hdr10`） | 峰值亮度设置值 |
| 杜比视界 | 126 | `vivid`（仅面板确认支持 Vivid 时，否则 `hdr10`） | 峰值亮度设置值 |
| HDR10 / HDR10+ | 125 | `hdr10` | 峰值亮度设置值 |
| 任何片源走纹理路径，或开关关闭 | | `no` | 不下发 |

- 杜比视界：鸿蒙没有对应的信令。RPU 由 libplacebo 应用后画面已经是 PQ，按 Vivid 上报只是借用这个类型标签，让面板拉起峰值亮度。
- 动态元数据由 libplacebo 逐帧用于色调映射，不转交给系统合成器。
- 不下发 `--target-peak` 时，libplacebo 会按 PQ 的名义峰值 10000 nit 推算目标亮度，高光被过度压暗。
- 纹理路径输出 SDR 时也不能下发 `--target-peak`：SDR 目标配上上千 nit 的峰值，整幅画面会被压暗。
- 纹理路径沿用 cnoim 的 SDR 目标（media-kit 762fdc63：BT.709 / BT.1886，spline 色调映射）。「启用 HDR 视频」关闭（默认）时，所有片源都按这个 SDR 目标输出，与上游现状一致。

逻辑在 `OhosHdrOutput`（`lib/plugin/pl_player/models/ohos_hdr_output.dart`），有单元测试覆盖。

## 验证

`snapshot_display` 截不到平台视图这一层，截图里视频区域是纯色块。请用 RenderService 的 dump 确认：

```bash
hdc shell hidumper -s RenderService -a allInfo | grep -E 'Name \[[0-9]+Surface\]'
```

全屏播放 HDR 片源时，`<viewId>Surface` 节点的 `NodeColorSpace` 应为 `7`（BT.2020）；Flutter 自身的 surface 为 `4`（sRGB）。

## 已知限制

- 只有全屏是 HDR。进出全屏会重建播放器，有一次短暂的重新缓冲。
- 平台视图模式下「左右翻转 / 上下翻转」不可用，因为它们是 Flutter 侧的绘制变换，设置中会隐藏这两项。
- 2in1 上鼠标悬停（不按键）不会传给视频区域：引擎没有为平台视图提供 hover 分发。
- media-kit 销毁仍挂着平台视图的播放器时，会打印 `[Player] has been disposed`，原生视图与视频输出也不会被释放（不影响播放），待在 media-kit 中修复。
