#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/happylife-watch-check.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
python3 - <<'PY'
import json, plistlib
from pathlib import Path
config = json.loads(Path('../app-config.json').read_text())
info = plistlib.loads(Path('HappyLifeWatch/Info.plist').read_bytes())
assert info['HappyLifeAPIBaseURL'] == config['apiBaseUrl'], 'Apple API URL must match the existing watch configuration'
assert info['WKApplication'] and info['WKWatchOnly']
assert 'WKRunsIndependentlyOfCompanionApp' not in info, 'A watch-only app cannot also declare independent companion mode'
print('PASS: independent watch app configuration and API origin')
PY
xcrun --sdk macosx swiftc HappyLifeWatch/WatchAPI.swift HappyLifeWatch/DeviceCredential.swift \
  HappyLifeWatch/WatchStore.swift tests/WatchAPITests.swift -o "$build_dir/api-tests"
"$build_dir/api-tests"
xcodebuild -project HappyLifeWatch.xcodeproj -target HappyLifeWatch \
  -configuration Release -sdk watchos CODE_SIGNING_ALLOWED=NO \
  SYMROOT="$build_dir/products" OBJROOT="$build_dir/objects" build > "$build_dir/build.log" 2>&1 || {
  cat "$build_dir/build.log"
  exit 1
}
echo 'PASS: unsigned watchOS Release build (physical device execution and signing are separate checks)'
