# Linko Moment Android 手机端候选包回执

状态：已生成并本地验签，尚未提交应用市场审核。

| 项目 | 核对结果 |
| --- | --- |
| 应用 | Linko Moment |
| 包名 | `net.impx.happylife` |
| 版本 | `1.0.0`（versionCode `9`） |
| 最低 / 目标 API | 26 / 36 |
| 构建源码提交 | `e8d9cda0cc54ff6b1a5250e4399f5e1618e0e9c8`，已推送至 `origin/main` |
| 签名证书 SHA-256 | `4596cdb1ea8a5eea1a2567c6800d2bf4f90f051198a5518beb13abb7ac359c83` |
| AAB SHA-256 | `09a52ecf026a6159ab494fb562e78e5d79ae6ba5dbc6d5e6c9d2fedc5663d27e` |
| APK SHA-256 | `e2f27c936a3fcc5ea522fceb476ab3a00971087b766d1b17005b130b76b33e6f` |
| 正式本机输出 | `~/.codex/build-outputs/family-reward-system/android-phone-store/runs/20261029-181247-90745bcf4933/output/` |

构建使用共享 Apple/Android 队列与 `host-build-output`；AAB 的 JAR 签名验证通过，APK 的 Android 签名验证通过。Android 35 模拟器已安装签名 APK，并以 `net.impx.happylife/...MainActivity` 冷启动；截图与活动状态位于 `android-phone-store-verify/runs/20261029-182407-bf40ae743044/`。该次验证脚本退出码为 0，但 `host-build-output` 报告模拟器后代进程或打开文件使清理延期，因此验收截图未提升为正式输出；需要在独立的干净队列批次中重新核验。

Atlas 网站和 API 已发布 `20261029-android-store-prep-e8d9cda`；独立读回 `version.json`、`/health` 和公开隐私政策，均为新版本，政策为 1.3 版，含账号注销入口。

## 待完成的市场提交条件

- 确定目标市场及其开发者账号；核实该包名是否已被占用、签名证书是否符合既有应用的升级要求。
- 使用真实审核账号在 Android 真机走通登录、家庭、奖励、审批和记录；形成真实功能截图和测试账号资料。
- 在目标市场填写内容分级、儿童与家庭、数据安全和隐私表单，并提交审核。当前仅有通用草稿，未填写任何市场后台表单。
- Android 手机端当前没有活动、照片或系统相册分享功能；若上架版本需包含这些功能，应先实现和重新构建。
