#!/usr/bin/env bash
set -euo pipefail
trap 'echo "not ok - REQ-023 test failed at line ${LINENO}" >&2' ERR

API_BASE="${FAMILY_REWARD_TEST_API_BASE:-http://127.0.0.1:5118}"
SUFFIX="${REQ023_TEST_SUFFIX:-$(date +%s)-$$}"
PARENT_A="req023-parent-a-${SUFFIX}"
PARENT_B="req023-parent-b-${SUFFIX}"

api() {
  local parent="$1"
  shift
  curl -fsS \
    -H "X-App-User-Role: parent" \
    -H "X-App-User-Id: ${parent}" \
    -H "X-User-Id: ${parent}" \
    "$@"
}

watch_api() {
  local token="$1"
  shift
  curl -fsS -H "X-Watch-Device-Token: ${token}" "$@"
}

assert_http_400() {
  local output_file="$1"
  shift
  local status
  status="$(curl -sS -o "$output_file" -w '%{http_code}' "$@")"
  test "$status" = "400"
}

group_a="$(api "$PARENT_A" -H 'Content-Type: application/json' \
  -d "{\"name\":\"REQ023-A-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
group_b="$(api "$PARENT_B" -H 'Content-Type: application/json' \
  -d "{\"name\":\"REQ023-B-${SUFFIX}\"}" "$API_BASE/api/family-groups")"
group_a_id="$(jq -er '.id' <<<"$group_a")"
group_b_id="$(jq -er '.id' <<<"$group_b")"

child_a="$(api "$PARENT_A" -H 'Content-Type: application/json' \
  -d "{\"name\":\"小明-${SUFFIX}\",\"familyGroupId\":${group_a_id}}" "$API_BASE/api/children")"
child_b="$(api "$PARENT_B" -H 'Content-Type: application/json' \
  -d "{\"name\":\"小红-${SUFFIX}\",\"familyGroupId\":${group_b_id}}" "$API_BASE/api/children")"
child_a_id="$(jq -er '.id' <<<"$child_a")"
child_b_id="$(jq -er '.id' <<<"$child_b")"
profile_a="$(jq -er '.profileKey' <<<"$child_a")"
profile_b="$(jq -er '.profileKey' <<<"$child_b")"

bind_code_a="$(api "$PARENT_A" -H 'Content-Type: application/json' \
  -d "{\"familyGroupId\":${group_a_id},\"expiresInMinutes\":10}" \
  "$API_BASE/api/children/${child_a_id}/auth-code" | jq -er '.code')"
bind_code_b="$(api "$PARENT_B" -H 'Content-Type: application/json' \
  -d "{\"familyGroupId\":${group_b_id},\"expiresInMinutes\":10}" \
  "$API_BASE/api/children/${child_b_id}/auth-code" | jq -er '.code')"
token_a="$(curl -fsS -H 'Content-Type: application/json' \
  -d "{\"code\":\"${bind_code_a}\",\"deviceName\":\"REQ023-A\"}" \
  "$API_BASE/api/watch/device-bind" | jq -er '.deviceToken')"
token_b="$(curl -fsS -H 'Content-Type: application/json' \
  -d "{\"code\":\"${bind_code_b}\",\"deviceName\":\"REQ023-B\"}" \
  "$API_BASE/api/watch/device-bind" | jq -er '.deviceToken')"

watch_page="$(curl -fsS "$API_BASE/watch")"
for text in '表盘设置' '我的世界' 'HelloKitty' '星光梦可' '生成好友码' '好友列表' '积分榜'; do
  grep -Fq "$text" <<<"$watch_page"
done
echo 'ok 1 - 手表菜单展示三款表盘、好友入口和好友积分榜'

grep -Fq 'name="viewport"' <<<"$watch_page"
grep -Fq '.panel:not([data-panel=home])' <<<"$watch_page"
grep -Fq 'touch-action:pan-y' <<<"$watch_page"
echo 'ok 2 - 好友与设置面板适配手表视口并支持纵向触摸滚动'

test "$(watch_api "$token_a" "$API_BASE/api/watch/settings" | jq -er '.watchFace')" = 'world'
for face in world hellokitty starlight; do
  saved="$(watch_api "$token_a" -X PUT -H 'Content-Type: application/json' \
    -d "{\"watchFace\":\"${face}\"}" "$API_BASE/api/watch/settings" | jq -er '.watchFace')"
  test "$saved" = "$face"
  test "$(watch_api "$token_a" "$API_BASE/api/watch/settings" | jq -er '.watchFace')" = "$face"
done
echo 'ok 3 - 三款表盘均可选择并按孩子持久化'

friend_code_a="$(watch_api "$token_a" -H 'Content-Type: application/json' -d '{"expiresInMinutes":5}' \
  "$API_BASE/api/watch/friend-code" | jq -er '.code')"
[[ "$friend_code_a" =~ ^[0-9]{8}$ ]]
assert_http_400 "/tmp/req023-invalid-${SUFFIX}.json" \
  -H "X-Watch-Device-Token: ${token_b}" -H 'Content-Type: application/json' \
  -d '{"code":"12AB"}' "$API_BASE/api/watch/friends"
jq -e '.error | contains("8 位")' "/tmp/req023-invalid-${SUFFIX}.json" >/dev/null
echo 'ok 4 - 好友认证码为 8 位随机数字且拒绝非法格式'

self_code_b="$(watch_api "$token_b" -H 'Content-Type: application/json' -d '{}' \
  "$API_BASE/api/watch/friend-code" | jq -er '.code')"
assert_http_400 "/tmp/req023-self-${SUFFIX}.json" \
  -H "X-Watch-Device-Token: ${token_b}" -H 'Content-Type: application/json' \
  -d "{\"code\":\"${self_code_b}\"}" "$API_BASE/api/watch/friends"
jq -e '.error | contains("自己")' "/tmp/req023-self-${SUFFIX}.json" >/dev/null
echo 'ok 5 - 好友码机制阻止孩子添加自己'

add_result="$(watch_api "$token_b" -H 'Content-Type: application/json' \
  -d "{\"code\":\"${friend_code_a}\"}" "$API_BASE/api/watch/friends")"
test "$(jq -er '.status' <<<"$add_result")" = 'ok'
test "$(jq -er --arg profile "$profile_a" '.friend.profileKey == $profile' <<<"$add_result")" = 'true'
assert_http_400 "/tmp/req023-replay-${SUFFIX}.json" \
  -H "X-Watch-Device-Token: ${token_b}" -H 'Content-Type: application/json' \
  -d "{\"code\":\"${friend_code_a}\"}" "$API_BASE/api/watch/friends"
jq -e '.error | contains("无效或已过期")' "/tmp/req023-replay-${SUFFIX}.json" >/dev/null
echo 'ok 6 - 两个孩子可跨家庭添加好友且认证码只能使用一次'

api "$PARENT_A" -H 'Content-Type: application/json' \
  -d "{\"familyGroupId\":${group_a_id},\"childId\":${child_a_id},\"type\":\"points\",\"direction\":\"+\",\"points\":12,\"description\":\"REQ023 leaderboard\"}" \
  "$API_BASE/api/transactions" >/dev/null
api "$PARENT_B" -H 'Content-Type: application/json' \
  -d "{\"familyGroupId\":${group_b_id},\"childId\":${child_b_id},\"type\":\"points\",\"direction\":\"+\",\"points\":5,\"description\":\"REQ023 leaderboard\"}" \
  "$API_BASE/api/transactions" >/dev/null
friends_payload="$(watch_api "$token_b" "$API_BASE/api/watch/friends")"
jq -e --arg profile "$profile_a" '.friends | any(.profileKey == $profile and .score == 12)' <<<"$friends_payload" >/dev/null
jq -e --arg first "$profile_a" --arg second "$profile_b" \
  '.leaderboard | length == 2 and .[0].profileKey == $first and .[1].profileKey == $second' \
  <<<"$friends_payload" >/dev/null
echo 'ok 7 - 手表好友列表展示积分并按积分生成包含自己的好友榜'

parent_view="$(api "$PARENT_A" "$API_BASE/api/children/${child_a_id}/friends?familyGroupId=${group_a_id}")"
jq -e --arg profile "$profile_b" '.friends | any(.profileKey == $profile)' <<<"$parent_view" >/dev/null
notifications_a="$(api "$PARENT_A" "$API_BASE/api/children/friend-notifications?unreadOnly=true")"
notifications_b="$(api "$PARENT_B" "$API_BASE/api/children/friend-notifications?unreadOnly=true")"
notification_a_id="$(jq -er --arg friend "$profile_b" '.notifications[] | select(.friendProfileKey == $friend) | .id' <<<"$notifications_a" | head -1)"
jq -e --arg friend "$profile_a" '.notifications | any(.friendProfileKey == $friend)' <<<"$notifications_b" >/dev/null
api "$PARENT_A" -X POST "$API_BASE/api/children/friend-notifications/${notification_a_id}/read" | jq -e '.status == "ok"' >/dev/null
api "$PARENT_A" "$API_BASE/api/children/friend-notifications?unreadOnly=true" \
  | jq -e --arg id "$notification_a_id" '.notifications | all((.id | tostring) != $id)' >/dev/null
echo 'ok 8 - Web 家长端可查看好友、接收双方通知并标记已读'

printf 'PASS REQ-023: 8/8 cases passed (%s, %s)\n' "$profile_a" "$profile_b"
