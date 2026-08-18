# 家加分
家加分 — 管理孩子积分、现金和物品奖励

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

## 手表 app

手表端 H5 入口为 `https://happylife.ai.impx.net/watch`。手表不再走统一账号登录，由家长在 Web 端家庭管理里生成儿童认证码，手表端输入认证码完成设备绑定，后续用设备 token 查询积分和提交积分申请。

仓库已提供 `watch-app/` 上架准备包，包含：

- Android WebView 手表壳工程
- 小天才、小米、华为平台配置
- 上架文案、权限说明和截图清单
- 不依赖 Android SDK 的配置校验脚本

校验：

```bash
node watch-app/scripts/verify-watch-app.mjs
```

真正提交商店仍需要对应平台开发者账号、签名证书和真机截图。
