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

复用现有 SystemConfig 的 Orbit WebApp bot、AgentFreeGatewayConfiguration 和 Goldfish.WebAppSdk；只选择当前已授权智能体，未新增模型密钥或直连模型服务。传入的是私有 JPEG dataURL 附件，不暴露下载地址。要求所授权智能体支持图片理解并能输出结构化 JSON；没有授权、模型不支持图片或响应不合法时保留失败状态，用户可重试或手动填写。

worker 异步领取持久任务（FOR UPDATE SKIP LOCKED），单任务3分钟预算，重启遗留 running 超过10分钟标失败供用户重试。每用户每天10次、图片/任务入口20次/分钟。会话专用于本次识别，结束后停止并归档，不触及其他用户会话。识别不自动保存；应用识别草稿和最终确认保存均由用户执行，避免异步覆盖正在编辑的内容。食品安全仍须用户核对，识别不是烹饪安全审核。

## 后续 Linux / 公共共建

Linux 客户端可复用相同认证接口读取用户自己的 recipe.body 和媒体；服务身份不能绕过个人权限。预留 contribution_allowed=false、contribution_authorization JSONB、review_state=private、sync_state=not_requested。未来运营审核后另建正式授权导出/同步接口，再同步到 Linux 公共知识库；本期不实现审核后台、定时同步或批量手绘生成，不自动公开第三方菜谱原图/完整表达。

步骤结构已经独立有序保存，为将来的版本化插画输入预留；本次不触发公共步骤插画生成，也不改变已存在的97张公共图片。

## 验证状态

真实隔离 PostgreSQL + HTTP 测试验证私有访问、匿名拒绝、跨用户修改拒绝、UUID大小写、零制作星标、无确认不保存、公共收藏不复制主体、JPEG格式、图片私有、识别入队去重/隔离、并发8次同打卡只计1次、不同操作累计、删除扣减与重放不复活、删除菜谱保留做菜历史。现有独立迁移运行两次验证账本跳过。

Orbit SDK worker 测试使用受控 HTTP 响应，不是真实模型准确率验收：验证私有附件、SSE解析、结构化草稿、不会自动入库、任务不重复生成、专属会话停止/归档及失败状态。现有公共菜谱/分类/时间偏好、图片和分享回归独立执行。

真机相机/相册、完整截图视觉验收、真实用户授权模型 OCR 及识别准确率仍需独立验证，不能由源码或构建替代。正式构建、生产迁移、发布和邀请同步回执追加于本节。
