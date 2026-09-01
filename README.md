# 家加分
家加分 — 管理孩子积分、现金和物品奖励

当前产品基线：**V0.8**（2026-09-02）。版本范围和后续演进边界见 [V0.8 版本记录](docs/releases/V0.8.md)。

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

## 小天才真机测试申请

已登录且列入允许名单的发布操作人可从“管理 > 真机测试申请”打开专用页面。页面会读取当前正式 APK、测试报告和发布元数据，逐项核对 SHA-256，预览收件人、主题、正文和附件，并在二次确认后通过用户中心受限邮箱凭证发送到小天才开放平台。每次发送的 Message-ID、线程关系、附件哈希和结果保存在 PostgreSQL，发送失败不会伪装成成功。

生产凭证只保存在 `/etc/agent-secrets/xiaotiancai-email.env`；仓库中的 `FamilyReward.Api/xiaotiancai-email.env.example` 仅列出变量名。安全授权只需“读取应用授权凭证”和“读取应用授权凭证密钥”，不得把授权码或邮箱授权码写入仓库、前端配置或发送记录。
