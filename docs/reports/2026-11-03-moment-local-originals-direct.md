# 本机照片及视频原件直读

## 行为

- 列表、地图、详情、播放及批量原件操作复用同一本地解析器。原件副本仍在时直接使用；副本丢失时通过保存的 PHAsset localIdentifier 查询对应系统相册资源，按长度及 SHA-256 校验后交给图片显示、AVPlayer 或文件导出。相册资源通过 PhotoKit 写到 App 私有文件以供 AVPlayer/分享读取，不创建网络下载请求，不上传 relay。
- 缺少相册标识的旧本机分享自动在已授权范围按指纹恢复索引并保存资源标识，后续直接定位；旧记录恢复串行执行，防止同时反复扫描同一相册。单次会话失败项不在每次列表重绘时重复扫描。活动菜单移除手动匹配入口。
- 仅当前账号的已登记本地分享，或服务端明确指向本机且属于当前账号的分享，可以触发自动历史索引恢复。不能因为用户名相同就扫描其他设备来源。GUID 使用 UUID 比较，包含大小写变体。
- 本机来源无可读原件时不创建向自己的下载请求，提示相册权限及原件是否存在；未授权时走系统 Photos 授权。仅 iCloud 有文件时不偷偷联网下载。其他设备来源沿用原下载流程。
- 照片详情优先原件，视频直接播放本地原件，视频列表预览也从本地原件生成。来源设备请求的自动供给同样使用本地解析器，避免副本丢失后要求手动匹配。
- 异步读取按账号会话 generation 隔离；退出或切换账号取消读取，返回时再次核对会话。修正 OriginalResourceFingerprint 显式初始化器，使跨文件检查与真实构建契约一致。

## 验证

`parent-app/ios/Tests/check-local-originals.py` 编译真实本地解析器、下载方法的网络前置逻辑及 PhotoKit 匹配器，只有操作系统边界使用夹具。已通过照片及视频直接索引、丢失副本恢复、保存相册标识、UUID 大小写、禁止自己下载、权限拒绝、其他设备隔离、旧分享自动恢复后不再次扫描、文件字节变化拒绝、禁止 iCloud 网络等检查。

iOS 版本 1.2.90（99），源码提交 `956edcd0c9f9d009295850db8147356c6aed4f0a`。两个安装身份已通过统一主机串行队列完成签名 archive/export，原生模型、相册匹配及 SDK 通知 HTTP 检查通过；Apple 实时 refresh 已确认两个身份均为 `VALID / testflight_visible`，可在各自 TestFlight 测试组更新。没有重新执行 wzs 生产来源设备修正，也没有重放原下载请求。

wzs 原件手机未连接，本次不宣称该手机真实相册、权限提示或视频播放已现场验收。

## 制品和清理

10 项 IPA、符号及身份/源码/SDK 清单在 Atlas 正式存储逐件核对长度和 SHA-256，确认可恢复后删除本地重复包及导出日志 31,038,828 字节、远端重复暂存 30,944,598 字节。构建 work 已清理，保留检查日志、小型元数据和校验清单；共享 RTC 库、其他任务工作树和未提交 Android 改动均保留。

- legacy IPA：`54e2091faee411a8bb0101ffd0ad40ebab7b3d7c4e79d43014ae60fcf54ad62e`；发布任务 `4854f1cd-ec85-4221-97be-e89f250dbc59`。
- successor IPA：`3537fce0d93e5a6681b98cac80f69cd4f3545caa86e6d7674798e57feb2aa641`；发布任务 `3a4366ff-1350-4399-8583-cace695abc44`。

## TestFlight 最终读回

- 版本：1.2.90（99），未提交正式 App Store 审核。
- legacy：`VALID / testflight_visible`，Apple build `2b95aef6-49bd-48c7-837e-180f9e74a83b`。
- successor：`VALID / testflight_visible`，Apple build `4e3f9a64-c946-4f43-bb95-bf865e5669b8`。
- 源码 `956edcd0c9f9d009295850db8147356c6aed4f0a` 已在正式 origin/main 独立核实；沿用同一发布任务至完成，未重复上传。各构建 latest.json 均 exitCode=0，无遗留 work。
