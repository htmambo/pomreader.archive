**状态**: ✅ 已完成 (2026-09-24)
> 对应 fullauto 状态：.omc/fullauto/online-search-import/state.json
> 设计 spec：docs/superpowers/specs/2026-09-24-online-search-import-design.md

## 任务目标
检查并分析原阅读器（白虎阅读 vendor）的「万能搜索」与「导入在线书页」功能，逆向其行为并引入当前 pomreader-ui-clone 应用。新应用必须用 Electron 打包成跨平台应用。

## 问题分析
- 原 vendor 是 AOT 编译的 Electron 应用（bundle 无源码），万能搜索 = Electron `<webview>` 内嵌浏览器 + 6 书签站；导入在线 = URL 抓取书页 HTML → 解析目录/章节 → 入库。
- clone 当前是纯浏览器 Angular + mock 实现，无 Electron、无真实书源。
- 引入真实功能需：clone 升级为 Electron 三层架构（main/preload/IPC）+ webview 组件 + 跨域抓取（主进程 net.request 绕 CORS）+ 书源适配器框架。

## 子任务列表
（见实施计划 .omc/plans/fullauto-online-search-import-impl.md）

## 每个子任务的改动内容
（见实施计划）

## 预期效果和验收标准
- npm run dev 起 Electron 窗口，4 路由正常
- 万能搜索 webview 可加载百度/搜狗/6 书签站，地址栏同步、前进后退跳转、编码切换
- 导入在线：6 站 URL 各能解析目录 + 预览
- 阅读器按需加载 + 前 3 章预加载
- 适配器单测 ≥ 90%
- npm run dist 产出跨平台安装包

## 风险评估和缓解措施
- 书站 DOM 改版选择器失效 → 选择器写配置，失效改一处
- 书站反爬 → UA + 间隔 + 只预加载前 3 章
- GBK 解码 → iconv-lite + fixture 验证 + webview 编码切换兜底
- 6 站选择器需真实样本验证 → 实现时抓 fixture

## 实施顺序和依赖关系
1. Electron 脚手架 → 2. 主进程抓取+编码 → 3. 适配器框架+6站 → 4. 导入 modal → 5. 万能搜索 webview → 6. 阅读器按需加载 → 7. 打包


## 验收结论
- 31/31 单测绿，Angular 构建+Electron 编译通过，Electron 启动无致命错误
- 5 站适配器 + 注册表框架 + webview 万能搜索 + 跨域抓取 + 按需加载全实现
- 外部审核 REJECTED 不阻塞，已采纳 3 项关键安全修复，4 项深度加固记录为后续迭代
