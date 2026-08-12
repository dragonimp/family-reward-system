# 项目管理外部市场平台模块审计

审计日期：2026-08-13

审计范围：`/Users/wengzhishan/Projects/Agent-Dash` 的项目管理“应用发布”下“外部市场平台”功能。该仓库当前工作树存在大量未提交改动，本次只读检查，没有修改 Agent-Dash。

## 现有能力

### 后端模型

`MarketplaceExternalPlatform` 当前字段：

- `code`
- `name`
- `platform_type`
- `developer_console_url`
- `api_base_url`
- `webhook_url`
- `configjson`
- `publish_mode`
- `sortorder`
- `status`
- `notes`

`ProjectMarketplaceAccount` 当前字段：

- `project_code`
- `platform_code`
- `name`
- `account_key`
- `account_name`
- `app_identifier`
- `developer_console_url`
- `credentialsjson`
- `configjson`
- `publish_mode`
- `status`
- `notes`

### 后端接口

- `GET /api/admin/marketplace/external-platforms`
- `POST /api/admin/marketplace/external-platforms`
- `PUT /api/admin/marketplace/external-platforms/{id}`
- `DELETE /api/admin/marketplace/external-platforms/{id}`
- `GET /api/admin/marketplace/project-accounts`
- `POST /api/admin/marketplace/project-accounts`
- `PUT /api/admin/marketplace/project-accounts/{id}`
- `DELETE /api/admin/marketplace/project-accounts/{id}`

### 前端页面

- 应用发布页展示外部市场账号、应用上架和版本记录。
- 外部市场平台管理页可维护平台编码、平台名称、平台类型、发布模式、开发者控制台、API Base URL、Webhook URL、配置 JSON、说明和状态。
- 项目平台账号表单可维护平台、账号名称、账号标识、账号主体、应用标识/AppID/包名、认证信息 JSON、上架参数 JSON。

### 初始化平台

当前内置平台：

- `xiaotiancai`：小天才手表应用市场。
- `xiaomi`：小米应用商店。
- `huawei`：华为 AppGallery Connect。
- `apple`：Apple App Store Connect。
- `wechat_miniprogram`：微信小程序平台。

## 缺口与优化建议

| 优先级 | 缺口 | 建议补充的平台管理工具 |
| --- | --- | --- |
| P0 | 只保存平台参数，不能判断某个版本是否满足平台上架材料要求 | 新增 `validate_marketplace_submission_package`：按平台配置校验 APK、图标、截图、隐私协议、软著、免责函、测试报告、版本号递增、包名不变等 |
| P0 | 没有平台版本送审状态管理，应用版本只能做内部审批，不跟踪外部市场受理、驳回、整改和上线 | 新增 `create_external_submission`、`list_external_submissions`、`update_external_submission_status`，记录平台、账号、版本、提交时间、受理号、审核状态、驳回原因、整改期限 |
| P0 | 小天才这类平台有特殊尺寸、邮件、附件和首次提交材料要求，但平台配置只有自由 JSON | 在 `MarketplaceExternalPlatform.configjson` 中标准化 `submissionChecklist`、`assetRequirements`、`legalRequirements`、`reviewInstructions`，并提供表单化编辑 |
| P1 | 平台账号 `credentialsjson` 能存凭据，但没有健康检查和过期提醒 | 新增 `validate_marketplace_account_credentials`：验证控制台登录态、API token、cookie、appId/appSecret 是否可用，不返回密钥原文 |
| P1 | 缺少素材资产管理 | 新增 `list_marketplace_assets`、`validate_marketplace_asset`：检查图标尺寸、截图数量/尺寸、文件格式、HTTPS 链接可访问性 |
| P1 | 缺少提交包生成能力 | 新增 `generate_marketplace_submission_bundle`：按平台输出邮件正文、附件清单、文件命名、审核说明和客服使用说明 |
| P1 | 缺少平台政策版本和规则变更记录 | 新增 `sync_marketplace_policy_snapshot` 或手工 `update_marketplace_policy_snapshot`：记录官方规则 URL、抓取/确认日期、关键要求和变更摘要 |
| P1 | 缺少整改和市场监控 | 新增 `create_marketplace_rectification_task`：记录评分阈值、投诉、平台整改通知、截止日期、负责人和关联任务 |
| P2 | 平台配置 JSON 缺少 schema，容易写错字段 | 为 `configjson` 增加平台 schema 校验和 UI JSON lint，避免无效 JSON 或拼错字段进入库 |
| P2 | 缺少账号密钥轮换和审计 | 新增账号凭据变更审计、密钥更新时间、到期时间、最后验证时间、操作人 |
| P2 | 缺少平台适配器运行状态 | 新增 `list_marketplace_adapters`、`test_marketplace_adapter`：显示人工/API/适配器发布能力是否真实可用 |
| P2 | 缺少目标机型/区域/渠道维度 | 平台配置增加目标机型、区域、分发渠道、儿童类应用政策和兼容性要求 |

## 对小天才最直接需要补的平台工具

1. 小天才提审包校验工具：校验 148 x 148 图标、320 x 360 介绍图 3-5 张、APK 大小、安装大小、隐私/协议 HTTPS、软著、免责函、测试报告、服务器性能说明。
2. 小天才邮件包生成工具：自动生成 `〖版本验收〗家加分手表积分` 邮件正文和附件命名。
3. 小天才审核状态跟踪：记录邮件发送时间、平台回复、驳回点、整改截止日期、最终上线时间。
4. 小天才账号能力记录：记录 `appId`、`appSecret`、权限范围、测试/生产环境差异，但列表页只显示是否已配置和最后验证时间。
5. 小天才真机矩阵：记录目标机型、系统版本、屏幕尺寸、测试结论和截图文件。

## 结论

当前“外部市场平台”模块适合维护平台和项目账号基础资料，但还不是完整的应用市场发布管理工具。下一步应优先补“提审包校验、外部送审状态、素材校验、凭据健康检查、平台规则快照”五类工具；这几类能直接减少小天才、小米、华为等真实上架时的漏项和返工。
