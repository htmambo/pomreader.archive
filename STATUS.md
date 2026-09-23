# Pom Reader Linux 重打包 — 状态

**项目**: macOS DMG → Manjaro KDE Wayland Linux 可运行版本
**当前路径**: `~/htdocs/pomreader/`
**总占用**: 640 MB

## 已完成

- ✅ 原 DMG 拆解（`7z` 提取 HFS+ → `白虎阅读_extracted/`）
- ✅ app.asar 拆包与重打包（`@electron/asar`）
- ✅ Electron 9.1.1 Linux x64 下载 / 解压 / SHA256 校验
- ✅ **Electron 9.1.1 → 44.4.5 升级**（2026-09-24，Chromium 152 / Node 24）
  - 运行时整体替换，SHA256 校验通过；旧 9.1.1 zip 保留可回滚
  - 兼容补丁 ①：`index.js` 加 `contextIsolation: false`（Electron 12+ 默认 true 会屏蔽渲染端 `require`，否则 `shell.openExternal` 失效）
  - 兼容补丁 ②：`index.prod.html` 在 bundle 前注入 `var global = globalThis;`（2020 年 webpack 4 bundle 依赖 Node `global`，否则白屏）
  - 兼容补丁 ③：webview 弹窗跳转——Angular 模板常量补 `allowpopups` 属性（`main-es2015/es5` 各 1 处），`index.js` 用 `setWindowOpenHandler` 复刻已移除的 `new-window` 页内跳转行为
  - 用户数据（PouchDB IndexedDB、阅读进度）已验证自动迁移；旧数据备份于 `~/.config/pom-reader-desktop.bak-e9.1.1-20260924`
  - 分发只保留 pacman 包（仅 Manjaro 使用）；tar.gz 脚本保留备用
  - 兼容补丁 ④：`index.js` 加 `app.setDesktopName('pomreader')`——Electron 44 默认原生 Wayland，KDE 用窗口 app_id 匹配 .desktop 文件取图标和名称；原 app_id 是包名 `pom-reader-desktop`，匹配不到 `pomreader.desktop`，导致任务栏显示 Wayland 通用黄 W 图标、Alt-Tab 显示 "electron"
- ✅ 系统库全套：gtk3 / nss / alsa-lib / libxss / libxtst / xdg-utils / at-spi2-core / libsecret / libnotify
- ✅ 图标提取（icns2png → 6 档 PNG）+ `icon.png` + `白虎阅读.desktop`
- ✅ 自定义 CSS/JS 注入：`customizations/page-flip.{css,js}`（3D 翻书动画，仅章节切换触发）
- ✅ `appmenu-gtk-module` 安装（消除启动警告）
- ✅ 路径迁移：原 `~/下载/` → `~/htdocs/pomreader/`（已 sed 更新 `.desktop` 硬编码路径）

## 待观察

- ⏳ **Fontconfig warning** `48-guessfamily.conf` 的 `xsi:nil` 属性 + monospace/serif/emoji 等常量报错
  - 影响范围：仅字体配置阶段警告，**不阻塞功能**
  - 判断标准：观察几天后若中文/西文显示出现方块或字体错乱，则修复（找到肇事包，正常 conf 替换）
  - 观察起始日：2026-09-24

## 启动

```bash
~/htdocs/pomreader/electron-linux/白虎阅读.sh
```

KDE 应用菜单安装（可选）：

```bash
cp ~/htdocs/pomreader/electron-linux/白虎阅读.desktop ~/.local/share/applications/
update-desktop-database ~/.local/share/applications/
```

## 打包分发

两个独立脚本，互不依赖：

### `pack-linux.sh` — tar.gz 归档

```bash
~/htdocs/pomreader/pack-linux.sh                  # 默认配置，源未变则跳过
~/htdocs/pomreader/pack-linux.sh 1.0.7            # 指定版本号
~/htops/pomreader/pack-linux.sh --force           # 强制重建
```

产物：`dist/白虎阅读-${VERSION}-linux-x64-${TIMESTAMP}.tar.gz`（+ `.sha256`）

### `pack-pacman.sh` — Arch pacman 包

```bash
~/htdocs/pomreader/pack-pacman.sh                 # 默认配置
~/htdocs/pomreader/pack-pacman.sh 1.0.7           # 指定版本
~/htdocs/pomreader/pack-pacman.sh --pkgrel 2      # 指定 pkgrel
```

产物：`dist/pomreader-${VERSION}-${PKGREL}-x86_64.pkg.tar.zst`（+ `.sha256`）

安装 / 卸载：

```bash
sudo pacman -U ~/htdocs/pomreader/dist/pomreader-1.0.6-1-x86_64.pkg.tar.zst
sudo pacman -Rns pomreader   # 卸载
```

两个脚本都满足：

- **幂等**：源指纹未变则跳过（`.build_state` 记录）
- **自动版本号**：从 `白虎阅读.desktop` 提取 → `$APP_VERSION` → 命令行参数 → 默认
- **历史归档**：旧版本自动清理（`--keep` 可调保留数）

## 调试入口

## 调试入口

应用启动后控制台执行：

```js
window.__pomFlip()   // 手动触发一次翻书动画（无路由变化时验证动画）
```

DevTools 远程调试：

```bash
~/htdocs/pomreader/electron-linux/白虎阅读.sh --remote-debugging-port=9222
# 然后浏览器访问 chrome://inspect，配置 localhost:9222
```

## 后续改造

- 重打包 asar 工作流：`cd ~/htdocs/pomreader/electron-linux && npx @electron/asar pack /tmp/pom-frontend resources/app.asar`
- 自定义 CSS/JS 修改后重打包参考：见 `customizations/` 下文件注释

## 备注

- `electron-v9.1.1-linux-x64.zip`（70 MB）保留在目录中作为旧运行时回滚备份，可随时删除节省空间
- asar 源目录 `白虎阅读_asar/` 与打包产物保持同步（含上述 3 个兼容补丁），改动后重打包：
  `npx @electron/asar pack 白虎阅读_asar electron-linux/resources/app.asar`
- 原 macOS 启动脚本里的 `Cmd+Q` / `Cmd+W` 等加速键在 Linux 上由 Electron 自动降级为 `Ctrl+Q` 等
- 启动器使用 `$(dirname "$0")` 相对路径，移动目录无需修改启动脚本