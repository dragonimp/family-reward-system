# Goldfish 工具库接入（家庭积分系统）

本目录用于放置可直接导入 Goldfish 的智能体工具库配置。

## MCP 服务信息

- 服务名称：`family-reward-mcp`
- 服务说明：`家庭积分系统 MCP 服务（按工具拆分）`
- MCP 接口地址：`https://happylife.ai.impx.net/api/mcp`
- 支持方法：`initialize`、`initialized`、`notifications/initialized`、`ping`、`tools/list`、`tools/call`
- 独立工具名（可直接用于 `tools/call`）：
  - `family_reward_add_child`
  - `family_reward_update_child`
  - `family_reward_query_children`
  - `family_reward_delete_child`
  - `family_reward_adjust_score`
  - `family_reward_query_score`
  - `family_reward_log_score_record`
  - `family_reward_create_record`
  - `family_reward_update_record`
  - `family_reward_delete_record`
  - `family_reward_query_operation_records`
  - `family_reward_query_rules`
  - `family_reward_create_rule`
  - `family_reward_update_rule`
  - `family_reward_delete_rule`
  - `family_reward_query_family_groups`
  - `family_reward_create_family_group`

## 可直接导入文件

- `goldfish-tool-library.json`

## 建议接入方式

1. 进入 Goldfish 的“智能体管理 -> 工具库管理”。
2. 新建 MCP 工具库或新增工具。
3. 将 `goldfish-tool-library.json` 内容作为配置导入。
4. 确认连接后，可先调用 `initialize`、`tools/list` 做连通性校验，再测试 `family_reward_query_score` / `family_reward_query_children`。
