#!/usr/bin/env bash

set -euo pipefail

GOLDFISH_HOME="${GOLDFISH_HOME:-${HOME}/.goldfish}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_LIBRARY_JSON="$SCRIPT_DIR/../application/mcp/family-reward-mcp-tool-library-split.json"

FAMILY_POINTS_MCP_TOKEN="${FAMILY_POINTS_MCP_TOKEN:-}"
FAMILY_POINTS_MCP_TOOL_KEY="${FAMILY_POINTS_MCP_TOOL_KEY:-family-reward-mcp}"
FAMILY_POINTS_MCP_NAME="${FAMILY_POINTS_MCP_NAME:-家庭积分应用}"
FAMILY_POINTS_MCP_DESC="${FAMILY_POINTS_MCP_DESC:-家庭积分应用 MCP：所有工具要求 parent_user_id；写操作仅允许所属家长，积分查询覆盖家长可访问的全部家庭。}"

FAMILY_POINTS_MCP_URL="${FAMILY_POINTS_MCP_URL:-}"
FAMILY_POINTS_MCP_SERVERS="${FAMILY_POINTS_MCP_SERVERS:-}"
FAMILY_REWARD_MCP_LIBRARY_JSON="${FAMILY_REWARD_MCP_LIBRARY_JSON:-$DEFAULT_LIBRARY_JSON}"

parse_library_json() {
  local file="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "检测到 FAMILY_REWARD_MCP_LIBRARY_JSON，但当前环境未安装 jq，无法自动解析 JSON。请安装 jq 或手工设置 FAMILY_POINTS_MCP_SERVERS。"
    return 1
  fi

  jq -r '
    .services[]
    | "\(.baseUrl // "")\(.mcpEndpoint // "")|\(
        .name
        | gsub("[^A-Za-z0-9]"; "-")
        | ascii_downcase
      )|\(
        .title // ""
      )|\(
        .description // ""
      )"
  ' "$file"
}

if [ -z "$FAMILY_POINTS_MCP_SERVERS" ] && [ -z "$FAMILY_POINTS_MCP_URL" ]; then
  if [ -n "$FAMILY_REWARD_MCP_LIBRARY_JSON" ] && [ -f "$FAMILY_REWARD_MCP_LIBRARY_JSON" ]; then
    parsed="$(parse_library_json "$FAMILY_REWARD_MCP_LIBRARY_JSON" || true)"
    if [ -n "$parsed" ]; then
      FAMILY_POINTS_MCP_SERVERS="$parsed"
    fi
  fi
fi

if [ -z "$FAMILY_POINTS_MCP_SERVERS" ] && [ -z "$FAMILY_POINTS_MCP_URL" ]; then
  cat <<'EOF'
请设置 FAMILY_POINTS_MCP_URL、FAMILY_POINTS_MCP_SERVERS，或设置 FAMILY_REWARD_MCP_LIBRARY_JSON 后重试。

示例（读取拆分库清单）：
  export FAMILY_REWARD_MCP_LIBRARY_JSON="/path/to/family-reward-mcp-tool-library-split.json"
  bash scripts/install-family-rewards-mcp-tool.sh

示例（服务拆分后手工多服务）：
  export FAMILY_POINTS_MCP_SERVERS=$'https://happylife.ai.impx.net/api/mcp|family-reward-mcp|家加分 MCP 服务（按工具拆分）|家加分 MCP：提供孩子、积分、记录、规则、家庭组等独立工具（family_reward_*）。|'
  bash scripts/install-family-rewards-mcp-tool.sh
EOF
  exit 1
fi

if [ -z "$FAMILY_POINTS_MCP_SERVERS" ]; then
  FAMILY_POINTS_MCP_SERVERS="${FAMILY_POINTS_MCP_URL}|${FAMILY_POINTS_MCP_TOOL_KEY}|${FAMILY_POINTS_MCP_NAME}|${FAMILY_POINTS_MCP_DESC}|${FAMILY_POINTS_MCP_TOKEN}"
fi

json_escape() {
  local value="$1"
  value="${value//'\\'/'\\\\'}"
  value="${value//'\"'/'\\\"'}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

write_tool_json() {
  local tools_dir=$1 name=$2 tool_key=$3 desc=$4 url=$5 token=$6
  mkdir -p "$tools_dir"
  cat > "$tools_dir/tool.json" <<EOF
{
  "id": 0,
  "toolKey": "$tool_key",
  "name": "$name",
  "toolType": "mcp",
  "description": "$desc",
  "configJson": "{\"transport\":\"streamable\",\"url\":\"$(json_escape "$url")\",\"token\":\"$(json_escape "$token")\"}",
  "status": "Active"
}
EOF
}

has_tool_key() {
  local key=$1
  if [ ! -f "$TOOL_ID_FILE" ]; then
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg key "$key" 'any(.[]; (.ToolKey // .toolKey) == $key)' "$TOOL_ID_FILE" >/dev/null
    return $?
  fi
  grep -Eq "\"(ToolKey|toolKey)\": \"${key}\"" "$TOOL_ID_FILE"
}

TOOL_ID_FILE="$GOLDFISH_HOME/tool_ids.json"
TOOL_ID_ENTRIES_FILE="$(mktemp)"
trap 'rm -f "$TOOL_ID_ENTRIES_FILE"' EXIT
declare -a pending_tool_keys=()
declare -a default_tool_json_entries=()
SERVICE_COUNT=0

while IFS= read -r line; do
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue

  IFS='|' read -r url key name desc token <<< "$line"
  url="$(printf "%s" "$url" | sed 's/[[:space:]]//g')"
  if [ -z "$url" ]; then
    echo "跳过一项服务：缺少 URL。配置行：$line"
    continue
  fi

  key="$(printf "%s" "${key:-$FAMILY_POINTS_MCP_TOOL_KEY}" | sed 's/[[:space:]]//g')"
  [ -z "$key" ] && key="$FAMILY_POINTS_MCP_TOOL_KEY"
  name="${name:-$FAMILY_POINTS_MCP_NAME}"
  desc="${desc:-$FAMILY_POINTS_MCP_DESC}"
  token="${token:-$FAMILY_POINTS_MCP_TOKEN}"

  write_tool_json "$GOLDFISH_HOME/tools/$key" "$name" "$key" "$desc" "$url" "$token"
  echo "家加分 MCP 工具已写入: $GOLDFISH_HOME/tools/$key/tool.json"

  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg key "$key" --arg name "$name" '{Id: 0, ToolKey: $key, Name: $name, ToolType: "mcp", McpToolIds: []}' >> "$TOOL_ID_ENTRIES_FILE"
  else
    default_tool_json_entries+=("{ \"Id\": 0, \"ToolKey\": \"${key}\", \"Name\": \"${name}\", \"ToolType\": \"mcp\", \"McpToolIds\": [] }")
  fi
  if [ ! -f "$TOOL_ID_FILE" ] || ! has_tool_key "$key"; then
    pending_tool_keys+=("$key")
  fi

  SERVICE_COUNT=$((SERVICE_COUNT + 1))
done < <(printf "%s\n" "$FAMILY_POINTS_MCP_SERVERS")

if [ "$SERVICE_COUNT" -eq 0 ]; then
  echo "没有解析到任何有效服务配置，已中止。"
  exit 1
fi

if [ ! -f "$TOOL_ID_FILE" ]; then
  {
    printf '%s\n' "["
    printf '  {\n    "Id": 0,\n    "ToolKey": "internal-tools",\n    "Name": "内部工具",\n    "ToolType": "internal",\n    "McpToolIds": []\n  }'
    if [ -s "$TOOL_ID_ENTRIES_FILE" ] || [ "${#default_tool_json_entries[@]}" -gt 0 ]; then
      printf ',\n'
    fi
    if [ -s "$TOOL_ID_ENTRIES_FILE" ]; then
      jq -s '.' "$TOOL_ID_ENTRIES_FILE" | sed '1d;$d;s/^/  /'
    fi
    for i in "${!default_tool_json_entries[@]}"; do
      printf '  %s' "${default_tool_json_entries[$i]}"
      if [ "$i" -lt $(( ${#default_tool_json_entries[@]} - 1 )) ]; then
        printf ','
      fi
      printf '\n'
    done
    printf ']\n'
  } > "$TOOL_ID_FILE"
  echo "已创建 ${TOOL_ID_FILE}，并自动包含家加分 MCP 工具引用。"
elif [ "${#pending_tool_keys[@]}" -gt 0 ]; then
  if command -v jq >/dev/null 2>&1 && [ -s "$TOOL_ID_ENTRIES_FILE" ]; then
    tmp_file="$(mktemp)"
    jq -s '
      .[0] as $current
      | .[1:] as $updates
      | reduce $updates[] as $u (
          $current;
          if any(.[]; (.ToolKey // .toolKey) == $u.ToolKey) then
            map(if (.ToolKey // .toolKey) == $u.ToolKey then (. + $u) else . end)
          else
            . + [$u]
          end
        )
    ' "$TOOL_ID_FILE" "$TOOL_ID_ENTRIES_FILE" > "$tmp_file"
    mv "$tmp_file" "$TOOL_ID_FILE"
    echo "已更新 ${TOOL_ID_FILE}，并包含家加分 MCP 工具引用。"
  else
    echo "${TOOL_ID_FILE} 已存在，未执行覆盖。请手动追加以下条目："
    for key in "${pending_tool_keys[@]}"; do
      echo "- 添加 ToolKey 为 \"$key\" 的 MCP 工具条目到全局 tool_ids.json"
    done
  fi
else
  echo "已检测到已存在的工具条目，无需追加。"
fi
