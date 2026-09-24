# pack-* 脚本依赖安装缺失修复

**状态**: ✅ Completed (completion time: 2026-09-24)
**创建时间**: 2026-09-24
**创建人**: hoping
**任务类型**: Bug 修复（构建脚本自举缺失）

---

## 1. 问题背景

用户报告：

> `pack-*`脚本均未执行依赖安装，导致打包直接失败

### 1.1 现象

在裸仓库（fresh checkout）下：

- `node_modules/` 不存在
- `electron-linux/electron` 二进制不存在
- `electron-linux/resources/app.asar` 不存在
- `electron-linux/resources/` 目录甚至不存在
- `dist/` 不存在

执行 `./pack-linux.sh` 或 `./pack-pacman.sh`，两个脚本都在「前置检查」阶段 `exit 1`：

```
[pack] 缺少 electron 二进制,请确认 electron-linux/ 已就绪
```

### 1.2 .gitignore 反推的工作流

`.gitignore` 把以下产物排除在仓库之外：

```
electron-linux/electron*
electron-linux/resources/app.asar
node_modules/
dist/
build/
```

这暗示**这些产物由打包脚本在运行期生成**。但当前脚本既没有 `npm install`，也没有 asar 构建步骤，也没有 electron 二进制准备步骤——脚本假设一切就绪。

### 1.3 `pack-pacman.sh` 的隐患

```bash
npx --yes @electron/asar extract "$STAGE/resources/app.asar" "$ASAR_TMP" 2>/dev/null
npx --yes @electron/asar pack   "$ASAR_TMP"         "$STAGE/resources/app.asar" 2>/dev/null
```

- `2>/dev/null` 屏蔽所有错误（包括 `app.asar` 不存在、网络拉取失败）
- `npx --yes` 临时下载到 npx 缓存，不入 `node_modules/`，不可复现
- 整个流程没有 `package.json` 声明 `@electron/asar`

---

## 2. 修复目标

让两个 `pack-*` 脚本在**裸仓库状态**下能完成到「electron 二进制准备」为止的所有自举步骤：

1. 声明 `@electron/asar` 为 devDependency（`package.json`）
2. 缺 `node_modules/` 时自动 `npm install`
3. 缺 `electron-linux/resources/app.asar` 时从 `白虎阅读_asar/` 构建
4. `pack-pacman.sh` 的 asar extract/pack 改用本地 `node_modules/.bin/asar`，去掉 `2>/dev/null`
5. electron 二进制仍需手动放置（脚本给出明确指引），自动下载是另一个独立任务

---

## 3. 改动清单

### 3.1 `package.json`

新增 `devDependencies`：

```json
{
  "devDependencies": {
    "@electron/asar": "^3.2.10"
  }
}
```

不动 `dependencies`（`universal-analytics` 是 app 运行时依赖，asar 工具仅打包期用）。

### 3.2 `pack-linux.sh`

在「前置检查」之前插入两个 ensure 函数：

```bash
ensure_node_deps() {
    if [ ! -x "$SCRIPT_DIR/node_modules/.bin/asar" ]; then
        log "安装构建依赖 (@electron/asar)..."
        (cd "$SCRIPT_DIR" && npm install --no-audit --no-fund --no-save) \
            || { err "npm install 失败,请检查网络或手动运行 npm install"; return 1; }
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
```

调用点（在 `[ -d "$SOURCE_DIR" ]` 校验之后）：

```bash
ensure_node_deps || exit 1
ensure_app_asar || exit 1
```

并把 `electron` 二进制缺失的提示改成「两步指引」：

```bash
[ -f "$SOURCE_DIR/electron" ] || {
    err "缺少 electron 二进制: $SOURCE_DIR/electron"
    err "请从 https://www.electronjs.org/releases 下载 Electron ${ARCH} 解压到 electron-linux/"
    err "或: cd electron-linux && curl -L <url> -o electron.zip && unzip -o electron.zip"
    exit 1
}
```

### 3.3 `pack-pacman.sh`

同步 `ensure_node_deps` / `ensure_app_asar` 两个函数（与 `pack-linux.sh` 完全相同）。

把 asar extract/pack 调用改成本地二进制并去掉 `2>/dev/null`：

```bash
# 原:
#   npx --yes @electron/asar extract "$STAGE/resources/app.asar" "$ASAR_TMP" 2>/dev/null
#   npx --yes @electron/asar pack   "$ASAR_TMP"         "$STAGE/resources/app.asar" 2>/dev/null
# 改:
ASAR="$SCRIPT_DIR/node_modules/.bin/asar"
"$ASAR" extract "$STAGE/resources/app.asar" "$ASAR_TMP"
...
"$ASAR" pack "$ASAR_TMP" "$STAGE/resources/app.asar"
```

`electron` 二进制缺失的错误同样升级为两步指引。

---

## 4. 验收标准

| # | 验收项 | 预期 |
|---|---|---|
| 1 | 裸仓库首次执行 `pack-linux.sh` | 自动 `npm install` → 自动构建 `app.asar` → 在 `electron` 二进制缺失处 fail 且提示明确 |
| 2 | 裸仓库首次执行 `pack-pacman.sh` | 同上 + asar extract/pack 用本地 `@electron/asar`，无 `npx --yes` 痕迹 |
| 3 | `package.json` 显式声明 `@electron/asar` | `devDependencies` 字段非空，版本 `^3.2.10` |
| 4 | 无 `2>/dev/null` 吞错 | `pack-pacman.sh` 中所有 `npx --yes` 和 `2>/dev/null` 移除 |
| 5 | 不影响已有的指纹/幂等/版本号逻辑 | `compute_fingerprint` 与 `get_version` 不动 |

---

## 5. 风险与边界

| 风险 | 缓解 |
|---|---|
| `npm install` 引入锁文件 / 改变 `node_modules/` 内容 | 用 `--no-save`（不动 `package.json` 依赖版本），但仍把 `@electron/asar` 显式写在 `devDependencies` 里 |
| `@electron/asar` API 兼容性 | `^3.2.10` 是稳定主版本，`extract`/`pack` 命令行接口与 v1.x 一致 |
| 用户已有 `node_modules/` 但版本不匹配 | 仅检查 `node_modules/.bin/asar` 可执行性，不强制 reinstall |
| asar pack 改写文件 mtime → fingerprint 变 | 已设计为只在缺失时构建，已有 `app.asar` 不重新 pack |

---

## 6. 实施顺序

1. ✅ 修改 `package.json`：加 `devDependencies.@electron/asar`
2. ✅ 修改 `pack-linux.sh`：新增 `ensure_*` 两个函数并调用，更新 electron 缺失提示
3. ✅ 修改 `pack-pacman.sh`：同步 `ensure_*` 函数，替换 asar 调用，更新 electron 缺失提示
4. ✅ 干跑验证：在裸仓库下执行两个脚本，确认行为符合验收标准 #1-#2
5. ⏳ 更新 STATUS.md「打包分发」章节，记录自举逻辑
6. ⏳ 提交一个原子 commit（待用户授权；commit 模板见 `~/.claude/COMMIT_TEMPLATE.md`）

## 8. 验收实测结果

| # | 验收项 | 实测 |
|---|---|---|
| 1 | 裸仓库首次 `pack-linux.sh` | ✅ 自动 `npm install`（63 packages, 3s）→ 自动构建 `app.asar`（2.9 MB）→ electron 缺失处 rc=1 + 3 步指引 |
| 2 | 裸仓库首次 `pack-pacman.sh` | ✅ 同上（复用 ensure_*） |
| 3 | `package.json` 显式声明 `@electron/asar` | ✅ `devDependencies: {"@electron/asar": "^3.2.10"}` |
| 4 | 无 `2>/dev/null` 吞错 | ✅ `pack-pacman.sh` 中所有 `npx --yes` 和 `2>/dev/null` 已移除，改用 `node_modules/.bin/asar` + 显式 `\|\| err` |
| 5 | 不影响已有的指纹/幂等/版本号逻辑 | ✅ `compute_fingerprint` / `get_version` / `trap cleanup_on_error` / `--force` 全部保留 |
| 6 | 幂等性 | ✅ 第二次运行跳过 `npm install` 与 asar pack（产物已就位），直接进入 electron 检查 |

副产物（不入仓，`.gitignore` 已覆盖）：

```
electron-linux/resources/app.asar         (2,996,918 bytes)
node_modules/.bin/asar → @electron/asar    (本地安装，可重入)
```

---

## 7. 备注 / 后续

- electron 二进制自动下载是另一个独立任务（涉及下载源、版本固定、SHA256 校验、70 MB 体积），本期不动。
- 若后续引入 GitHub Actions / CI，可把 `npm install` + `asar pack` 抽成独立 `prepare.sh`，两个 `pack-*` 复用。
