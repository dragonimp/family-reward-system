#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_root="${HAPPYLIFE_PARENT_BUILD_ROOT:-$PWD/build}"
mkdir -p "$build_root"
if [[ "${1:-}" != --signing-job ]]; then
  signing_helper="${APPLE_TEAM_SIGNING_HELPER:-$HOME/.local/share/apple-build-tools/with-team-signing}"
  [[ -x "$signing_helper" ]] || { echo 'Shared Apple team signing helper is unavailable.' >&2; exit 2; }
  exec "$signing_helper" bash "$PWD/archive.sh" --signing-job
fi
: "${APPLE_TEAM_ID:?Missing team signing environment}"
: "${APPLE_SIGNING_IDENTITY:?Missing signing identity}"
: "${APPLE_SIGNING_KEYCHAIN:?Missing signing keychain}"
xcodebuild -project HappyLifeParent.xcodeproj -scheme HappyLifeParent \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$build_root/Linko Family-signed.xcarchive" \
  -derivedDataPath "$build_root/DerivedData" CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=17.0 archive
app="$build_root/Linko Family-signed.xcarchive/Products/Applications/Linko Moment.app"
# This supplies the team's identity to the archive; export must still embed
# an App Store provisioning profile for this app before it is distributable.
codesign --force --sign "$APPLE_SIGNING_IDENTITY" --keychain "$APPLE_SIGNING_KEYCHAIN" \
  --identifier net.impx.happylife.parent.watchkitapp "$app/Watch/Linko Moment Watch.app"
codesign --force --sign "$APPLE_SIGNING_IDENTITY" --keychain "$APPLE_SIGNING_KEYCHAIN" \
  --entitlements "$PWD/HappyLifeShare/HappyLifeShare.entitlements" \
  --identifier net.impx.happylife.parent.share "$app/PlugIns/Linko Moment Share.appex"
codesign --force --sign "$APPLE_SIGNING_IDENTITY" --keychain "$APPLE_SIGNING_KEYCHAIN" \
  --entitlements "$PWD/HappyLifeParent/HappyLifeParent.entitlements" \
  --identifier net.impx.happylife.parent "$app"
codesign --verify --deep --strict "$app"
