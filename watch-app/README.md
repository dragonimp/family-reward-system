# 家加分手表 app 上架包

本目录为 `family-reward-REQ-008` 准备：面向小天才、小米、华为手表的手表端 app 版本。

当前实现采用轻量 Android WebView 壳，统一加载线上手表端入口：

- 入口：`https://happylife.ai.impx.net/watch?source=watch-app`
- 清单：`https://happylife.ai.impx.net/watch/manifest.json`
- 应用包名：`net.impx.happylife.watch`
- 手表端身份：输入家长生成的儿童认证码完成设备绑定
- 权限范围：仅网络访问和网络状态检测

## 设备绑定流程

1. 家长在 Web 端完成注册/登录。
2. 家长在孩子管理中创建儿童账号，并为孩子生成一次性认证码。
3. 手表 App 打开 `/watch`，输入认证码完成绑定。
4. 绑定成功后手表端保存 `deviceToken`，后续仅允许查询积分、提交积分申请和查看申请状态。
5. 家长可在 Web 端查看设备列表、生成一次性解绑认证码或直接解绑设备；孩子从手表端解绑时必须输入对应设备的解绑认证码。

## 目录

- `android/`：Android WebView 手表壳工程，可用于小米、华为以及 Android 系手表渠道打包。
- `platforms/`：三家平台的上架适配配置和审核说明。
- `store-listing/`：中文上架文案、权限说明、截图清单。
- `RELEASE-CHECKLIST.md`：平台账号、签名、真机截图、合规资料和完成证据边界。
- `scripts/verify-watch-app.mjs`：不依赖 Android SDK 的发布配置校验。

## 本地校验

```bash
node watch-app/scripts/verify-watch-app.mjs
dotnet build FamilyReward.slnx
```

## 打包边界

本仓库已准备可构建的 Android 工程和上架材料。真正生成签名包还需要平台开发者账号和签名证书：

- `HAPPYLIFE_WATCH_KEYSTORE`
- `HAPPYLIFE_WATCH_KEY_ALIAS`
- `HAPPYLIFE_WATCH_KEYSTORE_PASSWORD`
- `HAPPYLIFE_WATCH_KEY_PASSWORD`

配置 Android SDK/Gradle 后可在 `watch-app/android` 下执行：

```bash
./gradlew :app:assembleRelease
```

工程会从上述四个环境变量读取 release 签名配置；缺少任一项时 release 构建会直接报错，避免误交未签名产物。仓库不提交 Gradle wrapper 二进制、真实证书或密码，发布环境需提供受控 Gradle/JDK/Android SDK 工具链。
