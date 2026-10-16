# 鸿蒙 HDR 输出

播放 HDR 片源（HDR10 / HDR10+ / HDR Vivid / 杜比视界）时让系统真正进入 HDR 模式：面板拉起峰值亮度，按 BT.2020 PQ 显示；带动态元数据的片源由系统逐场景适配屏幕。

## 为什么纹理做不到

libmpv 在鸿蒙上已经会把 NativeWindow 切到 BT.2020 PQ / HLG，并挂上 HDR 元数据。问题出在上屏：视频原本渲染进 Flutter 纹理，引擎会把纹理重采样进自己的 SDR 合成层，色域和 HDR 元数据都在这一步丢失（#72）。

## 方案

| 播放场景 | 渲染路径 | 输出 |
| --- | --- | --- |
| 内嵌或全屏，且片源是 HDR | XComponent 平台视图（Flutter 3.44 自带的 HCPP 合成），直接交给 RenderService | HDR |
| 画中画，或 SDR 片源 | 原来的 Flutter 纹理 | `--ohos-hdr-mode=no`，由 mpv 色调映射到 SDR |

- 内嵌同样走平台视图：视频区之外由页面内容自己上底色（页面各层的 `backgroundColor` 与视频矩形内的黑底）。
- 画中画是另一块 XComponent，平台视图跟不过去。
- 渲染路径和传给 mpv 的 HDR 参数都在创建 Player 时确定（`OhosOutput`）。与新需要的不一致时重建播放器，并保留进度、播放状态和倍速：在 SDR 与 HDR 片源之间切换、进出画中画、改了峰值亮度设置。几档 HDR 之间切换得到的是同一个输出，不重建；进出全屏也不重建。重建与 `setDataSource` 共用一条串行队列（`PlayerRebuildQueue`）。

## 依赖

上游库的 HDR 改动目前都在以下 fork 的 `feat-ohos-hdr` 分支，后续计划提交给 cnoim：

| 仓库 | 内容 |
| --- | --- |
| [p1nbored/media-kit](https://github.com/p1nbored/media-kit) | 基于 cnoim `feat-ohos`（含 762fdc63）。`VideoControllerConfiguration` 新增 `usePlatformView` / `ohosHdrMode` / `ohosHdrTargetPeak`；XComponent 平台视图；固定下载下面构建出的 libmpv |
| [p1nbored/mpv](https://github.com/p1nbored/mpv) | `--ohos-hdr-mode`：按码流决定上报的 HDR 类型，给 NativeWindow 写描述实际输出的静态元数据与逐帧的 HDR Vivid 动态元数据（杜比视界、HDR10+ 换算而来）；设置缓冲区尺寸 |
| [p1nbored/FFmpeg](https://github.com/p1nbored/FFmpeg) | 鸿蒙解码路径解析 SEI 中的 HDR 元数据：静态的母版显示器信息与内容亮度（SEI 137/144），动态的 HDR Vivid、HDR10+ 与杜比视界 RPU |
| [p1nbored/libmpv-ohos-build](https://github.com/p1nbored/libmpv-ohos-build) | 用上面两个分支编译并发布 libmpv；`tests/run.sh` 是 HDR 元数据换算的主机端单元测试 |

`pubspec.yaml` 中 `media_kit`、`media_kit_video`、`media_kit_libs_video`、`media_kit_libs_ohos` 指向 p1nbored/media-kit。构建时 `media_kit_libs_ohos` 会自动下载并校验其 CMakeLists 里固定的那份 libmpv。

这份 libmpv 不含 cnoim/libmpv-ohos-build 的 0253df1（编译优化选项），其余与 cnoim 当前的构建一致（FLAC 解码器同样保留）。

## 设置

- **启用 HDR 视频**：默认开启。关闭或面板明确不支持 HDR 时，HDR 片源也按 SDR 输出。
- **匹配视频亮度**：默认开启。开启时按片源自身的亮度输出：mpv 不做色调映射，只有超出屏幕能力的部分由系统按元数据适配。关闭时由 mpv 把比「HDR 峰值亮度」亮的片源压缩到这个峰值；更暗的片源保持原亮度，不会被拉伸，交给系统的画面和元数据与开启时完全一样。两种情况下 HDR 画面都不随系统亮度变化。
- **HDR 峰值亮度**：关闭「匹配视频亮度」后才用：比它亮的片源由 mpv 压缩进这个范围，而不是被屏幕截断；更暗的片源保持原亮度。按屏幕的峰值亮度填写，默认 1000 nit，可在 200–10000 之间修改；填得比屏幕能达到的还高时，超出的部分仍会被屏幕截断。

「匹配视频亮度」与峰值亮度在播放中修改立即生效（重建播放器，保留进度）；「启用 HDR 视频」从下一次打开视频起生效。

## 信令

`--ohos-hdr-mode`：

| 场景 | 取值 |
| --- | --- |
| 平台视图输出 HDR | `auto` |
| 同上，但面板明确不支持 HDR Vivid | `hdr10`，只有静态元数据 |
| 纹理路径，或「启用 HDR 视频」关闭 | `no` |

`auto` 时 mpv 按码流决定上报给系统的类型，不看画质档位：

| 片源 | 系统 HDR 类型 | 动态元数据 |
| --- | --- | --- |
| HDR10 | HDR10 | 无 |
| HDR10+ | HDR Vivid | 由 ST 2094-40 换算 |
| HDR Vivid | HDR Vivid | 片源自带的；mpv 做了色调映射时按映射后的画面重新生成 |
| 杜比视界 | HDR Vivid | 由 RPU 的 L1 换算，叠加 L3 的偏移 |
| HLG | HLG | 无 |

- 鸿蒙只有 HLG、HDR10、HDR Vivid 三种类型，其中只有 HDR Vivid 带动态元数据，所以杜比视界和 HDR10+ 换算成 HDR Vivid 上报。杜比视界的 RPU 由 libplacebo 应用，交给系统的画面已经是 BT.2020 PQ。
- 杜比视界的 L1 是 CM v2.9 在 LMS 空间算的分析值，L3 是对它的偏移：CM v4 按 L1 + L3 重建自己基于 RGB 的分析值，平均值里还带着调色师的全局中间调偏移（Dolby Vision Color Grading Best Practices Guide 4.0，元数据层级一节）。mpv 按 dovi_tool 的编码（2048 为零，每级 1/2048 PQ）叠加，得到的同一组值（`mp_dovi_shot`）既换算成 HDR Vivid 的 maxRGB 统计量（HDR Vivid 要的正是基于 RGB 的统计量），也是 libplacebo 色调映射的依据。两处例外：峰值不低于 L1 测得的峰值。系统按峰值给图层分配亮度，报得比画面实际的低，高光就会被压向 SDR 白、跟着系统亮度走，libplacebo 也会截掉比它亮的高光；基于 RGB 的峰值本来也不会低于 CM v2.9 的。平均值不低于最小的非零码值：有峰值的画面平均不可能是全黑，L1 却可能把它舍入成 0，中间调偏移也可能把它压到 0；libplacebo 还会把 0 当成没有动态元数据，退回按静态的母版峰值（常见 4000 nit）映射。L2/L8（各目标显示器的调色修正）目前没有换算。
- libplacebo 自己只从 RPU 取 L1（启用 libdovi 时，解析原始 RPU 那一步还会再写一遍），所以 mpv 在这两步之后把 L1 + L3 写回它的 `max_pq_y` / `avg_pq_y`。「匹配视频亮度」关闭、片源比目标亮时，杜比视界不用 libplacebo 通用的 spline，而按杜比自己显示管理的曲线映射（mpv 的 `video/dovi_tone_map.c`，US 10,600,166 B2 表 1 的单调 cutoff 变体；杜比后来的专利 US 11,336,895 B2、WO 2023/056267 A1 把它列为 L1 + L3 + L8 这条路径的曲线；`--tone-mapping` 选了别的曲线时照用那条）。目标给片源的阴影和高光都留得下位置时，中间调 1:1 不动，只压缩高光；放不下时中间调移开，给高光或阴影各留一半的范围；黑、中间调、峰值之间用单调的三次 Hermite 曲线相连。L3 的中间调偏移移动的是曲线据以映射的中间调，而不是画面：正偏移让镜头显得比实际亮，中间调放不下就往下移，画面变暗；负偏移让它显得比实际暗，中间调被保持在杜比目标显示器的黑位（0.005 nit）之上，阴影和黑位随之抬起，画面发灰。以录到的测试片段映射到 1000 nit 为例：未修正的镜头 100 nit 处输出 98.5 nit（spline 是 73 nit），+0.5 的镜头暗约 37%，-0.5 的镜头阴影提亮约 20%–40%、黑位抬到 0.005 nit；映射到 1600 nit 时差别小一些（+0.5 暗约 9%）。曲线参数（cutoff、各留一半）是专利给的示例值，杜比实际出货的显示管理不公开，-0.5 发灰的程度未必与杜比设备完全一样。开启「匹配视频亮度」时 mpv 不做映射，偏移只经 HDR Vivid 元数据交给系统适配。L1 / L3 的最小值只进 HDR Vivid：libplacebo 映射 PQ 时一律以绝对黑为下限。
- 静态元数据（母版显示器、MaxCLL / MaxFALL）取自 SEI 137/144，描述的是实际输出：片源不比目标亮（按它的 MaxCLL，缺 MaxCLL 时按母版峰值；画面实际更亮时按实际的，即杜比视界、HDR Vivid 帧自带的峰值或 libplacebo 测得的峰值）时就是片源自己的值，比目标亮、要被压缩时峰值换成目标亮度。杜比视界片源缺这些 SEI 时，由 RPU 的 L6（MaxCLL / MaxFALL、母版亮度）与 L9（母版显示器原色）补齐。系统按 MaxCLL 决定把面板提亮多少，所以它不会是 0：缺 MaxCLL 时用母版峰值；完全没有亮度元数据的 PQ 片源按 libplacebo 的默认值（PQ 名义峰值 10000 nit）上报。
- `--target-peak`：「匹配视频亮度」开启时不下发，mpv 以片源自身的峰值为目标，不压缩高光；关闭时下发「HDR 峰值亮度」，mpv 只把比它亮的片源色调映射进来，上报的元数据按映射后的画面计算。libplacebo 只压缩、从不拉伸（没有开 `--inverse-tone-mapping`），所以更暗的片源原样输出，上报的也是片源自己的元数据，与开启时一样；mpv 对 libplacebo 的目标仍然是「HDR 峰值亮度」，测出比元数据标的更亮的画面照样会被压缩，这时上报的峰值随测量值上调，超过目标就按压缩后的画面上报。片源的峰值按优先级取自：杜比视界 L1 + L3 与 HDR Vivid 的逐帧峰值；其余片源由 libplacebo 在 GPU 上逐帧测量（HDR10+ 也测，测得的峰值优先于它的场景峰值），不只信静态的 MaxCLL——有的 HDR10 片源标 1000 nit，画面却到 10000 nit，只信元数据的话比标称值亮的部分要么被压成一片，要么原样交给屏幕截断。media-kit 默认关掉了测量（`hdr-compute-peak=no`），所以这时播放器显式打开（`OhosHdrOutput.measuresPeak`）；「匹配视频亮度」开启时不测，否则测出的更高峰值会让 mpv 去压缩画面。
- 鸿蒙按元数据给 HDR 图层分配亮度（graphic_2d `RSHdrUtil::UpdateSurfaceNodeNit`：由 MaxCLL 与动态元数据算出图层亮度，上限是屏幕此刻能达到的亮度），PQ 画面按绝对亮度显示，系统亮度只影响 SDR 界面。实测 HDR 画面在屏时系统把面板拉到 HDR 峰值（约 1600 nit），亮度条只改变 SDR 白（`display.getBrightnessInfo()` 报的 `sdrNits × 余量` 基本不变）。所以无论是否开启「匹配视频亮度」，HDR 画面都不随系统亮度变化。
- 纹理路径输出 SDR 时不能下发 `--target-peak`：SDR 目标配上上千 nit 的峰值，整幅画面会被压暗。
- 纹理路径沿用 cnoim 的 SDR 目标（media-kit 762fdc63：BT.709 / BT.1886，spline 色调映射）。

逻辑在 `OhosHdrOutput`（`lib/plugin/pl_player/models/ohos_hdr_output.dart`），有单元测试覆盖。

## 验证

`snapshot_display` 截不到平台视图这一层，截图里视频区域是纯色块。请用 RenderService 的 dump 确认：

```bash
hdc shell hidumper -s RenderService -a allInfo | grep -E 'Name \[[0-9]+Surface\]'
```

播放 HDR 片源时，`<viewId>Surface` 节点的 `NodeColorSpace` 应为 `7`（BT.2020）；Flutter 自身的 surface 为 `4`（sRGB）。

mpv 的 `vo/gpu-next/ohos` 模块在 verbose 级别打印 NativeWindow 的色彩空间、HDR 类型和静态元数据（含母版原色 `primaries R … G … B … W …`，可核对 L9），以及杜比视界 RPU 带了哪些层级（`Dolby Vision RPU levels: 1 2x3 3(min … max … avg …) 5 6 8x2 9 11 254`，`xN` 是同一层级的块数，括号里是 L3 的原始码值），在 debug 级别打印每次更新的动态元数据。mpv 做色调映射时，这一行末尾还有曲线的输入（`tone mapped from avg … max …`，4095 码值；avg 为 0 表示没有动态的平均值，例如 HDR10），可核对 L1 + L3 是否进了色调映射。

渲染服务在 debug 级别打印每个 HDR 视频图层的 `RSHdrUtil::UpdateSurfaceNodeNit`（`layerNits`、`displayNits`、`sdrNits`、`scaler`），可据此核对屏幕上的峰值。

## 已知限制

- 在 SDR 与 HDR 片源之间切换清晰度、进出画中画会重建播放器，有一次短暂的重新缓冲。
- 2in1 上鼠标悬停（不按键）不会传给视频区域：引擎没有为平台视图提供 hover 分发。
- media-kit 销毁仍挂着平台视图的播放器时，会打印 `[Player] has been disposed`，原生视图与视频输出也不会被释放（不影响播放），待在 media-kit 中修复。
