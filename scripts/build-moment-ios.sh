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
python3 - "$source_dir" "$HAPPYLIFE_PARENT_EXPORT_OPTIONS" <<'PY'
from pathlib import Path
import plistlib, re, sys
root = Path(sys.argv[1])
pbx = (root/'parent-app/ios/HappyLifeParent.xcodeproj/project.pbxproj').read_text()
versions = set(re.findall(r'MARKETING_VERSION = ([^;]+);', pbx))
builds = set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', pbx))
assert len(versions) == len(builds) == 1
version, build = next(iter(versions)), next(iter(builds))
assert re.fullmatch(r'[0-9]+(\.[0-9]+){1,2}', version)
assert re.fullmatch(r'[0-9]+(\.[0-9]+)*', build)
options = plistlib.loads((root/'parent-app/ios/ExportOptions.example.plist').read_bytes())
options['teamID'] = 'JQPH54K7SD'
Path(sys.argv[2]).write_bytes(plistlib.dumps(options))
print(f'Version preflight: {version} ({build}), phone/watch/share match')
PY
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
