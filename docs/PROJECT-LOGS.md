# 家加分 - 进展日志

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
