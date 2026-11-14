#!/usr/bin/env bash
#
# 给「鸿蒙 Flutter SDK」打本项目需要的补丁。
#
# 补丁：tool/patches/flutter_flutter_ohos_hwc.patch
#   - FlutterPage.ets：主 surface 背景按「本帧可见的 HCPP 平台视图数」在透明/不透明间切换；
#   - PlatformViewsControllerHybrid.ets：每帧把该计数发布到 AppStorage。
#
# 注意：光改引擎源码不够，构建实际读的是 bin/cache/artifacts/engine/ohos-*/ 下
# 预编译的 flutter_embedding_*.har（源码 har），所以脚本会顺带重打包这些 har。
#
# 用法：
#   bash tool/apply_patches.sh          # 幂等，可反复执行
#   FLUTTER_ROOT=/path/to/flutter bash tool/apply_patches.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT/tool/patches"
ENGINE_PATCH="$PATCH_DIR/flutter_flutter_ohos_hwc.patch"

# 相对 flutter root 的嵌入层源码根目录，以及需要覆盖进 har 的文件
EMBED_REL="engine/src/flutter/shell/platform/ohos/flutter_embedding/flutter"
EMBED_FILES=(
  "src/main/ets/embedding/ohos/FlutterPage.ets"
  "src/main/ets/plugin/platform/PlatformViewsControllerHybrid.ets"
)
HAR_MARKER="hcpp_pv_count"

log() { printf '[apply_patches] %s\n' "$*"; }
warn() { printf '[apply_patches] WARN: %s\n' "$*" >&2; }
die() { printf '[apply_patches] ERROR: %s\n' "$*" >&2; exit 1; }

# 幂等应用：已打过就跳过，能打就打，打不上直接失败。
apply_patch() {
  local repo="$1" patch="$2" name="$3"
  [ -f "$patch" ] || die "补丁不存在: $patch"
  if git -C "$repo" apply --reverse --check "$patch" >/dev/null 2>&1; then
    log "$name: 已应用，跳过"
    return 0
  fi
  if ! git -C "$repo" apply --check "$patch" >/dev/null 2>&1; then
    die "$name: 补丁无法应用（上游代码已变更？）。仓库: $repo"
  fi
  git -C "$repo" apply "$patch"
  log "$name: 已应用"
}

resolve_flutter_root() {
  if [ -n "${FLUTTER_ROOT:-}" ] && [ -d "$FLUTTER_ROOT" ]; then
    printf '%s\n' "$FLUTTER_ROOT"
    return 0
  fi
  command -v flutter >/dev/null 2>&1 || return 1
  local bin
  bin="$(cd "$(dirname "$(command -v flutter)")" && pwd)"
  printf '%s\n' "$(dirname "$bin")"
}

repack_engine_hars() {
  local flutter_root="$1"
  local engine_cache="$flutter_root/bin/cache/artifacts/engine"
  if [ ! -d "$engine_cache" ]; then
    warn "找不到引擎产物目录，跳过 har 重打包: $engine_cache"
    return 0
  fi

  local har tmp rel count=0
  while IFS= read -r -d '' har; do
    tar -tzf "$har" 2>/dev/null | grep -q "package/src/main/ets/embedding/ohos/FlutterPage.ets$" || continue
    # 已经是补丁版本就不动（幂等）；用 if 而不是 && continue，避免 set -e 提前退出
    if tar -xzf "$har" -O "package/src/main/ets/embedding/ohos/FlutterPage.ets" 2>/dev/null \
        | grep -q "$HAR_MARKER"; then
      continue
    fi

    tmp="$(mktemp -d)"
    tar -xzf "$har" -C "$tmp"
    for rel in "${EMBED_FILES[@]}"; do
      mkdir -p "$tmp/package/$(dirname "$rel")"
      cp "$flutter_root/$EMBED_REL/$rel" "$tmp/package/$rel"
    done
    [ -f "$har.orig" ] || cp "$har" "$har.orig"   # 首次重打包留一份原始 har
    tar -czf "$har" -C "$tmp" package
    rm -rf "$tmp"
    count=$((count + 1))
    log "har 已重打包: ${har#"$flutter_root"/}"
  done < <(find "$engine_cache" -name '*.har' -print0)

  if [ "$count" -eq 0 ]; then
    log "所有 har 均已是最新，无需重打包"
  fi
  return 0
}

main() {
  local flutter_root
  if flutter_root="$(resolve_flutter_root)"; then
    if [ -d "$flutter_root/.git" ]; then
      apply_patch "$flutter_root" "$ENGINE_PATCH" "flutter_flutter"
    else
      warn "$flutter_root 不是 git 仓库，跳过源码补丁（仍会处理 har）"
    fi
    repack_engine_hars "$flutter_root"
  else
    die "找不到 Flutter SDK，请设置 FLUTTER_ROOT"
  fi

  log "完成。改动落在本地 SDK 缓存，flutter upgrade 后需重跑。"
}

main "$@"
