# 华为官方要求核对笔记

资料整理日期：2026-08-13

## 发布路径

官方入口：

- https://developer.huawei.com/consumer/cn/appgallery/
- https://developer.huawei.com/consumer/cn/doc/app/agc-help-releaseapkrpk-0000001106463276

核对项：

- 应用开发和测试完成后，在 AppGallery Connect 提交上架申请。
- APK、RPK、AppBundle、APP 等包体路径需按目标系统选择。
- 当前家加分 Android WebView 壳只适合 APK/Android 兼容路径。
- HarmonyOS 原生手表或 HarmonyOS NEXT 场景需要独立 HarmonyOS 工程和包体。

## API 自动化

官方入口：

- https://developer.huawei.com/consumer/cn/doc/App/agc-help-publish-api-guide-0000002271134665
- https://developer.huawei.com/consumer/cn/doc/App/agc-help-connect-api-obtain-server-auth-0000002271134661
- https://developer.huawei.com/consumer/cn/doc/App/agc-help-publish-api-put-privacy-agreement-0000002271000633
- https://developer.huawei.com/consumer/cn/doc/app/agc-help-publish-api-post-app-age-rating-0000002236201262

核对项：

- AppGallery Connect 支持服务端 API 自动化，推荐优先使用 Service Account。
- Upload Management API 可用于服务端上传应用文件。
- Publishing API 可覆盖部分发布信息、隐私政策协议、年龄分级和提交发布流程。
- 软件包解析是异步过程，上架工具需要轮询解析状态后再提交审核。

## 审核和资质

官方入口：

- https://developer.huawei.com/consumer/cn/doc/50104
- https://developer.huawei.com/consumer/cn/doc/App/50111-02

核对项：

- 提交上线前需符合华为应用审核指南和适用法律法规。
- 需要真实有效的开发者、应用、联系人、测试账号和隐私信息。
- 软著/版权证书和主体授权材料需要与应用和发布主体匹配。
- 上线后应用信息或版本变更仍需重新提交审核。
