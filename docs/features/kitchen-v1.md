# 下厨房交付边界

当前完成双模式客户端、数据库分类和九道原创文字菜谱、按分类随机选择、随机去重、设备当地餐段加权、完整食材和步骤阅读。模式切换保留原组件状态。

接口使用现有应用认证和 PostgreSQL，JSON 为 camelCase。

- GET /api/recipes/categories
- GET /api/recipes/random?category=&exclude=&meal=
- GET /api/recipes/{id}
- POST /api/recipes/{id}/illustrations 当前明确返回 503 / recipe_illustrations_unavailable，不伪造任务。

## 数据库

20261107-kitchen-recipes-v1.sql 新建 kitchen_categories、kitchen_recipes 和分类索引。原生 UUID 主键，JSONB 保存版本化完整内容。初始四分类和九道原创文字菜谱只通过独立迁移导入，应用启动不建表或填充。

部署使用 scripts/run-db-migrations.sh，需要完成备份并配置 FAMILY_REWARD_DB_BACKUP 和受控 FAMILY_REWARD_DB_DSN。脚本以内容 SHA256、执行记录、事务和 advisory lock 防止重复或并发执行。已执行脚本不可修改，修订使用新脚本。回滚功能先关闭 published，保留用户使用过的数据。

内容为规则校验的试行文字菜谱，尚待人工烹饪复核，未复制第三方平台图片。鸡蛋熟度和生熟分离要求参考公开食品安全指引。
https://www.fda.gov/food/buy-store-serve-safe-food/safe-food-handling
https://www.foodsafety.gov/food-safety-charts/safe-minimum-internal-temperatures

## 尚未完成

Orbit 当前 Goldfish.WebAppSdk 提供会话、运行和聊天流，未发现可复用的正式图片生成与图片制品入库接口。未引入第三方模型直连或复制公共智能体服务。

尚无后台图像 worker、持久任务和查询接口、并发去重、失败重试、对象存储、图像版本校验、费用预算或轮询。当前不需要配置模型密钥。成品图与步骤图为空。客户端支持已有 HTTPS 图片字段；Android 使用 UriImageSource 缓存，iOS 使用 AsyncImage，尚无专用磁盘缓存。

九道文字菜谱不等于约 100 道完整菜谱建设。热门菜谱插画预生成和图片人工审核未完成。第二阶段需先补齐 Orbit 正式受控图片任务和制品接口。生成须读取已核对的菜谱结构及版本。

线上迁移、部署、登录客户端与真机验收需以实际回执为准。

## 2026-11-07 验证与发布记录

- 功能源码：`1de32e34ac35443e65e301436c9284017cd90ee5`，已推送正式 GitHub `main`。
- 隔离服务端打包修复：`80984919d0d6a56c7276e3d0f53a3fa13094841c`，已推送 `main`。打包时同时冻结正式 AgentIdentity Web SDK 和 Orbit WebApp 包，修复临时目录内相对依赖失效。
- 真实 PostgreSQL 隔离库：独立迁移执行两次、九道菜谱结构、认证、动态分类、下午茶时段明确选面、随机排除上一次结果、UUID 大小写详情访问均通过。
- 原有干饭 HTTP/模型回归、真实 Apple Maps 查询、Android 编译、iOS 签名 Archive/Export 均通过。没有把这些检查当作真机界面验收。
- 服务端包包含前端 lint/build；配套身份通知测试 19 项、Linko HTTP/WebSocket 检查 228 项通过。
- iOS 1.3.19（219），Bundle ID `net.impx.happylife`，主应用、Watch、分享扩展版本一致。Atlas IPA SHA256：`39ea93e1bc914df5206e7dc12ea90857442057c369839fdb408b977b99925ce3`。
- TestFlight 尝试：`03f35b50-1f9e-4a89-8547-c93695477e1a`。Apple 原上传任务：`32ba18c4-e438-4ae0-b3dc-5884da4e9360`。传输流中断后独立刷新确认 `AWAITING_UPLOAD`，随后只申请续传原任务，不重新创建上传。
- 服务端 Atlas 制品版本：`20261107-164357-activity-8098491`，版本记录 `b64adea3-be4c-44cb-91ab-c0759de2fd3c`，已留存但未激活。正式部署绑定目前仅有 `upgrade.default`，新增迁移需先由独立受控迁移操作完成并登记；尚未登记该迁移执行命令，生产数据库未变更。
- IPA、符号包及三个服务端包均已从 Atlas 下载并匹配 SHA256 后清理本地/传输副本。本地删除重复正式包及打包中间文件共 42,528,982 字节；临时编译目录由 host-build-output 清理，精简校验回执保留。
- Apple 材料读取接口返回 502，材料完整性尚未确认。TestFlight 组可见、邀请页同步、真实登录客户端及真机验收尚需独立读回。

完整需求尚未交付：除上述生产迁移和验收外，仍缺约 100 道菜谱建设、烹饪复核、成品图片，以及 AI 插画任务、生成、持久化、缓存与成本控制整条链路。
