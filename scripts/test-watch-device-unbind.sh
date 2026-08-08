#!/usr/bin/env bash
set -euo pipefail

API_BASE="${FAMILY_REWARD_TEST_API_BASE:-http://127.0.0.1:5113}"
PARENT_HEADERS=(-H 'X-App-User-Role: parent' -H 'X-App-User-Id: local-admin' -H 'X-User-Id: req013-parent')

group_id="$(curl -fsS "${PARENT_HEADERS[@]}" "$API_BASE/api/family-groups" | jq -er '.[0].id')"
child_name="REQ013-$(date +%s)"
child="$(curl -fsS "${PARENT_HEADERS[@]}" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$child_name\",\"familyGroupId\":$group_id}" "$API_BASE/api/children")"
child_id="$(jq -er '.id' <<<"$child")"

bind_code_payload="$(curl -fsS "${PARENT_HEADERS[@]}" -H 'Content-Type: application/json' \
  -d "{\"familyGroupId\":$group_id,\"expiresInMinutes\":10}" "$API_BASE/api/children/$child_id/auth-code")"
bind_code="$(jq -er '.code' <<<"$bind_code_payload")"
binding="$(curl -fsS -H 'Content-Type: application/json' \
  -d "{\"code\":\"$bind_code\",\"deviceName\":\"REQ-013 test watch\"}" "$API_BASE/api/watch/device-bind")"
device_id="$(jq -er '.deviceId' <<<"$binding")"
device_token="$(jq -er '.deviceToken' <<<"$binding")"
WATCH_HEADERS=(-H "X-Watch-Device-Token: $device_token" -H 'Content-Type: application/json')

missing_status="$(curl -sS -o /tmp/family-reward-req013-missing.json -w '%{http_code}' \
  "${WATCH_HEADERS[@]}" -d '{}' "$API_BASE/api/watch/device-unbind")"
test "$missing_status" = "400"
jq -e '.error | contains("解绑认证码")' /tmp/family-reward-req013-missing.json >/dev/null

bind_code_status="$(curl -sS -o /tmp/family-reward-req013-bind-code.json -w '%{http_code}' \
  "${WATCH_HEADERS[@]}" -d "{\"code\":\"$bind_code\"}" "$API_BASE/api/watch/device-unbind")"
test "$bind_code_status" = "400"

unbind_payload="$(curl -fsS "${PARENT_HEADERS[@]}" -H 'Content-Type: application/json' \
  -d "{\"familyGroupId\":$group_id,\"expiresInMinutes\":10}" \
  "$API_BASE/api/children/$child_id/devices/$device_id/unbind-code")"
unbind_code="$(jq -er '.code' <<<"$unbind_payload")"

wrong_status="$(curl -sS -o /tmp/family-reward-req013-wrong.json -w '%{http_code}' \
  "${WATCH_HEADERS[@]}" -d '{"code":"AAAAAA"}' "$API_BASE/api/watch/device-unbind")"
test "$wrong_status" = "400"

success="$(curl -fsS "${WATCH_HEADERS[@]}" -d "{\"code\":\"$unbind_code\"}" "$API_BASE/api/watch/device-unbind")"
test "$(jq -r '.status' <<<"$success")" = "ok"

replay_status="$(curl -sS -o /tmp/family-reward-req013-replay.json -w '%{http_code}' \
  "${WATCH_HEADERS[@]}" -d "{\"code\":\"$unbind_code\"}" "$API_BASE/api/watch/device-unbind")"
test "$replay_status" = "401"
jq -e '.code == "watch_device_invalid"' /tmp/family-reward-req013-replay.json >/dev/null

echo "PASS watch device unbind authorization"
