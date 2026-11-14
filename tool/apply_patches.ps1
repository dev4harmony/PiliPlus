#
# 给「鸿蒙 Flutter SDK」打本项目需要的补丁（Windows 版）。
#
# 补丁：tool/patches/flutter_flutter_ohos_hwc.patch
#   - FlutterPage.ets：主 surface 背景按「本帧可见的 HCPP 平台视图数」在透明/不透明间切换；
#   - PlatformViewsControllerHybrid.ets：每帧把该计数发布到 AppStorage。
#
# 光改源码不够：构建读的是 bin/cache/artifacts/engine/ohos-*/ 下的
# flutter_embedding_*.har（源码 har），所以本脚本会顺带重打包这些 har。
#
# 用法（幂等，可反复跑）：
#   powershell -ExecutionPolicy Bypass -File tool\apply_patches.ps1
#   $env:FLUTTER_ROOT = 'D:\piliplus\flutter_flutter'; .\tool\apply_patches.ps1
#
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$PatchDir = Join-Path $Root 'tool/patches'
$EnginePatch = Join-Path $PatchDir 'flutter_flutter_ohos_hwc.patch'

# 相对 flutter root 的嵌入层源码根目录，以及需要覆盖进 har 的文件
$EmbedRel = 'engine/src/flutter/shell/platform/ohos/flutter_embedding/flutter'
$EmbedFiles = @(
    'src/main/ets/embedding/ohos/FlutterPage.ets',
    'src/main/ets/plugin/platform/PlatformViewsControllerHybrid.ets'
)
$HarMarker = 'hcpp_pv_count'

function Write-Log([string]$Message) { Write-Host "[apply_patches] $Message" }
function Write-Warn([string]$Message) { Write-Warning "[apply_patches] $Message" }

$script:LastOutput = ''
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    # 原生命令往 stderr 写东西时，$ErrorActionPreference=Stop 会把它变成终止错误，
    # 导致 $LASTEXITCODE 拿不到真实值，这里临时降级并把输出留下来做诊断。
    # 注意：参数不能叫 $Args，那是 PowerShell 的自动变量。
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $Exe @Arguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $script:LastOutput = ($out | Out-String).Trim()
    return $code
}

# 幂等应用：已打过就跳过，能打就打，打不上直接失败
function Invoke-Patch([string]$Repo, [string]$Patch, [string]$Name) {
    if (-not (Test-Path $Patch)) { throw "补丁不存在: $Patch" }
    if ((Invoke-Native 'git' @('-C', $Repo, 'apply', '--reverse', '--check', $Patch)) -eq 0) {
        Write-Log "${Name}: 已应用，跳过"
        return
    }
    if ((Invoke-Native 'git' @('-C', $Repo, 'apply', '--check', $Patch)) -ne 0) {
        throw "${Name}: 补丁无法应用（上游代码已变更？）。仓库: $Repo`n$script:LastOutput"
    }
    if ((Invoke-Native 'git' @('-C', $Repo, 'apply', $Patch)) -ne 0) {
        throw "${Name}: git apply 失败。仓库: $Repo`n$script:LastOutput"
    }
    Write-Log "${Name}: 已应用"
}

function Resolve-FlutterRoot {
    if ($env:FLUTTER_ROOT -and (Test-Path $env:FLUTTER_ROOT)) { return $env:FLUTTER_ROOT }
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    # <root>\bin\flutter.bat -> <root>
    return Split-Path -Parent (Split-Path -Parent $cmd.Source)
}

function Invoke-RepackEngineHars([string]$FlutterRoot) {
    $cache = Join-Path $FlutterRoot 'bin/cache/artifacts/engine'
    if (-not (Test-Path $cache)) {
        Write-Warn "找不到引擎产物目录，跳过 har 重打包: $cache"
        return
    }
    $count = 0
    foreach ($har in Get-ChildItem -Path $cache -Recurse -Filter *.har) {
        $list = (& tar -tzf $har.FullName 2>$null) -join "`n"
        if ($list -notmatch 'package/src/main/ets/embedding/ohos/FlutterPage\.ets') { continue }

        $content = (& tar -xzf $har.FullName -O 'package/src/main/ets/embedding/ohos/FlutterPage.ets' 2>$null) -join "`n"
        if ($content -match $HarMarker) { continue }   # 已是补丁版本

        $tmp = Join-Path $env:TEMP ("harpatch_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        & tar -xzf $har.FullName -C $tmp
        foreach ($rel in $EmbedFiles) {
            $dest = Join-Path $tmp ("package/src/main/ets/" + ($rel -replace '^src/main/ets/', ''))
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Item (Join-Path $FlutterRoot ($EmbedRel + '/' + $rel)) $dest -Force
        }
        $orig = $har.FullName + '.orig'
        if (-not (Test-Path $orig)) { Copy-Item $har.FullName $orig -Force }   # 首次留原始 har
        & tar -czf $har.FullName -C $tmp package
        Remove-Item $tmp -Recurse -Force
        $count++
        Write-Log ("har 已重打包: " + $har.FullName.Substring($cache.Length + 1))
    }
    if ($count -eq 0) { Write-Log '所有 har 均已是最新，无需重打包' }
}

$flutterRoot = Resolve-FlutterRoot
if (-not $flutterRoot) { throw '找不到 Flutter SDK，请设置 FLUTTER_ROOT' }
if (Test-Path (Join-Path $flutterRoot '.git')) {
    Invoke-Patch $flutterRoot $EnginePatch 'flutter_flutter'
} else {
    Write-Warn "$flutterRoot 不是 git 仓库，跳过源码补丁（仍会处理 har）"
}
Invoke-RepackEngineHars $flutterRoot

Write-Log '完成。改动落在本地 SDK 缓存，flutter upgrade 后需重跑。'
