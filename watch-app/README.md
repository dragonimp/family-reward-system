# HappyLife 手表 app 上架包

本目录为 `family-reward-REQ-008` 准备：面向小天才、小米、华为手表的手表端 app 版本。

当前实现采用轻量 Android WebView 壳，统一加载线上手表端入口：

- 入口：`https://happylife.ai.impx.net/watch?source=watch-app`
- 清单：`https://happylife.ai.impx.net/watch/manifest.json`
- 应用包名：`net.impx.happylife.watch`
- 手表端身份：统一登录后默认为孩子
- 权限范围：仅网络访问和网络状态检测

## 目录

- `android/`：Android WebView 手表壳工程，可用于小米、华为以及 Android 系手表渠道打包。
- `platforms/`：三家平台的上架适配配置和审核说明。
- `store-listing/`：中文上架文案、权限说明、截图清单。
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

本机当前没有 Gradle wrapper 和 Android SDK，因此仓库内以工程文件与配置校验作为可验证交付。
