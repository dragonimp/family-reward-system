# 小米手表应用市场发布资料包

整理日期：2026-08-13

官方参考：

- 小米手表应用发布操作指南：https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2058
- 小米手表应用上架要求：https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2059

## 当前产品信息

| 项目 | 内容 |
| --- | --- |
| 应用名称 | 家加分手表积分 |
| 推荐展示名 | 家加分 |
| 包名 | `net.impx.happylife.watch` |
| 版本 | `1.0.0` / `100` |
| targetSdk | 35 |
| 手表入口 | `https://happylife.ai.impx.net/watch?source=watch-app&platform=xiaomi` |
| 功能范围 | 儿童认证码绑定、积分查询、积分申请、最近申请状态、设备解绑码 |
| 权限范围 | 网络访问、网络状态检测 |

## 已准备材料

- 应用基础资料：`01-app-basic-info.md`
- 审核使用说明：`02-review-user-guide.md`
- 测试用例与报告模板：`03-test-cases-and-report.md`
- 发布主体必须提供材料：`04-user-provided-materials.md`
- 官方要求核对笔记：`05-official-requirements-notes.md`

## 关键判断

当前 Android WebView 壳可作为小米手表 APK 提交基础；小米官方要求手表应用 targetSdk 不低于 26，当前工程 targetSdk 35 满足。若后续引入 native so，需要优先准备 32 位包体并重新检查 CPU 适配。

小米平台的联系人姓名、手机号、验证码、邮箱应从项目管理“项目平台账号”读取；短信验证码仍应作为上架执行时的人工输入，不应固化到仓库。
