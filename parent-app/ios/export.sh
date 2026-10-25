#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export_helper="${APPLE_ARCHIVE_EXPORT_HELPER:-$HOME/.local/share/apple-build-tools/export-ios-archive}"
build_root="${HAPPYLIFE_PARENT_BUILD_ROOT:-$PWD/build}"
output_dir="${HAPPYLIFE_PARENT_EXPORT_DIR:-$PWD/build/TestFlight}"
options="${HAPPYLIFE_PARENT_EXPORT_OPTIONS:-$build_root/ExportOptions.plist}"
[[ -x "$export_helper" ]] || { echo 'Shared Apple team export helper is unavailable.' >&2; exit 2; }
[[ -f "$options" ]] || { echo 'Prepare build/ExportOptions.plist with the authorized team ID.' >&2; exit 2; }
# The shared helper owns the keychain lock; never wrap it a second time.
"$export_helper" "$build_root/Linko Family-signed.xcarchive" "$options" "$output_dir"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :destination' "$options")" == export ]]; then
  python3 verify-ipa.py "$output_dir/Linko Moment.ipa"
fi
