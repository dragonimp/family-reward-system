#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:5102}"
SUFFIX="${REQ048_TEST_SUFFIX:-$(date +%s)-$$}"
USERNAME_A="req048-a-${SUFFIX}"
USERNAME_B="req048-b-${SUFFIX}"
PARENT_A="${USERNAME_A}parent"
PARENT_B="${USERNAME_B}parent"
GROUP_A_ID=""
GROUP_B_ID=""
CHILD_A_ID=""
CHILD_B_ID=""
RULE_A_ID=""
MEMBER_A_ID=""

api() {
  local parent="$1"
  shift
  curl -fsS \
    -H "X-App-User-Role: parent" \
    -H "X-App-User-Id: ${parent}" \
    -H "X-User-Id: ${parent}" \
    "$@"
}

mcp() {
  local tool_name="$1"
  local username="$2"
  local arguments="$3"
  jq -cn --arg name "$tool_name" --arg username "$username" --argjson arguments "$arguments" \
    '{name: $name, arguments: ($arguments + {username: $username})}' |
    curl -fsS -X POST "$API_BASE/api/mcp" -H 'Content-Type: application/json' --data-binary @-
}

cleanup() {
  set +e
  if [[ -n "$MEMBER_A_ID" ]]; then
    mcp family_reward_delete_family_member "$USERNAME_A" "{\"member_id\":$MEMBER_A_ID}" >/dev/null
  fi
  if [[ -n "$RULE_A_ID" ]]; then
    mcp family_reward_delete_rule "$USERNAME_A" "{\"rule_id\":$RULE_A_ID}" >/dev/null
  fi
  if [[ -n "$CHILD_A_ID" ]]; then
    api "$PARENT_A" -X DELETE "$API_BASE/api/children/$CHILD_A_ID" >/dev/null
  fi
  if [[ -n "$CHILD_B_ID" ]]; then
    api "$PARENT_B" -X DELETE "$API_BASE/api/children/$CHILD_B_ID" >/dev/null
  fi
  if [[ -n "$GROUP_B_ID" ]]; then
    api "$PARENT_B" -X DELETE "$API_BASE/api/family-groups/$GROUP_B_ID" >/dev/null
  fi
  if [[ -n "$GROUP_A_ID" ]]; then
    api "$PARENT_A" -X DELETE "$API_BASE/api/family-groups/$GROUP_A_ID" >/dev/null
  fi
}
trap cleanup EXIT

group_a="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"REQ048-A-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
group_b="$(api "$PARENT_B" -H 'Content-Type: application/json' -d "{\"name\":\"REQ048-B-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
GROUP_A_ID="$(jq -r '.id' <<<"$group_a")"
GROUP_B_ID="$(jq -r '.id' <<<"$group_b")"

child_a="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"REQ048孩子A-${SUFFIX}\",\"familyGroupId\":$GROUP_A_ID}" "$API_BASE/api/children")"
child_b="$(api "$PARENT_B" -H 'Content-Type: application/json' -d "{\"name\":\"REQ048孩子B-${SUFFIX}\",\"familyGroupId\":$GROUP_B_ID}" "$API_BASE/api/children")"
CHILD_A_ID="$(jq -r '.id' <<<"$child_a")"
CHILD_B_ID="$(jq -r '.id' <<<"$child_b")"
CHILD_A_NAME="$(jq -r '.name' <<<"$child_a")"
CHILD_B_NAME="$(jq -r '.name' <<<"$child_b")"

prejoin_denied="$(mcp family_reward_query_children "$USERNAME_A" "{\"family_group_id\":$GROUP_B_ID}")"
jq -e '.ok == false and (.error | contains("无权访问"))' <<<"$prejoin_denied" >/dev/null

invite_code="$(mcp family_reward_get_family_group_invite "$USERNAME_B" "{\"family_group_id\":$GROUP_B_ID}" | jq -r '.invite_code')"
mcp family_reward_join_family_group "$USERNAME_A" "{\"invite_code\":\"$invite_code\"}" |
  jq -e '.ok == true and .action == "join_family_group"' >/dev/null

owned_children="$(mcp family_reward_query_children "$USERNAME_A" '{}')"
jq -e --arg own "$CHILD_A_NAME" --arg other "$CHILD_B_NAME" '
  .ok == true
  and ([.children[].name] | index($own) != null)
  and ([.children[].name] | index($other) == null)
' <<<"$owned_children" >/dev/null

owned_scores="$(mcp family_reward_query_score "$USERNAME_A" '{}')"
jq -e --arg own "$CHILD_A_NAME" --arg other "$CHILD_B_NAME" '
  .ok == true
  and ([.children[].name] | index($own) != null)
  and ([.children[].name] | index($other) == null)
' <<<"$owned_scores" >/dev/null

circle_children="$(mcp family_reward_query_children "$USERNAME_A" "{\"family_group_id\":$GROUP_B_ID}")"
jq -e --arg own "$CHILD_A_NAME" --arg other "$CHILD_B_NAME" --argjson group "$GROUP_B_ID" '
  .ok == true
  and ([.children[].name] | index($own) != null)
  and ([.children[].name] | index($other) != null)
  and (.children | all(.family_group_id == $group))
' <<<"$circle_children" >/dev/null

circle_scores="$(mcp family_reward_query_score "$USERNAME_A" "{\"family_group_id\":$GROUP_B_ID}")"
jq -e --arg other "$CHILD_B_NAME" '
  .ok == true
  and ([.children[].name] | index($other) != null)
' <<<"$circle_scores" >/dev/null

detail_denied="$(mcp family_reward_query_score "$USERNAME_A" "{\"family_group_id\":$GROUP_B_ID,\"child_id\":$CHILD_B_ID,\"include_transactions\":true}")"
jq -e '.ok == false and (.error | contains("明细"))' <<<"$detail_denied" >/dev/null

dashboard="$(mcp family_reward_query_circle_dashboard "$USERNAME_A" "{\"family_group_id\":$GROUP_B_ID}")"
jq -e '.ok == true and .action == "query_circle_dashboard"' <<<"$dashboard" >/dev/null

group_update_denied="$(mcp family_reward_update_family_group "$USERNAME_A" "{\"family_group_id\":$GROUP_B_ID,\"name\":\"越权修改\"}")"
jq -e '.ok == false and (.error | contains("管理员"))' <<<"$group_update_denied" >/dev/null

group_update_allowed="$(mcp family_reward_update_family_group "$USERNAME_B" "{\"family_group_id\":$GROUP_B_ID,\"name\":\"REQ048-B-更新-${SUFFIX}\"}")"
jq -e '.ok == true and .action == "update_family_group"' <<<"$group_update_allowed" >/dev/null

denied="$(mcp family_reward_adjust_score "$USERNAME_A" "{\"child_id\":$CHILD_B_ID,\"delta\":9}")"
jq -e '.ok == false and (.error | contains("权限不足"))' <<<"$denied" >/dev/null

allowed="$(mcp family_reward_adjust_score "$USERNAME_A" "{\"child_id\":$CHILD_A_ID,\"delta\":3,\"description\":\"REQ-048 authorization test\"}")"
jq -e '.ok == true and .action == "adjust_score"' <<<"$allowed" >/dev/null

member_a="$(mcp family_reward_create_family_member "$USERNAME_A" "{\"display_name\":\"测试爷爷-${SUFFIX}\",\"role\":\"grandfather\"}")"
MEMBER_A_ID="$(jq -r '.familyMember.id' <<<"$member_a")"
jq -e '.ok == true and .action == "create_family_member"' <<<"$member_a" >/dev/null

mcp family_reward_query_family_members "$USERNAME_B" '{}' |
  jq -e --arg name "测试爷爷-${SUFFIX}" '.ok == true and ([.familyMembers[].displayName] | index($name) == null)' >/dev/null

member_update="$(mcp family_reward_update_family_member "$USERNAME_A" "{\"member_id\":$MEMBER_A_ID,\"display_name\":\"测试外公-${SUFFIX}\",\"role\":\"grandfather\"}")"
jq -e '.ok == true and .action == "update_family_member"' <<<"$member_update" >/dev/null

family_a="$(mcp family_reward_query_family_members "$USERNAME_A" '{}')"
CURRENT_MEMBER_A_ID="$(jq -r '.familyMembers[] | select(.isCurrentUser == true) | .id' <<<"$family_a")"
current_member_delete_denied="$(mcp family_reward_delete_family_member "$USERNAME_A" "{\"member_id\":$CURRENT_MEMBER_A_ID}")"
jq -e '.ok == false and (.error | contains("当前用户不能"))' <<<"$current_member_delete_denied" >/dev/null

rule_a="$(mcp family_reward_create_rule "$USERNAME_A" "{\"name\":\"REQ048规则-${SUFFIX}\",\"points\":5,\"rule_type\":\"reward\"}")"
RULE_A_ID="$(jq -r '.rule.id' <<<"$rule_a")"
jq -e '.ok == true and .action == "create_rule"' <<<"$rule_a" >/dev/null
mcp family_reward_update_rule_template "$USERNAME_A" "{\"rule_ids\":[$RULE_A_ID]}" |
  jq -e --argjson id "$RULE_A_ID" '.ok == true and (.rule_ids | index($id) != null)' >/dev/null
mcp family_reward_query_rules "$USERNAME_B" '{}' |
  jq -e --arg name "REQ048规则-${SUFFIX}" '.ok == true and ([.data.rules[].name] | index($name) == null)' >/dev/null

printf 'MCP authorization verification passed: household isolation, circle balance visibility, owned details/writes, and rule isolation.\n'
