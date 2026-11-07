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
