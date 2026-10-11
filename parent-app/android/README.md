# Linko Dear Android 家长端 20261011-android-parent.1

首版 Android 手机客户端与 Web、iOS 共用 `https://happylife.ai.impx.net` 后端。原生界面使用 .NET MAUI；用户中心登录和令牌续期复用 `AgentIdentity.NativeClient`，本应用仅在 Android SecureStorage 保存会话，不另建账号或业务令牌。

## 已提供

- 用户中心登录、注册、取消、退出和家长身份选择。
- 家庭列表与切换、创建家庭、邀请码加入、系统分享邀请链接。
- 孩子与积分、零用钱、物品余额；添加孩子；查看现有规则。
- 积分、零用钱和物品奖励或扣除；提交前确认，记录使用唯一幂等键；成功后从服务端刷新。
- 儿童手表配对码输入、生成限时儿童手表授权码。
- 孩子申请列表与批准、交易记录分页。

本版不包含 iOS 的所有功能。守约信用、成长图表、亲子互动、族谱、活动、AI 对话、扫码配对及 Android 手表安装仍待后续版本；这些功能仍可使用现有 Web/iOS 入口。后端没有为 Android 修改权限或数据结构。

## 构建

要求 .NET 10 MAUI Android workload、Android SDK 35/36 和 JDK 21。主仓库与 `AgentIdentity` 在同一 `Projects` 目录时可直接运行：

```sh
ANDROID_HOME=/path/to/android-sdk dotnet publish parent-app/android/LinkoFamily.csproj \
  -f net10.0-android -c Debug \
  -p:JavaSdkDirectory=/path/to/jdk-21 \
  -p:EmbedAssembliesIntoApk=true -p:AndroidUseSharedRuntime=false
```

若使用独立 worktree，传入 `-p:AgentIdentityNativeClientProject=/absolute/path/to/AgentIdentity.NativeClient.csproj`。正式发布必须使用受控 Android 发布签名；签名凭据从环境变量或本机受控文件注入，绝不放入仓库。签名材料和生成包不提交仓库。

## 验收边界

本次在 Android 35 手机模拟器安装并打开自包含调试 APK，读到原生登录界面；点击登录后从正式后端获得一次性验证码并打开系统浏览器。模拟器 Chrome 首次启动页挡住后续授权，尚未用真实家长账号完成登录、家庭数据、记账、审批与手表配对，也尚未在物理 Android 手机上验收。
