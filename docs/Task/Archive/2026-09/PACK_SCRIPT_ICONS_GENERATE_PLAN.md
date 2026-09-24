# pack-* 脚本自动生成多档应用图标

**状态**: ✅ Completed (completion time: 2026-09-24)
**创建人**: hoping
**任务类型**: 打包产物缺失修复（图标）

---

## 1. 背景

用户反馈：

> 打包后安装的应用在应用列表里没有图标。应该是压根就没有图标。dock里没有，切换窗口时也没有。

### 1.1 根因

PKGBUILD.template 期望 `白虎阅读_${size}x${size}x32.png`（16/32/128/256/512/1024）六档图标：

```bash
for size in 16 32 128 256 512 1024; do
    local src="${_pkgname}_${size}x${size}x32.png"
    if [ -f "$src" ]; then
        install -Dm644 "$src" \
            "$pkgdir/usr/share/icons/hicolor/${size}x${size}/apps/pomreader.png"
    else
        echo "    警告:跳过缺失的图标文件: $src"
    fi
done
```

但：

- `.gitignore` 明确排除 `electron-linux/白虎阅读_*x*.png`（多档图标不入仓）
- 打包脚本从未生成这些文件
- PKGBUILD 的 `if [ -f ... ] then ... else 跳过` 走跳过分支
- 结果：`/usr/share/icons/hicolor/<size>x<size>/apps/pomreader.png` 一张都没装

而 `.desktop` 已正确指向 `Icon=pomreader` + `StartupWMClass=pomrunner`，KDE 找不到对应图标 → dock / 应用列表 / Alt-Tab 全没图标。

### 1.2 现状

- `electron-linux/icon.png` 存在（1024×1024 RGBA，868 KB，从原 macOS .icns 提取）
- 系统已装 `magick`（ImageMagick 7）
- `icns2png` 不在系统，但不需要——Lanczos 重采样质量足够

---

## 2. 方案

新增 `ensure_icons()` 函数，从 `icon.png` 缩放生成 6 档图标：

```bash
ensure_icons() {
    local icon_source="$SOURCE_DIR/icon.png"
    local magick_cmd=""
    
    [ -f "$icon_source" ] || { err "缺少源图标: $icon_source"; return 1; }
    
    # 检测缺失的尺寸
    local missing=()
    for size in 16 32 128 256 512 1024; do
        [ ! -f "$SOURCE_DIR/${APP_NAME}_${size}x${size}x32.png" ] && missing+=("$size")
    done
    [ "${#missing[@]}" -eq 0 ] && return 0
    
    # 选 magick 或 convert
    if command -v magick >/dev/null 2>&1; then
        magick_cmd="magick"
    elif command -v convert >/dev/null 2>&1; then
        magick_cmd="convert"
    else
        err "需要 ImageMagick (magick 或 convert) 生成缺失图标"
        return 1
    fi
    
    log "从 icon.png 生成图标: ${missing[*]}"
    for size in "${missing[@]}"; do
        "$magick_cmd" "$icon_source" -resize "${size}x${size}" \
            "$SOURCE_DIR/${APP_NAME}_${size}x${size}x32.png" \
            || { err "生成图标失败 ($size)"; return 1; }
    done
}
```

调用顺序（pack-linux.sh / pack-pacman.sh）：

```
ensure_node_deps      # npm install @electron/asar
ensure_app_asar       # asar pack ← 白虎阅读_asar
ensure_icons          # magick resize ← icon.png          ← NEW
ensure_electron_binary # npm install electron + node install.js
```

---

## 3. 实测验收

| # | 验收项 | 实测 |
|---|---|---|
| 1 | 6 档 PNG 全部生成 | ✅ `16x16x32` 1.3 KB / `32x32x32` 3.2 KB / `128x128x32` 27 KB / `256x256x32` 81 KB / `512x512x32` 257 KB / `1024x1024x32` 902 KB |
| 2 | tarball 包含 6 档 PNG | ✅ `tar -tzf ... \| grep x*x*.png` 返回 6 行 |
| 3 | 幂等性（已有图标则跳过） | ✅ 第二次运行无"从 icon.png 生成图标"日志 |
| 4 | 源图标缺失时报错 | ✅ `err "缺少源图标: $SOURCE_DIR/icon.png"` + `return 1` |
| 5 | ImageMagick 缺失时报错 | ✅ `err "需要 ImageMagick..."` + 安装提示 |
| 6 | 用户预放置图标保留 | ✅ 检测函数只检查文件存在性,不重新生成 |
| 7 | PKGBUILD 安装后 `/usr/share/icons/hicolor/<size>x<size>/apps/pomreader.png` 有图标 | ⏳ 待用户重新打包安装后验证（脚本侧保证已就位） |

## 4. 风险

| 风险 | 缓解 |
|---|---|
| `magick` 重采样损失 vs 原 .icns 抽取 | icon.png 1024×1024 本身就是从 .icns 高质量抽出来的，Lanczos 重采样对应用图标足够；用户后续若找到原 .icns 可改用 icns2png 替换 |
| 中文文件名跨平台 tar 问题 | 已在 tarball 中验证，6 档 PNG 全部正常打包（linux tar 默认 UTF-8） |
| macOS 用户的 ImageMagick | `magick` (ImageMagick 7) 是跨平台的，Mac `brew install imagemagick` 即可 |

## 5. 后续

- 用户找到原 .icns 后：可加 `ensure_icons_from_icns()` 函数从 .icns 抽取（更高保真），覆盖 `ensure_icons` 的生成结果
- 或直接预放置 6 档 PNG 让 `ensure_icons` 跳过
