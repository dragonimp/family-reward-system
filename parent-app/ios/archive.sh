#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build
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
  -archivePath "$PWD/build/Linko-Family-signed.xcarchive" \
  -derivedDataPath "$PWD/build/DerivedData" CODE_SIGNING_ALLOWED=NO archive
app="$PWD/build/Linko-Family-signed.xcarchive/Products/Applications/Linko-Family.app"
# This supplies the team's identity to the archive; export must still embed
# an App Store provisioning profile for this app before it is distributable.
codesign --force --sign "$APPLE_SIGNING_IDENTITY" --keychain "$APPLE_SIGNING_KEYCHAIN" \
  --identifier net.impx.happylife.parent "$app"
codesign --verify --deep --strict "$app"
