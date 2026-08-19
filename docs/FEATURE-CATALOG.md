# 家加分功能点目录

## 文档信息

- 对应需求：`family-reward-REQ-024`（重新梳理补充本项目的功能点）
- 关联任务：`family-reward-TASK-038`（需求分析）
- Atlas 功能点引用：`4b179f4c-0585-4c66-ac31-8461fca54284`
- 梳理基线：Git `168a13f`（2026-08-15）
- 状态口径：`已实现` 表示仓库存在可定位实现；`待外部完成` 表示仍依赖发布主体、平台账号或真机；本目录不把历史 Python 服务计入当前产品能力。

## 产品范围与角色

家加分用于家长管理自己的家庭成员和孩子，并通过圈子与其他家庭协作查看孩子积分。当前产品包含家长 Web、儿童手表端、ASP.NET Core API、PostgreSQL 数据层以及供智能体调用的 MCP 接口。

| 角色/调用方 | 主要权限边界 |
| --- | --- |
| 家长 | 管理自己不随圈子切换的家庭成员、孩子档案、账户、交易和手表设备；访问自己创建或已加入的圈子 |
| 圈子管理员 | 创建/删除圈子、查看邀请码、管理圈子中的孩子成员 |
| 圈子成员 | 查看已加入圈子中的孩子余额和协作数据；不能执行管理员限定操作 |
| 儿童手表 | 通过一次性儿童认证码绑定单一孩子；使用设备令牌查询积分、规则和申请状态 |
| 智能体/MCP 客户端 | 通过 JSON-RPC 工具目录执行家庭、孩子、积分、规则、圈子、设备和申请操作 |

## 功能点清单

### A. 登录、身份与账户

| 编号 | 功能点 | 验收口径 | 状态 | 实现证据 |
| --- | --- | --- | --- | --- |
| FR-A01 | 统一登录 | 未经 `/auth/me` 服务端确认的浏览器缓存不能建立登录态；登录后可访问受保护路由 | 已实现 | `frontend/src/auth.ts`、`frontend/auth.test.ts`、`FamilyReward.Api/Program.cs` |
| FR-A02 | 应用身份选择 | 首次进入可选择家长或孩子身份，选择结果形成应用内资料 | 已实现 | `frontend/src/pages/Identity.tsx`、`/api/user/profile` |
| FR-A03 | 账号菜单 | 用户名菜单支持家庭切换、系统设置、修改资料、修改密码和退出；操作后菜单关闭 | 已实现 | `frontend/src/components/UserMenu.tsx`、`frontend/userMenu.test.ts` |
| FR-A04 | 前端访问保护 | 未登录用户进入业务路由时转到统一登录，身份未就绪时进入身份选择 | 已实现 | `frontend/src/components/ProtectedRoute.tsx`、`IdentityGate.tsx` |

### B. 圈子协作

| 编号 | 功能点 | 验收口径 | 状态 | 实现证据 |
| --- | --- | --- | --- | --- |
| FR-B01 | 圈子创建与切换 | 家长可创建圈子，只看到自己创建或已加入的圈子，并在 Web 中切换当前圈子 | 已实现 | `frontend/src/contexts/FamilyGroupContext.tsx`、`FamilyGroups.tsx`、`/api/family-groups` |
| FR-B02 | 圈子邀请码 | 管理员可获得 8 位邀请码、邀请链接和二维码；无效邀请码不能加入圈子 | 已实现 | `/api/family-groups/{id}/invite`、`/api/family-groups/join`、`scripts/test-family-group-invites.sh` |
| FR-B03 | 加圈自动同步孩子 | 家长按邀请码加入后，其名下有效孩子自动加入目标圈子，重复加入保持幂等 | 已实现 | `JoinFamilyGroup` 相关后端逻辑、`scripts/test-family-group-invites.sh` |
| FR-B04 | 圈子孩子成员视图 | 当前圈子展示孩子姓名、积分、现金、物品及归属家长 | 已实现 | `frontend/src/pages/FamilyGroups.tsx`、`/api/family-groups/{id}/children` |
| FR-B05 | 圈子孩子成员移除 | 仅管理员可从当前圈子移除孩子；保留孩子全局档案、家庭归属和其他圈子关系 | 已实现 | `/api/family-groups/{id}/children/{childId}`、`scripts/test-family-group-children.sh` |
| FR-B06 | 圈子删除 | 仅管理员可删除圈子；孩子档案、积分账户和家庭归属不随圈子误删 | 已实现 | `deleteFamilyGroup`、`frontend/userMenu.test.ts` |
| FR-B07 | 圈子访问隔离 | 查询、成员维护和统计操作校验当前用户是否属于目标圈子或具备管理员权限 | 已实现 | `EnsureFamilyGroupAccess` 相关后端逻辑 |

### C. 孩子档案与账户

| 编号 | 功能点 | 验收口径 | 状态 | 实现证据 |
| --- | --- | --- | --- | --- |
| FR-C01 | 全局孩子档案 | 孩子以 `profile_key` 跨家庭唯一存在，改名和状态变更在各家庭一致 | 已实现 | `child_profiles`、`child_user_bindings`、`scripts/test-global-child-management.sh` |
| FR-C02 | 孩子新增、编辑、删除 | 家长可管理自己名下孩子；不能通过手工 childId 管理其他家长的孩子 | 已实现 | `frontend/src/pages/Children.tsx`、`/api/children`、所有权校验逻辑 |
| FR-C03 | 跨圈子自动成员关系 | 新建孩子自动加入所属家长已创建或加入的圈子 | 已实现 | `CreateChildCore`、`EnsureChildInFamilyGroup` |
| FR-C04 | 全局共享账户 | 同一孩子的积分、现金、物品在不同家庭中读取同一账户余额 | 已实现 | `accounts`、`scripts/test-global-child-management.sh` |
| FR-C05 | 孩子归属边界 | 孩子管理、积分操作和交易查询按当前家长名下孩子过滤，不随家庭切换丢失 | 已实现 | `ownedOnly=true`、`frontend/userMenu.test.ts` |

### D. 奖励、规则与账本

| 编号 | 功能点 | 验收口径 | 状态 | 实现证据 |
| --- | --- | --- | --- | --- |
| FR-D01 | 积分/现金/物品调整 | 选择孩子后可对三类账户执行正负调整，并记录分类和说明 | 已实现 | `frontend/src/pages/Reward.tsx`、`/api/transactions` |
| FR-D02 | 规则快捷记账 | 可选正向或负向规则自动带出数量、分类和描述，确认后记账 | 已实现 | `Reward.tsx`、`Rules.tsx` |
| FR-D03 | 语音记账 | 浏览器识别语音后调用智能体纠正孩子姓名并解析奖励命令，用户确认后入账 | 已实现 | `parseRewardVoice`、`/api/agent/parse-reward` |
| FR-D04 | 批量交易 | API 支持一次提交多条交易，供批量业务或工具调用使用 | 已实现 | `/api/transactions/batch` |
| FR-D05 | 删除交易回滚 | 删除交易时在事务内同步回滚对应孩子的账户余额和累计值 | 已实现 | `DeleteTransactionCore`、`/api/transactions/{id}` |
| FR-D06 | 规则管理 | 支持新增、编辑、删除正向/负向规则，支持分类、启用状态和红线标记 | 已实现 | `frontend/src/pages/Rules.tsx`、`/api/rules` |

### E. 仪表盘、记录与统计

| 编号 | 功能点 | 验收口径 | 状态 | 实现证据 |
| --- | --- | --- | --- | --- |
| FR-E01 | 家庭仪表盘 | 展示孩子状态、家庭积分/现金/物品汇总、孩子数、快捷操作和最近动态 | 已实现 | `frontend/src/pages/Dashboard.tsx`、`/api/stats/dashboard` |
| FR-E02 | 交易查询 | 支持按孩子、类型、分类、日期和描述筛选，并分页展示 | 已实现 | `frontend/src/pages/Transactions.tsx`、`/api/transactions` |
| FR-E03 | CSV 导出 | 将当前页交易记录以带 UTF-8 BOM 的 CSV 下载 | 已实现 | `Transactions.tsx` 的 `exportCSV` |
| FR-E04 | 统计报表 | 展示累计统计、类别分布、孩子积分对比和交易次数 | 已实现 | `frontend/src/pages/Stats.tsx`、`/api/stats/dashboard`、`/leaderboard`、`/categories` |
| FR-E05 | 响应式业务页面 | 交易记录在小屏使用卡片、大屏使用表格；主要表单和导航适配移动端 | 已实现 | React 页面与 `frontend/src/styles/global.css` |

### F. 儿童手表端

| 编号 | 功能点 | 验收口径 | 状态 | 实现证据 |
| --- | --- | --- | --- | --- |
| FR-F01 | 一次性认证码绑定 | 家长为孩子生成限时认证码；手表使用后获得设备令牌，认证码不可重复使用 | 已实现 | `/api/children/{id}/auth-code`、`/api/watch/device-bind` |
| FR-F02 | 单孩子单有效设备 | 同一全局孩子最多存在一台有效手表，重复绑定被拒绝 | 已实现 | `ux_watch_device_bindings_active_child`、全局孩子回归脚本 |
| FR-F03 | 手表积分查询 | 手表展示孩子姓名、积分、现金和物品；不展示家庭组；积分最多一位小数 | 已实现 | `/watch`、`/api/watch/score`、`verify-watch-app.mjs` |
| FR-F04 | 手表规则与积分申请 | 手表可查询规则、提交奖励申请并查看申请状态；家长 API 可审批 | 已实现 | `/api/watch/rules`、`/requests`、`/approve` |
| FR-F05 | 设备管理 | 家长可查看孩子设备、直接撤销设备并查看绑定信息 | 已实现 | `Children.tsx`、`/api/children/{id}/devices` |
| FR-F06 | 一次性解绑码 | 家长按设备生成限时解绑码；手表需同时提交有效设备令牌和解绑码 | 已实现 | `/unbind-code`、`/api/watch/device-unbind`、`scripts/test-watch-device-unbind.sh` |
| FR-F07 | 表盘适配 | 查询内容双轴居中；按动态视口、安全区和横竖屏缩放；申请页可纵向滚动 | 已实现 | `/watch` 样式与脚本、`verify-watch-app.mjs` |
| FR-F08 | 紧凑功能菜单 | 手表以单一菜单按钮切换积分、申请、记录、设备，选择后收起 | 已实现 | `/watch`、`verify-watch-app.mjs` |
| FR-F09 | 三平台上架准备 | 提供 Android WebView 壳、小天才/小米/华为配置、上架文案、签名接线和校验清单 | 已实现 | `watch-app/`、`RELEASE-CHECKLIST.md` |
| FR-F10 | 三平台真实上架 | 使用发布主体账号、证书、合规资料和目标真机生成签名包并完成商店审核 | 待外部完成 | `watch-app/RELEASE-CHECKLIST.md` |

### G. 系统配置、智能体与 MCP

| 编号 | 功能点 | 验收口径 | 状态 | 实现证据 |
| --- | --- | --- | --- | --- |
| FR-G01 | 语音配置 | 可启停语音、配置识别语言和转写提供方 | 已实现 | `frontend/src/pages/Settings.tsx`、`/api/system/config` |
| FR-G02 | 智能体服务配置 | 可配置启用状态、地址、密钥、模型、超时和系统提示词 | 已实现 | `Settings.tsx`、`system_config.json` |
| FR-G03 | 智能体连通测试 | 系统设置页可发起测试请求并展示成功结果或错误 | 已实现 | `invokeAgent`、`/api/agent/invoke` |
| FR-G04 | MCP 协议服务 | 提供 initialize、ping、tools/list 和 tools/call 等 JSON-RPC 能力 | 已实现 | `/api/mcp`、`application/mcp/` |
| FR-G05 | MCP 孩子与积分工具 | 所有工具要求 `parent_user_id`；默认仅查询本人孩子，指定圈子可查看圈内孩子余额，明细和写操作仍限孩子所属家长 | 已实现 | `BuildMcpToolCatalog`、`scripts/test-family-reward-mcp.sh`、`scripts/test-family-reward-mcp-authorization.sh` |
| FR-G06 | MCP 家庭、规则与圈子工具 | 家庭成员不随圈子切换；规则按家长隔离；圈子只允许成员查询、管理员维护，并拒绝未声明参数 | 已实现 | `SafeInvokeFamilyRewardMcpTool`、`application/goldfish-tool-library.json` |
| FR-G07 | MCP 全业务工具目录 | 40 个工具覆盖孩子、账户记录、规则模板、家庭成员、圈子、设备、好友、积分申请和圈子统计 | 已实现 | `docs/FAMILY-REWARD-MCP-TOOLS.md`、`application/mcp/family-reward-mcp-tool-library-split.json` |

### H. 安全、数据与运维边界

| 编号 | 功能点 | 验收口径 | 状态 | 实现证据 |
| --- | --- | --- | --- | --- |
| FR-H01 | PostgreSQL 持久化与迁移 | 启动时幂等创建/升级家庭、孩子、账户、交易、规则和设备相关结构 | 已实现 | `EnsureDatabase` 相关后端逻辑 |
| FR-H02 | 事务一致性 | 加入圈子、创建孩子、记账、删交易、移除成员等多表操作使用事务保持一致 | 已实现 | `Program.cs` 中对应 Core 方法 |
| FR-H03 | 凭据与认证码保护 | 系统配置读写仅允许已建立家长资料的用户；绑定码和解绑码仅持久化哈希并具有失效/消费状态 | 已实现 | `/api/system/config` 的家长校验、认证码后端逻辑 |
| FR-H04 | 健康检查与配置化运行 | 提供 `/health`；数据库和监听地址可通过环境配置 | 已实现 | `/health`、`appsettings*.json`、`README.md` |
| FR-H05 | 自动化回归入口 | 提供前端登录/菜单测试、家庭邀请/成员/全局孩子/设备解绑脚本和手表静态校验 | 已实现 | `frontend/*.test.ts`、`scripts/test-*.sh`、`verify-watch-app.mjs` |

## 数据与权限边界摘要

1. `child_profiles.profile_key` 是全局孩子身份，`children` 是孩子在具体圈子中的成员关系，`accounts` 保存共享余额。
2. `child_user_bindings` 决定家长能否全局管理某个孩子；家庭成员身份不能替代孩子所有权。
3. 圈子用于协作可见范围；家庭和孩子归属不随圈子切换，孩子管理、积分操作和交易明细以当前家长所有权为主，圈子统计按所选圈子聚合。
4. 管理员操作、孩子所有权操作和手表设备操作都由服务端校验，不能依赖前端隐藏按钮作为权限控制。
5. 手表设备令牌、绑定认证码和解绑认证码是三种不同凭据；解绑必须绑定到具体设备。

## 验收与追踪建议

- Atlas 中可将本目录 A–H 八个模块作为功能点分组，将 `FR-*` 编号写入功能点验收描述，以便后续需求/缺陷稳定关联。
- REQ-024 的验收证据应包含：功能目录提交、前后端构建、现有自动化测试、手表校验以及 Atlas 回写记录。
- 真实三平台上架应保持为独立发布事项，不应把“工程准备完成”等同于“商店审核完成”。
- 历史 `server/`、`backend/` 仅用于行为对比，不纳入现行能力验收。
