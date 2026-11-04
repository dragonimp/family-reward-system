# Linko Moment Android 家长端

Android 手机端提交标识为 `net.impx.happylife`。儿童手表端使用独立的 Android 手表包及其既有商店材料；本目录只构建手机 App。

首个以此包名提交商店的版本为 `1.0.0 (9)`；上架准备材料见 `docs/publishing/android-phone/README.md`。旧包名 `net.impx.happylife.parent.android` 与此包不构成系统级覆盖升级。

`20261024-moment-invite-android.1` 在“我的”提供原生测试邀请页，使用 Atlas 账号调用应用专属邀请接口，显示二维码、链接、复制、系统分享与重新生成；项目成员及隐私资料从 Atlas 的公开应用接口读取。此前的 `20261017-dear-feedback-android.1` 增加心愿墙与意见墙。Apple TestFlight 等获取地址由 Atlas 应用后台管理，客户端不保存直链。

首版 Android 手机客户端与 Web、iOS 共用 `https://happylife.ai.impx.net` 后端。原生界面使用 .NET MAUI；用户中心登录和令牌续期复用 `AgentIdentity.NativeClient`，本应用仅在 Android SecureStorage 保存会话，不另建账号或业务令牌。

## 已提供

- 用户中心登录、注册、取消、退出；手机端登录后直接使用家长身份。
- 家庭列表与切换、创建家庭、邀请码加入、系统分享邀请链接。
- 孩子与积分、零用钱、物品余额；添加孩子；查看现有规则。
- 积分、零用钱和物品奖励或扣除；提交前确认，记录使用唯一幂等键；成功后从服务端刷新。
- 儿童手表配对码输入、生成限时儿童手表授权码。
- 孩子申请列表与批准、交易记录分页。
- 用户中心统一反馈墙：心愿、意见、公开提案投票、私人反馈及审核状态。

## 与 iOS 对齐的界面（1.0.3 / 12）

- 底部固定“成长、活动、运动、我的”四栏；审批、记录和规则收进成长页，显示孩子余额和守约状态。
- 活动原生列表按日期排序，标题右侧新增；活动内“⋯”收纳分享、管理、发布等操作。
- 照片、日常、打卡合并呈现，支持动态、紧凑和每行五张网格；紧凑模式的昵称、地点、海拔和按钮在照片右侧。列表只显示点评数量，输入放在详情页。
- 缩略图异步限流加载并使用有界内存缓存；照片详情支持左右浏览、缩放、下滑退出和点评。
- 消息列表与已读操作复用用户中心 NativeClient SDK；账户页采用分组设置样式。

原文件分享、下载传输、相机、部分活动管理、成长足迹和亲子互动仍打开现有完整 Web 页面；本次没有实现 Android 原生传输或系统推送注册。AI 对话、族谱、扫码配对及 Android 手表安装尚未补齐。本次不修改后端权限和数据结构。

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

1.0.3 (12) 已完成 Release ARM64 构建、15 项模型检查、发布证书校验以及 Android 35 既有应用的保留数据覆盖安装和冷启动。当前界面工具无法连接模拟器窗口，页面交互、登录后数据、照片手势及物理 Android 手机尚未验收。详见 `docs/reports/2026-11-03-moment-android-ios-layout.md`。
