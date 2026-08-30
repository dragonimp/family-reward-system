# 家加分 - 进展日志

## [2026-08-30] family-reward-REQ-065 方形手表表盘需求分析
- Orbit：`gpt_ce5e25fd21f04e458f84c8dd5231f455`；需求：`family-reward-REQ-065`（`603eb8b0-b06f-48f4-a9ee-88c47b24d634`）；分析任务：`family-reward-TASK-240`。
- 新增 `docs/REQ-065-ANALYSIS.md`，确认 REQ-065 与 REQ-063、REQ-066 的目标、终端范围和功能点相同，应选择一个主需求并只实施一套响应式方形 `/watch` 页面。
- 当前外框和内描边仍为圆形，华为/小米目标设备矩阵尚未建立；`TASK-240` 可凭分析文档和对应提交关闭，REQ-065 只能在确认为重复项时按重复关闭，不能视为方形表盘已交付。

## [2026-08-28] family-reward-REQ-062 VIP 表盘动画测试用例设计
- Orbit：`gpt_628da64994dc47f3b988976505cffc78`；需求：`family-reward-REQ-062`（`2af86812-fa22-4e91-b9c2-f97cd59fda5a`）；测试设计任务：`family-reward-TASK-231`（`d06b3ba5-6f62-46eb-a14b-6f54a823537b`）；功能点：`245414ae-7163-46af-82bb-1bb73cf9a63b`。
- 新增 `docs/publishing/xiaotiancai/13-req-062-static-test-cases.md`，建立九条需求—功能点—用例追踪，覆盖五款 VIP 动画、VIP/非 VIP 权益隔离、表盘切换、积分/时间刷新、五组窄屏视口、减少动态效果、弱网回退、点击可达性和无业务写入副作用。
- `TASK-231` 可凭测试设计文档和对应提交关闭；REQ-062 已有实现与基础静态自动化，但仍需执行权限、视觉、弱网和副作用用例并取得受控部署后的生产复测证据，当前不建议关闭需求。

## [2026-08-30] family-reward-REQ-063 方形手表表盘需求分析
- Orbit：`gpt_9880e63fb33d417bb46d5e1fd0a1c0bb`；需求：`family-reward-REQ-063`（`dce79135-f512-483f-899c-8f02bdf924a2`）；分析任务：`family-reward-TASK-238`。
- 新增 `docs/REQ-063-ANALYSIS.md`，确认当前 `/watch` 的外框与内描边均是圆形；定义统一方形容器、保守安全区、菜单内置定位、旧 WebView 回退与静态/真机验收矩阵，覆盖小天才、华为、小米类设备。
- `TASK-238` 可凭分析文档和对应提交关闭；仓库尚未实现方形外框，也没有三类设备的目标 WebView 验证证据，`REQ-063` 保持待实现。
- Orbit 重复分析派发 `gpt_b39244be65ed4b9eb4742bbbf2d8a894` / `TASK-245`：复核需求正文、功能点和当前圆形 CSS 均未改变，沿用同一实施边界与验收矩阵；`TASK-245` 可凭复核提交关闭，`REQ-063` 仍不可关闭。

## [2026-08-20] MCP 全业务工具与家庭/圈子权限重检
- 工具覆盖：MCP 工具由 18 个扩展到 40 个，补齐圈子修改/删除/邀请/加入/移除孩子，家庭成员增删改查，规则模板，儿童认证码与设备，好友通知，积分申请审批，以及圈子总览/排行/分类统计。
- 概念口径：家庭是当前家长自己的家庭成员与名下孩子，不随圈子切换；圈子是多个家庭协作查看孩子积分的空间。`family_group_id` 作为兼容技术字段保留，工具名称和描述统一使用新的产品口径。
- 权限边界：所有工具必填 `username`；默认孩子和积分查询仅返回本人孩子，指定圈子时先校验成员身份并开放圈内孩子余额；其他家庭孩子的明细、积分写入、资料、设备、好友和申请仍限孩子所属家长；个人规则和家庭成员按家长隔离。
- 网关材料：生成 `application/mcp/family-reward-mcp-tool-library-split.json` 和 `application/goldfish-tool-library.json`，并新增 `docs/FAMILY-REWARD-MCP-TOOLS.md` 记录 40 个工具的完整名称、描述和网关配置要求。
- 验证：ASP.NET Core 构建 0 警告、0 错误；目录测试 10/10，通过临时双家长数据验证未入圈拒绝、入圈余额可见、跨家庭明细/写入拒绝、家庭成员隔离、当前用户防删除、规则隔离和圈子管理员权限，测试数据已清理。
- 发布：提交 `cb28544` 已推送 `main` 并部署 `https://happylife.ai.impx.net`；生产服务 active，`/health` 返回版本 `3.1.0`，GET 目录和 JSON-RPC `tools/list` 均为 40 个工具；备份 `/var/backups/family-reward/20260820014936`。线上 `wss` 默认查询仅返回名下 3 个孩子，圈子 `220` 可查看圈内 3 个孩子余额，查询非本人孩子“孩子王”的积分明细被服务端拒绝。

## [2026-08-17] family-reward-REQ-045 家长手机端虚拟手表
- 未完成原因：Atlas `TASK-138` 在需求分析 20% 时因 `The operation was canceled` 被标记为阻塞，之后未重新入队；需求同时误关联到 `OPS-001 线上入口可访问`，未形成明确开发范围。
- 实现：新增 `FUNC-020 家长手机端虚拟手表与孩子切换`；手机底栏提供“虚拟手表”入口，默认选择当前家长名下第一个孩子，多孩子可通过选择器切换。虚拟手表通过同源 iframe 复用真实 `/watch` 表盘、菜单和响应式布局。
- 权限：新增家长鉴权的只读聚合接口 `GET /api/watch/preview/{childId}`，仅允许读取当前家长名下孩子；不生成或暴露设备令牌。积分申请、好友变更、表盘保存和设备解绑在预览模式统一拦截，真实手表 token 链路保持不变。
- 验证：ASP.NET Core 构建 0 警告 0 错误；前端测试 19/19、ESLint、TypeScript/Vite 生产构建、watch 发布包校验通过。本地真实 PostgreSQL 创建两个临时孩子，分别读取 12/34 分，另一家长访问返回 404，测试数据已清理。
- 生产验收：320x568 与 390x844 均无横向或页面级纵向溢出，缩放比例为 1；家长账号默认展示嘟嘟，切换彦谦后表盘更新为 133 积分、230 现金、2 物品；点击提交显示“虚拟手表仅供预览”，控制台无错误。同步修复真实表盘顶部状态行与孩子姓名重叠。
- 发布：提交 `4623454`、`db78a75` 已推送 `main`；生产资源 `index-D_CTAyhP.js` / `index-BMyu1H4i.css`，`/health` 返回 200，服务 active，最终备份 `/var/backups/family-reward/20260817232816`。

## [2026-08-17] family-reward-BUG-009 规则模板支持现有公共红线
- 根因：模板候选只读取 `rules`，而页面下方的现有公共红线来自独立 `redlines`，只能查看不能勾选；之前 REQ-039 的实现只覆盖新建个人红线。
- 修复：为现有 `redlines` 建立幂等、可追溯的统一公共规则映射，家长可在同一模板列表中勾选公共红线和个人红线；积分处理页仅使用模板已选规则，手表积分申请继续排除负分规则。
- 验证：前端测试 18/18、ESLint、Release 构建、Vite 生产构建全部通过；临时 PostgreSQL 真实 API 回归 7/7；生产库映射 10 条、重复 0；桌面 1280px 和手机 390px 规则页公共红线可见且无横向溢出。
- 发布：提交 `0fb482b` 已推送 `main` 并部署 `https://happylife.ai.impx.net`；资源 `index-B-NqjTk1.js` / `index-D3Eq-emd.css`，备份 `/var/backups/family-reward/20260816235353`，`/health` 返回 200。
- Atlas：`family-reward-BUG-009` 已关闭，`TASK-135` 与 `TASK-136` 已完成，`TC-REQ039-02` 复测 passed，生产完成记录为 `family-reward-REQ-044`。

## [2026-08-16] family-reward-REQ-033 AgentFreeWebAppChat 完整公共组件复用修正
- 修正结论：原实现只参考 BigData 的流式协议并自建移动对话框，不属于公共组件复用；现已同步 BigData 正在使用的完整 `AgentFreeWebAppChat`、`CleanChatView`、AG-UI/A2UI 渲染与会话管理模块，新增 `/assistant/*` 工作台路由，删除自建 `agentStream`/`agentSse` 链路。
- 服务边界：ASP.NET Core 新增同源 `/api/agentfree/*` WEBAP 代理，覆盖家庭积分应用智能体列表、会话、消息、时间线、重命名/归档、上下文重置、交互响应和流式对话；只允许 `agentCode=happylife`，并校验家长身份、会话归属及可读性。
- 验证结果：前端测试 18/18、ESLint、TypeScript/Vite build、dotnet build 全部通过；真实网关冒烟收到 `stream.start`、thinking/content `stream.delta` 和 `stream.done`，正文为“公共组件流式验证通过”。
- 发布结果：提交 `a52a775`、`508478b` 已推送 `origin/main` 并部署 `https://happylife.ai.impx.net`；最终备份 `/var/backups/family-reward/20260816211641`，资源 `index-CXra8JPK.js` / `index-D3Eq-emd.css`，`family-reward-api.service` active，线上 `/health` 返回 200。
- 浏览器验收：390x844 家长账号打开 `/assistant`，完整公共组件会话抽屉仅显示“家庭积分应用”，对话页包含附件、思考开关、排队/补充模式、常用命令和流式发送控件；不可读历史会话已过滤，复测无新增接口错误。

## [2026-08-16] family-reward-REQ-030 手表端菜单重构需求分析
- Orbit：`gpt_9b1f884295314ee8b3cea458658ce107`；需求：`family-reward-REQ-030`（`d34bd45e-a08c-49bd-b848-686797a54d87`）；任务：`family-reward-TASK-047`（`6382c278-699f-49d0-8723-1bc54ab02209`）；Atlas 功能点引用：`245414ae-7163-46af-82bb-1bb73cf9a63b`。
- 基于 Git `bfa6712` 的实际 `/watch` 页面和 API 完成差距分析：当前单按钮会展开六个右侧按钮，需改为表盘内独立菜单页；现有积分申请、申请记录、好友、排行榜、表盘设置和设备解绑 API 可复用，预计无需数据迁移。
- 新增 `docs/REQ-030-ANALYSIS.md`，明确首页不变、右侧单入口、六个带图标叶子菜单、返回规则、积分详情边界、常用申请项图标、语音转文字降级和 WebView 麦克风最小权限、安全解绑、五组代表性视口及十项验收标准。
- 将后续实施拆为菜单导航、积分申请增强、详情与好友拆页、设置迁移和综合验证五组；本次仅完成需求分析，不把尚未开发的 REQ-030 标记为完成。
- 分析验证：核对需求所涉及的 `/api/watch/score`、`rules`、`requests`、`friends`、`settings`、`device-bind`、`device-unbind` 路由；修复 `verify-watch-app.mjs` 对 REQ-023 合并 CSS 选择器的格式耦合，使申请页滚动检查读取实际声明块而不再误报。
- Atlas 同步阻塞：当前运行时没有 Atlas MCP 工具或资源，本机 `codex mcp list` 返回 `No MCP servers configured yet`。因此无法读取 Atlas 中真实公约、环境、关联缺陷/任务和功能点详情，也无法将 REQ-030、TASK-047、测试与证据写回。Atlas 恢复后应写回本文、将 TASK-047 更新为完成，并保持 REQ-030 为待开发状态。

## [2026-08-16] family-reward-BUG-001 孩子手表积分申请家长端未收到
- 根因：手表端已有积分申请提交和最近申请查询，服务端也有审批函数，但家长 Web 端没有待确认申请列表；已有 `/api/watch/requests` 仅面向手表设备 token，家长端不会收到孩子提交的申请。
- 修复：新增家长端 `GET /api/reward-requests`，按当前家庭和当前家长名下孩子返回手表端待确认申请；新增 `POST /api/reward-requests/{id}/approve`，确认后复用交易入账逻辑并把申请标记为 `approved`。
- 权限边界：家长端申请列表需要当前用户属于所选家庭，且只返回当前家长通过 `child_user_bindings` 归属的孩子申请；审批时将当前 `parent_app_user_id` 传入 `CreateTransaction`，继续执行“只能操作自己名下的孩子”校验。
- 前端：积分操作页新增“待确认申请”区域，展示孩子、申请事项、分类、积分和提交时间，可直接确认领取；确认成功后刷新孩子积分和待确认列表。
- 验证证据：`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；前端 `npm run build` 通过；本地 API 临时数据闭环通过，创建家庭组 `group_id=62` 和申请 `request_id=2`，覆盖儿童认证码、手表设备绑定、手表提交 6 分申请、家长端待确认列表可见、家长确认后积分入账为 6、删除临时家庭清理。
- Orbit 缺陷复测 `3d5ca1b8af7c` / `family-reward-TASK-046`：在独立本地 API 端口重跑 `family-reward-TC-E2E-001` 核心闭环，覆盖临时家庭和孩子创建、手表绑定、提交 7 分申请、家长待确认列表可见、家长确认、手表状态变为“已领取”、孩子积分变为 7，以及重复确认返回 400；测试数据已清理，复测通过。
- 回归验证：ASP.NET Core 构建通过（0 警告、0 错误）；前端 Node 测试 8/8、TypeScript 检查和 Vite 生产构建通过；`git diff --check` 通过。修正了既有回归用例的过宽断言，使普通积分操作继续按家长全局孩子范围工作，同时明确验证待确认申请读取和确认携带家庭范围。当前主工作树复用的 `node_modules` 不包含 ESLint，且环境没有 `npm`，因此无法执行 lint。
- Atlas 同步阻塞：当前运行时未暴露 Atlas MCP 工具或资源，本机 `codex mcp list` 返回 `No MCP servers configured yet`。因此无法读取 Atlas 中的真实公约、环境和关联事项，也无法将测试执行 `3d5ca1b8-af7c-4770-a579-9f0edce49e7b`、缺陷 `42eaa97f-c23d-4ae2-a002-0414b207acef`、修复任务 `f28b29e8-3fef-4c32-a9dd-ff9156e6f8fc`、执行任务 `family-reward-TASK-046` 及上述证据写回或关闭；Atlas 恢复后应将本次测试标记为通过，并据此关闭缺陷及关联任务。

## [2026-08-16] family-reward-REQ-026 家庭组改名
- 家庭管理新增家庭组改名能力：后端新增 `PUT /api/family-groups/{id}`，支持更新家庭名称和说明；前端家庭组列表中，创建者或 `owner` 可打开“修改家庭”弹窗并保存。
- 权限边界：沿用现有家庭组管理规则，仅家庭创建者、`owner` 角色或默认管理员可修改；普通已加入成员只能查看和选择，越权修改返回 403。
- 验证证据：`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；前端 `npm run build` 通过；`git diff --check` 通过；本地 API 临时数据冒烟通过，创建家庭组 `group_id=60` 后成功改名，非成员改名返回 403，随后已删除临时家庭组。
- 限制：`npm run lint` 未完成，原因是当前 `frontend/node_modules` 缺少 `eslint` 可执行文件。

## [2026-08-15] family-reward-REQ-023 手表表盘设置与孩子好友
- 手表端新增“设置-表盘设置”，支持“我的世界”、“HelloKitty”、“星光梦可”三款表盘；表盘偏好按孩子全局 `profile_key` 保存，切换后同一孩子设备继续复用该偏好。
- 手表端新增“好友”菜单：孩子可生成 8 位数字好友认证码，也可输入对方认证码添加好友；好友关系按孩子全局身份去重，不能添加自己，认证码一次性使用并有有效期。
- 新增好友列表和好友积分榜，手表端可查看好友积分，Web 家长端【孩子管理】可查看每个孩子的好友列表和包含自己的好友积分榜。
- 家长端新增好友消息通知：孩子通过手表添加好友后，相关家长账号可在【孩子管理】收到未读消息，并可标记已读。
- 数据模型新增 `watch_face_preferences`、`child_friend_codes`、`child_friendships`、`child_friend_notifications`，并补充必要索引；所有家长查看接口均通过当前家长与孩子绑定关系校验。
- 验证证据：`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；前端 `npm run build` 通过；本地 `/health` 返回 200，本地 `/watch` 响应包含“表盘设置”、“HelloKitty”、“星光梦可”、“生成好友码”和好友菜单；`git diff --check` 通过。
- 部署证据：提交 `549b096` 已推送 `origin/main`；生产主机 `zz.impx.net` 已备份 `/var/www/happylife/api` 与 `/var/www/happylife/frontend/static` 后同步新产物并重启 `family-reward-api.service`。线上 `https://happylife.ai.impx.net/health` 返回 200，`/watch` 已包含表盘设置、三款表盘和好友菜单，首页静态资源更新到 `index-BOkcMgBp.js` / `index-Cqr4TRPv.css`。
- Orbit `gpt_112eef0db67045cca2bfb7908720bbc3` / `family-reward-TASK-039` 复核：修复好友与表盘设置面板仍被内容缩放逻辑处理、无法按设计保持独立纵向滚动的问题；手表发布包校验新增 REQ-023 的表盘、好友接口、家长通知和一次性限时哈希好友码回归项。ASP.NET Core 构建通过（0 警告、0 错误），前端生产构建通过，Node 测试 8/8 通过，手表发布包校验与 `git diff --check` 通过。系统没有 `npm` 且复用的主工作树依赖缺少 ESLint 可执行文件，因此 lint 未运行。运行时未暴露 Atlas MCP 工具或资源，本机 `codex mcp list` 也无已配置服务，故无法读取 Atlas 公约/环境/关联事项，亦无法将 REQ-023、TASK-039、测试和完成证据写回或关闭；Atlas 恢复后应补录本节证据并将两项更新为完成。
- Orbit `gpt_c76b3af672bd4f67b8124f5b3f42a12c` / `family-reward-TASK-042` / test run `953c6c11854e`：新增可重复执行的 REQ-023 专项脚本，覆盖手表三款表盘与持久化、手表视口滚动、8 位数字码格式、自加拦截、跨家庭加好友、认证码一次性使用、好友积分榜、双方家长通知与已读处理，共 8/8 通过。测试发现并修复已用/无效好友码查询在数据 reader 尚未释放时提前回滚所导致的 PostgreSQL `A command is already in progress` 错误，重放现在稳定返回“好友认证码无效或已过期”。ASP.NET Core 构建通过（0 警告、0 错误），前端 Node 测试 8/8、TypeScript/Vite 生产构建、手表发布包校验和 `git diff --check` 均通过；环境没有 `npm`，复用依赖缺少 ESLint 可执行文件，故 lint 无法运行。运行时没有 Atlas MCP 工具/资源且本机 `codex mcp list` 无已配置服务，无法读取 Atlas 的真实 8 条用例、公约、环境和关联缺陷，也无法将 REQ-023、TASK-042、test run `953c6c11854e`、测试及完成证据写回或关闭；Atlas 恢复后应补录本条并更新事项状态。

## [2026-08-09] family-reward-REQ-018 家庭孩子成员管理与头像菜单收敛
- Orbit：`gpt_8bedc53115a644c1af0182627969bebf`；需求：`family-reward-REQ-018`（`1504c58c-a463-41f7-8aea-1979a970aa70`）；任务：`family-reward-TASK-033`（`89577270-3cc6-4892-9ad1-e56ae20c1cca`）；功能点：`5ec785f2-cce2-4e52-aa7f-ba1170f242e1`。
- 家庭组页面和导航统一更名为“家庭管理”；新增当前家庭的孩子成员区，展示孩子姓名、积分、现金、物品及归属家长。新增带家庭访问校验的 `GET /api/family-groups/{id}/children`，避免通过任意家庭 ID 越权查看。
- 新增管理员限定的 `DELETE /api/family-groups/{id}/children/{childId}`。删除仅移除所选家庭的孩子成员关系并撤销该家庭的有效认证码/设备；保留孩子与家长的全局归属。当孩子仍属于其他家庭时重挂全局账户锚点，当这是唯一家庭时保留无家庭归属的孩子记录，避免误删全局档案和账户。
- 用户头像菜单移除“新增家庭组”入口，仅保留家庭切换；选中家庭、系统设置、修改信息、修改密码或退出登录后自动关闭菜单。
- 自动化验证：前端 Node 测试 6/6 通过（新增头像菜单与家庭成员管理源码回归）；TypeScript 检查与 Vite 生产构建通过；ASP.NET Core 构建通过（0 警告、0 错误）；`git diff --check` 通过。当前环境无 `npm` 且 `frontend/node_modules` 未安装 ESLint 包，无法执行 lint。
- API 冒烟证据（运行 `req0181786256895`）：`/health` 返回 200；管理员家庭成员查询返回孩子及 `parentNames`；非管理员删除返回 403；管理员删除返回 `{"status":"ok"}`；移除后目标家庭孩子数为 0、原家庭仍为 1、家长全局孩子列表仍为 1。
- Atlas 同步阻塞：运行时工具与 MCP 资源均未暴露 Atlas，`list_mcp_resources` 仅有 `codex_apps`，本机 `codex mcp list` 返回 `No MCP servers configured yet`。因此无法读取 Atlas 中 REQ-018 的真实关联缺陷、公约和环境详情，也无法将需求、任务、测试与证据写回或关闭。Atlas 恢复后应将 `family-reward-REQ-018` 与 `family-reward-TASK-033` 更新为完成，并补录本节全部实现与验证证据。

## [2026-08-09] family-reward-REQ-017 手表申请页滚动与紧凑菜单
- Orbit：`gpt_1a0d077811ca46d3b7bfcb30a6758d27`；关联任务：`family-reward-TASK-032`（`cca1e8c3-a4d1-41a2-96e8-677c170e8494`）；功能点：`2ac19545-280c-485e-a6d2-0fc63884643f`。
- 申请页改为独立纵向滚动区域，支持触摸纵向滑动、细滚动条、滚动边界约束和 WebKit 手表 WebView 滚动条样式；申请页保持 1:1 字号，不再因表单较长被整体缩小。积分、记录、设备和绑定页继续使用既有无滚动缩放适配，不受本次改动影响。
- 右侧四个常驻功能键收纳为单个“菜单”按钮；点开后显示积分、申请、记录和设备入口，选择任一功能后自动收起并同步 `aria-expanded`，减少小表盘菜单长期挤占空间。
- 回归：扩展 `watch-app/scripts/verify-watch-app.mjs`，检查申请页只开放纵向滚动、跳过申请页缩放、触摸滚动和细滚动条，以及菜单折叠、展开与选中后收起行为。
- 验证证据：`node watch-app/scripts/verify-watch-app.mjs` 通过；`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；前端 Node 测试 4/4、TypeScript 检查和 Vite 生产构建通过；本地 `/health` 与 `/watch` 均返回 200，实际 `/watch` 响应包含申请页滚动和紧凑菜单规则；`git diff --check` 通过。当前 shell 没有 `npm`，且仓库未安装 ESLint 可执行文件，无法运行 `npm run lint`；本次未修改 React/TypeScript 源码。
- Atlas 同步阻塞：按任务要求检查运行时 MCP，未暴露 Atlas 工具或资源，`list_mcp_resources` 只有 `codex_apps`；本机 `codex mcp list` 也返回 `No MCP servers configured yet`。因此无法读取 Atlas 中 REQ-017 的真实关联缺陷、任务、公约和环境详情，也无法将需求、任务、测试及证据写回或关闭。Atlas 恢复后应将 `family-reward-REQ-017` 与 `family-reward-TASK-032` 更新为完成，并补录本节实现和验证证据。

## [2026-08-09] family-reward-REQ-014 孩子管理与家庭组关系修正
- 根因：前一版【孩子管理】仍随当前家庭组传递 `familyGroupId`，后端也先按家庭组解析再查孩子，导致同一家长切换家庭组时孩子列表变化。
- 修复：Web【孩子管理】改为按当前家长账号查询全局孩子；后端 `ownedOnly=true` 且未显式传家庭组时按 `child_user_bindings` 去重返回家长拥有的孩子，编辑、删除、手表认证码和设备管理均按家长-孩子绑定校验。
- 家庭组边界：家庭组列表保持只返回自己创建或已加入的组；直接管理家庭组成员接口增加创建者/owner 权限校验，新增/加入成员时同步该成员名下孩子到家庭组。
- 验证证据：`dotnet build FamilyReward.Api/FamilyReward.Api.csproj` 通过；`npm run build` 通过。

## [2026-08-09] family-reward-BUG-003 手表端展示效果问题
- 根因：积分查询首页只设置了 `text-align:center`，积分圆环和现金/物品指标仍按普通块级流从面板左侧开始排列，视觉上没有真正居中。
- 修复：查询首页激活时使用纵向 Flex 布局，通过 `align-items:center` 与 `justify-content:center` 将儿童姓名、积分圆环和指标区作为一个整体双轴居中；保留现有动态视口、无滚动和内容缩放适配。
- 回归：扩展 `watch-app/scripts/verify-watch-app.mjs`，明确检查查询首页的纵向排列、水平居中和垂直居中约束，防止再次退化为仅文字居中。
- 验证证据：`node watch-app/scripts/verify-watch-app.mjs` 通过；`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；本地 `/health` 返回 200，实际 `/watch` 响应包含完整双轴居中规则；`git diff --check` 通过。
- Atlas 同步阻塞：当前运行时未暴露 Atlas MCP 工具或资源，且 `codex mcp list` 返回 `No MCP servers configured yet`，无法读取 BUG-003/TASK-010 的真实关联需求、公约和环境，也无法把缺陷、任务、测试及完成证据写回或关闭。连接恢复后应将 `family-reward-BUG-003` 与 `family-reward-TASK-010` 更新为完成并补录本节证据。

## [2026-08-09] family-reward-REQ-014 全局孩子管理边界收紧
- `/api/children` 增加 `ownedOnly` 服务端过滤；【孩子管理】页面只请求当前家长通过 `child_user_bindings` 绑定的孩子，不再从前端透传统一用户 ID。
- 删除孩子、生成儿童认证码、查看/解绑手表设备、生成设备解绑码均校验当前家长是否为该孩子所属账号，避免家庭组成员通过手工 childId 管理别人孩子。
- 保留仪表盘、积分操作、交易记录、统计报表按家庭组展示组内孩子的协作视图；只收紧“孩子管理”和设备管理边界。
- `EnsureChildInFamilyGroup` 的账户初始化语句复用外层事务，保证创建家庭组、加入家庭组时自动同步名下孩子的事务一致性。
- 验证证据：ASP.NET Core 构建通过（0 警告、0 错误）；前端 Node 测试 4/4、TypeScript/Vite 生产构建通过；watch app 校验通过；`git diff --check` 通过。`npm run lint` 仍受已登记 BUG-002 影响，缺少 ESLint 可执行文件。

## [2026-08-09] family-reward-REQ-016 手表查询界面跨机型适配
- `/watch` 页面改为锁定动态可视视口，表盘尺寸同时受宽度、`100dvh` 高度、横竖屏与安全区约束，短屏、方屏及横屏不再产生页面级滚动条。
- 移除内容面板的 `overflow:auto` 和文本域拖动能力；激活面板根据实际可用宽高及内容尺寸计算缩放比例，在菜单切换、设备旋转、窗口/可视视口变化和字体加载完成后主动重新适配，避免内部滚动条。
- 响应式尺寸使用 `clamp()`/`vmin` 覆盖表盘边框、内容边距、积分环、指标区和菜单按钮；菜单预留横向空间，避免窄屏被裁切。保留 `100vh` 和基础 padding 作为旧 WebView 回退。
- 扩展 `watch-app/scripts/verify-watch-app.mjs`，检查动态视口、无滚动面板、主动适配事件，并覆盖 `194x368`、`240x240`、`320x360`、`466x466`、`368x194` 五组代表性纵向、方形和横向视口。
- 验证证据：watch app 校验通过；ASP.NET Core 构建通过（0 警告、0 错误）；前端 Node 测试 4/4、TypeScript 检查和 Vite 生产构建通过；本地 `/health` 返回 200，实际 `/watch` 响应包含动态视口和主动适配逻辑且不含 `overflow:auto`；`git diff --check` 通过。当前 shell 没有 `npm`，仓库也未安装 ESLint 可执行文件，因此无法重跑 lint；本次未修改 React/TypeScript 源码。
- Atlas 同步阻塞：运行时未暴露 Atlas MCP 工具或资源，`list_mcp_resources` 仅有其他插件，且 `codex mcp list` 返回 `No MCP servers configured yet`。因此无法读取 Atlas 中 REQ-016 的真实关联需求、缺陷、任务、公约和环境，也无法将 `family-reward-REQ-016`、`family-reward-TASK-008`、测试及完成证据写回或关闭。Atlas 连接恢复后应将需求和任务更新为完成，并补录本节全部实现与验证证据。
- Orbit 重试复查：再次扫描运行时工具仍无 Atlas，MCP 资源只有 `codex_apps`，本机 Codex 也仍未配置 MCP server；REQ-016 实现、代表性视口回归和 `git diff --check` 复验通过，远端写回与关闭的阻塞条件未变化。

## [2026-05-29 16:30] 项目启动与开发
- 完成后端 API 开发 (Python HTTP Server，零依赖)
- 完成前端页面开发 (React + HTML)
- API 测试通过: children、transactions、rules、stats、leaderboard
- 发现并修复 import os 缺失导致前端 500 错误
- 创建项目文档结构 (docs/, src/, scripts/)
- 创建 version.json (版本 1.0.0)
- 注意：技术选型偏离项目规范默认值 (.NET → Python)
- [2026-06-28] 新增系统设置页，支持语音文本输入和智能体服务配置。

## [2026-06-28 09:45] .NET 规范整改
- 按项目技术栈规范将实际后端迁移到 `FamilyReward.Api`。
- 后端采用 ASP.NET Core 10 Minimal API + PostgreSQL，端口固定为 `5102`，兼容现有 React 前端接口。
- 已实现孩子、交易、规则、统计、系统配置、智能体服务代理接口。
- 验证通过：`dotnet build FamilyReward.slnx`、`npm run build`、`/health`、`/api/children`、`/api/rules`、`/api/transactions`、`/api/system/config`。

## [2026-06-28 11:48] 线上部署
- 已部署到 `https://happylife.ai.impx.net`。
- 前端由 nginx 托管静态资源，后端由 `family-reward-api.service` 运行 ASP.NET Core API。
- 已为 `happylife.ai.impx.net` 签发并安装正确 HTTPS 证书。
- 验证通过：首页、`/health`、`/api/children`、`/api/rules`。

## [2026-07-13 23:05] 统一登录审计与本地开发修复
- 确认生产登录态只由 `/auth/me` 建立，不信任浏览器持久化用户数据。
- 补充 Vite `/auth` 代理，避免本地开发时认证路径被 SPA fallback 吞掉并形成重载循环。
- 新增 2 个回归测试；前端测试/构建和后端 Release 构建通过。
- 生产陈旧 Cookie 与完整 OAuth 登录/退出验证通过；生产代码未变更，未重复部署。

## [2026-08-02] 主业务链路代码审查
- 修复家庭组选择只在“孩子管理”生效的问题：首页、积分操作、交易记录、统计报表和语音解析现统一携带当前家庭组。
- 新增交易时校验孩子必须属于当前家庭组，避免错误家庭组写入。
- HTTP 删除交易改为复用事务化删除逻辑：删除记录时同步回滚孩子积分、现金或物品余额及累计收支，并限制在当前家庭组内。
- 家庭组切换时清理积分操作的旧选择，以及交易页的旧孩子筛选，避免残留状态误操作。
- 后端 Debug 构建通过（0 警告、0 错误）；前端 4 项测试和生产构建通过。
- `npm run lint` 无法启动：仓库尚未声明 ESLint 依赖和规则文件，已登记为工程化风险。

## [2026-08-08] family-reward-REQ-008 手表 app 版本适配与上架准备
- 验收核对：`watch-app/` 已包含 Android WebView 工程、小天才/小米/华为配置、Web/Android 图标、中文上架文案；线上 watch manifest 和 app-info 已返回 1.0.0 (100) 及三平台元数据。
- 补齐 release 签名接线：四项签名环境变量全部具备才允许生成 release 产物，避免误交未签名 APK/AAB。
- 新增 `watch-app/RELEASE-CHECKLIST.md`，明确三平台账号与准入、签名证书、HarmonyOS 工程边界、真机截图隐私边界、合规资料和真实上架完成证据。
- 扩展 `verify-watch-app.mjs`，校验服务端在线路由实现、儿童功能范围、三平台 child 配置、签名变量及发布清单章节。
- 测试证据：watch 配置校验通过；ASP.NET Core 构建通过（0 警告、0 错误）；生产 `/health` 为 200；生产 `/watch/manifest.json` 和 `/api/watch/app-info` 为 200；无设备 token 的 `/api/watch/score` 为 401 `watch_device_required`。
- 环境边界：本机无 npm、JDK、Gradle、Android SDK，无法在本机生成签名包或执行真机回归；真实上架还需发布主体的平台账号、签名证书、合规资料、目标设备和平台后台操作。
- Atlas 同步阻塞：当前 Codex 会话没有配置任何 MCP server（`codex mcp list` 返回 `No MCP servers configured yet`），无法读取或写回 Atlas；不得据此虚报 Atlas 状态已更新。
- Orbit `gpt_a3e2cb0a9e0146eabac905a4a8eafff9` / `family-reward-TASK-031` 复核（2026-08-09）：确认实现提交 `dfcba6a`、`179e1b2`、`de19124`、`8f13c7e` 已覆盖 REQ-008 的工程交付和上架准备边界；重新执行 watch 发布包校验、ASP.NET Core 构建（0 警告、0 错误）、前端 TypeScript/Vite 生产构建和 Node 测试（4/4）均通过，`git diff --check` 通过；线上 `/health`、`/watch/manifest.json`、`/api/watch/app-info` 分别返回 200，无设备 token 的 `/api/watch/score` 返回 401 `watch_device_required`。当前环境仅有 Node、无 npm 且未安装 ESLint 可执行文件，故无法重跑 lint；本次未修改 React/TypeScript 源码。运行时 MCP 资源仍只有 `codex_apps`，本机 `codex mcp list` 仍无服务，因此无法读取 Atlas 的真实公约/环境/关联事项，也无法将 REQ-008、TASK-031、测试和证据写回或更新状态；Atlas 恢复后应将 REQ-008 与 TASK-031 更新为完成，并补录本条证据。

## [2026-08-08] family-reward-BUG-002 前端 ESLint 门禁修复
- 为前端补齐 ESLint 9、TypeScript ESLint、React Hooks、React Refresh 和运行环境依赖，并提交可复现的 lockfile。
- 新增 flat config：检查 TypeScript/React 源码与配置文件，排除 `dist/`、`static/` 生成物；规则与现有 `tsconfig` 对 `any` 和未使用声明的约定保持一致。
- 更新 lint 脚本以兼容 ESLint 9 flat config，并继续启用未使用 disable 指令检查和零 warning 门禁。
- 测试证据：`npm ci`、`npm run lint`、`npm test`（4/4 通过）、`npm run build` 均通过。
- Atlas 同步阻塞：当前运行时未暴露 Atlas MCP 工具或资源，无法读取事项关联信息，也无法将 BUG-002 状态、测试与证据写回 Atlas；待连接恢复后应将该缺陷关闭为已完成并补录上述证据。

## [2026-08-08] family-reward-REQ-011 家庭组邀请码
- 将原家庭组 ID 邀请链接改为持久化的 8 位数字邀请码；只有家庭组创建者/管理员可以生成和查看，邀请码链接和二维码改为携带邀请码。
- 加入接口只接受邀请码，不再允许凭可枚举的家庭组 ID 直接加入；无效/失效邀请码返回 404，格式错误返回 400。
- 已有平台家长按邀请码加入后成为家庭成员，并在同一数据库事务内自动把其 `child_user_bindings` 名下全部有效孩子同步到目标家庭组；重复加入保持幂等，不会重复创建孩子。
- 数据模型新增 `family_group_invites`，儿童家庭成员唯一性改为 `(family_group_id, profile_key)`，允许不同家庭的同名孩子安全加入同一家庭组。
- 前端家庭组管理页支持输入/复制 8 位邀请码，明确提示自动同步名下全部孩子，并仅向管理员显示邀请码区域。
- 可复现测试：新增 `scripts/test-family-group-invites.sh`。本地 PostgreSQL 冒烟验证覆盖邀请码格式、正常加入、自动同步 1 名孩子、重复加入幂等、普通成员取码 403、无效码 404、按原始家庭组 ID 加入 400。
- 验证证据：`dotnet build FamilyReward.Api/FamilyReward.Api.csproj` 通过（0 警告、0 错误）；前端 `npm run lint`、`npm test`（4/4）、`npm run build` 通过；邀请流程脚本输出 `PASS family-group invite flow`。
- Atlas 同步阻塞：当前运行时没有 Atlas MCP 工具或资源，且 `codex mcp list` 返回 `No MCP servers configured yet`，无法读取 Atlas 的真实关联需求/缺陷/任务/公约/环境，也无法把 REQ-011、测试和证据回写或关闭。待 Atlas MCP 恢复后，应将 REQ-011 更新为完成并补录本节证据。

## [2026-08-08] family-reward-REQ-012 儿童手表积分页展示优化
- 手表积分首页移除家庭组名称，只保留儿童姓名、积分、现金和物品信息；家庭组仍作为服务端数据权限边界，不影响跨家庭组共享的儿童账户积分。
- 积分余额统一按至多一位小数展示；扩大积分圆环，使用响应式字号、等宽数字和紧凑字距，确保 `9999.9` 在常规及 260px 窄屏表盘中不被省略。
- 扩展 `watch-app/scripts/verify-watch-app.mjs`：防止家庭组元素或脚本回归，并检查一位小数格式化、数字布局以及 `9999.9` 回归样例。
- 验证证据：`node watch-app/scripts/verify-watch-app.mjs` 通过；`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）。
- Atlas 同步阻塞：当前运行时未暴露 Atlas MCP 工具或资源，且 `codex mcp list` 返回 `No MCP servers configured yet`，无法读取 REQ-012 的真实关联需求/缺陷/任务/公约/环境，也无法把需求状态、测试和完成证据写回 Atlas。待 Atlas MCP 恢复后，应将 REQ-012 更新为完成并补录本节证据。

## [2026-08-08] family-reward-REQ-013 手表设备解绑认证码
- 新增设备级一次性解绑认证码：家长端可针对某台有效手表生成，默认有效期 10 分钟（服务端限制 5–30 分钟）；生成新码会立即作废该设备尚未使用的旧码。
- 手表端解绑接口现在必须同时校验有效设备令牌和对应设备的解绑认证码；儿童绑定码、空码、错误码、过期码及其他设备的解绑码均不能解绑。
- 解绑码仅保存 SHA-256 哈希，成功解绑与消费认证码在同一数据库事务内完成；失败时手表保留本地设备令牌并展示错误，成功后才清除登录态。
- 家长 Web 端设备列表新增“生成解绑码”，展示适用设备、到期时间和一次性说明；原“家长直接解绑”管理能力保留。
- 新增可复现集成回归 `scripts/test-watch-device-unbind.sh`，隔离 PostgreSQL 数据库实测覆盖：缺码 400、绑定码冒用 400、错误码 400、正确解绑成功、重复调用 401 `watch_device_invalid`；数据库证据为绑定记录 1/已撤销 1、解绑码 1/已使用 1。
- 验证证据：`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；Node 前端测试 4/4 通过；TypeScript `tsc -b frontend` 与 Vite 生产构建通过；`node watch-app/scripts/verify-watch-app.mjs` 通过；`git diff --check` 通过。当前环境没有 `npm` 且未安装本地 ESLint 可执行文件，因此无法在本次会话重跑 `npm run lint`，TypeScript 构建已覆盖本次前端类型检查。
- Atlas 同步阻塞：运行时未暴露 Atlas MCP 工具或资源，且再次执行 `codex mcp list` 返回 `No MCP servers configured yet`。无法读取 Atlas 中 REQ-013 的关联需求/缺陷/任务、公约和环境，也无法将事项关闭或写回测试与完成证据；待 Atlas MCP 恢复后应将 REQ-013 更新为完成，并补录本节实现及验证证据。

## [2026-08-08] family-reward-REQ-014 全局孩子管理
- 新增 `child_profiles` 全局孩子档案，以 `profile_key` 作为跨家庭组唯一身份；孩子姓名、状态和备注统一从全局档案读取，所属账号修改后同步更新全部家庭组成员行，受邀家庭成员无权修改别人的孩子档案。
- 新建孩子时，除当前家庭组外，自动加入所属账号已创建或已加入的全部家庭组；家长通过 8 位邀请码加入其他家庭组时，继续自动同步其名下全部有效孩子，实现“默认自己的孩子 + 邀请别人的孩子”。
- 积分、现金和物品账户继续以唯一 `profile_key` 存储；在任一家庭组产生的积分交易会更新同一账户，并在其他家庭组立即读取到相同余额。
- 每个孩子只允许一个有效手表设备：数据库增加按 `child_profile_key` 的部分唯一索引，迁移时保留最早有效绑定并撤销重复项；绑定接口在并发前后均校验唯一性并返回明确错误。设备列表、家长解绑和解绑码生成均改为按全局孩子身份工作，可在孩子所属的任一家庭组管理同一设备。
- 新增可复现回归脚本 `scripts/test-global-child-management.sh`。本地 PostgreSQL/API 实测覆盖：两个家庭组自动加入、跨组改名一致、跨组共享 17 积分、受邀家长孩子自动加入、跨组查看唯一设备、第二台设备绑定被拒绝。
- 验证证据：`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；REQ-014 API 回归输出 `REQ-014 API verification passed: auto-membership, global profile, shared points, invited child, unique device.`；前端 ESLint 零 warning 通过；TypeScript `tsc -b` 与 Vite 生产构建通过。
- Atlas 同步阻塞：运行时未暴露 Atlas MCP 工具或资源，`list_mcp_resources` 仅返回其他已连接插件，且 `codex mcp list` 返回 `No MCP servers configured yet`。因此无法读取 Atlas 中 REQ-014 的真实关联需求/缺陷/任务、公约和环境，也无法将事项更新为完成或写回上述测试与证据；Atlas 连接恢复后应将 `family-reward-REQ-014` 更新为完成并补录本节全部证据。
- Orbit 重试复查：再次扫描运行时工具未发现 Atlas，MCP 资源仍只有 `codex_apps`，`codex mcp list` 仍返回无已配置服务；阻塞条件未变化，未虚报 Atlas 已读取或事项已关闭。

## [2026-08-08] family-reward-REQ-015 项目改名为家加分
- 将主 Web 页头、仪表盘、身份选择页、HTML 标题和根项目元数据统一改名为“家加分”。
- 将手表 H5 品牌、应用清单、上架配置和上架文案统一改为“家加分”/“家加分手表积分”；将后端默认智能助手提示和 MCP 用户可见展示名同步改为“家加分”。
- 更新 README、项目状态、需求清单、任务分解和 Goldfish/MCP 接入资料。为保持部署与客户端兼容，保留 `family-reward`、`FamilyReward`、现有域名、Android 包名以及 `HappyLifeWatch` 工程名/User-Agent 等技术标识。
- 验证证据：`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；项目本地 ESLint 入口零 warning 通过；前端 Node 测试 4/4 通过；TypeScript 与 Vite 生产构建通过；`node watch-app/scripts/verify-watch-app.mjs` 通过；JSON 配置解析通过；8 个代表性品牌面断言通过；`git diff --check` 通过。当前 shell 没有全局 `npm` 命令，已直接调用仓库内相同的 ESLint、TypeScript、Vite 和 Node 测试入口完成等价验证。
- Atlas 同步阻塞：运行时没有 Atlas MCP 工具或资源，`codex mcp list` 返回 `No MCP servers configured yet`。因此无法读取 Atlas 中 REQ-015 的真实关联需求、功能点、任务、公约和环境信息，也无法将需求、测试与完成证据写回或把 `family-reward-REQ-015` 关闭；Atlas 连接恢复后应将该事项更新为完成，并补录本节实现边界与全部验证证据。

## [2026-08-16] family-reward-BUG-001 手表积分申请跨家庭不可见
- 复现数据：生产库 `watch_reward_requests` 中存在 3 条 `pending` 申请，孩子为玥玥（`child_id=139`），实际家庭组为 `220`（长安在哪里），绑定家长为 `wssparent`。
- 根因：家长 Web 端“待确认申请”查询和确认请求都携带当前页面选中的家庭组；当家长切换到其他家庭组时，自己孩子在实际家庭组下提交的手表积分申请被 `family_group_id` 过滤掉。
- 修复：家长端默认按当前家长名下孩子聚合查询所有待确认手表申请；后端在未指定家庭组时按申请自身 `family_group_id` 入账，并继续校验家长与孩子绑定关系、家庭组成员权限。
- 验证证据：生产 SQL 按新查询条件确认 `wssparent` 可见 3 条待处理申请；`dotnet build FamilyReward.Api/FamilyReward.Api.csproj --no-restore` 通过（0 警告、0 错误）；前端 `npm run build` 通过；生产 `/health` 返回 200，首页加载 `index-C3YY20Jm.js`；生产 HTTP 使用 `wssparent` 查询 `/api/reward-requests?status=pending&limit=20` 返回玥玥 3 条待确认申请，使用 `wzsparent` 查询返回空。

## [2026-08-16] family-reward-REQ-028/030/031/032/033 移动端与反馈能力补齐
- REQ-028：家庭组管理新增明确的家庭组查看下拉框，切换后加载对应家庭组孩子，同时保留创建、邀请、加入、改名和删除能力。
- REQ-030：手表首页改为单一“菜单”入口，独立菜单完整展示积分申请、积分详情、添加好友、排行榜、表盘设置和设备绑定六项功能；各子页统一返回菜单并支持滚动，适配 240x240 与 368x194 屏幕。
- REQ-030：积分申请标题和备注增加语音输入；Android WebView 增加麦克风权限申请和可信来源权限桥接，不支持语音识别时明确回退到键盘输入，语音结果不会自动提交。
- REQ-031：Web 全局新增反馈入口，支持问题、建议和表扬三类反馈，提交时携带稳定记录标识、页面来源和脱敏后的上下文；后端同源代理固定写入 `family-reward` 项目，并只返回当前用户自己的反馈及回复。
- REQ-032：服务配置页压缩移动端间距、调整按钮和输入布局，并为长结果增加安全滚动，保证窄屏可操作。
- REQ-033：移动端底栏改为菜单、家庭智能体命令输入、语音和发送四个核心操作；对话以独立浮层显示，关闭后仍保留原业务仪表盘。
- 自动化覆盖：新增五条需求静态回归；扩展手表发布校验和 REQ-023 好友集成脚本，覆盖六项菜单、滚动、语音权限及新布局。
- 联调证据：本地反馈提交与“我的反馈”查询成功，来源 URL 中敏感参数已剔除；REQ-023 好友集成回归 8/8 通过；Chrome 在 240x240 与 368x194 两种手表尺寸完成视觉验收。

## [2026-08-16] family-reward-REQ-031 公共反馈组件复用修正
- 删除家加分前端自写的反馈表单、反馈列表及专用 service/type，改为直接加载 Atlas 统一发布的 `https://home.ai.impx.net/feedback-widget.js`。
- 通过公共组件的 `window.AgentDashFeedback.currentUser` 配置注入当前登录用户的姓名、邮箱和手机号；组件打开时优先回显邮箱，未配置邮箱时回退手机号。
- 家加分同源代理兼容公共组件的 `feedback_type`、`submitter_contact`、`source_url` 字段，缺失的来源记录编号由服务端生成，同时保留 URL 脱敏和 Atlas 项目固定绑定。

## [2026-08-18] family-reward-REQ-048 对外 MCP 家长权限隔离
- 家庭积分应用的 18 个 MCP 工具统一新增必填调用方身份参数，缺失参数在业务调用前直接拒绝；工具目录、Goldfish 工具库清单、安装模板和脚本同步更新。
- 孩子增删改查、积分调整和积分记录写操作按 `child_user_bindings` 校验家长归属，不能操作其他家长的孩子；规则增删改查按家长隔离，家庭组操作只允许访问当前家长创建或加入的家庭组。
- 积分查询按家长汇总其创建或加入的全部家庭组，并保留孩子全局档案去重，满足同一孩子加入多个家庭组时只返回一个积分账户。
- 自动化证据：后端构建 0 警告/0 错误；MCP 目录与参数回归 21/21；新增权限集成回归覆盖名下写入、跨家长拒绝、跨家庭组查询和规则隔离。

## [2026-08-18] family-reward-REQ-049 家长菜单与手表积分申请精简
- 家长 Web 端桌面和移动导航移除“交易记录”“统计报表”，首页移除“查看全部”交易跳转；历史页面和 API 保留，避免破坏已有数据与深链。
- 手表积分申请移除手工积分和说明输入，只允许先选择家长配置的正向奖励规则；标题与积分由所选规则带入，未选规则时禁止提交。
- 自动化证据：前端需求测试 21/21、严格 ESLint、TypeScript/Vite 生产构建、手表发布校验全部通过。

## [2026-08-25] family-reward-REQ-060 付费动态表盘需求分析
- Orbit：`gpt_ac7db6bf0cfb4a75aabf13081afc82ca`；需求：`family-reward-REQ-060`；分析任务：`family-reward-TASK-221`。
- 新增 `docs/REQ-060-ANALYSIS.md`，基于现有静态表盘偏好、设备令牌、积分申请和好友通知实现，明确拆分表盘商品、儿童解锁申请、家长通知、`agent-pay` 支付订单与孩子主题权益，服务端在保存表盘和支付回调两侧强制校验授权。
- 明确现有免费静态 `world` 不应被突然锁定，建议新增独立付费 `world_dynamic`；支付成功只授予权益，不强制切换表盘。定义金额/币种核验、回调验签、幂等、并发、多家长权限、失败恢复和动态效果降级验收边界。
- `agent-pay` 契约、价格/权益/退款口径以及库洛米和“我的世界”IP 授权尚未提供，会阻塞实现验收或上线但不阻塞分析任务。`TASK-221` 可凭分析文档和提交关闭；REQ-060 保持待实现。

## [2026-08-25] family-reward-REQ-059 付费动态表盘需求分析
- Orbit：`gpt_7eb2331585d84a7baee5c2f83ea61823`；需求：`family-reward-REQ-059`；分析任务：`family-reward-TASK-222`。
- 新增 `docs/REQ-059-ANALYSIS.md`；核对确认其 payload 与 `REQ-060` 相同且引用同一 Atlas 功能点，复用完整规格并明确两项只能实现一套商品、订单和权益模型。
- `TASK-222` 可凭分析文档和提交关闭；`REQ-059` 尚无动态主题、申请、通知、`agent-pay` 支付及权益校验实现，保持待实现。建议产品确认 `REQ-059`/`REQ-060` 的主需求编号并将另一项标记为重复。

## [2026-08-25] family-reward-REQ-061 家长 Web 端付费解锁表盘需求分析
- Orbit：`gpt_5e4a09bd45cd427c8cdb44ca498ee2ed`；需求：`family-reward-REQ-061`；分析任务：`family-reward-TASK-223`。
- 新增 `docs/REQ-061-ANALYSIS.md`，将“接收手表推送”落为可恢复的服务端申请通知，明确家长端主题名称展示、公共 pay 组件薄适配、可信支付回调、权益事务和在线/离线手表重新查询边界。
- 当前仓库没有表盘申请通知、公共 pay 集成、支付订单/回调、儿童权益或同步实现；`TASK-223` 可凭分析文档和提交关闭，`REQ-061` 保持待实现。公共 pay 契约、价格/权益/退款、多家长并发及同步时限需在开发验收前确认。
