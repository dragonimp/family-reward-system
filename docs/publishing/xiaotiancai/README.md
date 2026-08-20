# 家加分小天才上架资料包

整理日期：2026-08-13

本目录只面向小天才手表应用市场真实提审。通用手表端工程、三平台上架手册和发布签名边界仍以 `watch-app/` 为准；本目录把小天才官方当前公开要求拆成可提交材料、待补附件和审核说明。

## 已准备

- 应用基础资料：`01-app-basic-info.md`
- 客服/审核使用说明：`02-review-user-guide.md`
- 测试用例与报告模板：`03-test-cases-and-report.md`
- 隐私政策草案：`04-privacy-policy-draft.md`
- 用户协议草案：`05-user-agreement-draft.md`
- 首次提交免责函草案：`06-disclaimer-draft.md`
- 提审邮件模板：`07-release-email-template.md`
- 必须由发布主体提供的材料：`08-user-provided-materials.md`
- 官方要求核对笔记：`09-official-requirements-notes.md`
- 项目管理外部市场平台模块审计：`10-external-market-platform-module-audit.md`
- REQ-053 静态测试用例与追踪矩阵：`11-req-053-static-test-cases.md`

## 当前产品信息

| 项目 | 内容 |
| --- | --- |
| 应用名称 | 家加分手表积分 |
| 品牌名称 | 家加分 |
| 包名 | `net.impx.happylife.watch` |
| 版本 | `1.0.0` / `100` |
| 手表入口 | `https://happylife.ai.impx.net/watch?source=watch-app` |
| 线上清单 | `https://happylife.ai.impx.net/watch/manifest.json` |
| 应用信息接口 | `https://happylife.ai.impx.net/api/watch/app-info` |
| 后端健康检查 | `https://happylife.ai.impx.net/health` |
| 功能范围 | 儿童认证码绑定、积分查询、积分申请、最近申请状态、设备解绑码 |
| 权限范围 | 网络访问、网络状态检测 |

## 完成边界

仓库可准备文案、说明、测试模板、隐私/协议草案和资料清单；真实提审前仍需要发布主体提供企业证照、法人证件、软著、盖章免责函、最终联系方式、测试账号/认证码、真机截图和签名 APK。

官方小天才版本材料要求见：

- https://developer.okii.com/docs/publish/03-version.html
- https://developer.okii.com/docs/publish/02-resource.html
- https://developer.okii.com/docs/publish/02-resource-secure.html
- https://developer.okii.com/docs/publish/06-publish.html
- https://developer.okii.com/docs/develop/09-account.html
