#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
root="$(cd "$(dirname "$0")/.." && pwd)"
package="$ATLAS_BUILD_WORK/NotificationSDK"
mkdir -p "$package/Sources/AgentIdentity" "$package/Tests/AgentIdentityTests"
cp "$root/../AgentIdentity/packages/AgentIdentity-iOS/Sources/AgentIdentity/NotificationClient.swift" "$package/Sources/AgentIdentity/"
cp "$root/../AgentIdentity/packages/AgentIdentity-iOS/Sources/AgentIdentity/AgentIdentityLanguage.swift" "$package/Sources/AgentIdentity/"
cp -R "$root/../AgentIdentity/packages/AgentIdentity-iOS/Sources/AgentIdentity/Resources" "$package/Sources/AgentIdentity/"
python3 - "$root/../AgentIdentity/packages/AgentIdentity-iOS/Sources/AgentIdentity/AgentIdentitySession.swift" "$package/Sources/AgentIdentity/IdentityError.swift" <<'PYCODE'
from pathlib import Path
import sys
source=Path(sys.argv[1]).read_text();start=source.index('public enum IdentityError:');end=source.index('public struct AgentIdentityUserInfo:',start)
Path(sys.argv[2]).write_text('import Foundation\nimport Security\n'+source[start:end])
PYCODE
cp "$root/../AgentIdentity/packages/AgentIdentity-iOS/Tests/AgentIdentityTests/NotificationClientTests.swift" "$package/Tests/AgentIdentityTests/"
cat > "$package/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"NotificationSDK",defaultLocalization:"en",platforms:[.macOS(.v14)],products:[],targets:[.target(name:"AgentIdentity",resources:[.process("Resources")]),.testTarget(name:"AgentIdentityTests",dependencies:["AgentIdentity"])])
SWIFT
xcrun swift test --package-path "$package" --scratch-path "$ATLAS_BUILD_WORK/swift" > "$ATLAS_BUILD_LOGS/swift-tests.log" 2>&1 || { tail -35 "$ATLAS_BUILD_LOGS/swift-tests.log"; exit 1; }
tail -14 "$ATLAS_BUILD_LOGS/swift-tests.log" | tee "$ATLAS_BUILD_OUTPUT/checks.txt"
