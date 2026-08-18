#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:5102}"
SUFFIX="${REQ048_TEST_SUFFIX:-$(date +%s)-$$}"
PARENT_A="req048-a-${SUFFIX}-parent"
PARENT_B="req048-b-${SUFFIX}-parent"
GROUP_A_ID=""
GROUP_B_ID=""
CHILD_A_ID=""
CHILD_B_ID=""
RULE_A_ID=""

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
  local parent="$2"
  local arguments="$3"
  jq -cn --arg name "$tool_name" --arg parent "$parent" --argjson arguments "$arguments" \
    '{name: $name, arguments: ($arguments + {parent_user_id: $parent})}' |
    curl -fsS -X POST "$API_BASE/api/mcp" -H 'Content-Type: application/json' --data-binary @-
}

cleanup() {
  set +e
  if [[ -n "$RULE_A_ID" ]]; then
    mcp family_reward_delete_rule "$PARENT_A" "{\"rule_id\":$RULE_A_ID}" >/dev/null
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

invite_code="$(api "$PARENT_B" "$API_BASE/api/family-groups/$GROUP_B_ID/invite" | jq -r '.inviteCode')"
api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"inviteCode\":\"$invite_code\"}" "$API_BASE/api/family-groups/join" >/dev/null

owned_children="$(mcp family_reward_query_children "$PARENT_A" '{}')"
jq -e --arg own "$CHILD_A_NAME" --arg other "$CHILD_B_NAME" '
  .ok == true
  and ([.children[].name] | index($own) != null)
  and ([.children[].name] | index($other) == null)
' <<<"$owned_children" >/dev/null

visible_scores="$(mcp family_reward_query_score "$PARENT_A" '{}')"
jq -e --arg own "$CHILD_A_NAME" --arg other "$CHILD_B_NAME" '
  .ok == true
  and ([.children[].name] | index($own) != null)
  and ([.children[].name] | index($other) != null)
  and (.children | all(.family_groups | type == "array"))
' <<<"$visible_scores" >/dev/null

denied="$(mcp family_reward_adjust_score "$PARENT_A" "{\"child_id\":$CHILD_B_ID,\"delta\":9}")"
jq -e '.ok == false and (.error | contains("权限不足"))' <<<"$denied" >/dev/null

allowed="$(mcp family_reward_adjust_score "$PARENT_A" "{\"child_id\":$CHILD_A_ID,\"delta\":3,\"description\":\"REQ-048 authorization test\"}")"
jq -e '.ok == true and .action == "adjust_score"' <<<"$allowed" >/dev/null

rule_a="$(mcp family_reward_create_rule "$PARENT_A" "{\"name\":\"REQ048规则-${SUFFIX}\",\"points\":5,\"rule_type\":\"reward\"}")"
RULE_A_ID="$(jq -r '.rule.id' <<<"$rule_a")"
jq -e '.ok == true and .action == "create_rule"' <<<"$rule_a" >/dev/null
mcp family_reward_query_rules "$PARENT_B" '{}' |
  jq -e --arg name "REQ048规则-${SUFFIX}" '.ok == true and ([.data.rules[].name] | index($name) == null)' >/dev/null

printf 'REQ-048 MCP authorization verification passed: owned writes, cross-family score reads, rule isolation.\n'
