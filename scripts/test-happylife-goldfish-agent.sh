#!/usr/bin/env bash

set -euo pipefail

AGENTNODE_RESPONSES_URL="${AGENTNODE_RESPONSES_URL:-http://100.100.59.18:8650/v1/responses}"
AGENTNODE_API_KEY="${AGENTNODE_API_KEY:-goldfish-agent-node-default-key}"
AGENT_PROFILE="${AGENT_PROFILE:-happylife}"
MODEL="${MODEL:-goldfish}"
GOLDFISH_HOME="${GOLDFISH_HOME:-$HOME/.goldfish}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

if [ ! -f "$GOLDFISH_HOME/profiles/$AGENT_PROFILE/profile.json" ]; then
  echo "SKIP Goldfish agent tests: profile '$AGENT_PROFILE' not found under $GOLDFISH_HOME/profiles." >&2
  exit 0
fi

pass_count=0
fail_count=0

ask_agent() {
  local prompt="$1"
  local session_id="codex-happylife-agent-$(date +%s)-$RANDOM"
  jq -cn \
    --arg model "$MODEL" \
    --arg prompt "$prompt" \
    --arg profile "$AGENT_PROFILE" \
    --arg session_id "$session_id" \
    '{
      model: $model,
      input: $prompt,
      metadata: {
        agent_type: "Goldfish",
        AgentProfile: $profile,
        session_id: $session_id
      }
    }' |
    curl -sS "$AGENTNODE_RESPONSES_URL" \
      -H "Authorization: Bearer $AGENTNODE_API_KEY" \
      -H 'Content-Type: application/json' \
      --data-binary @-
}

assert_contains_all() {
  local label="$1"
  local prompt="$2"
  shift 2
  local response text
  response="$(ask_agent "$prompt")"
  text="$(jq -r '.output_text // .output[0].content[0].text // .error // .' <<<"$response")"
  local missing=()
  for expected in "$@"; do
    if [[ "$text" != *"$expected"* ]]; then
      missing+=("$expected")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    printf 'PASS %s\n' "$label"
    pass_count=$((pass_count + 1))
  else
    printf 'FAIL %s\n' "$label"
    printf 'Prompt: %s\n' "$prompt"
    printf 'Missing: %s\n' "${missing[*]}"
    printf 'Answer:\n%s\n' "$text"
    fail_count=$((fail_count + 1))
  fi
}

assert_contains_any() {
  local label="$1"
  local prompt="$2"
  shift 2
  local response text
  response="$(ask_agent "$prompt")"
  text="$(jq -r '.output_text // .output[0].content[0].text // .error // .' <<<"$response")"
  for expected in "$@"; do
    if [[ "$text" == *"$expected"* ]]; then
      printf 'PASS %s\n' "$label"
      pass_count=$((pass_count + 1))
      return
    fi
  done
  printf 'FAIL %s\n' "$label"
  printf 'Prompt: %s\n' "$prompt"
  printf 'Expected one of: %s\n' "$*"
  printf 'Answer:\n%s\n' "$text"
  fail_count=$((fail_count + 1))
}

assert_contains_all "孩子列表 query" "查询孩子列表" "彦谦" "玥玥" "嘟嘟" "薇薇" "小宇" "雨茉" "28"
assert_contains_all "全部孩子 list" "列出全部孩子" "ID" "彦谦" "玥玥" "雨茉"
assert_contains_all "孩子们积分" "我要查询孩子们的积分" "彦谦" "128" "玥玥" "145.5" "雨茉" "100"
assert_contains_all "单个孩子积分" "玥玥现在多少分" "玥玥" "145.5"
assert_contains_any "最近明细" "查询彦谦最近5条积分明细" "彦谦" "记录" "明细"
assert_contains_any "今天加分明细" "查询今天的加分明细" "工具" "记录" "明细" "没有"
assert_contains_any "规则查询" "查询积分规则" "规则" "积分" "奖励"
assert_contains_any "不存在孩子 ID" "查询ID 6的孩子" "未找到" "不存在" "没有"
assert_contains_any "错别字孩子名会查清单对比" "查询玥玥玥现在多少分" "玥玥" "可能" "确认"

printf '\nGoldfish agent tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
