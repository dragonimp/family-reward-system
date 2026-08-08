#!/usr/bin/env bash

set -euo pipefail

API_URL="${API_URL:-http://localhost:5102}"
run_id="$(date +%s)"
owner_id="invite-owner-${run_id}"
member_id="invite-member-${run_id}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

call_api() {
  local method="$1"
  local path="$2"
  local app_user_id="$3"
  local body="${4:-}"
  local args=(-sS -X "$method" "${API_URL}${path}" -H 'Content-Type: application/json' -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${app_user_id}")
  if [ -n "$body" ]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}"
}

owner_group="$(call_api POST /api/family-groups "$owner_id" "{\"name\":\"邀请码测试家庭-${run_id}\"}")"
owner_group_id="$(jq -er '.id' <<<"$owner_group")"
member_group="$(call_api POST /api/family-groups "$member_id" "{\"name\":\"加入者原家庭-${run_id}\"}")"
member_group_id="$(jq -er '.id' <<<"$member_group")"

call_api POST /api/children "$member_id" "{\"familyGroupId\":${member_group_id},\"name\":\"邀请码测试孩子-${run_id}\"}" >/dev/null

invite="$(call_api GET "/api/family-groups/${owner_group_id}/invite" "$owner_id")"
invite_code="$(jq -er '.inviteCode | select(test("^[0-9]{8}$"))' <<<"$invite")"
join_result="$(call_api POST /api/family-groups/join "$member_id" "{\"inviteCode\":\"${invite_code}\"}")"
jq -e --argjson group_id "$owner_group_id" '
  .ok == true
  and .familyGroupId == $group_id
  and .linkedChildCount == 1
' >/dev/null <<<"$join_result"

call_api POST /api/family-groups/join "$member_id" "{\"inviteCode\":\"${invite_code}\"}" >/dev/null
joined_children="$(call_api GET "/api/children?familyGroupId=${owner_group_id}" "$member_id")"
jq -e --arg name "邀请码测试孩子-${run_id}" '
  [.[] | select(.name == $name)] | length == 1
' >/dev/null <<<"$joined_children"

forbidden_status="$(curl -sS -o /dev/null -w '%{http_code}' "${API_URL}/api/family-groups/${owner_group_id}/invite" -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${member_id}")"
test "$forbidden_status" = "403"

invalid_status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${API_URL}/api/family-groups/join" -H 'Content-Type: application/json' -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${member_id}" -d '{"inviteCode":"00000000"}')"
test "$invalid_status" = "404"

raw_id_status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${API_URL}/api/family-groups/join" -H 'Content-Type: application/json' -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${member_id}" -d "{\"familyGroupId\":${owner_group_id}}")"
test "$raw_id_status" = "400"

printf 'PASS family-group invite flow: code=%s group=%s linked_children=1\n' "$invite_code" "$owner_group_id"
