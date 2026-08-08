# 家加分 - 任务分解

| 任务 ID | 任务名称 | 优先级 | 依赖 | 状态 | 说明 |
|---------|---------|--------|------|------|------|
| T01 | 后端 API 开发 | P0 | 无 | ✅ 完成 | ASP.NET Core 10 + PostgreSQL |
| T02 | 前端页面开发 | P0 | T01 | ✅ 完成 | React + TypeScript + Tailwind CSS |
| T03 | API 联调测试 | P0 | T01, T02 | ✅ 完成 | health、children、rules、transactions、system config 已验证 |
| T04 | 部署到 happylife.ai.impx.net | P0 | T03 | ✅ 完成 | 已上线 https://happylife.ai.impx.net |
| T05 | 系统设置与语音配置开发 | P1 | T02 | ✅ 完成 | 新增系统设置、语音输入、智能体服务入口 |
| T06 | 智能体服务联调 | P1 | T05 | ✅ 完成 | 新增 `/api/system/config` 与 `/api/agent/invoke` |
| T07 | 代码审查 | P1 | T06 | ✅ 完成 | 修复家庭组切换未贯穿业务页面、跨家庭组交易写入及删除交易未回滚余额问题 |
| T08 | .NET 规范整改 | P0 | T01 | ✅ 完成 | 已将实际后端迁移到 FamilyReward.Api |
| family-reward-TASK-008 | 处理 REQ-016 手表查询界面适配 | P1 | 手表 H5 | ✅ 完成 | 动态视口/安全区表盘尺寸、无滚动面板、旋转和可视视口变化时主动重算 |
