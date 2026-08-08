# 家加分 MCP 测试案例

测试脚本：

```bash
scripts/test-family-reward-mcp.sh
scripts/test-happylife-goldfish-agent.sh
```

默认测试生产 MCP：

```bash
MCP_URL="https://happylife.ai.impx.net/api/mcp" scripts/test-family-reward-mcp.sh
```

可按环境覆盖：

```bash
MCP_URL="http://localhost:5102/api/mcp" \
FAMILY_GROUP_ID=1 \
KNOWN_CHILD_ID=1 \
KNOWN_CHILD_NAME="彦谦" \
MISSING_CHILD_ID=6 \
scripts/test-family-reward-mcp.sh
```

## 覆盖场景

1. 工具目录
   - `/api/mcp` 返回 18 个工具。
   - `family_reward_query_children` 只声明 `family_group_id`、`child_id`、`child_name`。
   - `family_reward_list_children` 只声明 `family_group_id`，用于“查询孩子列表/列出孩子”等清单场景。
   - 工具描述明确说明：只传 `family_group_id` 时返回该家庭组全部孩子。

2. 参数严谨性
   - `childId` 等 camelCase 未声明字段必须被拒绝。
   - 错误信息必须提示使用 `tools/list` 中声明的 snake_case 字段。

3. 家庭组查询
   - `family_reward_query_family_groups` 可返回家庭组列表。
   - `family_reward_query_children` 只传 `family_group_id` 时返回该家庭组全部 active 孩子。
   - 返回的 `count` 必须等于 `children.length`。
   - 所有孩子的 `family_group_id` 必须等于请求值。

4. 孩子定位
   - 可用 `family_group_id + child_id` 查询单个孩子。
   - 可用 `family_group_id + child_name` 查询单个孩子。
   - 指定不存在的 `child_id` 时必须返回 `ok:false`，不能退回家庭组列表。

5. 积分查询
   - 只传 `family_group_id` 时返回该家庭组孩子余额列表。
   - 传 `family_group_id + child_id + include_transactions` 时返回单个孩子余额和最近交易。
   - 指定不存在的孩子时必须返回 `ok:false`。

6. 操作记录查询
   - 支持 `family_group_id + page + page_size` 分页查询。
   - 支持 `family_group_id + child_id + start_date + end_date` 查询单个孩子日期范围内的积分明细。
   - 指定不存在的孩子时必须返回 `ok:false`。
   - 非 `yyyy-MM-dd` 日期必须被拒绝。

7. 规则查询
   - `family_reward_query_rules` 可正常返回规则数据。

8. Goldfish Harness 端到端查询
   - “查询孩子列表”必须返回全部孩子 ID 和姓名。
   - “列出全部孩子”必须返回全部孩子 ID 和姓名。
   - “我要查询孩子们的积分”必须返回全部孩子积分清单。
   - “玥玥现在多少分”必须返回单个孩子积分。
   - “查询彦谦最近5条积分明细”必须调用明细查询能力并返回记录上下文。
   - “查询今天的加分明细”必须基于工具结果回答，不得编造明细。
   - “查询积分规则”必须返回规则上下文。
   - “查询ID 6的孩子”必须说明未找到，不能把第 6 个孩子误认为 ID 6。

## 当前生产基线

家庭组 `1` 当前 active 孩子数量为 6，ID 分别为：

```text
1, 2, 3, 4, 5, 28
```

注意：列表中的第 6 个孩子不是 `id=6`，而是 `id=28`。
