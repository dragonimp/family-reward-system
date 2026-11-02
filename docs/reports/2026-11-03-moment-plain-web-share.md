# 活动及邀请使用普通网页链接分享

用户反馈分享到微信时提示“不支持的分享类型”。当前实现使用 URL ShareLink，同时附加 subject、message 和 preview；确认存在组合分享载荷，但没有在 wzs 手机复现微信拒绝的具体类型，因此不将原因视为已证明。

改为单条 String 分享项，内容为“活动名称 + 换行 + 原 HTTPS 链接”，不再附加 URL/消息/预览组合。活动链接和邀请链接复用同一组件，活动名称仍保留。链接地址、邀请 Token 和权限边界不变：打开链接公开展示活动基本信息，进入后验证权限。接收方可能自行抓取网页标题或生成预览，这不需要发送额外分享类型。

版本 1.2.91（100）。源码 `38386b02f9d1d2bdbc470ad119722183eb60a988` 已独立核实在正式 origin/main。两个身份的签名 archive/export、版本和原生模型检查通过；Apple 实时 refresh 已确认两个身份均为 `VALID / testflight_visible`，可在各自测试组更新。本次未通过微信发送消息给任何联系人；不能将构建或 TestFlight 可见性当作真实微信送达验收。

## 制品与清理

两种身份的 10 项 IPA、符号及元数据已在 Atlas 正式存储核验长度及 SHA-256；随后清理本地重复包与导出日志 31,039,782 字节、远端重复暂存 30,945,562 字节。临时 work 已由统一输出管理清理，两个 latest.json 均 exitCode=0。保留正式存储中的 IPA/符号及小型检查和身份回执。

- legacy：任务 `d28f124c-292e-4752-9768-14c8520c07b3`，IPA SHA-256 `7e48a0263b0da34a95eb462d57228e181d6e5d616f9ad1d7e6230cb5e96614bc`。
- successor：任务 `e013943f-d0f3-4bcc-ada0-55eb51c7b58d`，IPA SHA-256 `7368a5a6673ff00f432c536fed441f07e4e5c49874b81b9534c5d87b0bd188b8`。

本次未创建工作树，无关 Android 和 AGENTS.md 未提交内容保留。

## TestFlight 最终读回

- 1.2.91（100），legacy Apple build `a95e1192-7f1a-4dc5-9043-33e5beab728c`，`VALID / testflight_visible`。
- 1.2.91（100），successor Apple build `3463f558-435b-46bd-a6e7-e7bcd3427a71`，`VALID / testflight_visible`。
- 仅跟踪原有任务至完成，未重复上传，未提交正式 App Store 审核。发布源码与 GitHub main 包含关系独立核实。
