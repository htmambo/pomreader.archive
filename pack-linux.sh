#!/usr/bin/env bash
# pack-linux.sh — 白虎阅读 Linux 可独立运行 tar.gz 打包脚本
#
# 特性:
#   - 幂等:源未变化则跳过打包,产物保持一致
#   - 增量:基于 (path|size|mtime) 元数据指纹,源变化才重建
#   - 版本号:优先 .desktop 提取 → $APP_VERSION → 命令行参数 → 默认 1.0.6
#   - 历史归档:previous_builds/ 自动保留最近 N 个旧版本
#   - 校验:同步生成 SHA256
#
# 用法:
#   ./pack-linux.sh                # 默认配置,源未变则跳过
#   ./pack-linux.sh 1.0.7          # 指定版本号
#   ./pack-linux.sh --force        # 强制重建,跳过幂等检查
#   ./pack-linux.sh --keep 10      # 历史归档保留数量 (默认 5)
#   ./pack-linux.sh --no-archive   # 不归档旧版本(覆盖构建)
#   ./pack-linux.sh --help
#
# 产物:
#   dist/${APP_NAME}-${VERSION}-linux-x64-${TIMESTAMP}.tar.gz
#   dist/${APP_NAME}-${VERSION}-linux-x64-${TIMESTAMP}.tar.gz.sha256
#   dist/previous_builds/          # 历史版本(可一键回滚)

set -euo pipefail

# ===== 配置 =====
APP_NAME="白虎阅读"
DEFAULT_VERSION="1.0.6"
ARCH="linux-x64"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/electron-linux"
DIST_DIR="$SCRIPT_DIR/dist"
STATE_FILE="$DIST_DIR/.build_state"
KEEP_PREVIOUS=5

# ===== 帮助 =====
usage() {
    sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { printf '\033[1;34m[pack]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pack]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[pack]\033[0m %s\n' "$*" >&2; }

# ===== 参数解析 =====
VERSION=""
FORCE=0
ARCHIVE_OLD=1
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)        usage ;;
        --force|-f)       FORCE=1 ;;
        --no-archive)     ARCHIVE_OLD=0 ;;
        --keep)           KEEP_PREVIOUS="${2:-5}"; shift ;;
        --keep=*)         KEEP_PREVIOUS="${1#*=}" ;;
        --*)              err "未知参数: $1"; exit 2 ;;
        *)                VERSION="$1" ;;
    esac
    shift
done

# ===== 前置检查 =====
[ -d "$SOURCE_DIR" ] || { err "源目录不存在: $SOURCE_DIR"; exit 1; }
[ -f "$SOURCE_DIR/electron" ] || { err "缺少 electron 二进制,请确认 electron-linux/ 已就绪"; exit 1; }
[ -x "$SOURCE_DIR/electron" ] || { err "electron 不可执行: $SOURCE_DIR/electron"; exit 1; }
[ -f "$SOURCE_DIR/${APP_NAME}.sh" ] || { err "缺少启动脚本: ${APP_NAME}.sh"; exit 1; }

mkdir -p "$DIST_DIR/previous_builds"

# ===== 版本号解析 =====
get_version() {
    if [ -n "$VERSION" ]; then
        echo "$VERSION"; return
    fi
    if [ -n "${APP_VERSION:-}" ]; then
        echo "$APP_VERSION"; return
    fi
    if [ -f "$SOURCE_DIR/${APP_NAME}.desktop" ]; then
        local v
        v=$(grep -oP '白虎阅读 \K[0-9]+\.[0-9]+\.[0-9]+' "$SOURCE_DIR/${APP_NAME}.desktop" 2>/dev/null || true)
        if [ -n "$v" ]; then echo "$v"; return; fi
    fi
    echo "$DEFAULT_VERSION"
}

VERSION=$(get_version)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_NAME="${APP_NAME}-${VERSION}-${ARCH}-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"

# ===== 指纹计算 =====
compute_fingerprint() {
    (
        cd "$SOURCE_DIR"
        find . -type f \
            ! -path './.omc/*' \
            ! -name '.omc' \
            -printf '%P\t%s\t%T@\n' 2>/dev/null \
            | LC_ALL=C sort \
            | sha256sum \
            | cut -d' ' -f1
    )
}

current_fp=$(compute_fingerprint)
last_fp=""
last_archive=""
last_timestamp=""
if [ -f "$STATE_FILE" ]; then
    last_fp=$(sed -n '1p' "$STATE_FILE" 2>/dev/null || true)
    last_archive=$(sed -n '2p' "$STATE_FILE" 2>/dev/null || true)
    last_timestamp=$(sed -n '3p' "$STATE_FILE" 2>/dev/null || true)
fi

# ===== 幂等判断 =====
# 当用户显式指定版本号或 --force 时,产物名/语义已变,跳过短路
if [ "$FORCE" -eq 0 ] && [ -z "$VERSION" ] && [ -z "${APP_VERSION:-}" ] \
    && [ "$current_fp" = "$last_fp" ] && [ -n "$last_archive" ] \
    && [ -f "$DIST_DIR/$last_archive" ]; then
    log "源未变化 (fingerprint=${current_fp:0:12}…)"
    log "当前产物: $last_archive"
    log "构建于:   $last_timestamp"
    log "如需重建: $0 --force"
    exit 0
fi

# ===== 错误处理:失败回滚 =====
cleanup_on_error() {
    local rc=$?
    err "打包失败 (rc=$rc),清理半成品..."
    rm -f "$ARCHIVE_PATH" "$ARCHIVE_PATH.sha256"
    exit $rc
}
trap cleanup_on_error ERR

# ===== 归档旧产物 =====
if [ "$ARCHIVE_OLD" -eq 1 ] && [ -n "$last_archive" ] && [ -f "$DIST_DIR/$last_archive" ]; then
    log "归档旧版本 → previous_builds/"
    mv "$DIST_DIR/$last_archive" "$DIST_DIR/previous_builds/" 2>/dev/null || true
    mv "$DIST_DIR/${last_archive}.sha256" "$DIST_DIR/previous_builds/" 2>/dev/null || true
fi

# ===== 打包 =====
log "构建 → $ARCHIVE_NAME"

# 排除规则:原始压缩包、备份、内部状态、编辑器临时
tar -czf "$ARCHIVE_PATH" \
    --exclude='electron-v*.zip' \
    --exclude='default_app.asar.bak' \
    --exclude='SHASUMS256.txt' \
    --exclude='.omc' \
    --exclude='.omc/*' \
    --exclude='*.swp' \
    --exclude='*.bak' \
    --exclude='__pycache__' \
    --exclude='.DS_Store' \
    --transform "s|^$(basename "$SOURCE_DIR")|$(basename "$SOURCE_DIR")|" \
    -C "$(dirname "$SOURCE_DIR")" \
    "$(basename "$SOURCE_DIR")"

# ===== 校验 =====
(
    cd "$DIST_DIR"
    sha256sum "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

# ===== 状态持久化 =====
{
    printf '%s\n%s\n%s\n' "$current_fp" "$ARCHIVE_NAME" "$TIMESTAMP"
} > "$STATE_FILE"

# ===== 轮转 previous_builds =====
prune_previous() {
    local archives=()
    local f
    while IFS= read -r f; do
        archives+=("$f")
    done < <(ls -1t "$DIST_DIR/previous_builds/"*.tar.gz 2>/dev/null || true)

    if [ "${#archives[@]}" -gt "$KEEP_PREVIOUS" ]; then
        for ((i = KEEP_PREVIOUS; i < ${#archives[@]}; i++)); do
            rm -f "${archives[$i]}" "${archives[$i]%.tar.gz}.sha256"
        done
    fi
}
prune_previous

trap - ERR

# ===== 输出 =====
size=$(du -h "$ARCHIVE_PATH" | cut -f1)
sha=$(awk '{print $1}' "$ARCHIVE_PATH.sha256")
log "✓ 完成: $ARCHIVE_NAME"
log "  体积:   $size"
log "  SHA256: $sha"
log "  路径:   $DIST_DIR/$ARCHIVE_NAME"
log "  解压:   tar -xzf \"$ARCHIVE_NAME\" -C <target>"
log "  运行:   ./$(basename "$SOURCE_DIR")/${APP_NAME}.sh"

if [ -d "$DIST_DIR/previous_builds" ] && [ -n "$(ls -A "$DIST_DIR/previous_builds" 2>/dev/null)" ]; then
    count=$(ls -1 "$DIST_DIR/previous_builds"/*.tar.gz 2>/dev/null | wc -l)
    log "历史: previous_builds/ ($count 个,保留最近 $KEEP_PREVIOUS)"
fi