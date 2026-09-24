#!/usr/bin/env bash
# pack-pacman.sh — 白虎阅读 Arch Linux pacman 包打包脚本
#
# 产物:dist/pomreader-${VERSION}-${PKGREL}-x86_64.pkg.tar.zst
# 安装:sudo pacman -U dist/pomreader-*.pkg.tar.zst
# 启动:在应用菜单搜"白虎阅读",或终端执行 pomreader
#
# 特性:
#   - 幂等:source 指纹未变则跳过 makepkg 调用
#   - 自动版本号:从 .desktop 提取 → $APP_VERSION → 命令行参数 → 默认 1.0.6
#   - 自动清理:构建完成后可保留或删除临时 build/ 目录
#   - 路径迁移:.desktop 内硬编码 ~/htdocs/pomreader 自动改写为 /usr/bin/pomreader
#   - 隔离的 /usr/bin/pomreader:硬编码 /opt/pomreader/electron,与 macOS 原版 \$DIR 相对路径无关
#
# 用法:
#   ./pack-pacman.sh                  # 默认版本,源未变则跳过
#   ./pack-pacman.sh 1.0.7            # 指定版本号
#   ./pack-pacman.sh --force          # 强制重建,跳过幂等检查
#   ./pack-pacman.sh --pkgrel 2       # 设定 pkgrel(默认 1)
#   ./pack-pacman.sh --keep-build     # 构建后保留 build/ 目录(默认清理)
#   ./pack-pacman.sh --sign           # 生成 GPG 签名 .sig(需配置 GPG)
#   ./pack-pacman.sh --install-deps   # 同步安装运行时依赖(checkdeps)
#   ./pack-pacman.sh --electron-version 44.4.5  # 指定 Electron 运行时版本
#   ./pack-pacman.sh --help

set -euo pipefail

# ===== 配置 =====
APP_NAME="白虎阅读"
PKG_NAME="pomreader"
INSTALL_PATH="/opt/${PKG_NAME}"
DEFAULT_VERSION="1.0.6"
DEFAULT_ELECTRON_VERSION="44.4.5"
ARCH="x86_64"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/electron-linux"
DIST_DIR="$SCRIPT_DIR/dist"
BUILDDIR="$SCRIPT_DIR/build"
STATE_FILE="$DIST_DIR/.build_state"
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
# 仓库只入白虎阅读_asar/ 源码与 electron-linux/ 的壳文件,electron 二进制与
# resources/app.asar 由本脚本在运行期生成。这里保证 @electron/asar 与 app.asar
# 就绪后再做前置检查。
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
    err "  1. 从 https://www.electronjs.org/releases 下载 electron-linux-x64.zip"
    err "  2. 解压到 $SOURCE_DIR/:"
    err "       cd $SOURCE_DIR && unzip -o electron-v\${VERSION}-linux-x64.zip"
    err "  3. 确认 $SOURCE_DIR/electron 存在且可执行 (chmod +x)"
}

# ===== 参数解析 =====
VERSION=""
VERSION_EXPLICIT=0
PKGREL="1"
FORCE=0
KEEP_BUILD=0
SIGN_PKG=0
INSTALL_DEPS=0
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)                usage ;;
        --force|-f)               FORCE=1 ;;
        --pkgrel)                 PKGREL="${2:-1}"; shift ;;
        --pkgrel=*)               PKGREL="${1#*=}" ;;
        --keep-build)             KEEP_BUILD=1 ;;
        --sign)                   SIGN_PKG=1 ;;
        --install-deps)           INSTALL_DEPS=1 ;;
        --electron-version)       ELECTRON_VERSION="${2:-$DEFAULT_ELECTRON_VERSION}"; shift ;;
        --electron-version=*)     ELECTRON_VERSION="${1#*=}" ;;
        --*)                      err "未知参数: $1"; exit 2 ;;
        *)                        VERSION="$1"; VERSION_EXPLICIT=1 ;;
    esac
    shift
done

# ===== 前置检查 =====
command -v makepkg >/dev/null || { err "缺少 makepkg,请安装 pacman 包管理器"; exit 1; }
command -v bsdtar  >/dev/null || { err "缺少 bsdtar,请安装 libarchive"; exit 1; }
[ -d "$SOURCE_DIR" ]         || { err "源目录不存在: $SOURCE_DIR"; exit 1; }

# 自举:缺构建依赖就 npm install,缺 app.asar 就从白虎阅读_asar/ 重建,
# 缺图标就从 icon.png 缩放生成,缺 electron 运行时二进制就 npm install 自动下载
ensure_node_deps || exit 1
ensure_app_asar || exit 1
ensure_icons || exit 1
ensure_electron_binary || exit 1

mkdir -p "$DIST_DIR"

if [ ! -f "$SOURCE_DIR/electron" ]; then
    hint_electron_missing
    exit 1
fi
[ -x "$SOURCE_DIR/electron" ] || { err "electron 不可执行: chmod +x $SOURCE_DIR/electron"; exit 1; }
[ -f "$SOURCE_DIR/${APP_NAME}.sh" ]    || { err "缺少启动脚本: ${APP_NAME}.sh"; exit 1; }
[ -f "$SOURCE_DIR/${APP_NAME}.desktop" ] || { err "缺少 desktop 文件: ${APP_NAME}.desktop"; exit 1; }

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
PKG_FILE="${PKG_NAME}-${VERSION}-${PKGREL}-${ARCH}.pkg.tar.zst"
PKG_PATH="$DIST_DIR/$PKG_FILE"

# ===== Source 指纹(基于排除规则打包后的元数据) =====
compute_fingerprint() {
    (
        cd "$SOURCE_DIR"
        find . -type f \
            ! -path './.omc/*' \
            ! -name '.omc' \
            ! -name 'electron-v*.zip' \
            ! -name 'default_app.asar.bak' \
            ! -name 'SHASUMS256.txt' \
            -printf '%P\t%s\t%T@\n' 2>/dev/null \
            | LC_ALL=C sort \
            | sha256sum \
            | cut -d' ' -f1
    )
}

current_fp=$(compute_fingerprint)
last_fp=""
last_pkg=""
if [ -f "$STATE_FILE" ]; then
    last_fp=$(sed -n '1p' "$STATE_FILE" 2>/dev/null || true)
    last_pkg=$(sed -n '2p' "$STATE_FILE" 2>/dev/null || true)
fi

# ===== 幂等判断 =====
# 用户显式指定版本号或 --force 时,产物名/语义已变,跳过短路
if [ "$FORCE" -eq 0 ] && [ "$VERSION_EXPLICIT" -eq 0 ] && [ -z "${APP_VERSION:-}" ] \
    && [ "$current_fp" = "$last_fp" ] && [ -n "$last_pkg" ] \
    && [ -f "$DIST_DIR/$last_pkg" ]; then
    log "源未变化 (fingerprint=${current_fp:0:12}…)"
    log "当前产物: $last_pkg"
    log "如需重建: $0 --force"
    exit 0
fi

# ===== 准备构建目录 =====
log "准备构建目录: $BUILDDIR"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"

# ===== 预处理 asar(移除 Google Analytics) =====
# 原应用通过 universal-analytics 模块上报数据到 UA-105718492-3。
# 打包前把 node_modules/universal-analytics stub 化:所有 API 返回空对象,
# 这样 window.visitor.event(...) 调用 noop,网络零请求。
# STAGE 目录名必须是 "electron-linux",这样 tar 内的顶层目录名与 PKGBUILD 期望一致。
STAGE="$BUILDDIR/electron-linux"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$SOURCE_DIR/." "$STAGE/"

if [ -f "$STAGE/resources/app.asar" ]; then
    log "预处理 app.asar: stub 化 universal-analytics"
    ASAR_TMP="$BUILDDIR/asar-tmp"
    rm -rf "$ASAR_TMP"
    mkdir -p "$ASAR_TMP"
    # 使用 ensure_node_deps 已安装的本地 @electron/asar,避免 npx 临时下载与错误吞没
    ASAR="$SCRIPT_DIR/node_modules/.bin/asar"
    "$ASAR" extract "$STAGE/resources/app.asar" "$ASAR_TMP" \
        || { err "asar extract 失败"; exit 1; }

    UA_DIR="$ASAR_TMP/node_modules/universal-analytics"
    if [ -d "$UA_DIR" ]; then
        cat > "$UA_DIR/index.js" <<'STUB'
// 白虎阅读 (Pom Reader) - Google Analytics 已禁用
// 原 universal-analytics 模块已被替换为 stub。所有调用静默 noop,零网络请求。
const noop = function() {};
const chainable = new Proxy({}, {
  get: function() { return noop; }
});
module.exports = function() { return chainable; };
module.exports.event = noop;
module.exports.pageview = noop;
module.exports.set = noop;
module.exports.send = noop;
module.exports.exception = noop;
module.exports.timing = noop;
STUB
    fi

    "$ASAR" pack "$ASAR_TMP" "$STAGE/resources/app.asar" \
        || { err "asar pack 失败"; exit 1; }
    rm -rf "$ASAR_TMP"
fi

# ===== 归档 source =====
log "打包 source → electron-linux.tar.gz"
tar -czf "$BUILDDIR/electron-linux.tar.gz" \
    --exclude='electron-v*.zip' \
    --exclude='default_app.asar.bak' \
    --exclude='SHASUMS256.txt' \
    --exclude='.omc' \
    --exclude='.omc/*' \
    --exclude='*.swp' \
    --exclude='*.bak' \
    --exclude='__pycache__' \
    --exclude='.DS_Store' \
    -C "$BUILDDIR" \
    "electron-linux"

SOURCE_SHA=$(sha256sum "$BUILDDIR/electron-linux.tar.gz" | cut -d' ' -f1)
log "source sha256: ${SOURCE_SHA:0:16}…"

# ===== 生成 PKGBUILD =====
log "生成 PKGBUILD (version=$VERSION, pkgrel=$PKGREL)"
# 从静态模板复制并替换占位符(@XXX@),避免双层 heredoc 嵌套陷阱
TEMPLATE="$SCRIPT_DIR/PKGBUILD.template"
[ -f "$TEMPLATE" ] || { err "缺少模板: $TEMPLATE"; exit 1; }

sed -e "s|@PKG_NAME@|$PKG_NAME|g" \
    -e "s|@APP_NAME@|$APP_NAME|g" \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@PKGREL@|$PKGREL|g" \
    -e "s|@ARCH@|$ARCH|g" \
    -e "s|@SOURCE_SHA@|$SOURCE_SHA|g" \
    "$TEMPLATE" > "$BUILDDIR/PKGBUILD"

# ===== 调用 makepkg =====
log "调用 makepkg..."
MAKEPKG_ARGS=(--nocheck --skippgpcheck --noconfirm --force)
[ "$INSTALL_DEPS" -eq 1 ] && MAKEPKG_ARGS+=(--syncdeps) || MAKEPKG_ARGS+=(--nodeps)
[ "$SIGN_PKG" -eq 1 ]    && MAKEPKG_ARGS+=(--sign)

(
    cd "$BUILDDIR"
    makepkg "${MAKEPKG_ARGS[@]}"
)

# ===== 复制产物 =====
shopt -s nullglob
built=("$BUILDDIR"/*.pkg.tar.*)
shopt -u nullglob

if [ "${#built[@]}" -eq 0 ]; then
    err "makepkg 未生成产物"
    exit 1
fi

log "复制产物 → dist/"
cp -f "${built[@]}" "$DIST_DIR/"

# ===== 校验和 =====
(
    cd "$DIST_DIR"
    for f in *.pkg.tar.*; do
        [[ "$f" == *.sig ]] && continue
        sha256sum "$f" > "$f.sha256"
    done
)

# ===== 状态持久化 =====
{
    printf '%s\n%s\n' "$current_fp" "$PKG_FILE"
} > "$STATE_FILE"

# ===== 清理 build 目录 =====
if [ "$KEEP_BUILD" -eq 0 ]; then
    rm -rf "$BUILDDIR"
else
    log "保留构建目录: $BUILDDIR"
fi

# ===== 清理旧产物 =====
if [ -n "$last_pkg" ] && [ "$last_pkg" != "$PKG_FILE" ] && [ -f "$DIST_DIR/$last_pkg" ]; then
    log "清理旧产物: $last_pkg"
    rm -f "$DIST_DIR/$last_pkg" "$DIST_DIR/$last_pkg.sha256"
fi

# ===== 输出 =====
size=$(du -h "$PKG_PATH" | cut -f1)
sha=$(awk '{print $1}' "$PKG_PATH.sha256")
log "✓ 完成: $PKG_FILE"
log "  体积:    $size"
log "  SHA256:  $sha"
log "  路径:    $DIST_DIR/$PKG_FILE"
log ""
log "安装:    sudo pacman -U \"$DIST_DIR/$PKG_FILE\""
log "启动:    pomreader (或在应用菜单搜 '$APP_NAME')"
log "卸载:    sudo pacman -Rns $PKG_NAME"