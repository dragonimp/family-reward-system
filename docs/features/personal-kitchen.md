# 个人厨房（2026-11-08）

## 实现范围

iOS `MyKitchenView.swift`、Android `MyKitchenPage.cs` 实现我的厨房、个人列表/搜索/全部与星标与上传筛选、原始图片、食材步骤详情、编辑/删除私有菜谱、公共菜谱收藏/取消、个人星标、拍照/相册/手动创建、识别记录恢复、结构化编辑确认、做菜照片打卡、历史/次数及手动关联。首页仅扩展右上角更多菜单；原有分类和随机选择布局、时间权重和出去吃逻辑保持不变。公共做法页加入一个进入个人操作的入口，完成/分享位置保留；私有菜谱不生成公开分享页。

复用 FamilyStore 认证、原生相机/相册、系统导航与既有样式；iOS 公共相机包装由 private 调整为模块内可复用。Android 媒体始终由已登录的 HttpClient 下载并校验会话世代，不把令牌放入图片 URL。

## 数据与存储

独立迁移 `scripts/migrations/20261108-personal-kitchen-v1.sql` 由现有部署迁移运行器执行，备份、SHA256、持久账本、事务与 advisory lock；启动不建表或修改历史数据。PostgreSQL 原生 UUID；owner_id 来源为认证人类用户的签名身份主键，GUID 身份在入口规范化，业务字符串不统一改变大小写。

新增五张表：

- kitchen_personal_media：owner_id、purpose、JPEG BYTEA、SHA256、created_at。上传源图和成品图均存 PostgreSQL，客户端将照片规范化为 JPEG，最长边1600；不保留相册原始 HEIC 文件。只通过当前用户认证 GET /api/kitchen/media/{id} 读取，不存公开 static 目录。服务端限制8MiB/2400万像素，单用户200MiB；不修改既有公共图。
- kitchen_personal_recipes：owner_id、body JSONB、original_media_id、recognition_id、source_text、ai_result、version、created/updated/deleted_at；默认私有。body 包含食材、数量/单位（字符串允许“适量”和未知空值）、准备工作、有序 steps（编号/动作/食材/时间/火候/说明/注意事项）及菜谱时间/人数/难度。未知时间人数用 null，不推测。
- kitchen_user_recipes：owner_id/recipe_id、kind、favorite、starred、updated_at。公共菜谱主体仍只在 kitchen_recipes，不复制。
- kitchen_cooking_checkins：客户端稳定 id、owner_id、recipe_id/kind、cooked_on DATE、media_id、note、菜名快照、request_hash、created/deleted_at。食谱详情自动传 recipe_id；直接拍照可选择已有公共/个人菜谱，或先创建。次数由有效记录 count(*) 派生；删除同步减少。相同操作重放不重复计数，改变载荷冲突，新操作新 UUID。
- kitchen_recognition_tasks：owner_id/username/media_id、state/result/error、created/updated_at。result 保存 AI 原始响应与结构化草稿/uncertainFields；确认保存后 private recipe.ai_result 另保存识别来源快照，body 是用户最终修改后的内容。

制作日期只表达用户选择的日历日期，不做 UTC 换算；created/updated 时间点使用 TIMESTAMPTZ。Android 识别记录显示设备当地时间。

既有活动照片打卡依赖活动成员和定位，是不同业务，未将其自动导入或伪造关联。厨房历史允许 recipe_id 为空并由用户 PATCH 明确关联；当前没有可确定属于做菜的旧活动记录可迁移。

## API（全部 /api/kitchen，已登录人类用户）

GET /catalog：可选公共/自己私有菜谱；GET /recipes?filter=&q=；GET /recipes/{id}?kind=；PUT /recipes/{id}（confirmed/version/recipe/来源及图片识别引用）；DELETE /recipes/{id}；PUT /recipes/{id}/relationship。

POST /media：稳定UUID/purpose/base64 JPEG；GET /media/{id}：私有JPEG。

GET /checkins；PUT /checkins/{id}；PATCH /checkins/{id}/recipe；DELETE /checkins/{id}；GET /cooked：派生累计次数。

POST /recognitions：稳定UUID/mediaId；GET /recognitions：最近20个自己的任务；GET /recognitions/{id}。入队与结果查询独立，页面离开仍执行。

## AI 配置与边界

复用 AgentFreeGatewayConfiguration 和 Goldfish.WebAppSdk。SystemConfig.agent.kitchenWebAppBotId 可指定厨房入口，未设置使用 Orbit 默认 WebApp 授权范围；kitchenAgentId 可明确选择当前用户已授权且活跃的目标，未设置选择当前用户自己拥有的 Goldfish 实例。原积分专用 bot 不适用于菜谱，保持其配置不变。未新增模型密钥或直连模型服务。传入的是私有 JPEG dataURL 附件，不暴露下载地址。要求所授权智能体支持图片理解并能输出结构化 JSON；没有授权、模型不支持图片或响应不合法时保留失败状态，用户可重试或手动填写。

worker 异步领取持久任务（FOR UPDATE SKIP LOCKED），单任务3分钟预算，重启遗留 running 超过10分钟标失败供用户重试。每用户每天10次、图片/任务入口20次/分钟。会话专用于本次识别，结束后停止并归档，不触及其他用户会话。识别不自动保存；应用识别草稿和最终确认保存均由用户执行，避免异步覆盖正在编辑的内容。食品安全仍须用户核对，识别不是烹饪安全审核。

## 后续 Linux / 公共共建

Linux 客户端可复用相同认证接口读取用户自己的 recipe.body 和媒体；服务身份不能绕过个人权限。预留 contribution_allowed=false、contribution_authorization JSONB、review_state=private、sync_state=not_requested。未来运营审核后另建正式授权导出/同步接口，再同步到 Linux 公共知识库；本期不实现审核后台、定时同步或批量手绘生成，不自动公开第三方菜谱原图/完整表达。

步骤结构已经独立有序保存，为将来的版本化插画输入预留；本次不触发公共步骤插画生成，也不改变已存在的97张公共图片。

## 验证状态

真实隔离 PostgreSQL + HTTP 测试验证私有访问、匿名拒绝、跨用户修改拒绝、UUID大小写、零制作星标、无确认不保存、公共收藏不复制主体、JPEG格式、图片私有、识别入队去重/隔离、并发8次同打卡只计1次、不同操作累计、删除扣减与重放不复活、删除菜谱保留做菜历史。现有独立迁移运行两次验证账本跳过。

Orbit SDK worker 测试使用受控 HTTP 响应，不是真实模型准确率验收：验证私有附件、SSE解析、结构化草稿、不会自动入库、任务不重复生成、专属会话停止/归档及失败状态。现有公共菜谱/分类/时间偏好、图片和分享回归独立执行。

真机相机/相册、完整截图视觉验收、真实用户授权模型 OCR 及识别准确率仍需独立验证，不能由源码或构建替代。正式构建、生产迁移、发布和邀请同步回执追加于本节。

## 真实识别链路限制

已用原创中文菜谱图片执行真实 Orbit SDK 测试；截至本次记录，未获得成功识别结果：原积分专用实例返回积分提示而非菜谱；用户个人 Goldfish 实例返回 provider model_not_found；另一既有 Goldfish 实例超时；已授权 Codex 实例返回 AgentNode reverse journal recovery 502/turn_not_found。各测试均在隔离数据库使用专属会话，结束停止并归档，没有将响应伪造成菜谱。未修改用户共享智能体定义、模型凭据或运行中的节点来掩盖错误。

因此，图片上传、草稿编辑/保存、识别任务/失败处理已实现，但真实 AI 图片转结构化菜谱仍未验收通过，当前不能宣称可用。需 Orbit 提供一个当前用户已授权、模型及节点正常、支持图片并能输出菜谱 JSON 的厨房目标，再通过 kitchenAgentId/kitchenWebAppBotId 配置及真实测试验证。

可选真实测试使用 tests/PersonalKitchen 的 KITCHEN_LIVE_ORBIT_USERNAME/BASE/BOT/AGENT/IMAGE 环境变量，复用正式 SDK；不在生产库插入测试记录。默认测试只使用受控 HTTP 响应。本次不开发公共共建后台、Linux 定时同步或批量插画生成；真机相机/相册及完整视觉验收仍未完成。

## 修改文件清单

- FamilyReward.Api/PersonalKitchenEndpoints.cs：全部私有厨房 API 与权限/幂等/校验。
- FamilyReward.Api/KitchenRecognitionWorker.cs：Orbit 图片识别持久队列与草稿。
- FamilyReward.Api/KitchenOrbitResolver.cs：仅从当前用户已授权活跃实例中选择厨房目标。
- FamilyReward.Api/Program.cs：认证人类身份、限流、模块及 worker 注册。
- scripts/migrations/20261108-personal-kitchen-v1.sql：五表、索引及私有媒体复合外键。
- parent-app/ios/HappyLifeParent/MyKitchenView.swift：我的厨房完整页面、编辑器与照片打卡。
- parent-app/ios/HappyLifeParent/KitchenView.swift：更多菜单及公共菜谱个人操作入口。
- parent-app/ios/HappyLifeParent/DearSocialView.swift：复用已有相机包装。
- parent-app/ios/HappyLifeParent.xcodeproj/project.pbxproj：新文件及版本222。
- parent-app/android/MyKitchenPage.cs：对应 MAUI 原生页面。
- parent-app/android/KitchenPanel.cs：更多菜单及详情个人操作入口。
- parent-app/android/FamilyStore.cs：带认证和会话世代校验的私有图片读取。
- parent-app/android/Platforms/Android/AndroidManifest.xml：相机权限与拍照应用可见性。
- parent-app/android/LinkoFamily.csproj：版本1.0.9（18）。
- scripts/build-moment-android-release.sh：相同版本的签名包、manifest及回执核对。
- scripts/check-personal-kitchen.sh：隔离数据库和迁移回放验证。
- tests/PersonalKitchen/PersonalKitchen.csproj、Program.cs：HTTP/数据库、SDK可控响应、可选真实识别测试。
- docs/features/personal-kitchen.md：实现、接口、存储、验证和未完成事项。

## 当前发布回执

- iOS 1.3.22（222）：源码 c3be52fd69db18a20d8069a1c37662460608ab9b，签名 Archive/Export通过；Atlas IPA SHA256 6f62c4d4063f7149c6fb96496128f98d9dea24adcf15fd7c6b30a1b5e7df0bd8。TestFlight d25ed37d-ca5b-4ccc-8e63-ee58c8d790ea 已 VALID/testflight_visible；Apple build 02850c01-9712-4322-aa9d-ff602e60ccc6。邀请同步 e817bfa5-2d8e-4de1-b5ac-2c13e1222eb9 verified。
- Android 1.0.9（18）：源码399bb1b，正式签名与包版本核验通过；Atlas版本a7cfc2f4-e669-43cd-beab-86032230c10b，APK SHA256 ebf234b523ca0b7a1d0e684877a136451d5cb117f714a14d27b77f4792f28402。邀请绑定3a90d4b6-192f-446b-921e-b421fd6f44ae verified，独立读回版本和实际APK URL。
- 首次API版20261108-013614-activity-c3be52f：Atlas版本f032dd61-7d0d-452f-a4a3-b841e2233549，部署5b3a8ab4-6ad7-487f-8d91-34f9850a72ec stored，日志确认ledger验证/切换/启动/健康。迁移记录20261108-personal-kitchen-v1 SHA256 ff43374b9eb163249f88d42ef9bd72becdb7b8127b5b2a9ed736ffae3c41e6ba，五表归属family_reward_app，备份及校验清单受限保留。路由改为个人厨房专用目标的补充服务版本另行追加。
- 后端聚焦31项检查、现有菜谱/图片/分享回归、原干饭HTTP/模型检查、真实城市中心Apple Maps查询通过；配套228项HTTP/WebSocket、前端lint/build通过。构建仅有既有SDK跨平台文件权限/地图弃用警告；原生正式编译无错误。
- 已从Atlas重新下载12个正式制品，159,405,933字节全部匹配SHA256与大小。正式分发与真机安装/界面/拍照验收独立，后者尚未完成。

- Apple材料只读核对本次仍返回HTTP502/ apple_materials_read_failed；没有进行材料写入，不宣称欧盟交易商或材料完整性已核验。内部TestFlight可见已独立确认，未提交外部Beta或App Store审核。
- 公开邀请页数据独立读取显示1.3.22（222）及1.0.9（18）；后台目的地读回真实APK SHA256与正式制品一致，未覆盖外部测试等其他入口。
- 已清理本地6个已在Atlas验证可恢复的重复正式包，共159,404,586字节；保留精简校验回执、受限数据库备份与迁移记录。没有新建worktree。另有未跟踪application/ocr_recipe.py不属于发布文件，已保留，未提交/删除。

- 最终API版本20261108-015436-activity-8f05d10：源码8f05d10d76b61d9416e4ee25468509a3bde37614，已推送GitHub main；Atlas版本f78b18eb-e895-4ba0-803c-83dbb76261cf，部署0cd754ce-0a1f-4539-8091-74fdd24ca8a2 complete=true/stored/exitCode=0。运行指针、启动及健康独立读回。没有新增生产数据修复或修改已有迁移。
- 最终服务端三个制品119,580,496字节已从Atlas下载并验证后清理本地及远端传输副本。本轮累计本地清理278,985,082字节；正式制品、符号包可由Atlas恢复，源码中的公共步骤图片继续保留。
