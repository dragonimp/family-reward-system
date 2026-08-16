#!/usr/bin/env bash
set -euo pipefail
trap 'echo "not ok - personal rule template test failed at line ${LINENO}" >&2' ERR

API_BASE="${FAMILY_REWARD_TEST_API_BASE:-http://127.0.0.1:5119}"
SUFFIX="${REQ036_TEST_SUFFIX:-$(date +%s)-$$}"
PARENT_A="req036-a-${SUFFIX}-parent"
PARENT_B="req036-b-${SUFFIX}-parent"

api() {
  local parent="$1"
  shift
  curl -fsS -H "X-App-User-Role: parent" -H "X-App-User-Id: ${parent}" -H "X-User-Id: ${parent}" "$@"
}

mcp() {
  local tool="$1"
  local arguments="$2"
  curl -fsS -H 'Content-Type: application/json' -d "$(jq -cn --arg name "$tool" --argjson arguments "$arguments" '{name:$name,arguments:$arguments}')" "$API_BASE/api/mcp"
}

rules_a="$(api "$PARENT_A" "$API_BASE/api/rules")"
rules_b="$(api "$PARENT_B" "$API_BASE/api/rules")"
jq -e '.hasTemplate == false and (.rules | length) >= 3 and (.rules | all(.isPublic == true)) and (.publicRules | any(.isRedLine == true and .score < 0 and .sourceRedlineId != null))' <<<"$rules_a" >/dev/null
jq -e '.hasTemplate == false and (.personalRules | length) == 0' <<<"$rules_b" >/dev/null
echo 'ok 1 - 现有公共红线已转为可选模板规则'

first_two="$(jq -c '[.publicRules[] | select(.score > 0) | .id][0:2]' <<<"$rules_a")"
api "$PARENT_A" -X PUT -H 'Content-Type: application/json' -d "{\"ruleIds\":${first_two}}" "$API_BASE/api/rule-template" >/dev/null
custom_web="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"整理书包-${SUFFIX}\",\"category\":\"习惯\",\"points\":6,\"description\":\"睡前整理\"}" "$API_BASE/api/rules")"
custom_web_id="$(jq -er '.id' <<<"$custom_web")"
rules_a="$(api "$PARENT_A" "$API_BASE/api/rules")"
jq -e --argjson id "$custom_web_id" '.hasTemplate == true and (.rules | length) == 3 and (.templateRuleIds | index($id) != null) and (.personalRules | any(.id == $id and .isPublic == false))' <<<"$rules_a" >/dev/null
api "$PARENT_B" "$API_BASE/api/rules" | jq -e --argjson id "$custom_web_id" '.rules | all(.id != $id)' >/dev/null
echo 'ok 2 - Web新增规则只进入当前家长模板，其他家长不可见'

public_id="$(jq -er '.publicRules[0].id' <<<"$rules_a")"
public_redline_id="$(jq -er '.publicRules | map(select(.isRedLine == true and .sourceRedlineId != null)) | first | .id' <<<"$rules_a")"
status="$(curl -sS -o /tmp/req036-public-edit.json -w '%{http_code}' -X PUT -H "X-App-User-Role: parent" -H "X-App-User-Id: ${PARENT_A}" -H "X-User-Id: ${PARENT_A}" -H 'Content-Type: application/json' -d '{"name":"禁止修改","category":"测试","points":1,"description":""}' "$API_BASE/api/rules/${public_id}")"
test "$status" = '404'
jq -e '.error | contains("公共规则")' /tmp/req036-public-edit.json >/dev/null
echo 'ok 3 - 公共规则保持只读'

mcp family_reward_query_rules '{}' | jq -e '.ok == false and (.error | contains("user_id"))' >/dev/null
custom_mcp="$(mcp family_reward_create_rule "{\"user_id\":\"${PARENT_A}\",\"name\":\"主动阅读-${SUFFIX}\",\"category\":\"学习\",\"points\":8}")"
custom_mcp_id="$(jq -er '.rule.id' <<<"$custom_mcp")"
mcp family_reward_query_rules "{\"user_id\":\"${PARENT_A}\"}" | jq -e --argjson id "$custom_mcp_id" '.ok == true and (.data.personalRules | any(.id == $id))' >/dev/null
mcp family_reward_query_rules "{\"user_id\":\"${PARENT_B}\"}" | jq -e --argjson id "$custom_mcp_id" '.data.rules | all(.id != $id)' >/dev/null
echo 'ok 4 - MCP强制用户入参且新增规则隔离到该用户模板'

redline="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"说谎红线-${SUFFIX}\",\"category\":\"红线\",\"points\":5,\"ruleType\":\"redline\"}" "$API_BASE/api/rules")"
redline_id="$(jq -er '.id' <<<"$redline")"
jq -e '.score == -5 and .type == "negative" and .isRedLine == true' <<<"$redline" >/dev/null
mcp_redline="$(mcp family_reward_create_rule "{\"user_id\":\"${PARENT_A}\",\"name\":\"破坏物品-${SUFFIX}\",\"category\":\"红线\",\"points\":3,\"rule_type\":\"redline\"}")"
jq -e '.ok == true and .rule.score == -3 and .rule.isRedLine == true' <<<"$mcp_redline" >/dev/null
echo 'ok 5 - Web与MCP均可明确新增红线减分规则'

ordered_ids="$(jq -cn --argjson mcp "$custom_mcp_id" --argjson web "$custom_web_id" --argjson redline "$redline_id" --argjson public_redline "$public_redline_id" --argjson public "$first_two" '[$mcp,$web] + $public + [$public_redline,$redline]')"
api "$PARENT_A" -X PUT -H 'Content-Type: application/json' -d "{\"ruleIds\":${ordered_ids}}" "$API_BASE/api/rule-template" >/dev/null
api "$PARENT_A" "$API_BASE/api/rules" | jq -e --argjson expected "$ordered_ids" --argjson public_redline "$public_redline_id" '.templateRuleIds == $expected and (.rules | any(.id == $public_redline and .isRedLine == true))' >/dev/null
echo 'ok 6 - 现有公共红线与个人红线均可选入模板并持久化'

group="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"REQ036-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
group_id="$(jq -er '.id' <<<"$group")"
child="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"模板孩子-${SUFFIX}\",\"familyGroupId\":${group_id}}" "$API_BASE/api/children")"
child_id="$(jq -er '.id' <<<"$child")"
code="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"familyGroupId\":${group_id}}" "$API_BASE/api/children/${child_id}/auth-code" | jq -er '.code')"
token="$(curl -fsS -H 'Content-Type: application/json' -d "{\"code\":\"${code}\",\"deviceName\":\"REQ036-watch\"}" "$API_BASE/api/watch/device-bind" | jq -er '.deviceToken')"
watch_rules="$(curl -fsS -H "X-Watch-Device-Token: ${token}" "$API_BASE/api/watch/rules")"
jq -e --argjson web "$custom_web_id" --argjson mcp "$custom_mcp_id" --argjson redline "$redline_id" --argjson public_redline "$public_redline_id" '(.rules | length) <= 8 and .rules[0].id == $mcp and .rules[1].id == $web and (.rules | all(.points > 0 and .id != $redline and .id != $public_redline))' <<<"$watch_rules" >/dev/null
echo 'ok 7 - 手表按模板顺序展示前8条奖励规则并排除红线'

printf 'PASS REQ-039: 7/7 cases passed (%s)\n' "$PARENT_A"
