#!/usr/bin/env bash

set -euo pipefail

MCP_URL="${MCP_URL:-https://happylife.ai.impx.net/api/mcp}"
FAMILY_GROUP_ID="${FAMILY_GROUP_ID:-}"
KNOWN_CHILD_ID="${KNOWN_CHILD_ID:-}"
KNOWN_CHILD_NAME="${KNOWN_CHILD_NAME:-}"
MISSING_CHILD_ID="${MISSING_CHILD_ID:-999999999}"
USER_CENTER_USERNAME="${USER_CENTER_USERNAME:-wss}"
export FAMILY_GROUP_ID KNOWN_CHILD_ID KNOWN_CHILD_NAME MISSING_CHILD_ID USER_CENTER_USERNAME

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

pass_count=0
fail_count=0

call_mcp() {
  local tool_name="$1"
  local arguments="$2"
  jq -cn --arg name "$tool_name" --arg username "$USER_CENTER_USERNAME" --argjson arguments "$arguments" \
    '{name: $name, arguments: ($arguments + {username: $username})}' |
    curl -sS -X POST "$MCP_URL" -H 'Content-Type: application/json' --data-binary @-
}

call_mcp_without_username() {
  local tool_name="$1"
  local arguments="$2"
  jq -cn --arg name "$tool_name" --argjson arguments "$arguments" \
    '{name: $name, arguments: $arguments}' |
    curl -sS -X POST "$MCP_URL" -H 'Content-Type: application/json' --data-binary @-
}

assert_jq() {
  local label="$1"
  local json="$2"
  local expression="$3"
  if jq -e "$expression" >/dev/null <<<"$json"; then
    printf 'PASS %s\n' "$label"
    pass_count=$((pass_count + 1))
  else
    printf 'FAIL %s\n' "$label"
    jq . <<<"$json"
    fail_count=$((fail_count + 1))
  fi
}

catalog="$(curl -sS "$MCP_URL")"
assert_jq "catalog exposes 40 tools" "$catalog" '.tools.tools | length == 40'
assert_jq "query_children declares strict snake_case keys" "$catalog" '
  [.tools.tools[] | select(.name == "family_reward_query_children") | .inputSchema.properties | keys]
  | .[0] == ["child_id", "child_name", "family_group_id", "username"]
'
assert_jq "list_children declares family group and username only" "$catalog" '
  [.tools.tools[] | select(.name == "family_reward_list_children") | .inputSchema.properties | keys]
  | .[0] == ["family_group_id", "username"]
'
assert_jq "all tools require username" "$catalog" '
  .tools.tools | length == 40 and all(.inputSchema.required | index("username") != null)
'
assert_jq "catalog covers current parent business UI" "$catalog" '
  [.tools.tools[].name] as $names
  | [
      "family_reward_add_child",
      "family_reward_update_child",
      "family_reward_query_children",
      "family_reward_delete_child",
      "family_reward_query_family_members",
      "family_reward_create_family_member",
      "family_reward_update_family_member",
      "family_reward_delete_family_member",
      "family_reward_query_family_groups",
      "family_reward_create_family_group",
      "family_reward_update_family_group",
      "family_reward_delete_family_group",
      "family_reward_get_family_group_invite",
      "family_reward_join_family_group",
      "family_reward_remove_family_group_child",
      "family_reward_query_rules",
      "family_reward_create_rule",
      "family_reward_update_rule",
      "family_reward_delete_rule",
      "family_reward_update_rule_template",
      "family_reward_query_score",
      "family_reward_query_operation_records",
      "family_reward_query_child_devices",
      "family_reward_query_child_friends",
      "family_reward_query_reward_requests",
      "family_reward_query_circle_dashboard"
    ]
    | all(. as $name | $names | index($name) != null)
'
assert_jq "family and circle descriptions are distinct" "$catalog" '
  ([.tools.tools[] | select(.name == "family_reward_query_family_members") | .description][0] | contains("不随圈子切换"))
  and ([.tools.tools[] | select(.name == "family_reward_query_family_groups") | .description][0] | contains("不等同于"))
'
assert_jq "query_children documents family_group_id list query" "$catalog" '
  .tools.tools[]
  | select(.name == "family_reward_query_children")
  | .description
  | contains("family_group_id")
'

unknown_arg="$(call_mcp family_reward_query_children '{"childId":1}')"
assert_jq "unknown camelCase parameter is rejected" "$unknown_arg" '
  .ok == false and (.error | contains("未知参数")) and (.error | contains("childId"))
'

missing_username="$(call_mcp_without_username family_reward_query_children '{}')"
assert_jq "missing username is rejected" "$missing_username" '
  .ok == false and .action == "validate_parent" and (.error | contains("username"))
'

groups="$(call_mcp family_reward_query_family_groups '{}')"
assert_jq "family groups can be queried" "$groups" '.ok == true and (.familyGroups | type == "array")'

owned_children="$(call_mcp family_reward_query_children '{}')"
if [[ -z "$KNOWN_CHILD_ID" ]]; then
  KNOWN_CHILD_ID="$(jq -r '.children[0].id // empty' <<<"$owned_children")"
fi
if [[ -z "$KNOWN_CHILD_NAME" ]]; then
  KNOWN_CHILD_NAME="$(jq -r '.children[0].name // empty' <<<"$owned_children")"
fi
if [[ -z "$FAMILY_GROUP_ID" ]]; then
  FAMILY_GROUP_ID="$(jq -r '.children[0].family_group_id // empty' <<<"$owned_children")"
fi
if [[ -z "$KNOWN_CHILD_ID" || -z "$KNOWN_CHILD_NAME" || -z "$FAMILY_GROUP_ID" ]]; then
  printf 'SKIP child-dependent MCP checks: username %s has no owned child in a circle.\n' "$USER_CENTER_USERNAME"
  printf '\nMCP catalog tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  if [ "$fail_count" -gt 0 ]; then
    exit 1
  fi
  exit 0
fi
export FAMILY_GROUP_ID KNOWN_CHILD_ID KNOWN_CHILD_NAME

children_by_group="$(call_mcp family_reward_query_children "{\"family_group_id\":$FAMILY_GROUP_ID}")"
assert_jq "family_group_id returns all active children in group" "$children_by_group" '
  .ok == true
  and .family_group_id == (env.FAMILY_GROUP_ID | tonumber)
  and .count == (.children | length)
  and (.children | all(.family_group_id == (env.FAMILY_GROUP_ID | tonumber)))
'

children_by_list_tool="$(call_mcp family_reward_list_children "{\"family_group_id\":$FAMILY_GROUP_ID}")"
assert_jq "list_children returns all active children in group" "$children_by_list_tool" '
  .ok == true
  and .family_group_id == (env.FAMILY_GROUP_ID | tonumber)
  and .count == (.children | length)
  and (.children | all(.family_group_id == (env.FAMILY_GROUP_ID | tonumber)))
'

child_by_id="$(call_mcp family_reward_query_children "{\"family_group_id\":$FAMILY_GROUP_ID,\"child_id\":$KNOWN_CHILD_ID}")"
assert_jq "child can be queried by id within group" "$child_by_id" '
  .ok == true
  and .count == 1
  and .child.id == (env.KNOWN_CHILD_ID | tonumber)
  and .children == null
'

child_by_name="$(call_mcp family_reward_query_children "{\"family_group_id\":$FAMILY_GROUP_ID,\"child_name\":\"$KNOWN_CHILD_NAME\"}")"
assert_jq "child can be queried by name within group" "$child_by_name" '
  .ok == true
  and .count == 1
  and .child.name == env.KNOWN_CHILD_NAME
'

missing_child="$(call_mcp family_reward_query_children "{\"family_group_id\":$FAMILY_GROUP_ID,\"child_id\":$MISSING_CHILD_ID}")"
assert_jq "missing child reference does not fall back to group list" "$missing_child" '
  .ok == false
  and .count == 0
  and .child == null
  and .children == null
  and .requires_child_list_retry == true
  and .retry_tool == "family_reward_list_children"
  and (.error | contains("未找到匹配的孩子"))
'

score_group="$(call_mcp family_reward_query_score "{\"family_group_id\":$FAMILY_GROUP_ID}")"
assert_jq "score query supports group-level child balances" "$score_group" '
  .ok == true
  and .action == "query_score"
  and .family_group_id == (env.FAMILY_GROUP_ID | tonumber)
  and .count == (.children | length)
  and (.children | type == "array")
  and (.children | all(has("id") and has("name") and has("score") and has("cash") and has("items")))
'

score_child="$(call_mcp family_reward_query_score "{\"family_group_id\":$FAMILY_GROUP_ID,\"child_id\":$KNOWN_CHILD_ID,\"include_transactions\":true,\"limit\":5}")"
assert_jq "score query supports one child with recent transactions" "$score_child" '
  .ok == true
  and .child.id == (env.KNOWN_CHILD_ID | tonumber)
  and (.transactions | type == "array")
  and .total == (.transactions | length)
'

score_missing="$(call_mcp family_reward_query_score "{\"family_group_id\":$FAMILY_GROUP_ID,\"child_id\":$MISSING_CHILD_ID}")"
assert_jq "score query missing child is explicit failure with retry guidance" "$score_missing" '
  .ok == false
  and .children == null
  and .requires_child_list_retry == true
  and .retry_tool == "family_reward_list_children"
'

ops_group="$(call_mcp family_reward_query_operation_records "{\"family_group_id\":$FAMILY_GROUP_ID,\"page\":1,\"page_size\":5}")"
assert_jq "operation records support group pagination" "$ops_group" '
  .ok == true
  and .data.page == 1
  and .data.page_size == 5
  and (.data.items | length) <= 5
'

ops_child="$(call_mcp family_reward_query_operation_records "{\"family_group_id\":$FAMILY_GROUP_ID,\"child_id\":$KNOWN_CHILD_ID,\"start_date\":\"2026-01-01\",\"end_date\":\"2026-12-31\",\"page\":1,\"page_size\":10}")"
assert_jq "operation records support child and date filters" "$ops_child" '
  .ok == true
  and .child.id == (env.KNOWN_CHILD_ID | tonumber)
  and (.data.items | all(.child_id == (env.KNOWN_CHILD_ID | tonumber)))
'

ops_missing="$(call_mcp family_reward_query_operation_records "{\"family_group_id\":$FAMILY_GROUP_ID,\"child_id\":$MISSING_CHILD_ID}")"
assert_jq "operation records missing child is explicit failure with retry guidance" "$ops_missing" '
  .ok == false
  and .children == null
  and .requires_child_list_retry == true
  and .retry_tool == "family_reward_list_children"
'

bad_date="$(call_mcp family_reward_query_operation_records "{\"family_group_id\":$FAMILY_GROUP_ID,\"start_date\":\"2026/01/01\"}")"
assert_jq "invalid dates are rejected" "$bad_date" '.ok == false and (.error | contains("日期格式无效"))'

rules="$(call_mcp family_reward_query_rules '{}')"
assert_jq "rules can be queried" "$rules" '.ok == true and .action == "query_rules"'

printf '\nMCP tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
