#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?run through host-build-output}"
: "${ATLAS_BUILD_OUTPUT:?run through host-build-output}"
: "${ATLAS_BUILD_LOGS:?run through host-build-output}"
root="$(git rev-parse --show-toplevel)"
commit="$(git -C "$root" rev-parse HEAD)"
remote="$(git -C "$root" ls-remote origin refs/heads/main | cut -f1)"
[[ "$commit" == "$remote" ]] || { echo 'Release source must match origin/main.' >&2; exit 1; }
git -C "$root" diff --quiet HEAD -- parent-app/ios watch-app/apple scripts/build-moment-ios.sh
source_dir="$ATLAS_BUILD_WORK/source"
mkdir -p "$source_dir"
git -C "$root" archive "$commit" | tar -x -C "$source_dir"
ln -s "$root/../AgentIdentity" "$ATLAS_BUILD_WORK/AgentIdentity"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export HAPPYLIFE_PARENT_BUILD_ROOT="$ATLAS_BUILD_WORK/ios"
export HAPPYLIFE_PARENT_EXPORT_DIR="$ATLAS_BUILD_OUTPUT"
export HAPPYLIFE_PARENT_EXPORT_OPTIONS="$ATLAS_BUILD_WORK/ios/ExportOptions.plist"
mkdir -p "$HAPPYLIFE_PARENT_BUILD_ROOT"
python3 "$source_dir/scripts/prepare-moment-ios-release.py" "$source_dir" \
  "$HAPPYLIFE_PARENT_EXPORT_OPTIONS" "$ATLAS_BUILD_OUTPUT/release-identity.json" \
  "${MOMENT_IOS_RELEASE_FLAVOR:-successor}"
xcrun swiftc "$source_dir/parent-app/ios/HappyLifeParent/ExerciseSession.swift" \
  "$source_dir/parent-app/ios/Tests/ExerciseSessionTests.swift" -o "$ATLAS_BUILD_WORK/exercise-tests"
"$ATLAS_BUILD_WORK/exercise-tests"
bash "$source_dir/parent-app/ios/archive.sh" > "$ATLAS_BUILD_LOGS/archive.log" 2>&1 || { tail -65 "$ATLAS_BUILD_LOGS/archive.log"; exit 1; }
bash "$source_dir/parent-app/ios/export.sh" > "$ATLAS_BUILD_LOGS/export.log" 2>&1 || { tail -65 "$ATLAS_BUILD_LOGS/export.log"; exit 1; }
python3 - "$HAPPYLIFE_PARENT_BUILD_ROOT" "$ATLAS_BUILD_OUTPUT" <<'PY'
import sys, zipfile
from pathlib import Path
archive = Path(sys.argv[1])/'Linko Family-signed.xcarchive'
with zipfile.ZipFile(Path(sys.argv[2])/'Linko-Moment-symbols.zip', 'w', zipfile.ZIP_DEFLATED) as output:
    for item in (archive/'dSYMs').rglob('*'):
        if item.is_file(): output.write(item, str(item.relative_to(archive)))
PY
printf '%s\n' "$commit" > "$ATLAS_BUILD_OUTPUT/source-commit.txt"
shasum -a 256 "$ATLAS_BUILD_OUTPUT/Linko Moment.ipa" "$ATLAS_BUILD_OUTPUT/Linko-Moment-symbols.zip" > "$ATLAS_BUILD_OUTPUT/sha256.txt"
echo 'PASS: signed IPA, symbols and source receipt ready'
