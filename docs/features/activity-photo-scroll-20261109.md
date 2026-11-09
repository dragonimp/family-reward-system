# 活动照片滚动区域修复（2026-11-09）

## 已实现

Android 活动详情曾把日期、位置共享与操作按钮固定在照片列表上方，导致照片仅在下半屏滚动。现将这些内容作为 CollectionView.Header，与照片统一滚动；保留标题、返回与更多菜单。大图、紧凑、每行五张网格使用同一布局，返回活动列表时恢复原布局。切换模式前解除旧页头父级，避免重复挂载。

iOS 现有详情使用整体 List，本次未修改。后端、数据库和既有业务流程未修改。

## 修改文件

- parent-app/android/MomentActivityPanel.cs：滚动页头与内容区域。
- parent-app/android/LinkoFamily.csproj：1.0.22（31）。
- scripts/build-moment-android-release.sh：对应制品和发布说明。

## 验证与发布

- git diff --check：通过。
- tests/MomentAndroidModels：通过（GUID、时间和分享范围等模型检查，不代替滚动手势测试）。
- Android arm64 Release：构建通过，现有发布证书签名校验通过，包名 net.impx.happylife，版本 1.0.22 / 31。
- 构建源码 e288d8a70b64429d5c4d6dc816715d898b438a52 已推送 origin/main。
- Atlas family-points 发布记录 dc4439fa-08e3-47e9-a8de-45097f1a3010，状态 published。
- APK SHA256 f6a7d7f91327be2d08a56b813669aa5631875118345f673b7d4689fdc44087eb，20431476 字节。
- 邀请页 Android 更新操作 7ce4d37c-af68-495b-9c13-dd95ad78bd8c，verified；独立读回 1.0.22（31）。保留原 iOS 入口。
- 邀请页：https://home.ai.impx.net/invite/SW2wL0kd3pX20t6xSNLXsDK4

## 待验证

尚未在登录后的真实 Android 设备验证滚动手势、三种布局切换及返回行为；编译与模型检查不能替代该项验收。

## 产物保留与清理

已从 Atlas 独立下载 APK 与构建回执，大小及 SHA256 均吻合。构建包装器已清理临时源码及编译目录；本地 APK 与签名旁文件删除 20597327 字节，远端本次上传副本同时清理。正式包与回执保留在 Atlas，本地保留精简构建回执、清单和 SDK 提交记录。
