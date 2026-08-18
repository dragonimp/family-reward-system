## 家庭积分应用 MCP 工具配置（Goldfish）

用于把家加分 MCP 工具接入 Goldfish 的本地 `.goldfish` 配置。

### 1) 配置参数

- `FAMILY_REWARD_MCP_LIBRARY_JSON`（可选）：拆分库清单（JSON）路径，默认 `application/mcp/family-reward-mcp-tool-library-split.json`（脚本会按仓库根目录/脚本路径解析）。
- `FAMILY_POINTS_MCP_URL`（可选）：MCP 服务 URL，例如 `https://happylife.ai.impx.net/api/mcp`。
- `FAMILY_POINTS_MCP_TOKEN`（可选）：MCP 访问令牌。
- `FAMILY_POINTS_MCP_TOOL_KEY`（可选）：默认 `family-reward-mcp`。
- `FAMILY_POINTS_MCP_NAME`（可选）：默认 `家庭积分应用`。
- `FAMILY_POINTS_MCP_DESC`（可选）：工具描述，默认说明所有工具必须传入 `parent_user_id`，孩子和规则写操作按家长归属校验，积分查询覆盖该家长创建或加入的全部家庭组。
- `FAMILY_POINTS_MCP_SERVERS`（可选）：服务拆分后使用。每行一条，格式：
  `url|toolKey|name|description|token`
  - `url`：必填
  - `toolKey`：可选，默认 `family-reward-mcp`
  - `name`：可选
  - `description`：可选
  - `token`：可选，不填则复用 `FAMILY_POINTS_MCP_TOKEN`
- `GOLDFISH_HOME`（可选）：默认 `~/.goldfish`

### 2) 快速应用

```bash
# 推荐：优先读取拆分库清单
export FAMILY_REWARD_MCP_LIBRARY_JSON="application/mcp/family-reward-mcp-tool-library-split.json"
export FAMILY_POINTS_MCP_TOKEN=""  # 如无 token 可留空
bash scripts/install-family-rewards-mcp-tool.sh
```

```bash
# 手工多服务（当你不想走库文件时）
export FAMILY_POINTS_MCP_SERVERS=$'https://happylife.ai.impx.net/api/mcp|family-reward-mcp|家庭积分应用|家庭积分应用 MCP：所有工具必须传入 parent_user_id，并按家长归属校验孩子、积分、规则和家庭组权限。|'
bash scripts/install-family-rewards-mcp-tool.sh
```

### 3) 脚本行为

- 会写入 `tools/<toolKey>/tool.json`（例如 `tools/family-reward-mcp/tool.json`）
- 会尝试更新/创建 `~/.goldfish/tool_ids.json`：
  - 文件不存在时，会写入示例默认条目
  - 文件存在时，只提示待追加的 `toolKey`，不会覆盖现有配置

### 4) tool.json 示例

参考：`family-point-mcp.tool.template.json`。
