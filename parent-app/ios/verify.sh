#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build
xcrun swiftc HappyLifeParent/NativeModels.swift Tests/NativeModelTests.swift -o build/native-model-tests
build/native-model-tests
if rg -n 'WKWebView|import WebKit' HappyLifeParent --glob '*.swift'; then
  echo 'Business app must contain only native views' >&2
  exit 1
fi
plutil -lint HappyLifeParent/Info.plist HappyLifeParent.xcodeproj/project.pbxproj
xcodebuild -project HappyLifeParent.xcodeproj -scheme HappyLifeParent \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PWD/build/DerivedData" CODE_SIGN_IDENTITY=- build
xcodebuild -project HappyLifeParent.xcodeproj -scheme HappyLifeParent \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/Linko Family.xcarchive" \
  -derivedDataPath "$PWD/build/DerivedData" CODE_SIGNING_ALLOWED=NO archive

python3 - <<'PY_CHECK'
import plistlib
from pathlib import Path
app = Path('build/Linko Family.xcarchive/Products/Applications/Linko Family.app')
phone = plistlib.loads((app/'Info.plist').read_bytes())
watch = plistlib.loads((app/'Watch/Linko Family Watch.app/Info.plist').read_bytes())
assert watch['WKApplication']
assert watch['WKCompanionAppBundleIdentifier'] == phone['CFBundleIdentifier']
assert watch['CFBundleIdentifier'].startswith(phone['CFBundleIdentifier'] + '.')
assert watch['WKRunsIndependentlyOfCompanionApp'] is True
assert not watch.get('WKWatchOnly', False)
assert watch['CFBundleVersion'] == phone['CFBundleVersion']
assert watch['CFBundleShortVersionString'] == phone['CFBundleShortVersionString']
print('PASS: archived independent companion Watch app and matching iPhone version')
PY_CHECK
