# 家庭奖励管理系统 - 进展日志

## [2026-05-29 16:30] 项目启动与开发
- 完成后端 API 开发 (Python HTTP Server，零依赖)
- 完成前端页面开发 (React + HTML)
- API 测试通过: children、transactions、rules、stats、leaderboard
- 发现并修复 import os 缺失导致前端 500 错误
- 创建项目文档结构 (docs/, src/, scripts/)
- 创建 version.json (版本 1.0.0)
- 注意：技术选型偏离项目规范默认值 (.NET → Python)
- [2026-06-28] 新增系统设置页，支持语音文本输入和智能体服务配置。

## [2026-06-28 09:45] .NET 规范整改
- 按项目技术栈规范将实际后端迁移到 `FamilyReward.Api`。
- 后端采用 ASP.NET Core 10 Minimal API + PostgreSQL，端口固定为 `5102`，兼容现有 React 前端接口。
- 已实现孩子、交易、规则、统计、系统配置、智能体服务代理接口。
- 验证通过：`dotnet build FamilyReward.slnx`、`npm run build`、`/health`、`/api/children`、`/api/rules`、`/api/transactions`、`/api/system/config`。

## [2026-06-28 11:48] 线上部署
- 已部署到 `https://happylife.ai.impx.net`。
- 前端由 nginx 托管静态资源，后端由 `family-reward-api.service` 运行 ASP.NET Core API。
- 已为 `happylife.ai.impx.net` 签发并安装正确 HTTPS 证书。
- 验证通过：首页、`/health`、`/api/children`、`/api/rules`。

## [2026-07-13 23:05] 统一登录审计与本地开发修复
- 确认生产登录态只由 `/auth/me` 建立，不信任浏览器持久化用户数据。
- 补充 Vite `/auth` 代理，避免本地开发时认证路径被 SPA fallback 吞掉并形成重载循环。
- 新增 2 个回归测试；前端测试/构建和后端 Release 构建通过。
- 生产陈旧 Cookie 与完整 OAuth 登录/退出验证通过；生产代码未变更，未重复部署。

## [2026-08-02] 主业务链路代码审查
- 修复家庭组选择只在“孩子管理”生效的问题：首页、积分操作、交易记录、统计报表和语音解析现统一携带当前家庭组。
- 新增交易时校验孩子必须属于当前家庭组，避免错误家庭组写入。
- HTTP 删除交易改为复用事务化删除逻辑：删除记录时同步回滚孩子积分、现金或物品余额及累计收支，并限制在当前家庭组内。
- 家庭组切换时清理积分操作的旧选择，以及交易页的旧孩子筛选，避免残留状态误操作。
- 后端 Debug 构建通过（0 警告、0 错误）；前端 4 项测试和生产构建通过。
- `npm run lint` 无法启动：仓库尚未声明 ESLint 依赖和规则文件，已登记为工程化风险。

## [2026-08-08] family-reward-REQ-008 手表 app 版本适配与上架准备
- 验收核对：`watch-app/` 已包含 Android WebView 工程、小天才/小米/华为配置、Web/Android 图标、中文上架文案；线上 watch manifest 和 app-info 已返回 1.0.0 (100) 及三平台元数据。
- 补齐 release 签名接线：四项签名环境变量全部具备才允许生成 release 产物，避免误交未签名 APK/AAB。
- 新增 `watch-app/RELEASE-CHECKLIST.md`，明确三平台账号与准入、签名证书、HarmonyOS 工程边界、真机截图隐私边界、合规资料和真实上架完成证据。
- 扩展 `verify-watch-app.mjs`，校验服务端在线路由实现、儿童功能范围、三平台 child 配置、签名变量及发布清单章节。
- 测试证据：watch 配置校验通过；ASP.NET Core 构建通过（0 警告、0 错误）；生产 `/health` 为 200；生产 `/watch/manifest.json` 和 `/api/watch/app-info` 为 200；无设备 token 的 `/api/watch/score` 为 401 `watch_device_required`。
- 环境边界：本机无 npm、JDK、Gradle、Android SDK，无法在本机生成签名包或执行真机回归；真实上架还需发布主体的平台账号、签名证书、合规资料、目标设备和平台后台操作。
- Atlas 同步阻塞：当前 Codex 会话没有配置任何 MCP server（`codex mcp list` 返回 `No MCP servers configured yet`），无法读取或写回 Atlas；不得据此虚报 Atlas 状态已更新。
