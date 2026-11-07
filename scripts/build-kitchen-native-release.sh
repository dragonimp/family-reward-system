#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?Use one host-build-queue and host-build-output invocation}"
bash scripts/build-dining-native-release.sh
bash scripts/build-moment-android-release.sh
