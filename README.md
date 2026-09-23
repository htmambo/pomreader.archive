# pomreader

把 macOS 上 `白虎阅读`（pom-reader-desktop 1.0.6）的 Electron DMG 重打包成 Manjaro KDE Wayland 可直接运行的 Linux 版本，附带可独立分发的 tar.gz 与 pacman 包。

## 仓库结构

| 路径 | 作用 |
|---|---|
| `白虎阅读_asar/` | 解包并打过兼容性补丁的 asar 工作区（`index.js`、`app/`）。再次重打包用 `npx @electron/asar pack`。 |
| `electron-linux/` | 已放置 Electron 44.4.5 运行时与启动器；仅入仓入口脚本、`.desktop`、图标、自定义扩展与版本号，二进制不入仓。 |
| `electron-linux/customizations/` | 章节切换 3D 翻书动画（CSS + JS Hook）。 |
| `pack-linux.sh` / `pack-pacman.sh` | 幂等的打包脚本（tar.gz / pacman 双轨）。带 SHA256 与历史归档轮转。 |
| `PKGBUILD.template` | pacman 打包模板。 |
| `STATUS.md` | 当前进度、兼容性补丁清单、待观察事项。 |

> `白虎阅读.dmg`、`白虎阅读_extracted/`、Electron 运行时二进制定位为外部输入，不入仓；`dist/`、`node_modules/`、`.omc/` 与 Chromium 私有资源同样排除。

## 启动

```bash
~/htdocs/pomreader/electron-linux/白虎阅读.sh
```

注册到 KDE 应用菜单（可选）：

```bash
cp ~/htdocs/pomreader/electron-linux/白虎阅读.desktop ~/.local/share/applications/
update-desktop-database ~/.local/share/applications/
```

## 打包

```bash
./pack-linux.sh                 # tar.gz
./pack-pacman.sh                # pacman 包
```

两个脚本均按源指纹判定幂等；`--force` 强制重建，`--keep N` 调整历史归档保留数。

## 兼容性补丁（已合入 asar）

| # | 部位 | 用途 |
|---|---|---|
| ① | `index.js` `contextIsolation: false` | Electron 12+ 默认 true，渲染端 `require` 失效 |
| ② | `app/index.prod.html` 注入 `var global = globalThis;` | 旧 webpack 4 bundle 依赖 Node `global`，否则白屏 |
| ③ | bundle 模板的 webview 补 `allowpopups` + `setWindowOpenHandler` | 复刻 Electron ≥ 22 移除的 `new-window` 页内跳转 |
| ④ | `app.setDesktopName('pomreader')` | 原生 Wayland 下 KDE 用 app_id 匹配 `.desktop` 取图标与名称 |
| ⑤ | `app.requestSingleInstanceLock()` + `second-instance` | dev / pacman 共享 `~/.config/pom-reader-desktop`，防止 IndexedDB 写入失败 |

## 调试

```bash
~/htdocs/pomreader/electron-linux/白虎阅读.sh --remote-debugging-port=9222
# 浏览器访问 chrome://inspect，添加 localhost:9222
```

应用内控制台：`window.__pomFlip()` 手动触发一次翻书动画。
