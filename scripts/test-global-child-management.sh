#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:5102}"
SUFFIX="${REQ014_TEST_SUFFIX:-$(date +%s)-$$}"
PARENT_A="req014-parent-a-${SUFFIX}"
PARENT_B="req014-parent-b-${SUFFIX}"

api() {
  local parent="$1"
  shift
  curl -fsS \
    -H "X-App-User-Role: parent" \
    -H "X-App-User-Id: ${parent}" \
    -H "X-User-Id: ${parent}" \
    "$@"
}

group_a1="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"REQ014-A1-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
group_a2="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"REQ014-A2-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
group_b="$(api "$PARENT_B" -H 'Content-Type: application/json' -d "{\"name\":\"REQ014-B-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
group_a1_id="$(jq -r '.id' <<<"$group_a1")"
group_a2_id="$(jq -r '.id' <<<"$group_a2")"
group_b_id="$(jq -r '.id' <<<"$group_b")"

child_a="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"孩子A-${SUFFIX}\",\"familyGroupId\":${group_a1_id}}" "$API_BASE/api/children")"
child_a1_id="$(jq -r '.id' <<<"$child_a")"
profile_a="$(jq -r '.profileKey' <<<"$child_a")"
child_a2="$(api "$PARENT_A" "$API_BASE/api/children?familyGroupId=${group_a2_id}" | jq -c --arg profile "$profile_a" '.[] | select(.profileKey == $profile)')"
test -n "$child_a2"
child_a2_id="$(jq -r '.id' <<<"$child_a2")"
group_a3="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"name\":\"REQ014-A3-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
group_a3_id="$(jq -r '.id' <<<"$group_a3")"
api "$PARENT_A" "$API_BASE/api/children?familyGroupId=${group_a3_id}" \
  | jq -e --arg profile "$profile_a" '.[] | select(.profileKey == $profile)' >/dev/null

api "$PARENT_A" -X PUT -H 'Content-Type: application/json' \
  -d "{\"name\":\"全局孩子A-${SUFFIX}\",\"note\":\"REQ-014 global profile\",\"status\":\"active\",\"familyGroupId\":${group_a2_id}}" \
  "$API_BASE/api/children/${child_a2_id}" >/dev/null
api "$PARENT_A" "$API_BASE/api/children?familyGroupId=${group_a1_id}" \
  | jq -e --arg profile "$profile_a" --arg name "全局孩子A-${SUFFIX}" '.[] | select(.profileKey == $profile and .name == $name)' >/dev/null

api "$PARENT_A" -H 'Content-Type: application/json' \
  -d "{\"familyGroupId\":${group_a1_id},\"childId\":${child_a1_id},\"type\":\"points\",\"direction\":\"+\",\"points\":17,\"description\":\"REQ-014 shared points\"}" \
  "$API_BASE/api/transactions" >/dev/null
api "$PARENT_A" "$API_BASE/api/children?familyGroupId=${group_a2_id}" \
  | jq -e --arg profile "$profile_a" '.[] | select(.profileKey == $profile and .score == 17)' >/dev/null

child_b="$(api "$PARENT_B" -H 'Content-Type: application/json' -d "{\"name\":\"受邀孩子B-${SUFFIX}\",\"familyGroupId\":${group_b_id}}" "$API_BASE/api/children")"
profile_b="$(jq -r '.profileKey' <<<"$child_b")"
invite_code="$(api "$PARENT_A" "$API_BASE/api/family-groups/${group_a1_id}/invite" | jq -r '.inviteCode')"
api "$PARENT_B" -H 'Content-Type: application/json' -d "{\"inviteCode\":\"${invite_code}\"}" "$API_BASE/api/family-groups/join" \
  | jq -e '.linkedChildCount >= 1' >/dev/null
api "$PARENT_B" "$API_BASE/api/children?familyGroupId=${group_a1_id}" \
  | jq -e --arg profile "$profile_b" '.[] | select(.profileKey == $profile)' >/dev/null

auth_code_1="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"familyGroupId\":${group_a1_id}}" "$API_BASE/api/children/${child_a1_id}/auth-code" | jq -r '.code')"
api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"code\":\"${auth_code_1}\",\"deviceName\":\"REQ014-watch-1\"}" "$API_BASE/api/watch/device-bind" \
  | jq -e '.deviceToken | length > 0' >/dev/null
api "$PARENT_A" "$API_BASE/api/children/${child_a2_id}/devices?familyGroupId=${group_a2_id}" \
  | jq -e '[.devices[] | select(.revokedAt == null)] | length == 1' >/dev/null
auth_code_2="$(api "$PARENT_A" -H 'Content-Type: application/json' -d "{\"familyGroupId\":${group_a1_id}}" "$API_BASE/api/children/${child_a1_id}/auth-code" | jq -r '.code')"
second_bind="$(curl -sS \
  -H "X-App-User-Role: parent" \
  -H "X-App-User-Id: ${PARENT_A}" \
  -H "X-User-Id: ${PARENT_A}" \
  -H 'Content-Type: application/json' \
  -d "{\"code\":\"${auth_code_2}\",\"deviceName\":\"REQ014-watch-2\"}" \
  "$API_BASE/api/watch/device-bind")"
jq -e '.error | contains("已绑定设备")' <<<"$second_bind" >/dev/null

printf 'REQ-014 API verification passed: auto-membership, global profile, shared points, invited child, unique device.\n'
