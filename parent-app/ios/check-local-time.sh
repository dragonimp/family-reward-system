#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -z "${HOST_BUILD_QUEUE_TOKEN:-}" ]]; then
  exec "$HOME/.local/bin/host-build-queue" --label moment-native-time-checks -- "$HOME/.local/bin/host-build-output" --project family --target native-time-checks -- bash "$0"
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$root"
sdk_root="${AGENT_IDENTITY_ROOT:-$root/../AgentIdentity}"
sdk="$sdk_root/packages/AgentIdentity-iOS"
harness="$ATLAS_BUILD_WORK/harness"
mkdir -p "$harness/Sources/TimeChecks"
cp parent-app/ios/Tests/LocalTimeChecks.swift "$harness/Sources/TimeChecks/"
export MOMENT_TIME_SDK_PATH="$sdk"
export MOMENT_TIME_SOURCE_ROOT="$root"
python3 - <<'PY_MANIFEST'
import json, os
from pathlib import Path
sdk=json.dumps(os.environ['MOMENT_TIME_SDK_PATH'])
manifest="""// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MomentTimeChecks", platforms: [.macOS(.v12)], dependencies: [
  .package(name: "AgentIdentity", path: SDK_PATH)
], targets: [
  .executableTarget(name: "TimeChecks", dependencies: [.product(name: "AgentIdentityLocalization", package: "AgentIdentity")])
])
"""
(Path(os.environ['ATLAS_BUILD_WORK'])/'harness/Package.swift').write_text(manifest.replace('SDK_PATH',sdk))
root=Path(os.environ['MOMENT_TIME_SOURCE_ROOT'])
phone=(root/'parent-app/ios/HappyLifeParent/HappyLifeParentApp.swift').read_text()
watch=(root/'watch-app/apple/HappyLifeWatch/WatchAPI.swift').read_text()
helpers=phone[phone.index('\nfunc localDateText('):phone.index('\nprivate var connectionKinds')]
helpers+=watch[watch.index('\nfunc watchLocalTime('):]
(Path(os.environ['ATLAS_BUILD_WORK'])/'harness/Sources/TimeChecks/ActualTimeHelpers.swift').write_text('import Foundation\nimport AgentIdentityLocalization\n'+helpers)
PY_MANIFEST
xcrun --sdk macosx swift build --package-path "$harness" --scratch-path "$ATLAS_BUILD_WORK/swift" -j 2 > "$ATLAS_BUILD_LOGS/models.log" 2>&1 || { tail -80 "$ATLAS_BUILD_LOGS/models.log"; exit 1; }
bin="$(xcrun --sdk macosx swift build --package-path "$harness" --scratch-path "$ATLAS_BUILD_WORK/swift" --show-bin-path)"
for language in en zh-Hans; do
  mkdir -p "$bin/$language.lproj"
  cp "parent-app/ios/HappyLifeParent/$language.lproj/Localizable.strings" "$bin/$language.lproj/Localizable.strings"
done
TZ=America/Los_Angeles xcrun --sdk macosx swift run --skip-build --package-path "$harness" --scratch-path "$ATLAS_BUILD_WORK/swift" TimeChecks | tee "$ATLAS_BUILD_OUTPUT/local-time-checks.txt"
