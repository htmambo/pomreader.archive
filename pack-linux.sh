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
#   ./pack-linux.sh --electron-version 44.4.5  # 指定 Electron 运行时版本
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
DEFAULT_ELECTRON_VERSION="44.4.5"
ARCH="linux-x64"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/electron-linux"
DIST_DIR="$SCRIPT_DIR/dist"
STATE_FILE="$DIST_DIR/.build_state"
KEEP_PREVIOUS=5
ELECTRON_VERSION="${ELECTRON_VERSION:-$DEFAULT_ELECTRON_VERSION}"

# ===== 帮助 =====
usage() {
    sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { printf '\033[1;34m[pack]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pack]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[pack]\033[0m %s\n' "$*" >&2; }

# ===== 自举:依赖安装与 app.asar 构建 =====
# 仓库只入白虎阅读_asar/ 源码与 electron-linux/ 的壳文件(脚本/icon/desktop/html/license/version),
# electron 二进制与 resources/app.asar 由本脚本在运行期生成。
# 这里保证 @electron/asar 与 app.asar 就绪后再做前置检查。
ensure_node_deps() {
    if [ ! -x "$SCRIPT_DIR/node_modules/.bin/asar" ]; then
        log "安装构建依赖 (@electron/asar)..."
        (cd "$SCRIPT_DIR" && npm install --no-audit --no-fund --no-save) \
            || { err "npm install 失败,请检查网络或手动执行: cd $SCRIPT_DIR && npm install"; return 1; }
    fi
}

ensure_app_asar() {
    if [ ! -f "$SOURCE_DIR/resources/app.asar" ]; then
        if [ ! -d "$SCRIPT_DIR/白虎阅读_asar" ]; then
            err "缺少 app.asar 且无源目录 白虎阅读_asar/,无法重建"
            return 1
        fi
        log "构建 app.asar ← 白虎阅读_asar/"
        mkdir -p "$SOURCE_DIR/resources"
        (cd "$SCRIPT_DIR" && "$SCRIPT_DIR/node_modules/.bin/asar" pack \
            "白虎阅读_asar" "$SOURCE_DIR/resources/app.asar") \
            || { err "asar pack 失败"; return 1; }
    fi
}

ensure_icons() {
    # PKGBUILD 期望 ${APP_NAME}_${size}x${size}x32.png(16/32/128/256/512/1024),
    # 这些文件不入仓(.gitignore 已排除),需要从 icon.png 缩放生成。
    local icon_source="$SOURCE_DIR/icon.png"
    local magick_cmd=""

    if [ ! -f "$icon_source" ]; then
        err "缺少源图标: $icon_source"
        return 1
    fi

    local missing=()
    local size
    for size in 16 32 128 256 512 1024; do
        if [ ! -f "$SOURCE_DIR/${APP_NAME}_${size}x${size}x32.png" ]; then
            missing+=("$size")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi

    if command -v magick >/dev/null 2>&1; then
        magick_cmd="magick"
    elif command -v convert >/dev/null 2>&1; then
        magick_cmd="convert"
    else
        err "需要 ImageMagick (magick 或 convert) 生成缺失图标: ${missing[*]}"
        err "  安装: sudo pacman -S imagemagick"
        err "  或手动放置图标到: $SOURCE_DIR/${APP_NAME}_\${size}x\${size}x32.png"
        return 1
    fi

    log "从 icon.png 生成图标: ${missing[*]}"
    for size in "${missing[@]}"; do
        local out="$SOURCE_DIR/${APP_NAME}_${size}x${size}x32.png"
        # -define png:color-type=6 强制 8-bit RGBA,避免小图被 magick 自动 quantize 成 8-bit 调色板
        # 调色板模式在某些 KDE 版本下渲染异常(透明度丢失或不显示)
        "$magick_cmd" "$icon_source" -resize "${size}x${size}" \
            -define png:color-type=6 PNG32:"$out" \
            || { err "生成图标失败 ($size): $out"; return 1; }
    done
    log "图标生成完成"
}

ensure_electron_binary() {
    if [ ! -x "$SOURCE_DIR/electron" ]; then
        log "下载 Electron ${ELECTRON_VERSION} ${ARCH}..."
        log "  (首次约 70MB,后续跳过;镜像: ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/)"

        local tmpdir
        tmpdir="$(mktemp -d)"

        # 临时目录装 electron 包(只装 JS 壳,二进制靠下一步 install-electron 触发下载)
        if ! (cd "$tmpdir" && npm install "electron@${ELECTRON_VERSION}" \
                --no-audit --no-fund --no-save); then
            rm -rf "$tmpdir"
            err "Electron npm 包安装失败,请检查网络"
            err "  镜像: ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/"
            err "  或手动放置 electron 二进制到 $SOURCE_DIR/electron"
            return 1
        fi

        # electron@44.4.5+ 改为懒下载:install.js 是 bin 'install-electron'。
        # npm install 不再触发 postinstall,需主动调用。
        if ! (cd "$tmpdir/node_modules/electron" && node install.js); then
            rm -rf "$tmpdir"
            err "Electron 二进制下载失败(已在 npm 包安装后调用 install.js)"
            err "  镜像: ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/"
            return 1
        fi

        local electron_dist="$tmpdir/node_modules/electron/dist"
        if [ ! -d "$electron_dist" ]; then
            rm -rf "$tmpdir"
            err "未找到 electron dist 目录: $electron_dist"
            return 1
        fi

        # dist 内容与 electron-linux/ 中文自定义文件名无冲突;cp -a 不删目标已有文件
        # 故 app.asar (ensure_app_asar 已构建) 与中文壳文件保持原样
        if ! cp -a "$electron_dist/." "$SOURCE_DIR/"; then
            rm -rf "$tmpdir"
            err "复制 Electron 运行时失败"
            return 1
        fi

        rm -rf "$tmpdir"
        [ -x "$SOURCE_DIR/electron" ] || chmod +x "$SOURCE_DIR/electron"
        log "Electron ${ELECTRON_VERSION} ${ARCH} 已就绪"
    fi
}

hint_electron_missing() {
    err "缺少 electron 二进制: $SOURCE_DIR/electron"
    err "修复步骤:"
    err "  1. 从 https://www.electronjs.org/releases 下载 electron-${ARCH}.zip"
    err "  2. 解压到 $SOURCE_DIR/:"
    err "       cd $SOURCE_DIR && unzip -o electron-\${VERSION}-${ARCH}.zip"
    err "  3. 确认 $SOURCE_DIR/electron 存在且可执行 (chmod +x)"
}

# ===== 参数解析 =====
VERSION=""
FORCE=0
ARCHIVE_OLD=1
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)                usage ;;
        --force|-f)               FORCE=1 ;;
        --no-archive)             ARCHIVE_OLD=0 ;;
        --keep)                   KEEP_PREVIOUS="${2:-5}"; shift ;;
        --keep=*)                 KEEP_PREVIOUS="${1#*=}" ;;
        --electron-version)       ELECTRON_VERSION="${2:-$DEFAULT_ELECTRON_VERSION}"; shift ;;
        --electron-version=*)     ELECTRON_VERSION="${1#*=}" ;;
        --*)                      err "未知参数: $1"; exit 2 ;;
        *)                        VERSION="$1" ;;
    esac
    shift
done

# ===== 前置检查 =====
[ -d "$SOURCE_DIR" ] || { err "源目录不存在: $SOURCE_DIR"; exit 1; }

# 自举:缺构建依赖就 npm install,缺 app.asar 就从白虎阅读_asar/ 重建,
# 缺图标就从 icon.png 缩放生成,缺 electron 运行时二进制就 npm install 自动下载
ensure_node_deps || exit 1
ensure_app_asar || exit 1
ensure_icons || exit 1
ensure_electron_binary || exit 1

mkdir -p "$DIST_DIR/previous_builds"

[ -f "$SOURCE_DIR/electron" ] || { hint_electron_missing; exit 1; }
[ -x "$SOURCE_DIR/electron" ] || { err "electron 不可执行: $SOURCE_DIR/electron (chmod +x)"; exit 1; }
[ -f "$SOURCE_DIR/${APP_NAME}.sh" ] || { err "缺少启动脚本: ${APP_NAME}.sh"; exit 1; }

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