# 移除顶部下载请求横幅

- 从 FamilyRoot 移除顶部 safeAreaInset，并删除仅供其使用的 PhotoTransferBanner；活动及其他页面不再被常驻横幅占用顶部空间。
- 推送代理、前台系统通知呈现、通知点击进入消息、“我的”的消息列表、未读数与原文件传输实现均未修改。
- iOS 版本 1.2.87（96），发布源码 `8e363bcfa42cc14fa75d9dc7e5210c753241bcee`，已独立核实 origin/main 包含该提交。保留用户 AGENTS.md 的未提交改动。
- 继续使用旧入口 Linko MomentX / 新入口 Linko Moment 的安装名称；此次未操作商店展示名称或 App Store 审核。

## 验证和发布

- diff 检查与项目 plist 检查通过。
- 新旧两入口的原生模型、日期与运动检查、Release Archive、App Store 导出、独立签名/Profile、Bundle ID、嵌入 Watch/Share、版本及安装名称校验通过。旧入口已通过独立 refresh 读回 VALID / testflight_visible，Apple build `93048326-9ca2-498d-9c3c-f6b33f904e07`；新入口同样已通过独立 refresh 读回 VALID / testflight_visible，Apple build `6561ae18-4b04-405b-a2b4-c75110e7289c`。最终核对时间 `2026-11-03T00:30:32.903685+08:00`。
- 本次未操作真实设备，不能将构建和分发等同于真机菜单或真实推送验收。

## 正式制品

- legacy IPA SHA-256：`3e4f9c64b4ea8b6f95e609641a69292c3298f0b0ad52395b1ebd722486807f17`；attempt `ee6c9e2b-8de3-4349-8ea4-f81483c67402`。
- successor IPA SHA-256：`5d1d7906ef335cf561f3553e4ca4d06e32c621748a8e7e90e8282423fcd64619`；attempt `7613ccf1-afca-4ae9-b98f-16bed9de1abb`。
- 两入口各 5 项制品（IPA、符号包、源码提交、SDK 依赖、安装身份）已正式保存于 Atlas，并从正式存储独立核对全部长度与 SHA-256。

## 清理

整个双入口构建使用一次 host-build-queue，两个 host-build-output 目标均 exitCode=0，各自 work 已自动清理，无 cleanupDeferred。构建后的本地适配器仅按开放文件归属释放本次闲置 ibtoold，以避免上次构建中的目录句柄导致清理延后；未修改公共构建工具或停止其他任务。work 释放空间未单独统计。

在确认 IPA 和符号文件可由正式存储恢复后，另删除本地可恢复包和导出诊断 30,569,730 字节、远端重复暂存 30,476,923 字节。只保留小型元数据、SHA 清单、精简日志和发布回执；正式制品仍由 Atlas 保存。
