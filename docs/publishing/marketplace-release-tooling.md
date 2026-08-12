# 项目管理应用上架工具缺口

整理日期：2026-08-13

目标：项目管理“应用上架”应能统一承载小天才、小米、华为等三方平台的材料准备、上传、送审、状态同步和证据归档。

## 当前已有能力

从 Agent-Dash 只读检查可见，当前已有：

- 外部市场平台 CRUD：`/api/admin/marketplace/external-platforms`
- 项目平台账号 CRUD：`/api/admin/marketplace/project-accounts`
- 应用、版本、审批、上架、下架状态管理：`/api/admin/marketplace/apps`
- 平台账号可保存 `credentialsjson` 和 `configjson`
- 内置外部平台包含 `xiaotiancai`、`xiaomi`、`huawei`、`apple`、`wechat_miniprogram`

不足：这些能力主要管理内部状态和基础账号参数，不能真正管理外部发布包，也不能把材料上传到三方平台并完成外部送审。

## 需要补的数据对象

| 对象 | 用途 |
| --- | --- |
| `MarketplaceSubmissionPackage` | 一个项目应用版本的一次外部发布包，绑定项目、应用、版本、包名、versionCode、目标平台 |
| `MarketplaceSubmissionAsset` | 发布材料资产，例如 APK、图标、截图、软著、隐私政策、用户协议、测试报告、免责函 |
| `MarketplaceSubmissionTarget` | 某个发布包在某个平台的发布目标，保存平台账号、发布模式、外部应用 ID、状态 |
| `MarketplaceExternalSubmission` | 外部平台送审记录，保存提交时间、受理号、审核状态、驳回原因、整改期限、上线时间 |
| `MarketplacePolicySnapshot` | 平台规则快照，保存官方文档 URL、确认日期、素材规格、合规要求 |
| `MarketplaceCredentialHealth` | 平台账号凭据健康状态，保存最后验证时间、过期时间、验证结果 |

## 需要补的 MCP/API 工具

| 工具 | 用途 |
| --- | --- |
| `get_marketplace_release_context` | 读取项目、应用、版本、平台账号、联系人、测试账号、密钥引用和平台规则 |
| `create_marketplace_submission_package` | 创建三方发布包，绑定 APK、版本、包名、目标平台 |
| `attach_marketplace_submission_asset` | 上传或登记一个发布材料资产 |
| `list_marketplace_submission_assets` | 查看发布包当前材料完整度 |
| `validate_marketplace_submission_package` | 按平台规则校验 APK、图标、截图、软著、隐私协议、备案、测试账号、版本号递增 |
| `generate_marketplace_submission_bundle` | 生成平台需要的邮件、附件清单、审核说明、测试报告和文件命名 |
| `validate_marketplace_account_credentials` | 验证平台账号、API token、网页登录态或邮件发送配置是否可用 |
| `upload_marketplace_submission_assets` | 将 APK、图标、截图、资质文件上传到目标平台或暂存区 |
| `submit_marketplace_release` | 触发外部平台送审；支持 `draft`、`review`、`publish` 模式 |
| `check_marketplace_submission_status` | 拉取或录入外部平台审核状态 |
| `record_marketplace_rectification` | 记录驳回/投诉/整改要求和截止日期 |
| `archive_marketplace_release_evidence` | 归档签名哈希、截图、提交回执、审核结果和上线证据 |

## 平台自动化策略

| 平台 | 推荐实现 | 人工边界 |
| --- | --- | --- |
| 小天才 | 生成邮件正文和附件包；如配置 SMTP/Gmail/Outlook，可发送 `developer@eebbk.com`；保存邮件 Message-ID 和附件哈希 | 商务准入、平台群沟通、盖章免责函、法人证件、软著原件 |
| 小米 | 使用网页登录态/浏览器自动化登录小米澎湃 OS 开发者平台，创建应用、上传 APK、图标、截图、软著、备案和测试账号，最终提交审核 | 短信验证码、实名认证、平台二次确认、被驳回后的人工沟通 |
| 华为 | 优先使用 AppGallery Connect Service Account/API：上传包体、更新隐私政策/年龄分级、提交审核、轮询状态 | 协议签署、账号实名认证、目标手表系统确认、HarmonyOS 原生工程 |

## 平台账号配置规范

项目管理的 `ProjectMarketplaceAccount` 应统一配置：

```json
{
  "contact": {
    "name": "",
    "title": "",
    "mobile": "",
    "email": ""
  },
  "testAccount": {
    "parentLogin": "",
    "childAuthCode": "",
    "expiresAt": ""
  },
  "listing": {
    "privacyPolicyUrl": "",
    "userAgreementUrl": "",
    "copyrightName": "",
    "appRecordName": ""
  },
  "automation": {
    "mode": "manual|browser|api|email",
    "webLoginCredentialId": "",
    "serviceAccountRef": "",
    "mailCredentialRef": ""
  }
}
```

密钥、密码、证书和短信验证码不能明文写入普通配置；应存密钥引用或由执行时人工输入。

## 三平台材料矩阵

| 材料 | 小天才 | 小米 | 华为 |
| --- | --- | --- | --- |
| 签名 APK | 必需 | 必需 | APK 路径必需 |
| 包名一致 | 必需 | 必需 | 必需 |
| 版本号递增 | 必需 | 必需 | 必需 |
| 图标 | 148 x 148 PNG | 512 x 512 PNG | 以 AGC 当前后台为准 |
| 截图 | 320 x 360 PNG，3-5 张 | 1080 x 1080 PNG，默认 4 张 | 以目标包体类型和后台为准 |
| 隐私政策 | HTTPS 必需 | URL 必需 | 必需 |
| 用户协议 | HTTPS 必需 | 建议/按后台要求 | 必需或按后台要求 |
| 软著/版权 | 必需 | 必需 | 必需 |
| 备案/核准 | 按平台要求 | 必需 | 按 AGC 要求 |
| 联系人手机/邮箱 | 必需 | 必需 | 必需 |
| 审核测试账号/认证码 | 必需 | 必需 | 必需 |
| 首次提交免责函 | 必需 | 特殊行业/平台要求时 | 按审核要求 |
| 服务器性能报告 | 首次提交要求或说明 | 一般不要求 | 一般不要求 |

## 最小可用闭环

第一阶段先实现：

1. 发布包和资产登记。
2. 三平台规则校验。
3. 平台账号联系人/测试账号读取。
4. 小天才邮件包生成。
5. 小米浏览器自动化草稿上传。
6. 华为 API 上传和提交草稿。
7. 外部审核状态手工/自动回写。

做到这一步，项目管理才能真正成为“统一应用上架入口”，而不是只改内部应用状态。
