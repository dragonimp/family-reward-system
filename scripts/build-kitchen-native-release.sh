#!/usr/bin/env bash
set -euo pipefail
: "${HOST_BUILD_QUEUE_TOKEN:?Use one host-build-queue invocation}"
# Separate formal outputs survive a later platform failure; both share one host lease.
"$HOME/.local/bin/host-build-output" --project family-reward --target kitchen-selection-ios -- bash scripts/build-dining-native-release.sh
"$HOME/.local/bin/host-build-output" --project family-reward --target kitchen-selection-android -- bash scripts/build-moment-android-release.sh
