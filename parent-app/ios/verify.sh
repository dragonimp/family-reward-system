#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -z "${HOST_BUILD_QUEUE_TOKEN:-}" ]]; then
  exec "$HOME/.local/bin/host-build-queue" --label linko-moment-ios-verify -- "$HOME/.local/bin/host-build-output" --project family --target ios-native-verification -- bash "$0"
fi
cd "$root/parent-app/ios"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
bash "$root/parent-app/ios/check-local-time.sh"
python3 "$root/scripts/check-ios-localization.py"
xcrun swiftc HappyLifeParent/NativeModels.swift Tests/NativeModelTests.swift -o "$ATLAS_BUILD_WORK/native-model-tests"
"$ATLAS_BUILD_WORK/native-model-tests"
if rg -n 'WKWebView|import WebKit' HappyLifeParent --glob '*.swift'; then
  echo 'Business app must contain only native views' >&2
  exit 1
fi
plutil -lint HappyLifeParent/Info.plist HappyLifeParent.xcodeproj/project.pbxproj
xcodebuild -project HappyLifeParent.xcodeproj -scheme HappyLifeParent \
  -jobs 2 -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$ATLAS_BUILD_WORK/DerivedData" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=17.0 build -quiet
xcodebuild -project HappyLifeParent.xcodeproj -scheme HappyLifeParent \
  -jobs 2 -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ATLAS_BUILD_WORK/Linko Family.xcarchive" \
  -derivedDataPath "$ATLAS_BUILD_WORK/DerivedData" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=17.0 archive -quiet

python3 - <<'PY_CHECK'
import plistlib, os
from pathlib import Path
app = Path(os.environ['ATLAS_BUILD_WORK'])/'Linko Family.xcarchive/Products/Applications/Linko Moment.app'
phone = plistlib.loads((app/'Info.plist').read_bytes())
watch = plistlib.loads((app/'Watch/Linko Moment Watch.app/Info.plist').read_bytes())
assert watch['WKApplication']
assert watch['WKCompanionAppBundleIdentifier'] == phone['CFBundleIdentifier']
assert watch['CFBundleIdentifier'].startswith(phone['CFBundleIdentifier'] + '.')
assert watch['WKRunsIndependentlyOfCompanionApp'] is True
assert not watch.get('WKWatchOnly', False)
assert watch['CFBundleVersion'] == phone['CFBundleVersion']
assert watch['CFBundleShortVersionString'] == phone['CFBundleShortVersionString']
assert phone['UIDeviceFamily'] == [1, 2]
assert 'UIInterfaceOrientationLandscapeLeft' in phone['UISupportedInterfaceOrientations~ipad']
print('PASS: archived iPhone/iPad app and independent companion Watch with matching version')
PY_CHECK

python3 - <<'PY_EXPORT'
import json, os
from pathlib import Path
entries = {}
for path in Path(os.environ['ATLAS_BUILD_WORK']).rglob('*.stringsdata'):
    if '/AgentIdentity' in str(path): continue
    for table, values in json.loads(path.read_text()).get('tables', {}).items():
        if table == 'Localizable':
            for value in values: entries[value['key']] = value
(Path(os.environ['ATLAS_BUILD_OUTPUT'])/'compiler-localization.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2)+'\n')
PY_EXPORT

python3 "$root/scripts/check-ios-localization.py" --extracted "$ATLAS_BUILD_WORK/DerivedData" --report "$ATLAS_BUILD_OUTPUT/localization-coverage.json"
printf "Native model tests, simulator build, unsigned archive and Watch bundle checks passed\n" > "$ATLAS_BUILD_OUTPUT/verification.txt"
