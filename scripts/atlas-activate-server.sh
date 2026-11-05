#!/usr/bin/env bash
set -euo pipefail
# Old root shell activation is retired. Use the enrolled application profile through Atlas.
[[ $# == 3 ]] || { echo 'Use an Atlas central deployment task with an exact published version.' >&2; exit 2; }
export ATLAS_PROJECT_CODE=family-reward ATLAS_RELEASE_VERSION="$1"
: "${ATLAS_COMMAND_OPERATION_ID:?Stable central task UUID required}"
exec node /opt/Atlas/tools/releases-sdk/pipeline-cli.js deployment
