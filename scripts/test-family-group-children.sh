#!/usr/bin/env bash

set -euo pipefail

API_URL="${API_URL:-http://localhost:5102}"
run_id="req018-$(date +%s)"
owner_id="${run_id}-owner"
outsider_id="${run_id}-outsider"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

call_owner_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local args=(-sS -X "$method" "${API_URL}${path}" -H 'Content-Type: application/json' -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${owner_id}")
  if [ -n "$body" ]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}"
}

first_group="$(call_owner_api POST /api/family-groups "{\"name\":\"REQ018家庭A-${run_id}\"}")"
first_group_id="$(jq -er '.id' <<<"$first_group")"
child="$(call_owner_api POST /api/children "{\"familyGroupId\":${first_group_id},\"name\":\"REQ018孩子-${run_id}\",\"score\":18,\"cash\":8,\"items\":1}")"
jq -e '.id > 0' >/dev/null <<<"$child"

second_group="$(call_owner_api POST /api/family-groups "{\"name\":\"REQ018家庭B-${run_id}\"}")"
second_group_id="$(jq -er '.id' <<<"$second_group")"
second_child_id="$(call_owner_api GET "/api/family-groups/${second_group_id}/children" | jq -er --arg name "REQ018孩子-${run_id}" --arg owner "$owner_id" '.[] | select(.name == $name and .parentNames == $owner and .score == 18 and .cash == 8 and .items == 1) | .id')"

forbidden_status="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "${API_URL}/api/family-groups/${second_group_id}/children/${second_child_id}" -H 'X-App-User-Role: parent' -H "X-App-User-Id: ${outsider_id}")"
test "$forbidden_status" = "403"

removed="$(call_owner_api DELETE "/api/family-groups/${second_group_id}/children/${second_child_id}")"
jq -e '.status == "ok"' >/dev/null <<<"$removed"
test "$(call_owner_api GET "/api/family-groups/${second_group_id}/children" | jq 'length')" = "0"
test "$(call_owner_api GET "/api/family-groups/${first_group_id}/children" | jq --arg name "REQ018孩子-${run_id}" '[.[] | select(.name == $name)] | length')" = "1"
test "$(call_owner_api GET '/api/children?ownedOnly=true' | jq --arg name "REQ018孩子-${run_id}" '[.[] | select(.name == $name)] | length')" = "1"

printf 'PASS family child management: owner=%s original_group=%s removed_group=%s outsider_delete=403\n' "$owner_id" "$first_group_id" "$second_group_id"
