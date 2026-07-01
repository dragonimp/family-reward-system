# family-reward-system
家庭奖励管理系统 — 管理孩子积分现金物品奖励

## 技术栈
- 后端：ASP.NET Core 10 Minimal API
- 数据库：PostgreSQL
- 前端：React 18 + TypeScript + Tailwind CSS

## 本地运行
1. 确认 PostgreSQL 已启动，并存在 `family_rewards` 数据库。
2. 启动后端：
   ```bash
   dotnet run --project FamilyReward.Api/FamilyReward.Api.csproj
   ```
3. 启动前端：
   ```bash
   cd frontend
   npm run dev
   ```

默认地址：
- 前端：`http://localhost:3000`
- 后端：`http://localhost:5102`
- 健康检查：`http://localhost:5102/health`
