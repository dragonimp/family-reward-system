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
