#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build
# Keep signing inside the existing team's serialized keychain job.
if [[ "${1:-}" != --signing-job ]]; then
  signing_helper="${APPLE_TEAM_SIGNING_HELPER:-$HOME/.local/share/apple-build-tools/with-team-signing}"
  [[ -x "$signing_helper" ]] || { echo 'Shared Apple team signing helper is unavailable.' >&2; exit 2; }
  exec "$signing_helper" bash "$PWD/archive.sh" --signing-job
fi
: "${APPLE_TEAM_ID:?Missing team signing environment}"
: "${APPLE_SIGNING_IDENTITY:?Missing signing identity}"
# Xcode-managed App Store profiles are applied by the export helper. Build first,
# then give both archived code objects the correct identifiers before export.
xcodebuild -project HappyLifeWatch.xcodeproj -scheme HappyLife \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/HappyLife.xcarchive" \
  CODE_SIGNING_ALLOWED=NO archive
app="$PWD/build/HappyLife.xcarchive/Products/Applications/HappyLife.app"
codesign --force --sign "$APPLE_SIGNING_IDENTITY" --keychain "$APPLE_SIGNING_KEYCHAIN" \
  --identifier net.impx.happylife.watch.apple.watchkitapp "$app/Watch/HappyLifeWatch.app"
codesign --force --sign "$APPLE_SIGNING_IDENTITY" --keychain "$APPLE_SIGNING_KEYCHAIN" \
  --identifier net.impx.happylife.watch.apple "$app"
codesign --verify --deep --strict "$app"
