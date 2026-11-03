# 活动分享页入口顺序调整

入口改为“在 App 中打开 → 安装测试版 → 继续网页版 · 进入活动”，移除旧版 Linko MomentX 提示和独立旧版按钮，保留微信系统浏览器指引。仅修改公开介绍页面，无需更新 iOS。

源码 eccdf3d9335e7195f490a6c107e2e93ca1a75a4a 已推送 origin/main。24 项 HTTP 页面检查及微信/Safari 点击行为检查通过；服务构建完成 13 项通知和 223 项 HTTP/WebSocket 检查，前端 lint/build 通过。

Atlas API/Web 已激活版本 20261103-135143-activity-eccdf3d，操作 family-pipeline-20261103-135143-activity-eccdf3d-api。公网 version.json 及实际公开活动 HTML 独立核验通过：按钮顺序正确、旧版提示消失、微信指引保留。没有重新执行生产数据修复。

3 项服务正式制品 SHA-256/长度经独立校验后，清理本地和远端重复压缩包各 19,010,075 字节，统一管理器已清理编译工作目录。保留小型清单、测试和部署回执，正式包可从 Atlas 恢复。未修改其他任务的 Android/AGENTS.md 内容。
