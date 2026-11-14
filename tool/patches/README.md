# 鸿蒙渲染相关补丁

本目录的补丁解决一件事：**让视频/网页的平台视图（HCPP）尽可能走进 RenderService
的硬件合成，同时不牺牲 Flutter 自身的图层资格。**

它是本地 SDK 上的改动，不在本仓库的源码里，所以 clone 之后需要显式执行一次。

```bash
# macOS / Linux / git-bash
bash tool/apply_patches.sh

# Windows
powershell -ExecutionPolicy Bypass -File tool\apply_patches.ps1
```

脚本是幂等的：已打过就跳过，能打就打，打不上会直接报错（说明上游代码变了，需要更新补丁）。
`flutter upgrade` 之后需要重新执行。

## `flutter_flutter_ohos_hwc.patch`

作用于**鸿蒙 Flutter SDK**（`CPF-Flutter/flutter_flutter`，分支 `oh-3.44.9-dev`）。

- `FlutterPage.ets`（`FlutterSurface`）：主 surface 的合成器背景色由
  「HCPP 开关 / renderFit」决定，改成「本帧有没有可见的平台视图」决定：
  - 无平台视图 → 首帧后置为不透明黑（`xComponentColor`），主 surface 才能当 HWC 候选；
  - 有平台视图 → 透明（主动退出竞争，把同 App 内唯一的 HWC 名额让给视频/网页）。

  背景为什么这么关键：`RSUniHwcVisitor::ProcessSolidLayerDisabled` 对 XComponent（XCOM）
  节点只有「不透明黑」放行，「透明」直接判 `DISABLED_BY_BACKGROUND_ALPHA`。

- `PlatformViewsControllerHybrid.ets`：每帧把「实际参与合成的平台视图数量」发布到
  `AppStorage['hcpp_pv_count']`（`onDisplayPlatformViewHybrid` 收集、
  `onEndFrameHybrid` 发布，值不变不写，避免每帧触发 UI 重渲染）。
  用「本帧可见数量」而不是「HCPP 是否开启」，因为后者装完应用就是恒 true，
  等于永久放弃主 surface 的 HWC 资格。

> **注意**：只改这个源码目录不会影响构建产物——`flutter build hap` 用的是
> `bin/cache/artifacts/engine/ohos-*/` 下预编译的 `flutter_embedding_*.har`
> （源码 har，里面就是 `.ets`）。所以 `apply_patches` 会顺带重打包这些 har：
> 解包 → 覆盖两个 `.ets` → 重新打包，原文件备份为 `*.har.orig`。这步不需要 DevEco。

## VS Code 任务链

`.vscode/tasks.json` 里已经串好了，F5（`build_env` 作为 preLaunchTask）和
`build_hap` 任务都会自动执行：

```
precache_ohos → apply_patches → build_env → build_hap
```

`precache_ohos`（`flutter precache --ohos`）是为了保证 `bin/cache/artifacts/engine`
下的 har 已经就位——没有 har 时补丁只会改源码，构建产物不会有任何变化。

## CI

`ohos` 发布流程是「clone 上游 flutter_flutter → build hap」，在 build 之前插两步：

```yaml
      - name: Precache ohos artifacts
        run: flutter precache --ohos
        shell: bash

      - name: Apply ohos patches
        run: bash tool/apply_patches.sh
        shell: bash
```

## 长期做法

补丁是权宜方案，上游合入后就可以删掉：给 `CPF-Flutter/flutter_flutter` 提 PR，
或维护一个带该提交的分支，让 `.fvmrc` / README 指向它——这样所有 clone 的人零成本获得。
