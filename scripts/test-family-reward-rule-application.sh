#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:5102}"
SUFFIX="${RULE_APPLICATION_TEST_SUFFIX:-$(date +%s)-$$}"
USERNAME="rule-application-${SUFFIX}"
PARENT_ID="${USERNAME}parent"
GROUP_ID=""
CHILD_ID=""
RULE_ID=""

api() {
  curl -fsS \
    -H "X-App-User-Role: parent" \
    -H "X-App-User-Id: ${PARENT_ID}" \
    -H "X-User-Id: ${PARENT_ID}" \
    "$@"
}

mcp() {
  local tool_name="$1"
  local arguments="$2"
  jq -cn --arg name "$tool_name" --arg username "$USERNAME" --argjson arguments "$arguments" \
    '{name: $name, arguments: ($arguments + {username: $username})}' |
    curl -fsS -X POST "$API_BASE/api/mcp" -H 'Content-Type: application/json' --data-binary @-
}

cleanup() {
  set +e
  if [[ -n "$RULE_ID" ]]; then
    mcp family_reward_delete_rule "{\"rule_id\":$RULE_ID}" >/dev/null
  fi
  if [[ -n "$CHILD_ID" ]]; then
    api -X DELETE "$API_BASE/api/children/$CHILD_ID" >/dev/null
  fi
  if [[ -n "$GROUP_ID" ]]; then
    api -X DELETE "$API_BASE/api/family-groups/$GROUP_ID" >/dev/null
  fi
}
trap cleanup EXIT

group="$(api -H 'Content-Type: application/json' -d "{\"name\":\"规则匹配测试-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
GROUP_ID="$(jq -r '.id' <<<"$group")"

child="$(api -H 'Content-Type: application/json' -d "{\"name\":\"测试玥玥-${SUFFIX}\",\"familyGroupId\":$GROUP_ID}" "$API_BASE/api/children")"
CHILD_ID="$(jq -r '.id' <<<"$child")"
CHILD_NAME="$(jq -r '.name' <<<"$child")"

rule="$(mcp family_reward_create_rule "{\"name\":\"照顾妹妹\",\"description\":\"照顾妹妹，爱护妹妹\",\"category\":\"帮忙\",\"points\":5,\"rule_type\":\"reward\"}")"
RULE_ID="$(jq -r '.rule.id' <<<"$rule")"
jq -e '.ok == true and .rule.points == 5' <<<"$rule" >/dev/null

request_id="rule-application-${SUFFIX}"
first="$(mcp family_reward_apply_matching_rule "{\"child_id\":$CHILD_ID,\"behavior\":\"今天帮助妹妹，请加分\",\"request_id\":\"$request_id\"}")"
jq -e --argjson rule_id "$RULE_ID" --argjson child_id "$CHILD_ID" '
  .ok == true
  and .action == "apply_matching_rule"
  and .matched_rule.id == $rule_id
  and .matched_rule.name == "照顾妹妹"
  and .points_delta == 5
  and .before_score == 0
  and .after_score == 5
  and .deduplicated == false
  and .transaction.child_id == $child_id
  and .transaction.direction == "+"
  and .transaction.points == 5
' <<<"$first" >/dev/null

second="$(mcp family_reward_apply_matching_rule "{\"child_name\":\"$CHILD_NAME\",\"behavior\":\"今天帮助妹妹，请加分\",\"request_id\":\"$request_id\"}")"
jq -e '
  .ok == true
  and .after_score == 5
  and .deduplicated == true
  and .transaction.id != null
' <<<"$second" >/dev/null

score="$(mcp family_reward_query_score "{\"child_id\":$CHILD_ID,\"include_transactions\":true,\"limit\":20}")"
jq -e '
  .ok == true
  and .child.score == 5
  and ([.transactions[] | select(.description | contains("照顾妹妹"))] | length) == 1
  and ([.transactions[] | select(.description | contains("今天帮助妹妹"))][0].points) == 5
' <<<"$score" >/dev/null

printf 'Rule application verification passed: matched active rule, wrote one +5 transaction, updated balance, and deduplicated replay.\n'
