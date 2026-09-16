# 仓库指南

## 项目结构与模块组织

本仓库是一个后端/全栈混合项目，首选后端为 ASP.NET Core。

- `FamilyReward.Api/`：主后端，C# minimal API，入口为 `Program.cs`，包含数据库访问和 HTTP 路由。
- `frontend/src/`：React 前端源码。
- `frontend/src/pages/`：路由页面，包括 Dashboard、Children、Reward、Transactions、Rules、Stats。
- `frontend/src/components/`：共享 UI 组件。
- `frontend/src/services/`：API 客户端和类型化接口封装。
- `frontend/src/types/`：共享 TypeScript 类型。
- `frontend/static`、`frontend/public`、`frontend/dist/`：静态资源和构建产物。
- `server/` 和 `backend/`：历史 Python 实现，仅在明确迁移或对比行为时使用。
- `docs/`：项目笔记、状态和任务记录。
- `scripts/`：部署和构建辅助脚本。

## 构建、测试与开发命令

- `dotnet run --project FamilyReward.Api/FamilyReward.Api.csproj`：启动 API，默认地址 `http://localhost:5102`，也可用 `FAMILY_REWARD_API_URLS` 覆盖。
- `cd frontend && npm run dev`：启动 Vite 开发服务，默认 `http://localhost:3000`。
- `cd frontend && npm run build`：类型检查并生成生产资源。
- `cd frontend && npm run lint`：运行严格模式 ESLint。
- `cd frontend && npm run preview`：本地预览已构建前端。
- `cd server && python3 app.py` 或 `cd backend && python3 app.py`：仅用于对比历史 Python 后端。

## 编码风格与命名约定

- C# 使用 4 空格缩进、nullable-enabled 风格；I/O 方法显式使用 async，接口和动作命名要清晰。
- TypeScript/React 使用 2 空格缩进；组件使用 `PascalCase`，变量和函数使用 `camelCase`，事件处理函数命名要表达意图。
- API 路径集中维护在 `frontend/src/services/*.ts`，并复用 `frontend/src/types` 中的共享类型。
- UI 变更前运行 `npm run lint`。

## 测试要求

当前仓库还没有配置独立测试套件。

- 前端验证：修改后运行 lint，并手工检查相关路由。
- 后端验证：使用健康检查和 API 冒烟检查（`/health`、`/api/children`、`/api/transactions`）。
- 后续测试依赖稳定后，优先在对应项目下补充自动化测试。

## 提交与 Pull Request 规范

当前 git 历史基本只有初始提交（`Initial commit: HappyLife Family Reward System`），暂未形成严格提交约定。

- 使用聚焦提交，摘要简短；可以使用 `feat`、`fix`、`chore` 等清晰前缀。
- PR 应包含摘要、变更文件、已运行的验证命令；涉及界面变化时附前后截图。

## 安全与配置注意事项

- 数据库凭据通过环境变量配置，例如 PostgreSQL 连接信息。
- 不要提交密钥、`.env` 文件或生成的运行期文件（`bin/`、`obj/`、`node_modules/`）。
- 保持 CORS 设置与本地和部署 URL 一致。
