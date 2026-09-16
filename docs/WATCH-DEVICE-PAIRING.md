# 手表显示设备码，由家长确认绑定

## 使用方式

1. 未绑定的 Apple Watch / H5 手表页获取 8 位设备码和二维码，10 分钟有效。
2. 家长用手机相机扫码进入家庭管理，设备码自动填入；也可以直接在家庭管理或孩子的手表绑定窗口输入设备码。
3. 家长选择自己名下的孩子并点击确认；手表在前台每 5 秒查询结果，批准后自动进入儿童首页。
4. 已有有效设备的孩子需要先由家长解绑旧设备；原有儿童认证码接口保留兼容旧客户端。

## 权限及恢复

- 新确认接口使用 AgentIdentity SDK 验证的用户身份，从服务端查询家长资料，不信任客户端的用户/家长身份头。再次检查孩子所属账号。
- 二维码只包含短期设备码及本应用家长页面地址，不含设备令牌或孩子资料。
- 私有 256 位随机设备令牌通过 HTTPS 下发。原生手表先把待绑定会话保存在钥匙串，再显示设备码；批准后改存正式令牌。
- H5 在原有同源本地存储内保存待绑定会话。页面关闭、网络错误不会清除已保存的设备凭据；只有 401 才重新进入绑定。
- 短期会话保存在服务内存中，最多 1024 条。服务重启会使未确认的码失效；已确认绑定继续保存在原有设备表，持有已保存令牌的手表可恢复批准结果。
- 同一会话串行确认；相同家长/孩子重试幂等，不同家长/孩子重放拒绝。数据库已有唯一索引继续限制每个孩子只有一台有效设备。
- 创建、轮询、确认接口分别限流；响应禁止缓存。本次无需数据库迁移或生产数据修正。

## 已运行验证（2026-09-16，北京时间）

- 前端 lint、TypeScript/Vite 构建；H5 内联脚本语法、发布包检查及 `node watch-app/scripts/test-h5-pairing.mjs` 行为测试通过。H5 首次离线加载会保留设备绑定并显示“重新连接”。
- 后端 Debug 构建、Linux x64 Release 发布通过。
- `dotnet run --project tests/WatchPairing/WatchPairing.csproj`：令牌隔离、二维码结构、失败不消耗设备码、并发幂等、重放限制、过期通过。
- `PGDATABASE=family_watch_pairing_test_20260916 dotnet run --project tests/WatchPairing.Integration/WatchPairing.Integration.csproj`：隔离本地 PostgreSQL 测试库；验证 HTTP 完整流程、未登录、伪造身份头、跨家长拒绝、并发确认、实际孩子积分读取、已有设备冲突、服务实例重建后的批准恢复以及解绑失效。测试认证处理器仅位于测试项目。
- `bash watch-app/apple/verify.sh`：原生 API/状态测试、钥匙串待绑定恢复、断网恢复、批准/过期分支及 watchOS Release 构建通过。
- `archive.sh` / `export.sh`：MyVnc 同团队专用密钥签名的 1.0.0（2）通过最终 IPA 校验。
- Apple Vision 已独立解码实际生成的二维码，结果与家长绑定 URL 完全一致。
- 桌面浏览器工具返回 `cgWindowNotFound`，家长页面实际浏览器验收待补；40mm 手表模拟器已完成截图检查，修正二维码尺寸后首屏同时显示完整二维码和设备码，Apple Vision 成功识别截图中的生产绑定 URL。用户真机扫码验收仍待完成。

## 发布状态

- 现有 TestFlight 1.0.0（1）已在用户专属内部组中测试。
- 小表盘布局修正版 1.0.0（3）本地签名包：`watch-app/apple/build/TestFlight/HappyLife.ipa`；SHA-256 `d43c5b7a182a027582a197d6677e59f4d50099c2399bd73c0f28b0acdcad8b46`。上传状态以本机 `build/evidence/` 的 Apple API 读回为准。
- 服务端使用 Atlas 官方 `atlas-package-server.sh` 生成 `family-points` / `20260916-watch-pairing` 的 API、Web、server-linux 三个制品，暂存 `/tmp/family-pair-atlas-20260916/`。
- Atlas 实时目录：应用 `735a18a1-ba4c-4471-b409-279d8014b16a` / `family-points`，当前仅有 1.0.0 元数据，无制品。结构化项目环境为空；服务器没有本应用的 Atlas 升级配置和发布凭据。仓库 `scripts/atlas-deploy-server.sh` 仍转调旧部署脚本，尚未接入共享发布生命周期。
- 用户明确授权本次沿用旧部署脚本。北京时间 2026-09-16 已部署，备份为 `/opt/backups/family-reward/20260916023541`；独立读取线上 H5 确认反向绑定代码，下载线上前端包并与本机构建 SHA-256 对比一致；实际生产创建短期设备码并查询 pending，伪造身份确认返回 401，未操作真实孩子绑定。
- Apple 构建 `5c3dd23c-2959-4ee7-9004-f4473581ee02` / 1.0.0（2）已处理 `VALID`，加入原个人内部测试组后独立读回 `IN_BETA_TESTING`；测试员仍只有用户本人。设备实际安装、扫码和孩子绑定由用户验收。
- 新 Atlas 发布流程已启动，跟踪任务 `family-reward-TASK-263`；构建与发布适配见 [接入记录](ATLAS-RELEASE-ADOPTION.md)，生产生命周期尚未切换。

- 最终小表盘修正版 1.0.0（3），Apple 构建 `bd74e727-ec02-4c88-aca8-dc1304600cec`：`VALID` / `IN_BETA_TESTING`，已加入同一单人内部测试组；最终证据 `pairing-build3.json`、`pairing-group.json` 和 `pairing-watch-40mm-v3.png`。
