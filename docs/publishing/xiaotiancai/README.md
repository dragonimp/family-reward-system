# 家加分小天才上架资料包

整理日期：2026-08-20

本目录只面向小天才手表应用市场真实提审。通用手表端工程、三平台上架手册和发布签名边界仍以 `watch-app/` 为准；本目录把小天才官方当前公开要求拆成可提交材料、待补附件和审核说明。

## 已准备

- 应用基础资料：`01-app-basic-info.md`
- 客服/审核使用说明：`02-review-user-guide.md`
- 测试用例与实测报告：`03-test-cases-and-report.md`
- 官网测试标准与报告模板映射：`14-official-test-standards-and-template-mapping.md`
- 官网测试模板原件：`official-templates/`
- 隐私政策定稿：`04-privacy-policy-draft.md`（历史文件名保留）
- 用户协议定稿：`05-user-agreement-draft.md`（历史文件名保留）
- 首次提交免责函定稿：`06-disclaimer-draft.md`（待公司盖章）
- 服务器性能实测报告：`12-server-performance-report.md`
- 已校验图标及介绍图：`assets/`
- 提审邮件模板：`07-release-email-template.md`
- 材料来源与外部动作边界：`08-user-provided-materials.md`
- 官方要求核对笔记：`09-official-requirements-notes.md`
- 项目管理外部市场平台模块审计：`10-external-market-platform-module-audit.md`
- REQ-053 静态测试用例与追踪矩阵：`11-req-053-static-test-cases.md`
- REQ-055 材料补齐纠正分析：`../../REQ-055-ANALYSIS.md`

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
| 权限范围 | 网络访问、网络状态检测；主动语音输入时使用麦克风，不保存原始录音 |

## 完成边界

上架任务应先从用户中心、图灵软件主体资料和历史发布资产查询复用已有证照、凭证与账号，再由项目从源码、受控构建和真实环境生成、验证、上传并登记签名 APK、图标、介绍图、协议和报告。只有系统中缺失的外部机构证件/资质、平台本人验证码或签署/盖章动作，以及平台强制要求的物理真机证据，才保留为外部待办；详见 `08-user-provided-materials.md` 和 `../../REQ-055-ANALYSIS.md`。

官方小天才版本材料要求见：

- https://developer.okii.com/docs/publish/03-version.html
- https://developer.okii.com/docs/publish/02-resource.html
- https://developer.okii.com/docs/publish/02-resource-secure.html
- https://developer.okii.com/docs/publish/06-publish.html
- https://developer.okii.com/docs/develop/09-account.html
