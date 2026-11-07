# 下厨房交付边界

当前完成双模式客户端、数据库分类、按分类随机选择、随机去重、设备当地餐段加权、完整食材和步骤阅读。模式切换保留原组件状态。菜谱现扩充至 30 道，含饭/面/粥各 8 道、甜品 6 道，全部 97 个步骤配有可复用的原创 AI 手绘图；运行期按需生成与重新生成仍未接通。

分类入口为“做饭、做面、做粥、甜品”。默认不选择分类，随机范围为全库；再次点击已选分类取消选择，恢复全库范围。原有当地餐段权重保持不变，不排除用户明确选择的分类。“随便做”旧分类记录只禁用、不删除；后端继续兼容旧客户端的 `category=all` 请求。

扩充数据源见 `kitchen-catalog-v2.json`。独立迁移 `20261107-kitchen-dessert-catalog-v1.sql` 新增甜品分类与 21 道完整原创菜谱，同时绑定对应的 63 张已预生成插画，不覆盖原有九道菜谱和图片。默认份量为两人，食材用量、准备工作、熟度和防烫说明均保留。新增内容为规则校验的试行菜谱，尚待人工烹饪复核。

接口使用现有应用认证和 PostgreSQL，JSON 为 camelCase。

- GET /api/recipes/categories
- GET /api/recipes/random?category=&exclude=&meal=
- GET /api/recipes/{id}
- POST /api/recipes/{id}/illustrations 当前明确返回 503 / recipe_illustrations_unavailable，不伪造任务。
- GET /api/recipe-illustrations/{id}/v{version}/steps/{number}.jpg：公开的原创菜谱图片，原生图片组件无需额外 Bearer；限定 UUID、版本和步骤，返回 JPEG、SHA256 ETag 和 immutable 缓存，未知版本返回 404。

## 数据库

20261107-kitchen-recipes-v1.sql 新建 kitchen_categories、kitchen_recipes 和分类索引。原生 UUID 主键，JSONB 保存版本化完整内容。初始四分类和九道原创文字菜谱只通过独立迁移导入，应用启动不建表或填充。

部署使用 scripts/run-db-migrations.sh，需要完成备份并配置 FAMILY_REWARD_DB_BACKUP 和受控 FAMILY_REWARD_DB_DSN。脚本以内容 SHA256、执行记录、事务和 advisory lock 防止重复或并发执行。已执行脚本不可修改，修订使用新脚本。回滚功能先关闭 published，保留用户使用过的数据。

内容为规则校验的试行文字菜谱，尚待人工烹饪复核，未复制第三方平台图片。鸡蛋熟度和生熟分离要求参考公开食品安全指引。
https://www.fda.gov/food/buy-store-serve-safe-food/safe-food-handling
https://www.foodsafety.gov/food-safety-charts/safe-minimum-internal-temperatures

## 尚未完成

Orbit 当前 Goldfish.WebAppSdk 提供会话、运行和聊天流，未发现可复用的正式图片生成与图片制品入库接口。未引入第三方模型直连或复制公共智能体服务。

尚无后台图像 worker、持久任务和查询接口、并发去重、失败重试、对象存储、费用预算或轮询。当前不需要配置模型密钥。成品图仍为空；现有 34 张步骤图随服务端版本发布，菜谱版本变化后不得复用旧图，修改图片须使用新的不可变版本。客户端支持已有 HTTPS 图片字段；Android 使用 UriImageSource 缓存，iOS 使用 AsyncImage，尚无专用磁盘缓存。

步骤图采用内置 image_gen 工具逐步生成，先读取结构化文字步骤，再约束食材、动作、厨具和温暖水彩/铅笔风格；无图中文字。逐图检查后修正粥类熟度检查动作，采用两把勺子而不是手指触碰热食。最终 JPEG 仅作传输编码优化，文字步骤及食品安全说明不变。提示词、资产路径和 SHA256 见 `kitchen-illustration-assets.json`，结构化步骤输入见 `kitchen-illustration-prompts.json`。资产位于 `FamilyReward.Api/recipe-illustrations/`，不放进手机安装包。

`20261107-kitchen-illustrations-v1.sql` 是独立一次性迁移：先逐道核对 recipeVersion 和原始步骤，全部匹配才绑定图片 URL 并将 illustrationStatus 置为 ready。任一道步骤变更均失败并回滚，不覆盖维护过的菜谱。版本及实际 JPEG 随 API 制品一起交付。

30 道菜谱不等于约 100 道完整菜谱建设。现有 30 道已预生成步骤图并做视觉核对；进一步扩充与人工烹饪复核仍待推进。运行期生成仍需补齐 Orbit 正式受控图片任务和制品接口。生成须读取已核对的菜谱结构及版本。

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

## 2026-11-07 分类加载失败修复

手机截图提示“菜谱暂时无法加载”。线上 `/api/recipes/categories` 实测 404，确认客户端 1.3.19 已可用而服务端仍为旧版。

- 从 Atlas 已发布 API 制品提取独立迁移和原始执行器，先完成 PostgreSQL 自定义格式备份及备份目录校验，再以现有 `family_reward_app` 角色执行。持久迁移记录 SHA256 为 `628ec0a28f04a40e4f0c26792d37fc128926e0eadad57c6468ce376c1586e223`，读回四分类、九菜谱，新表归属应用角色。没有启动时建表或填充。
- 旧制品错误标注为 `api/server`，与构建清单的 `linux/server-linux` 不符，首次部署任务 `826299dd-a477-4cce-b502-a95bbe01fe84` 失败。Atlas 拒绝修改不可变版本（409），因此按原构建清单重新构建并发布新版本，没有覆盖旧版本。
- API 新版 `20261107-174137-activity-6503bbc`，对应源码 `6503bbcdac1fe517fb3d3aa1a81ef7cfc077f2f1`，构建及配套 228 项检查通过。Atlas 部署任务 `c7b64b0e-177d-42ea-96d1-2da21414bd34` 已返回 `stored/exitCode=0`，日志确认迁移校验、激活和健康验证完成，实际运行指针已读回。
- 线上分类接口从 404 恢复为未登录请求 401；健康检查正常。发布服务身份不是用户登录身份，其访问也按预期返回 401。尚未取得手机端重试成功或真实用户会话读取结果，不将路由检查当作客户端端到端验收。
- 既有 TestFlight 尝试已确认 `VALID/testflight_visible`，仍为 1.3.19（219），无需新安装包。邀请页内部测试入口已通过 Atlas 同步并独立读回 1.3.19（219）。
- 本次服务端 API 上线解决分类路由缺失；AI 插画和菜谱扩充仍未完成。数据库备份、迁移脚本、执行日志和校验清单保留在受限运维目录；已留存的制品副本在下载并核验哈希后清理。

## 2026-11-07 步骤插画显示修复上线

- 功能源码 `8f76e2f55ddccf0513bfd3ab4a288de9c01ccae5` 已推送正式 GitHub main。未修改原生客户端和“出去吃”布局、行为；使用现有 iOS/Android HTTPS 图片字段。
- 34 张最终图片覆盖现有九道菜谱的全部步骤，共 15,912,368 字节。原图用内置 image_gen 逐步生成并检查，最终交付 JPEG 以减少传输量；提示词和原始结构化步骤均已留档。原始绘图不含步骤文字，原生文字教程保持不变。
- 真实 PostgreSQL 隔离测试通过图片绑定、完整打包、匿名原生图片加载、UUID 大小写、JPEG 字节、ETag/304、缺失版本/非法步骤 404，以及既有分类、随机推荐和认证检查。额外修改最后一道菜的步骤，确认迁移失败并回滚此前全部图片绑定，恢复后执行成功，重复执行跳过。
- 服务端版 `20261107-181946-activity-8f76e2f`，Atlas 版本记录 `fcf3cc2c-90f7-4cc3-af0d-c7886388c441`。构建、前端 lint/build、配套 228 项 HTTP/WebSocket 检查通过，API 包独立检查包含全部 34 张 JPEG。
- 生产迁移先完成 PostgreSQL 备份及备份清单校验，再从已发布 API 包提取原始迁移运行器执行。迁移记录 `20261107-kitchen-illustrations-v1`，SHA256 `74afd49f11b625087149022e9518a128c9ecf0619d698c2b4501c308045713d6`。读回九道 ready、34 个步骤 URL。
- Atlas 激活任务 `e516bb9a-050c-4658-9c8c-1ff058fa63a1` 完成为 stored/exitCode=0；独立日志确认迁移记录校验、排空、切换、启动及健康读回。
- 从生产库读取实际 URL，逐个验证 34 个公网图片地址均 200、JPEG、SHA256 与最终源图完全一致，缓存头和条件请求 304 正常。本机额外通过公网下载一张 446,356 字节示例并匹配 SHA256。尚无手机端实际显示的读回，不将服务端检查写成真机验收。
- 五个制品已从 Atlas 重新下载并核验后清理传输副本；本地删除 55,011,266 字节重复发布包，临时编译目录由 host-build-output 清理。数据库备份、迁移和精简执行回执继续受限保留。
- 用户若仍停留在旧详情，返回“下厨房”重新随机/换一道后打开“查看做法”，即可获取新的插画字段，无需更新安装包。按需生成、用户重新生成、持久生成任务和对象存储仍未实现；本次修复范围为现有九道菜谱的预生成与可复用显示。

## 2026-11-07 甜品、取消选择与菜谱扩充发布

- iOS/Android 默认不选任何分类，取消选择恢复空分类请求；再次点击当前分类清空选择。新增“不选分类，随便做一道”说明。选中灰实线、未选中浅灰虚线样式保留，模式切换不重置另一模式。
- 原生交互提交 `681b539`，构建隔离提交 `46d1408`，服务端/菜谱/图片提交 `cc78e8d358b12b7f25b084afe6a00f73de897ab2`，均已推送正式 GitHub main。Android SDK 工作树存在其他任务的未提交改动，改用其已发布 HEAD 快照，没有回退或包含那些改动。
- 初次组合构建在 Android SDK 未提交改动检查处失败，未发布该次结果。改为同一个主机串行队列内按平台使用独立 host-build-output，完成的平台产物不因后一平台失败被清理；最终两个平台均构建成功。
- 隔离 PostgreSQL 与 HTTP 检查通过 30 道完整数据、四个动态分类、空/缺省/all 分类兼容、午餐时明确选甜品、下午茶选面食、随机去重、97 张图片随包发布、认证和 UUID 变体。旧步骤不匹配时图片迁移整批回滚、重复迁移跳过的检查保留。前端 lint/build、原有干饭回归、真实 Apple Maps、原生模型及配套 228 项 HTTP/WebSocket 检查通过。
- 独立迁移 `20261107-kitchen-dessert-catalog-v1` 在生产备份、备份目录检查及校验和保存后，由已发布 API 包中的原始运行器执行；迁移 SHA256 `0d310dbbb9961fad79ef83d7c6f569321596315134b42749b33b3f475873e3bb`。生产独立读回饭/面/粥各八道、甜品六道，旧 all 分类保留但禁用，原九道未覆盖。
- API 版 `20261107-201547-activity-cc78e8d`，Atlas 记录 `8973a7ef-f9e7-440b-9b7e-d478d85969c7`。部署任务 `d7f4e0bd-3235-44f5-9868-f971bcfc4479` 已 stored/exitCode=0；日志确认迁移记录校验、激活和健康读回。读取生产库实际地址验证全部 97 张 JPEG 的 200、immutable 缓存及 SHA256，图片总计 48,154,604 字节。
- iOS 1.3.20（220）对应 `46d1408d45eb4f90caa7efd22af1883355f1ccf3`，主应用/Watch/分享扩展版本一致。TestFlight 尝试 `b1405a02-e06a-44ab-b638-44e6148a28ad`，Apple build `78ff5b7c-2e11-4654-b5e7-bc06a84022cf`，已 VALID/testflight_visible。材料读取接口仍返回 502，不把测试组可见解释为材料完整性已核验。
- Android 1.0.7（16）对应 `cc78e8d358b12b7f25b084afe6a00f73de897ab2`，使用既有正式签名，包名、版本、v2 签名和证书校验通过。APK SHA256 `0572f195508e7958879580e113c3cd09df0bc733303f4c031a9f1b545e1261d8`，Atlas 记录 `ad77eed2-2310-4f11-a344-b824d1cda233`。
- 邀请入口保持原 URL。Android 绑定操作 `b520b367-4d7b-4e53-8be2-cd56c5a33efe` 与 TestFlight 同步操作 `3a819d87-cf50-4cea-9cb5-49f868d033a9` 均 verified；独立公开读回内部测试 1.3.20（220）及 Android 1.0.7（16），其他入口未覆盖。
- 14 个制品已从 Atlas 重新下载并匹配 SHA256 后清理传输副本；本地删除重复包和打包中间文件 158,801,208 字节。临时编译目录已由 host-build-output 清理，保留 Git 中的正式图片、提示词、菜谱、版本清单及受限备份/回执。没有新 worktree。
- 本次未执行真机安装、分类点击与取消选择的真机验收，签名/编译、平台可获取和设备实测分别记录。自动生成/重新生成的运行期任务与对象存储仍未接通。

## 2026-11-07 做法页完成与系统分享

- 源码提交 `52a0bc7de6f502de983048013884342f4b908892`，已推送正式 GitHub main。iOS 做法页明确使用 topBarLeading 放置“完成”、topBarTrailing 放置分享；复用现有 MomentShareLink/ShareLink、SF Symbols `square.and.arrow.up`，不附加品牌图片 SharePreview。Android 同步左侧完成、右侧通用分享图标，复用 MomentStyle.IconButton 与系统 Share.Default。
- JSON 新增计算字段 shareUrl，不改数据库。链接为 `https://happylife.ai.impx.net/api/recipes/{id}/share`；只包含菜谱 UUID，不附用户凭据或私有会话参数。旧缓存没有链接时，系统分享真实的完整文字菜谱，不伪造 URL。
- 新增同工程公开 HTML 分享页，仅允许已发布、结构有效的库内菜谱，未发布或不存在返回 404。接收方无需安装 App 或登录，即可阅读食材、用量、准备工作、有序步骤、实际手绘图和注意事项。页面设置真实 Open Graph 标题、简介及现有菜谱图；文本/属性 HTML 转义，图片限定自有 HTTPS 素材，提供 CSP/nosniff/referrer 策略。
- 隔离 PostgreSQL/HTTP 测试通过匿名页面、真实文字/插画、未知/未发布 404、HTML 注入和危险图片协议拒绝、canonical 分享 URL，以及原分类、随机、认证、UUID 与图片缓存回归。前端 lint/build、原生模型与干饭回归、真实地图查询及配套 228 项 HTTP/WebSocket 检查通过。iOS/Android 正式签名包构建完成。
- API 版 `20261107-205012-activity-52a0bc7`，Atlas 记录 `b427b43d-47d9-446c-97de-d3beaaa111b4`。部署任务 `c2889704-f3f7-4799-a765-2ad0c5cd954f` 已 stored/exitCode=0，日志确认激活与健康验证完成。逐个匿名请求生产库实际 30 个分享页，确认全部 200、真实菜名、步骤文字、图片 URL 和 CSP。
- iOS 目标 1.3.21（221），主应用、Watch、分享扩展包版本已核验一致；Atlas 记录 `b0c37114-39d0-4c3e-87b9-2c3c12a0247b`，TestFlight 尝试 `b8938c5d-0ede-41ec-a99b-08bbb5f456a3`，原 Apple 上传 `8aebdc81-e09d-43c5-b5c2-9b6f19955052`。处理中不创建第二个上传任务，测试组可见以随后独立读回为准。
- Android 1.0.8（17），Atlas 记录 `bc725011-d202-428c-a98f-2291f04048e6`，正式签名、包名和 manifest 版本通过。APK SHA256 `10b8aa4f603c2e45fb9076c7cab848f34ef8524bb0acbaba03339fbbf9b23b78`。邀请绑定操作 `56da4f73-97f0-447c-a2a0-f57b191dc969` verified；保留原入口及其他平台目的地。
- 13 个制品已从 Atlas 重新下载并匹配 SHA256 后删除传输副本；本地删除重复包/打包中间文件 158,831,416 字节，编译临时目录由 host-build-output 清理，必要校验清单和受限运维回执保留。
- 浏览器预览工具实测返回“The browser access host is unavailable”，未宣称浏览器截图验收成功。未执行 iPhone/Android 的真实系统分享面板、微信目标选择、实际发送或接收验收；系统分享与真实链接接入不等同于这些设备结果。
- 发布收尾已读回 iOS `VALID/testflight_visible`，Apple build `8aebdc81-e09d-43c5-b5c2-9b6f19955052`。邀请同步操作 `902831df-4800-4fc7-afdc-13204833ec8b` verified，公开邀请页独立读回 iOS 内部测试 1.3.21（221）、Android 1.0.8（17）。Apple 材料读取仍返回 502，不能据此声称材料完整性通过；不影响已独立确认的内部测试组可见事实。
