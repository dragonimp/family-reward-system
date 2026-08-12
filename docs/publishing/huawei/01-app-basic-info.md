# 华为应用基础资料

## 基础字段

| 字段 | 建议填写 |
| --- | --- |
| 应用名称 | 家加分 |
| 软著对应名称 | 需与软著/备案名称一致；如软著为“家加分手表积分”，后台名称应同步 |
| 包名 | `net.impx.happylife.watch` |
| Version Name | `1.0.0` |
| Version Code | `100` |
| 软件包类型 | APK，前提是目标华为手表支持 Android/Wear OS APK 路径 |
| 分类 | 生活服务 / 工具 / 亲子家庭类，最终以 AppGallery Connect 后台可选项为准 |
| 分发区域 | 先按中国大陆审核路径准备，后续扩展海外需补多语言和区域隐私声明 |
| 隐私政策 | 从项目管理平台账号或应用上架材料读取 |
| 用户协议 | 从项目管理平台账号或应用上架材料读取 |
| 审核测试账号 | 从项目管理平台账号读取家长测试账号和一次性儿童认证码 |

## 应用介绍

```text
家加分是家庭奖励管理工具。孩子可在手表端查看积分、提交奖励申请并查看申请状态，家长在 Web 端管理孩子、规则、审核和设备绑定。
```

## 更新说明

```text
首版上线。支持手表端认证码绑定、积分查询、积分申请、最近申请状态和设备解绑码。
```

## 平台管理应配置的字段

建议写入项目管理的 `ProjectMarketplaceAccount.credentialsjson`：

```json
{
  "authMode": "service_account",
  "clientId": "",
  "clientSecretRef": "",
  "appId": "",
  "serviceAccountKeyRef": ""
}
```

建议写入 `ProjectMarketplaceAccount.configjson`：

```json
{
  "contact": {
    "name": "",
    "mobile": "",
    "email": ""
  },
  "distribution": {
    "countries": ["CN"],
    "packageType": "apk",
    "targetDevice": "watch_android_compatible"
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
  }
}
```
