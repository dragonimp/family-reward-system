# Moment 系统相册自动匹配原件

目标：无需为每张历史照片重复选择文件；已有原件自动匹配，未找到时才保留手动入口。

## 行为与范围

1. 已缓存的照片直接走现有服务器缓存，不触发相册扫描。
2. 待传输请求先核对当前账号 App 的原文件目录；没有匹配文件时，在已有 readWrite/limited 授权的范围内自动扫描本机相册。没有权限时，仅在点击“自动匹配本机与系统相册原件”后发起系统授权；拒绝时保留系统设置和单文件选择入口。
3. 以请求中的文件长度和 SHA-256 核验，不依赖昵称、设备型号、文件名或缩略图判定。分块读取，超出目标长度即取消，避免为每个候选读取完整大视频。只导出匹配原件，导出后再次核验，再通过既有 Connect SDK 上传并接续原请求。
4. 记录每个资源的标识、修改时间和完整指纹，按账号隔离，最多 20,000 条；后续扫描复用。导出时仍重新核验，缓存过时不会导致错误共享。
5. 扫描、哈希、导出及大文件复制在 utility executor 执行，主线程只更新进度和索引。离开请求页或退出账号会取消匹配。未匹配到文件时保留等待请求，不提前写 unavailable。
6. 仅读取系统允许的范围，不修改或删除系统相册资源，不自动下载整库云端原件。云端文件需先下载到本机；编辑、转码后字节变化的文件不会被当作同一原件。

## Apple 契约

使用 [PHAssetResourceManager requestData](https://developer.apple.com/documentation/photos/phassetresourcemanager/requestdata%28for%3Aoptions%3Adatareceivedhandler%3Acompletionhandler%3A%29) 读取原始资源，而非重编码的显示图片。资源请求明确关闭 [isNetworkAccessAllowed](https://developer.apple.com/documentation/photos/phassetresourcerequestoptions/isnetworkaccessallowed)。limited 授权只处理可访问资源；设置 [PHPhotoLibraryPreventAutomaticLimitedAccessAlert](https://developer.apple.com/cn/documentation/photos/phauthorizationstatus/limited) 避免每次启动重复自动弹出照片选择提示，并提供主动调整访问范围的设置入口。

## 验证与发布

- 原生流式指纹检查通过：多块拼接与 SHA-256 已知向量、大小写、错误哈希、截断及超长拒绝。
- Swift 解析、现有原生模型、日期与运动会话检查通过。
- `parent-app/ios/Tests/check-library-originals.py` 直接编译实际匹配器，替换 PhotoKit 回调边界为确定性资源：拒绝访问时不读取、不同名正确原件匹配、同名不同内容拒绝、超长取消、云端跳过且网络关闭、持久指纹复用、过期指纹导出重验及进行中请求取消均通过。测试替身不替代真实 iPhone 的相册授权/资源验收。
- 包校验增加相册用途描述与 limited 提示配置检查。
- 原生源码 `9cd23263e729fd195084f78094edb0b4822eb970` 已独立核对包含于 origin/main；首次构建源码 `390a72c` 仅用于编译验证，正式制品采用后续的异步复制修正提交。
- iOS 版本 1.2.85（94），双入口签名构建和正式 Atlas 制品校验通过；legacy 已读回 VALID/testflight_visible，Apple build `092cddb9-b23b-41ac-821d-d6e45f98ed0d`，successor 仍待 Apple 处理。未更改后端契约或再次执行历史设备迁移。
- 本次未在 wzs 的 iPhone18,1 上验证真实相册匹配；不能将流式校验单测、构建通过或发布完成等同于该设备的原件恢复已完成。

## 正式制品与清理

- 两个正式签名包来自 9cd2326，均已验证 App Store 分发签名、Bundle ID、内嵌 Watch/Share Extension 版本、相册用途描述与 limited 配置；正式 Atlas 存储分别 4 项制品的长度和 SHA-256 已独立核验。
- successor IPA SHA-256：`3845fbe987ef178fe6d33443b2b163437b7a7bdbb776b0d76e04f2ccc123cf1f`；Apple attempt `c893cb06-5682-4bb7-8a78-94abd6ceb90f`。
- legacy IPA SHA-256：`adfcab1f858f301a613982a79aeac4c2d657cbbeb8f62f541ce5ab5d55556844`；Apple attempt `18dfb9b6-ae1d-4e17-acd5-49dcecf4f37e`。
- 本地正式输出：`~/.codex/build-outputs/family-reward/ios-library-185-ready/runs/20261102-083730-068e9bb27e99/output/`。
- 原始签名过程返回后，管理器部分 run 因子进程/开放文件检查延后清理；已在进程组和文件均不活跃后完成定向清理。首轮旧源码构建不用于发布；为纳入异步复制修正，停止了本任务的旧 legacy 构建并以新提交重新构建。仅操作本任务登记的进程组和目录。
- 回收本轮闲置中间目录及重复 IPA/符号包释放本地 1,041,692,173 字节；删除已正式归档的远端暂存重复文件释放 30,499,196 字节。保留正式 185-ready 输出、精简日志、SHA-256 清单和 Atlas 发布回执。
- 08:35 左右只读复核：此前两条卡住的历史请求仍为 waiting，精确租户/活动/照片作用域的服务器原件缓存均存在；不要求分享者重新选择这两张原图。

## 真机检查边界

08:43—08:44 在现有测试 iPhone 13 Pro（iPhone14,2）通过 TestFlight 从 1.2.84（93）更新到 legacy 1.2.85（94），正常启动并恢复原用户中心账号，系统通知登记状态成功。打开实际“相册照片.jpg”下载请求，显示缩略图、请求人及“原文件已就绪，等待请求人打开 App 接收”，没有弹出文件重选或相册授权。测试结束返回活动列表并释放主机构建/设备队列。未修改系统相册权限、未重新选择或重新共享该用户文件。

此验证证明已缓存请求不要求重选文件，不等同于在真实系统相册完成首次自动扫描、匹配和上传；相册匹配部分的当前证据是正式签名编译、流式哈希检查和实际匹配器的确定性回调测试。wzs 所用 iPhone18,1 的真实相册原件匹配仍未直接验收。

另独立复核 1.2.83/1.2.84 双入口的 16 项历史正式制品在 Atlas 存储中的 SHA-256 和字节数，回收本地历史 IPA/符号包 60,498,571 字节，仅保留必要元数据、发布回执以及当前 1.2.85 正式输出。原生 RTC 共享库仍保留为构建依赖。

## Apple 处理与限流记录

successor 于 08:49 遇到 App Store Connect `apps` 查询 HTTP 429 / RATE_LIMIT_EXCEEDED，Atlas 将该次状态核对记为 failed；Apple 上传 ID `7e1e8328-22eb-4e13-a7e2-837134233f58` 已存在。核对 Atlas 正式恢复契约并等待冷却后，使用同一 attempt 的 refresh 读取原上传任务，恢复为 apple_processing，错误已清空；没有新建 attempt、重传 IPA 或绕过限流。08:52:43 的后续正式读回仍为 UPLOAD_PROCESSING，worker 继续处理，尚未将 successor 宣称为 TestFlight 可见。legacy 已 VALID/testflight_visible 并在测试机安装确认；已就绪入口可独立使用。

08:53:53 后续核对再次收到相同 `apps` HTTP 429，successor attempt 当前为 failed（状态查询受限，不能据此判断 Apple 原上传制品失败），尚无 apple_build_id，未确认测试组可见。保留同一 attempt/upload ID 及正式制品，不再高频重复恢复或上传；限流解除后需以同一 attempt 的正式 refresh 恢复核对。此次交付边界为：自动匹配功能实现与检查完成，legacy TestFlight 可见且已安装；successor 分发尚未完成。本任务未改动 Atlas 服务或其他应用的发布任务。
