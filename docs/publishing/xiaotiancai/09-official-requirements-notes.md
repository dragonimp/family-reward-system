# 小天才官方要求核对笔记

资料复核日期：2026-08-24

本笔记来自小天才开放平台公开文档，真实提交当天仍以平台后台和官方最新页面为准。

## 定制 Android、开放机型与测试获取

官方页面：

- https://developer.okii.com/docs/develop/00-model.html
- https://developer.okii.com/docs/develop/01-setting.html
- https://developer.okii.com/docs/develop/06-problem.html

核对项：

- 小天才手表采用 Android 系统，不是 Android Wear/Wear OS，按普通 Android 应用方式开发。
- 开放系统版本为 Android 4.4、7.1.1、8.1.0，CPU 为 ARMv7 32 位；主流开放机型为 320x360，D3 为 240x240。
- 当前 APK 的 `minSdk=23`，首版覆盖 Android 7.1.1/8.1.0 的 320x360 开放机型，不覆盖 D3 的 Android 4.4/API 19。
- 官方要求按测试需要从电商或线下购买手表，并联系小天才获取开发数据线。
- ADB 调试需要平台下发权限；手表需绑定、更新最新固件并重启。ADB 安装应用后也可能需要重启才可见。
- 测试环境和生产环境由平台协助切换；小天才账号 SDK 由平台技术人员在对接群提供，测试与生产使用不同 `appId/appSecret`。
- 公开开发文档未发现官方模拟器或远程真机入口，因此 AOSP Android 8.1 只能作为前置预检，最终兼容结论必须来自小天才开放机型真机。

## 版本提供

官方页面：https://developer.okii.com/docs/publish/03-version.html

核对项：

- 新应用提交材料发送至 `developer@eebbk.com`。
- 邮件标题格式：`〖版本验收〗xx应用`。
- APK 包大小不超过 30 MB。
- 安装后大小不超过 40 MB。
- 应用图标：PNG，148 x 148 px，直角正方形。
- 应用介绍图：PNG，320 x 360 px，直角，3-5 张。
- 应用简介不超过 20 个中文字符。
- 应用详细介绍不超过 100 个中文字符。
- 需要用户协议和隐私政策 HTTPS 链接。
- 需要软件著作权登记证书，且同一软著证书不能重复用于多个应用。
- 每次提交需要版本更新说明。
- 需要开发者公司名称、营业执照、法人身份证正反面。
- 首次提交需要免责函。
- 每个版本需要测试报告；首次提交还需要服务器负载/性能报告，或说明未提供原因并确保服务可用。
- 每次提审 `versionCode` 必须递增。
- 已上线应用的 `packageName` 不能变更。
- 官方建议同一 APK 兼容多机型，可在代码中根据 `android.os.Build.MODEL` 做机型适配。

## 审核规范

官方页面：https://developer.okii.com/docs/publish/02-resource.html

核对重点：

- 应用内容、功能、数据、安全、兼容性、功耗、稳定性都需满足平台审核规范。
- 儿童应用要特别关注未成年人保护、隐私合规、内容安全和家长知情。
- 应用备案、资质材料和主体信息需要与实际发布主体一致。

## 安全标准

官方页面：https://developer.okii.com/docs/publish/02-resource-secure.html

核对重点：

- 不包含恶意代码、后门、欺骗、诱导下载、违规 SDK 或第三方 WebView 内核。
- 提供账号注销或数据删除路径。
- 敏感数据需要加密传输和合理保护。
- 隐私政策必须覆盖实际收集和使用的数据。
- 用户注销后应删除或按要求处理相关数据。

## 市场监控

官方页面：https://developer.okii.com/docs/publish/06-publish.html

核对重点：

- 上线后仍会受市场监控。
- 评分低于平台阈值或出现重大投诉时，平台可能要求整改。
- 应建立用户反馈、投诉处理、版本修复和下架应急流程。

## 账号系统

官方页面：https://developer.okii.com/docs/develop/09-account.html

核对重点：

- 如接入小天才账号系统，小天才会分配 `appId`、`appSecret` 和权限范围。
- 测试环境和生产环境可能使用不同 `appId` / `appSecret`。
- 当前家加分采用“家长 Web 端生成儿童认证码，手表端输入认证码绑定设备”的独立绑定模型；如果平台要求必须接入小天才账号 SDK，需要另行评估并实现。
