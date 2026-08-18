#!/usr/bin/env bash

set -euo pipefail

API_URL="${API_URL:-http://localhost:5102}"
run_id="$(date +%s)"
owner_id="household-owner-${run_id}"
other_id="household-other-${run_id}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

call_api() {
  local method="$1"
  local path="$2"
  local app_user_id="$3"
  local body="${4:-}"
  local args=(-sS -X "$method" "${API_URL}${path}" -H 'Content-Type: application/json' -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${app_user_id}" -H "X-User-Name: ${app_user_id}")
  if [ -n "$body" ]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}"
}

members="$(call_api GET /api/family-members "$owner_id")"
current_id="$(jq -er 'select(length == 1) | .[0] | select(.isCurrentUser == true and .role == "guardian") | .id' <<<"$members")"

current="$(call_api PUT "/api/family-members/${current_id}" "$owner_id" "{\"displayName\":\"测试家长\",\"role\":\"father\",\"note\":\"当前用户\"}")"
jq -e '.displayName == "测试家长" and .role == "father" and .isCurrentUser == true' >/dev/null <<<"$current"

created="$(call_api POST /api/family-members "$owner_id" '{"displayName":"测试奶奶","role":"grandmother","note":"家庭成员"}')"
member_id="$(jq -er 'select(.displayName == "测试奶奶" and .role == "grandmother" and .isCurrentUser == false) | .id' <<<"$created")"

same_members="$(call_api GET '/api/family-members?familyGroupId=999999' "$owner_id")"
jq -e --argjson current_id "$current_id" --argjson member_id "$member_id" '
  length == 2
  and any(.[]; .id == $current_id and .role == "father")
  and any(.[]; .id == $member_id and .role == "grandmother")
' >/dev/null <<<"$same_members"

other_members="$(call_api GET /api/family-members "$other_id")"
jq -e 'length == 1 and .[0].isCurrentUser == true' >/dev/null <<<"$other_members"

cross_update_status="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "${API_URL}/api/family-members/${member_id}" -H 'Content-Type: application/json' -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${other_id}" -d '{"displayName":"越权修改","role":"mother"}')"
test "$cross_update_status" = "404"

cross_delete_status="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "${API_URL}/api/family-members/${member_id}" -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${other_id}")"
test "$cross_delete_status" = "404"

current_delete_status="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "${API_URL}/api/family-members/${current_id}" -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${owner_id}")"
test "$current_delete_status" = "409"

updated="$(call_api PUT "/api/family-members/${member_id}" "$owner_id" '{"displayName":"测试妈妈","role":"mother","note":"已更新"}')"
jq -e '.displayName == "测试妈妈" and .role == "mother" and .note == "已更新"' >/dev/null <<<"$updated"

call_api DELETE "/api/family-members/${member_id}" "$owner_id" | jq -e '.status == "ok"' >/dev/null

printf 'PASS household members: current=%s member=%s isolation=ok circle_independent=ok\n' "$current_id" "$member_id"
