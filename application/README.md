# Goldfish 工具库接入（家庭积分系统）

本目录用于放置可直接导入 Goldfish 的智能体工具库配置。

## MCP 服务信息

- 服务名称：`family-reward-mcp`
- 服务说明：`家庭积分系统 MCP 服务（统一工具）`
- MCP 接口地址：`https://happylife.ai.impx.net/api/mcp`
- 支持方法：`initialize`、`initialized`、`notifications/initialized`、`ping`、`tools/list`、`tools/call`
- 统一工具名：`family_reward_tool`
- 工具支持动作：
  - `add_child`
  - `adjust_score`
  - `query_score`
  - `query_children`

## 可直接导入文件

- `goldfish-tool-library.json`

## 建议接入方式

1. 进入 Goldfish 的“智能体管理 -> 工具库管理”。
2. 新建 MCP 工具库或新增工具。
3. 将 `goldfish-tool-library.json` 内容作为配置导入。
4. 确认连接后，可先调用 `initialize`、`tools/list` 做连通性校验，再测试 `adjust_score` / `query_children`。
