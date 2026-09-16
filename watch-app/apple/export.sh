#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export_helper="${APPLE_ARCHIVE_EXPORT_HELPER:-$HOME/.local/share/apple-build-tools/export-ios-archive}"
options="${HAPPYLIFE_EXPORT_OPTIONS:-$PWD/build/ExportOptions.plist}"
[[ -x "$export_helper" ]] || { echo 'Shared Apple team export helper is unavailable.' >&2; exit 2; }
[[ -f "$options" ]] || { echo 'Copy ExportOptions.example.plist to build/ExportOptions.plist and set the authorized team ID.' >&2; exit 2; }
# The shared helper owns the dedicated keychain job lock. Do not wrap it again.
"$export_helper" "$PWD/build/HappyLife.xcarchive" "$options" "$PWD/build/TestFlight"
destination="$(/usr/libexec/PlistBuddy -c 'Print :destination' "$options")"
if [[ "$destination" == export ]]; then
  python3 verify-ipa.py "$PWD/build/TestFlight/HappyLife.ipa"
fi
