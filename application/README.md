# Goldfish 工具库接入（家加分）

本目录用于放置可直接导入 Goldfish 的智能体工具库配置。

## MCP 服务信息

- 服务名称：`family-reward-mcp`
- 服务说明：`家加分 MCP：家庭是当前家长自己的成员和孩子；圈子是多个家庭协作查看孩子积分的空间`
- MCP 接口地址：`https://happylife.ai.impx.net/api/mcp`
- 支持方法：`initialize`、`initialized`、`notifications/initialized`、`ping`、`tools/list`、`tools/call`
- 独立工具：40 个，完整名称、描述和权限见 `docs/FAMILY-REWARD-MCP-TOOLS.md`。

## 可直接导入文件

- `goldfish-tool-library.json`（40 个工具及完整 `inputSchema`）

## 建议接入方式

1. 进入 Goldfish 的“智能体管理 -> 工具库管理”。
2. 新建 MCP 工具库或新增工具。
3. 将 `goldfish-tool-library.json` 内容作为配置导入。
4. 确认连接后，可先调用 `initialize`、`tools/list` 做连通性校验，再测试 `family_reward_query_score` / `family_reward_query_children`。
