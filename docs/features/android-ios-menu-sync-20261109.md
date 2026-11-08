# Android / iOS 菜单对齐与账号栏目同步

## 范围与页面对照

以当前 iOS 源码为准：保留 1.3.44 已迁移到「我的」的连接手表入口，同时修复用户提供的六张截图中的差异。Android 最终目标1.0.19（28），iOS同步设置版本1.3.45（245）。未修改既有积分、照片、手表配对或家庭成员的权限。

| 页面 | 调整 |
|---|---|
| 底部导航 | 干饭、带娃、活动、运动、我的；默认五栏，用户可关闭前四栏，「我的」不可关闭 |
| 干饭模式 | 出去吃 / 下厨房改为并排分段按钮，切换保留内容状态 |
| 出去吃 | 推荐 / 附近 / 常去 / 随机；位置与筛选并排，橙色推荐卡；口味、食物类型和路程集中到筛选页；打卡、记录收藏、生活圈、重新定位放右上菜单 |
| 用户与权益 | 公共账号组件、修改密码、账号注销、套餐权益、消息中心、语言设置 |
| 应用与设置 | 连接手表、扫码登录、栏目启用、AI对话、家族族谱、家庭成员、邀请家人、通知照片位置权限 |
| 活动列表 | 保留空间与活动列表；截图中的iOS活动详情不等同于Android列表，不能删除列表来伪造一致 |
| 活动详情 | 日期/成员、共享位置开关、活动地图、分享/拍照/拍视频/打卡/创建运动、大图/紧凑/每行5张网格；紧凑保留打卡和日常，不再仅显示照片 |

「附近」按距离挑选、「随机」等权挑选，仍只处理原有时间、类别和路程筛选后的候选。早餐、午餐、下午茶、晚餐规则没有改动。

## 复用与功能边界

账号第一行继续使用 AgentIdentity.Maui.UserCenterAccountRow。语言与消息中心继续使用既有用户中心组件/SDK，普通网页使用公共 InAppWebLinks；未复制登录、聊天或账号管理体系。

AI对话、家族族谱和家庭成员复用现有正式站内页面。扫码入口用Android相机拍摄二维码或选择相册图片，端内ZXing解码，仅接受正式应用同源 /auth/native/approve 和严格64位小写十六进制挑战ID，用户仍须确认并进入既有服务端审批页。它不是iOS的实时取景扫描界面。扫码临时图片不上传服务端。依赖为 [ZXing.Net 0.16.11](https://www.nuget.org/packages/ZXing.Net/0.16.11)。

照片/视频原文件共享继续复用现有完整活动Web组件；分享、拍照、拍视频入口会明确提示进入应用内完整活动页完成，未声称已实现Android原生P2P文件传输或与iOS完全相同的拍摄交互。

活动打卡复用既有接口，服务端实际位置/海拔要求不变，同一次失败重试保留同一requestId。共享位置复用已有租约接口，明确开启后仅在前台更新，离开模块或应用进入后台关闭租约；不会默认共享位置。地图使用已授权活动成员/打卡位置，底图为OpenStreetMap，不虚构坐标。

## 栏目启用账号同步

新增 account_module_preferences：owner_id、sections JSONB、version BIGINT、updated_at TIMESTAMPTZ。使用签名人类身份主键，GUID在入口类型化解析为统一D格式，业务字符串不统一改大小写。客户端不传owner、不按家庭组存设置，不与全局语言偏好另建副本。

- GET /api/user/module-preferences：读取当前账号配置，未初始化只返回默认值，不写数据库。
- POST /api/user/module-preferences/bootstrap：首次设备设置同步，导入显式保存的旧本机开关；已存在账号配置时只返回已有值，不覆盖。
- PATCH /api/user/module-preferences：key、enabled、expectedVersion，按版本原子修改单个栏目。冲突返回409，客户端刷新并提示核对；不静默覆盖其他设备修改。

两端移除AppStorage/Preferences作为栏目配置权威来源，改用同一API。首次同步仅导入有显式值的旧设置，未保存的旧Android默认“隐藏带娃”不再继续隐藏；账号尚无配置时默认五栏。多台旧设备的显式值有冲突时，以最先成功同步的配置为准，之后用户在任一设备修改即可同步。

本机缓存按账号隔离，旧全局配置仅允许当前设备首次迁入的账号使用，不会迁入后续其他账号。正常前台每10秒读取，回到前台/设置页主动刷新。修改失败不会伪装为已保存。需要两端升级到本次版本才具备这一同步能力。

独立迁移 scripts/migrations/20261109-account-module-preferences-v1.sql 仅创建表，使用既有部署迁移账本、SHA256、事务和备份规则；应用服务启动不建表、不批量改用户配置。按用户认证请求导入当前设备选择属于设置同步，不是服务启动时覆盖生产配置。

## 文件

- FamilyReward.Api/ModulePreferenceEndpoints.cs、Program.cs
- scripts/migrations/20261109-account-module-preferences-v1.sql、scripts/check-module-preferences.sh
- parent-app/android/FamilyPage.cs、FamilyStore.cs、MomentStyle.cs
- parent-app/android/DiningPanel.cs、DiningModels.cs
- parent-app/android/MomentActivityPanel.cs、MomentActivityLocations.cs、MomentActivityMapPage.cs
- parent-app/android/MomentLoginScanner.cs、MomentModels.cs、Platforms/Android/AndroidQrImage.cs
- parent-app/android/LinkoFamily.csproj、scripts/build-moment-android-release.sh
- parent-app/ios/HappyLifeParent/FamilyStore.swift、HappyLifeParentApp.swift
- parent-app/ios/HappyLifeParent.xcodeproj/project.pbxproj
- tests/ModulePreferences/ModulePreferences.csproj、Program.cs
- tests/Dining/Program.cs、tests/MomentAndroidModels/Program.cs

## 验证

真实隔离PostgreSQL + HTTP：匿名/服务身份拒绝、默认配置、显式旧值导入、第二设备不覆盖、双向读取、GUID身份大小写、过期版本拒绝、不同栏目不清空、8个并发同版本修改仅1个成功、账号隔离、「我的」不可关闭、类型校验及no-store；独立迁移回放跳过。现有干饭HTTP/模型和Android日期/GUID模型检查，并新增附近/随机和二维码边界检查。

iOS与Android初步编译通过。正式构建/发布及上线结果另行追加。编译、签名、平台可获取与真机菜单操作/真实设备同步分开验收，不将API模拟设备结果写成真机验收。

安卓位置共享离开模块或进入后台时，租约和开关一起关闭；回到页面不会显示错误的“仍在共享”状态。1.0.18（27）作为首个已验证中间包保留在Atlas，最终分发采用1.0.19（28）。


## 发布与收尾结果

- iOS 1.3.45（245），源码a38844584092e8439f3786be87ac83f663487752；Atlas版本febb1246-5bcc-40b7-acea-78ea7bcb1885。TestFlight尝试56236e79-7ac2-4b57-8dcd-c271ee3cd0cc，Apple构建d45410e2-16e1-4c6b-8a23-b3c3bde35a6f，已VALID/testflight_visible。
- 已通过正式材料API补充中英文测试说明，操作b1367e93-2c61-4a44-b4ee-d722b5e6ef4e；独立读回HTTP200、ready=true、issues=[]，包括目标构建图标。未提交外部Beta或App Store审核。
- iOS邀请同步21f53623-17b2-4099-95ce-b7c5b6bd4f26 verified。Android最终1.0.19（28），源码34b637376073bf1c3f7c7711c46806aee33a687e，Atlas版本8d4ac2fd-cb63-40ee-ae7d-9284094c37ba；APK SHA256 8772353ef00e28cd6c15b4950ddfad8f11f737e28a431b2d70032fc4707d8fe0，原正式签名及manifest校验通过。邀请绑定3f41c53f-ff2a-41e7-993b-87819bd960e2 verified，公开邀请数据读回iOS1.3.45（245）/Android1.0.19（28）。
- API版本20261109-003340-activity-a388445，Atlas版本af0f5007-734a-444a-8175-2df0934f1ba7；部署429638f1-3543-4aae-b220-9c2e4ce5ec41 complete=true/stored/exitCode=0。日志、运行指针和健康独立读回；设置接口未登录返回401。
- 生产迁移先备份并核对pg_restore清单，账本20261109-account-module-preferences-v1，SHA256 7319624d626d6d31fb256a804fbd5fc86917c90b1e1e501973de45699739d1ed，新表归属family_reward_app。迁移没有批量写入用户设置，原始表为空；首次设备同步由已认证用户请求完成。
- 同步API14项检查通过，干饭推荐/日期/GUID/二维码模型检查通过；iOS/Android正式签名包成功，前端lint/build与配套267项HTTP/WebSocket通过。
- Android1.0.18中间包已在自有ARM64模拟器升级安装、动态解析launcher并冷启动，Status:ok、崩溃缓冲为空。界面停在首次隐私确认，未进入登录后菜单；没有替用户确认隐私协议，也没有宣称菜单截图或真实双设备同步验收。最终1.0.19仅做增量正式构建与签名/版本校验，未重复称已安装实测。
- 模拟器已退出，adb无设备；QA子脚本exitCode=0，但外层首次因后代进程释放延迟记录cleanupDeferred，原错误保留，后续核对工作目录已不存在且无自有模拟器进程。该清理状态不改写为UI验收成功。
- 14个正式制品182,370,492字节已从Atlas重新下载并核对SHA256/大小。清理本地7个重复包182,368,937字节，正式包及符号包可由Atlas恢复；保留精简回执、QA启动记录、受限数据库备份及独立迁移。没有新增worktree，原未跟踪application/ocr_recipe.py未提交或删除。
