# 任务索引

## 进行中

- _(无)_

## 已完成 (Archive)

### 2026-09

- ✅ [pack-* 脚本依赖安装修复](Archive/2026-09/PACK_SCRIPT_DEPS_INSTALL_PLAN.md) — Completed 2026-09-24
  - `package.json` 新增 `@electron/asar` devDependency
  - `pack-linux.sh` / `pack-pacman.sh` 启动期自动 `npm install` + 从 `白虎阅读_asar/` 构建 `app.asar`
  - `pack-pacman.sh` 替换 `npx --yes @electron/asar ... 2>/dev/null` 为本地 `node_modules/.bin/asar` + 显式错误

- ✅ [pack-* 脚本自动下载 Electron 二进制](Archive/2026-09/PACK_SCRIPT_ELECTRON_DOWNLOAD_PLAN.md) — Completed 2026-09-24
  - 新增 `ensure_electron_binary()`,缺 `electron` 时 `npm install electron@<ver>` + `node install.js` 触发懒下载
  - 关键修复:electron@44.4.5+ 移除了 postinstall script,改用 bin `install-electron` 主动调用
  - CLI `--electron-version VER` 与 env `ELECTRON_VERSION` 双通道覆盖
  - `cp -a dist/. SOURCE_DIR/` 安全(无文件名冲突)

- ✅ [pack-* 脚本自动生成多档应用图标](Archive/2026-09/PACK_SCRIPT_ICONS_GENERATE_PLAN.md) — Completed 2026-09-24
  - 新增 `ensure_icons()`,从 `electron-linux/icon.png` (1024×1024 RGBA) 用 ImageMagick `magick` 缩放生成 6 档 PNG
  - 修复打包安装后 dock / 应用列表 / 窗口切换器都没图标的 bug(根因:多档图标不入仓,PKGBUILD 静默跳过)
  - tarball 验证含全部 6 档 PNG;幂等性 ✓
