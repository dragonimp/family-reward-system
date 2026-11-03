# 再次打开本机原件的读取性能

## 定位

代码的 SharedPhoto 索引包含 assetIdentifier、原件副本路径、长度和 SHA-256，并通过 writeIndex 原子写入 Application Support 下的账号目录。源码证明存在持久化逻辑，不等于已经读取并确认 wzs 手机上的实际索引文件。

已确认的性能缺陷：localOriginal 每次打开都完整计算副本 SHA-256；availableOriginal 接着再次计算同一文件 SHA-256。列表与详情都会经过这条路径，重启后仍然重复，文件越大成本越高。此缺陷不要求索引丢失也会出现。未把源码观察当作现场耗时剖析。

## 修复

新增账号内持久校验记录，绑定文件路径、设备/文件身份、长度、纳秒级修改及变更时间和预期 SHA-256。未变化的已验证文件直接复用，重启后亦然；文件变化或记录缺失时重新完整计算并比对 SHA-256。同大小内容变化并恢复 mtime 仍由 ctime 触发重验，文件替换通过 inode/时间变化重验，符号链接拒绝。

并发读取相同文件合并一次实际校验。列表第二次校验命中同一记录，避免再次读取整个文件。不规范化业务账号、路径或令牌，不修改媒体、Photos 原件或生产来源设备记录。

版本 1.2.92（101），源码 `8b007b055443927f3129a30fb7c3f48d3a1f0a6f` 已核实推送至 origin/main；专项检查通过，Apple 实时 refresh 已确认两个安装身份均为 `VALID / testflight_visible`。本次未读取 wzs 手机的实际索引文件，实际设备冷启动和再次打开的耗时尚未现场复验。

## 专项检查

- OriginalFileVerifierTests：并发打开只校验一次；重新实例化校验器从磁盘读取记录，未变化文件新增完整校验次数为零；同大小文件改写并恢复 mtime、原子替换、符号链接、错误大小/原件版本和文件缺失均覆盖。
- check-local-originals：真实解析器及 PhotoKit 边界夹具检查通过，包含照片和视频、相册索引、副本恢复、其他设备隔离、禁止自己下载、历史索引复用及错误字节拒绝。
- NativeModelTests 基础检查通过。所有 Apple 构建/测试通过统一主机队列，曾因其他任务实际占用而排队，没有停止其他任务或绕过锁。

## 发布制品与清理

两个安装身份的签名 archive/export 及版本检查通过，构建 latest.json 均 exitCode=0。10 项正式 IPA、符号和元数据已在 Atlas 存储逐件核验长度及 SHA-256。核验可恢复后清理本地重复包/导出日志 31,157,739 字节及远端重复暂存 31,063,376 字节，work 已清理；保留正式存储和小型回执。

- legacy 任务 `16d3d828-c8fb-4366-9856-c0907d6d2ab0`；IPA SHA-256 `4a2091d27b6ede46bb3894bbb66d90ef221bf55c90ac08c8d7ac4d159bdadb2e`。
- successor 任务 `1a117397-d478-4d98-acf0-2c57c4a0ee9d`；IPA SHA-256 `02c192fc12011dd9755b22c7d4040ee0903e7dd8b53dfff09fdea2bcec4035f0`。

没有新建 worktree，没有修改无关 Android、AGENTS.md 或生产媒体归属数据。

## TestFlight 最终读回

1.2.92（101）两个安装身份均 `VALID / testflight_visible`，测试组可见：

- legacy Apple build：`e87c7881-2b20-42ff-b6bb-888936ca1312`。
- successor Apple build：`a3ca5c1a-2914-47e5-a3b0-2653edf78321`。

全程跟踪同一发布任务，没有重复上传或重放生产数据修正；未提交正式 App Store 审核。发布源码 `8b007b055443927f3129a30fb7c3f48d3a1f0a6f` 已在正式 GitHub main 验证可恢复。首次生成校验记录仍需完整读取一次，已有文件内容变化时也会重验；没有以缓存记录替代变化后的原件真实性检查。
