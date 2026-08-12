# 华为手表应用市场发布资料包

整理日期：2026-08-13

官方参考：

- 华为 AppGallery Connect：https://developer.huawei.com/consumer/cn/appgallery/
- AppGallery Connect 发布 APK：https://developer.huawei.com/consumer/cn/doc/app/agc-help-releaseapkrpk-0000001106463276
- AppGallery Connect Publishing API：https://developer.huawei.com/consumer/cn/doc/App/agc-help-publish-api-guide-0000002271134665
- AppGallery Connect API 服务端鉴权：https://developer.huawei.com/consumer/cn/doc/App/agc-help-connect-api-obtain-server-auth-0000002271134661
- 华为应用审核指南：https://developer.huawei.com/consumer/cn/doc/50104
- 华为软著资质文件示例：https://developer.huawei.com/consumer/cn/doc/App/50111-02

## 当前产品信息

| 项目 | 内容 |
| --- | --- |
| 应用名称 | 家加分手表积分 |
| 推荐展示名 | 家加分 |
| 包名 | `net.impx.happylife.watch` |
| 版本 | `1.0.0` / `100` |
| 手表入口 | `https://happylife.ai.impx.net/watch?source=watch-app&platform=huawei` |
| 功能范围 | 儿童认证码绑定、积分查询、积分申请、最近申请状态、设备解绑码 |
| 权限范围 | 网络访问、网络状态检测 |

## 关键判断

华为手表发布前必须先确认目标设备类型：

- 如果目标是 Android/Wear OS 兼容路径，当前 Android WebView 壳可作为 APK 基础，走 AppGallery Connect APK 发布流程。
- 如果目标是 HarmonyOS 原生手表或 HarmonyOS NEXT 设备，不能直接用当前 Android 壳替代，需要另立 HarmonyOS 工程并生成对应包体。

华为平台具备 AppGallery Connect API。项目管理上架工具应优先支持 Service Account/API Client 鉴权、上传包体、提交隐私政策/年龄分级、提交发布请求和轮询审核状态；无法 API 化或涉及验证码/协议签署的步骤保留人工确认。

## 已准备材料

- 应用基础资料：`01-app-basic-info.md`
- 审核使用说明：`02-review-user-guide.md`
- 测试用例与报告模板：`03-test-cases-and-report.md`
- 发布主体必须提供材料：`04-user-provided-materials.md`
- 官方要求核对笔记：`05-official-requirements-notes.md`
