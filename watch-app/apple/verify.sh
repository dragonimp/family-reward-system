#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_dir="$(mktemp -d "${ATLAS_BUILD_WORK:-${TMPDIR:-/tmp}}/linko-watch-check.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
python3 - <<'PY'
import plistlib
from pathlib import Path
info = plistlib.loads(Path('../../parent-app/ios/WatchInfo.plist').read_bytes())
assert info['WKApplication'] and info['WKRunsIndependentlyOfCompanionApp']
assert not info.get('WKWatchOnly', False)
assert info['WKCompanionAppBundleIdentifier'] == 'net.impx.happylife.parent'
print('PASS: companion watch configuration')
PY
xcrun --sdk macosx swiftc HappyLifeWatch/WatchAPI.swift HappyLifeWatch/DeviceCredential.swift \
  HappyLifeWatch/WatchStore.swift tests/WatchAPITests.swift -o "$build_dir/api-tests"
"$build_dir/api-tests"
echo 'PASS: shared Watch API checks; companion Watch build is verified by parent-app/ios/verify.sh'
if [[ -n "${ATLAS_BUILD_OUTPUT:-}" ]]; then
  printf '%s\n' 'PASS: shared Watch API and companion configuration checks' > "$ATLAS_BUILD_OUTPUT/watch-api-verify.txt"
fi
