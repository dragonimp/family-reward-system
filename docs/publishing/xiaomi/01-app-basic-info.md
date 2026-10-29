# 小米应用基础资料

## 基础字段

| 字段 | 建议填写 |
| --- | --- |
| 应用创建名称 | Linko Moment |
| 后台展示名称 | Linko Moment |
| 软著对应名称 | 必须以最终签发证书及 APP 备案名称核对，当前尚无证明 |
| 包名 | `net.impx.happylife.watch` |
| Version Name | `1.0.1` |
| Version Code | `101` |
| 分类 | 以当前后台和实际功能选择，待手表发布入口恢复后核定 |
| 上架时间 | 审核通过后立即上架 |
| 一句话简介 | 孩子的成长奖励助手 |
| 应用介绍 | Linko Moment 手表端供孩子查看家庭积分、提交奖励申请、查看申请状态，并通过家长生成的认证码完成设备绑定。家长在手机或 Web 端管理孩子、规则和审核。 |
| 隐私政策 URL | `https://happylife.ai.impx.net/legal/privacy.html`；公网仍为旧 1.0 版，必须先通过 Atlas 发布 1.1 版并读回 |
| 测试账号 | 从项目管理平台账号读取审核测试家长账号和一次性儿童认证码 |

## 更新日志

```text
支持手表端认证码绑定、积分查询、积分申请、最近申请状态和设备解绑码；增加首次隐私告知及应用内隐私政策入口。
```

## 素材规格

| 素材 | 小米要求 | 当前准备策略 |
| --- | --- | --- |
| 应用图标 | PNG，512 x 512 px；中间圆形、四角透明；与安装后桌面图标一致 | 需导出最终 PNG |
| 应用截图 | PNG，1080 x 1080 px；单张不超过 5 MB；官方文档对数量有 3-4 与 3-5 的差异 | 默认准备 4 张，最终以后台校验为准 |
| APK | `.apk`，包名与创建应用一致 | `1.0.1 (101)` 已签名验签，与历史手表证书一致；见提审门槛回执 |
| 软著/版权 | 计算机软件著作权登记证书或 APP 电子版权认证证书 | 需发布主体提供 |
| 备案信息 | APP 备案信息；主体不一致需提供主体名称、统一社会信用代码、营业执照附件和备案说明 | 需发布主体提供 |

## 平台管理应配置的字段

建议写入项目管理的 `ProjectMarketplaceAccount.configjson`：

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
    "category": "",
    "releaseTiming": "after_approval",
    "privacyPolicyUrl": "",
    "copyrightName": "",
    "appRecordName": ""
  }
}
```
