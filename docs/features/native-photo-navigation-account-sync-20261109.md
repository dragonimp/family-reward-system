# 原文件、地图选择、活动首页滚动与账户数据同步

## 已实现

- Android 活动照片详情的“获取原文件”不再打开活动网页。复用 MyVnc.Realtime.Client 原生 DataChannel/HTTP 缓存 SDK，支持等待分享者批准、接收状态、长度与 SHA256 核验、按账户/空间/活动隔离缓存，以及中断后的继续获取。获取后原生显示照片，可保存至 Android MediaStore 或分享真实文件；视频交给系统文件查看器。Android 8/9 通过系统文件分享选择保存目标。
- 请求和缓存权限仍由既有活动成员/照片请求接口判断；离开照片或切换照片取消本次请求，账号改变时停止传输。只在传输完整及业务完成回执成功后提升为正式缓存文件。失败保留可继续使用的部分文件，不以缩略图冒充原文件。
- 干饭“带我过去”和收藏导航增加地图选择。Android：高德、百度；iOS：高德、百度、苹果。未安装或无法打开时提示重新选择，不自动改用内置网页。步行/驾车继承路程模式。明确传递 GCJ-02 或 WGS84，跨平台同步的地图收藏保留来源；苹果地图先解析导入的高德餐厅，无法唯一确认时提示改选，避免将 GCJ-02 当作 GPS。
- Android 活动首页的空间、好友入口和列表说明作为列表页头统一滚动，标题/更多/消息保留固定。活动详情继续使用同一整体滚动方式，照片大图/紧凑/网格均保留。
- 干饭原先两端各自维护本机档案，已增加统一的账户服务。历史选择/打卡、收藏、生活圈、自建餐厅及偏好计数现在使用相同服务端账户档案。原有本机文件保留，新缓存、基线与待发送请求写入同一原子文件，避免网络中断、进程重启或回复丢失导致重复打卡。
- 首次合并两端旧档案，后续使用三方增量合并；收藏删除墓碑阻止旧设备重新导入已取消的收藏；不同设备的计数增量合并，重试使用相同操作 UUID。语义重复 UUID 或冲突内容拒绝覆盖。移除客户端历史 300 条截断，避免将本地裁剪传播为账户历史删除。
- 进入页面、修改后和可见页面每 30 秒同步；安卓进入记录页面不取消未完成同步，记录页面可自动刷新。网络失败显示状态且保留本机内容。

## 同类问题检查

- 运动：iOS/Android 均使用 `/api/exercise/records`，共享服务端记录与删除标记，未另建平台库。本次补齐两端 GUID 大小写身份比较；活动分享继续复用相同服务接口。
- 活动：两端通过同一 `/api/dear/social` 网关访问 Linko 活动、照片元数据和评论。原文件分布在分享设备或服务器缓存是既有文件传输设计，不属于分别维护活动记录。
- 我的厨房：个人菜谱、星标和制作打卡已有服务端账户接口，本次不复制数据或改写其库表。
- 业务按领域使用其既有服务存储；本次统一的是同一业务在两端的数据源，并非把运动、菜谱和活动强行放入干饭表。
- 本次没有读取或推测 wss 手机中的记录内容，也没有伪造历史。原来仅在设备上的记录，需要该设备更新并以原账号打开干饭后上传合并；真机一致性尚未验收。

## 接口与数据库

- `GET /api/dining/account`：当前登录账户的档案和版本，`private, no-store`。
- `POST /api/dining/account/sync`：`operationId`、`baseline`、`archive`；账户从用户中心身份派生，不接受客户端指定其他用户。事务内账户锁、三方合并与持久化操作回执，重复提交不重复计数。
- `account_dining_archives`：`owner_id`、`archive JSONB`、`tombstones JSONB`、`version`、`updated_at TIMESTAMPTZ`。
- `account_dining_sync_operations`：`owner_id`、`operation_id UUID`、`payload_sha256`、`completed_at TIMESTAMPTZ`；账户+操作唯一键。
- 独立迁移 `scripts/migrations/20261109-account-dining-sync-v1.sql`，SHA256 `0867c2366dbfe5edb15d271e326d177c3775fdb5b5044c7e232fd3fc777a85ad`。无应用启动迁移或生产回填。
- 已在发布前完成 PostgreSQL 全库备份和恢复清单核对；迁移账本与表归属读回正确（family_reward_app），迁移后档案表为空，没有改写旧数据。备份和迁移回执保留在服务器受限目录。
- 回滚可恢复原服务版本并保留新增表，不删除已同步用户数据；数据库备份仅供受控恢复。

## 文件范围

- 后端：FamilyReward.Api/DiningAccountEndpoints.cs、Program.cs、FamilyReward.Api.csproj，shared/DiningSyncMerge.cs。
- Android：DiningModels.cs、DiningPanel.cs、DiningSyncState.cs、ExerciseSync.cs、MomentActivityPanel.cs、MomentPhotos.cs、MomentOriginals.cs、MomentOriginalContract.cs、FamilyStore.cs、LinkoFamily.csproj，Platforms/Android/AndroidManifest.xml、MomentMediaLibrary.cs。
- iOS：DiningView.swift、DiningModels.swift、ExerciseView.swift、Info.plist、HappyLifeParent.xcodeproj/project.pbxproj，版本目录及中英文语言资源。
- 验证/构建：tests/DiningSync、tests/Dining、tests/MomentAndroidModels、parent-app/ios/Tests/DiningModelTests.swift，scripts/check-dining-sync.sh、build-moment-android-release.sh。

## 已测试

- 真实隔离 PostgreSQL + HTTP：17 项，覆盖匿名/服务身份拒绝、大小写 GUID 身份、旧设备导入、UTC 时间、幂等重试、操作 ID 冲突、取消收藏墓碑、重新收藏、并发收藏、离线计数合并、非法数据、账号隔离、no-store。独立迁移重复执行跳过。
- 干饭 C# 模型/HTTP检查、Swift 菜谱外出用餐模型与离线同步信封持久化检查通过；早餐/午餐/下午茶/晚餐规则未改动。
- 原文件请求契约检查通过：过期、超限、错误协议、错误 SHA 和非媒体格式拒绝；既有 GUID、日期、扫码模型检查通过。
- 运动 HTTP/存储及契约回归通过，覆盖幂等、摘要补充、权限、GUID、轨迹、删除标记。
- 公共活动服务 272 项 HTTP/WebSocket 检查、用户中心通知 19 项检查通过；后端构建、前端 lint/build 通过。
- iOS 1.3.48（248）签名 IPA、原生模型与签名/包身份校验通过；Android 1.0.23（32）正式签名 APK 构建与版本/证书校验通过。
- 全仓 iOS 本地化检查仍被既有 HappyLifeParentApp.swift 未本地化文案阻塞；本次新增文案已加入中英文目录，保留目录外既有翻译，没有删除旧资源。该项不标为全量通过。

## 未验证

未连接登录后的真实手机：wss 两端历史合并、原文件实际跨设备接收/保存/分享、各地图实际跳转和接收终点、活动页面完整滚动手势均未宣称实测。源码、构建、发布和用户设备验收分别记录。

## 官方协议参考

- 高德 Android 路径规划：https://developer.amap.com/api/amap-mobile/guide/android/route
- 高德应用调起：https://developer.amap.com/api/amap-mobile/gettingstarted
- 百度 URI：https://lbsyun.baidu.com/index.php?title=%E6%A8%A1%E6%9D%BF%3Auri%E7%9A%84iOS
- Apple MapKit：https://developer.apple.com/documentation/mapkit/launch-options-dictionary-keys

## 发布证据

- 后端源码 `29279df510197c6633ca5fff85426a15c145d10f`，Atlas版本 `20261109-132932-activity-29279df`，发布ID `59661f24-bedb-4605-93b5-cf694437f6a6`。
- 部署 `3b24a6dc-1c57-431e-9955-4b12f6f4b5ae`，complete=true、stored_and_verified、exitCode=0。独立读回运行指针与本机版本端点匹配，服务 active/running，公网 /health 正常，新同步接口匿名 401。
- iOS源码 `f3cd5ba1cf3cce4f66027c9df1de856d2856c8e0`，Atlas版本ID `65f46698-0cd0-48da-bfd1-ff1fdc565802`，IPA SHA256 `66293dea35d6bdfa21bf473205a21d7553e8b152a9aa5a28464fa11c32dbeae7`。TestFlight尝试 `5e6ae485-2e42-4231-8d29-6fc9864aa47a`，处理状态另行追加。
- Android最终源码 `74acdd1bf6754831f02a177efb854c7878e1c021`，发布与邀请入口读回另行追加。

### 最终发布读回

- Android：Atlas版本ID `565bce76-414c-408e-a1e1-32617d32ce16`，1.0.23（32），APK SHA256 `b3d7d25682a288067c904d575cfe8d3ee258aabc24764cb73fdcf13f04cef7c0`，30,529,466 字节。包内 arm64 Connect DataChannel ABI 符号与许可文件已核对。
- iOS：Apple 构建 `9987b289-3ca9-4a66-aad5-b2873f1731a0`，VALID / testflight_visible，内部测试组可见。中英文测试说明更新操作 `c469f428-6e3f-490d-9572-a347ed597288`，独立材料读回 HTTP 200、ready=true、issues=[]，目标构建图标已由 Apple 提取。未提交外部 Beta 或 App Store 审核。
- iOS邀请同步 `c948ed20-f6f5-458d-bd54-202eb02da9f4` verified；Android邀请绑定 `94d34181-144d-4e03-85d8-c66ccac24578` verified。公开邀请数据独立读回 iOS 1.3.48（248）/Android 1.0.23（32），保留其他平台和旧外部邀请入口。
- 更新入口：https://home.ai.impx.net/invite/SW2wL0kd3pX20t6xSNLXsDK4
- 所有发布源码已推送 GitHub origin/main，各平台构建提交均被主分支包含；没有创建额外 worktree。保留原未跟踪 application/ocr_recipe.py。

### 缓存身份扫描候选

运动两端的服务端身份查询及本次会话守卫使用 GUID 语义，但既有运动本机文件名仍由原始身份字符串派生。若历史上同一设备实际收到仅大小写不同的身份值，可能形成多个本机缓存键；本次未观察到 wss 的此类设备证据，不能认定历史数据已经损坏，也没有自动改写或合并本机历史文件。服务器记录的 GUID 大小写、账户隔离和删除回归已通过；该缓存路径候选需要设备历史核对后再决定独立迁移。

### 清理与保留

服务端三个包、iOS IPA及符号包、Android APK和两类构建回执均已从 Atlas 独立下载核对 SHA256 与大小。正式包、符号和回执保留在 Atlas，可恢复；本机保留精简构建/测试/来源清单及下载校验回执，生产数据库备份保留在受限目录。构建包装器已清理本轮临时源码与编译目录。

本轮清理本机重复与未分发中间包共 287,195,506 字节；同时删除对应远端上传暂存包，没有删除 Atlas 正式制品、生产运行数据或其他任务文件。
