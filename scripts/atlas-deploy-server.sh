#!/usr/bin/env bash
set -euo pipefail
# Compatibility client. Building and publishing immutable artifacts use Atlas separately.
[[ "${ATLAS_SERVER_EXECUTION:-0}" == 1 ]] || {
  echo 'Submit deployment to Atlas. The old Mac SSH/build/activation entry is retired.' >&2
  exit 75
}
export ATLAS_PROJECT_CODE=family-reward
exec node /opt/Atlas/tools/releases-sdk/pipeline-cli.js deployment
