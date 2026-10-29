# Linko Moment Apple Watch 端

当前唯一发布入口是 `parent-app/ios/HappyLifeParent.xcodeproj` 的 `HappyLifeParent` scheme。归档 iPhone App 时同时嵌入 Apple Watch App。

本目录的 `HappyLifeWatch/` 保存仍在使用的 SwiftUI、API、状态与图标资源；iPhone 工程的 Watch target 直接引用这些文件。手表可独立联网运行，但不作为单独的 Apple 应用提交。

`verify.sh` 运行共享 Watch API 与状态测试。完整的 iPhone + Watch 构建及嵌入验证使用 `parent-app/ios/verify.sh`。旧的独立 watchOS Xcode 工程及其单独归档、导出脚本已经移除。旧版发布记录保留在项目历史文档中。
