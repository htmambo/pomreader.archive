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
  - 兼容补丁 ⑤：`index.js` 加 `app.requestSingleInstanceLock()`——dev 版与 pacman 安装版共享 `~/.config/pom-reader-desktop`，双实例会争用 IndexedDB leveldb 锁：后启动的实例写入全部失败（症状：导入解析正常但弹窗不关闭），且并发写覆盖导致丢书（本次事故丢了《赘婿》《诛仙》）
  - 兼容补丁 ⑥：`index.prod.html` 内联脚本接管阅读页方向键滚动——章节切换重建 `.read-screen` DOM 导致滚动容器失焦，原生 ArrowUp/Down 失效；脚本在 `#/read/` 页面对 ArrowUp/Down（±40px）和 PageUp/Down（±0.9 屏）显式 `scrollBy`，其他页面与输入框不受影响
  - 暗色模式配色调整（2026-09-24，参照用户提供的截图）：`DARK_READ_REGION_COLOR #A0A0A0→#666666`、`DARK_READ_REGION_BACKGROUND #323B49→#161819`、`DARK_READ_SCREEN_BACKGROUND #9CA1A6→#161819`（外圈/面板统一背景）。修改了 bundle 默认值（`mO.set` 处，es2015/es5 各一份）+ 通过应用设置界面写入用户 `_pouch_config` 存量配置
  - 全局深色主题（2026-09-24）：`index.prod.html` 注入 `<style>`（`body[data-color-mode="dark"]` 驱动的布局/侧栏/卡片/按钮/弹窗/抽屉/输入框配色，调色板：内容背景 #161819、左侧菜单栏 #0e0f11（层次区分）、浮层 #1b1d1e、边框 #26292b、正文 #666666、书名/标题/高亮 #999999）+ 启动脚本从 `_pouch_config` 的 by-sequence 表（行结构 `{value, _doc_id_rev}`）读取 COLOR_MODE 给 body 打标；bundle `refreshStyle()` 开头插一行 `document.body.setAttribute("data-color-mode",this.colorMode)` 保证切换时同步
  - 纹理背景（2026-09-24）：用户提供的 4 张 50×50 平铺纹理（`images/`）复制进 asar `app/assets/themes/`：`body_dark_bg.png`(#101113)、`body_light_bg.png`(#e2d1a5)、`reader_dark_bg.png`(#181a1b)、`reader_light_bg.png`(#f4eac7)。注入 CSS 按 body/reader × 深浅接线：菜单栏/外圈=body 纹理、框架内/阅读区=reader 纹理；原 `assets/bg.png`/`bg-light.png` 为死资源未引用
  - 「使用默认配置」开关（2026-09-24）：注入 CSS 全部选择器加 `[data-default-theme="1"]` 门控；开关状态存 localStorage `pomUseDefaultTheme`（默认开）；`index.prod.html` 尾部脚本用 MutationObserver 在「阅读效果配置」弹窗「基本配置」分隔线下注入复选框，切换即时生效——勾选=默认纹理/配色，取消=回退到设置里配置的颜色（应用原生外观）
  - 「阅读效果配置」弹窗跟随选中方案（2026-09-24）：脚本监听弹窗内 白天/夜晚 radio（`.ant-radio-button-wrapper-checked` 的 class 变化 + input 事件），实时读取该方案的「字体颜色/界面背景」输入值写到弹窗 `--pom-modal-fg/--pom-modal-bg` CSS 变量；弹窗背景/文字/边框/输入框/按钮全部用变量 + `color-mix()` 派生；激活的 radio 反色显示（前景/背景对调，含 antd `::before` 主色条的覆盖）；示例预览区保持应用原逻辑不动
  - 滚动条主题（2026-09-24）：白天/夜晚两套 `::-webkit-scrollbar` 配色（8px 细条，轨道透明，夜晚 thumb #2e3236、白天 thumb #c9b98f；弹窗内滚动条用 `--pom-modal-fg` 的 color-mix 派生）；`.read-screen` 和书架列表容器（内联 `overflow: scroll`）改为 `overflow: auto`，内容不溢出时不显示滚动条
  - 页头暗色适配（2026-09-24）：书架/万能搜索/免责声明三页共用 nz-page-header，标题 `.ant-page-header-heading-title`（默认 rgba(0,0,0,.85)）→ #999999、副标题/页头内容/extra → #666666；免责声明正文原已被全局规则覆盖无需改

## 已知事故与数据说明（2026-09-24）

- 双实例争用导致《赘婿》《诛仙》从书架丢失；升级前完整备份在 `~/.config/pom-reader-desktop.bak-e9.1.1-20260924/`
- 恢复选项：整目录还原备份（会丢升级后新增的书和进度），或用万能搜索重新导入丢失的书
- 排查方法备忘：`WAYLAND_DEBUG=1 <启动命令> 2>&1 | grep set_app_id` 查 Wayland app_id；IndexedDB 锁冲突在 `--enable-logging` 日志里表现为 `Failed to open LevelDB database ... LOCK`
- ✅ 系统库全套：gtk3 / nss / alsa-lib / libxss / libxtst / xdg-utils / at-spi2-core / libsecret / libnotify
- ✅ 图标提取（icns2png → 6 档 PNG）+ `icon.png` + `白虎阅读.desktop`
- ~~自定义 CSS/JS 注入：page-flip 翻书动画~~ **已移除**（2026-09-24）：触发时机不符合预期（章节切换无路由变化，实际只能挂在菜单跳转上），用户决定放弃该特性；`customizations/` 目录及 `index.prod.html` 注入引用已全部删除
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

DevTools 远程调试：

```bash
~/htdocs/pomreader/electron-linux/白虎阅读.sh --remote-debugging-port=9222
# 然后浏览器访问 chrome://inspect，配置 localhost:9222
```

## 后续改造

- 重打包 asar 工作流：`白虎阅读_asar/` 为源目录，改动后：
  `npx @electron/asar pack 白虎阅读_asar electron-linux/resources/app.asar`
- ✅ **`pack-*` 脚本自举（2026-09-24）**：`npm install` 与 `app.asar` 构建已内嵌到两个脚本启动期；裸仓库首次运行会自动安装 `@electron/asar` 并从 `白虎阅读_asar/` 重建 `electron-linux/resources/app.asar`，之后幂等跳过。`pack-pacman.sh` 内的 `npx --yes @electron/asar ... 2>/dev/null` 已替换为本地 `node_modules/.bin/asar` + 显式错误处理（不再吞错）。
- ✅ **Electron 运行时自动下载（2026-09-24）**：新增 `ensure_electron_binary()`，缺 `electron-linux/electron` 时调用 `npm install electron@<ver>` + `node install.js` 触发懒下载（electron@44.4.5+ 移除了 postinstall）。默认版本 44.4.5，`--electron-version` / `ELECTRON_VERSION` 双通道覆盖。镜像可通过 `ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/` 切换。
- ✅ **多档应用图标自动生成（2026-09-24）**：新增 `ensure_icons()`，从 `icon.png` (1024×1024 RGBA) 用 ImageMagick `magick` 缩放生成 16/32/128/256/512/1024 六档 PNG（PKGBUILD 安装到 `/usr/share/icons/hicolor/<size>x<size>/apps/pomreader.png`）。修复打包安装后 dock / 应用列表 / Alt-Tab 都没图标的 bug——根因是多档图标不入仓、PKGBUILD `if [ -f ] then install; else 跳过` 走跳过分支。

## 备注

- `electron-v9.1.1-linux-x64.zip`（70 MB）保留在目录中作为旧运行时回滚备份，可随时删除节省空间
- asar 源目录 `白虎阅读_asar/` 与打包产物保持同步（含上述 6 个兼容补丁），改动后重打包：
  `npx @electron/asar pack 白虎阅读_asar electron-linux/resources/app.asar`
- 原 macOS 启动脚本里的 `Cmd+Q` / `Cmd+W` 等加速键在 Linux 上由 Electron 自动降级为 `Ctrl+Q` 等
- 启动器使用 `$(dirname "$0")` 相对路径，移动目录无需修改启动脚本