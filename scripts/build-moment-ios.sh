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
common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
ln -s "$(dirname "$(dirname "$common")")/AgentIdentity" "$ATLAS_BUILD_WORK/AgentIdentity"
connect_root="$(dirname "$(dirname "$common")")/MyVnc"
identity_root="$(dirname "$(dirname "$common")")/AgentIdentity"
ln -s "$connect_root" "$ATLAS_BUILD_WORK/MyVnc"
: "${CONNECT_RTC_LIBRARY_DIR:?Provide the matching committed ios-arm64 Connect native output}"
python3 - "$connect_root" "$identity_root" "$CONNECT_RTC_LIBRARY_DIR" "$ATLAS_BUILD_OUTPUT" <<'SDK'
import hashlib,json,subprocess,sys
from pathlib import Path
connect,identity,native,output=map(Path,sys.argv[1:])
receipts={}
for key,path,scope in [('connect',connect,['sdk/MyVnc.Realtime.Apple','native/rtc']),('identity',identity,['packages/AgentIdentity-iOS'])]:
    commit=subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
    remote=subprocess.check_output(['git','-C',str(path),'ls-remote','origin','refs/heads/main'],text=True).split()[0]
    assert commit==remote, key+' source is not pushed main'
    subprocess.run(['git','-C',str(path),'diff','--quiet','HEAD','--',*scope],check=True)
    receipts[key]=commit
assert (native/'source-commit.txt').read_text().strip()==receipts['connect']
assert (native/'native-version.txt').read_text().splitlines()[0]=='ios-arm64'
receipts['nativeLibrarySha256']=hashlib.sha256((native/'libmyvnc-rtc.a').read_bytes()).hexdigest()
(output/'sdk-dependencies.json').write_text(json.dumps(receipts,indent=2)+'\n')
SDK
export MOMENT_IOS_RELEASE_FLAVOR="${MOMENT_IOS_RELEASE_FLAVOR:-successor}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export HAPPYLIFE_PARENT_BUILD_ROOT="$ATLAS_BUILD_WORK/ios"
export HAPPYLIFE_PARENT_EXPORT_DIR="$ATLAS_BUILD_OUTPUT"
export HAPPYLIFE_PARENT_EXPORT_OPTIONS="$ATLAS_BUILD_WORK/ios/ExportOptions.plist"
mkdir -p "$HAPPYLIFE_PARENT_BUILD_ROOT"
python3 "$source_dir/scripts/prepare-moment-ios-release.py" "$source_dir" \
  "$HAPPYLIFE_PARENT_EXPORT_OPTIONS" "$ATLAS_BUILD_OUTPUT/release-identity.json" \
  "$MOMENT_IOS_RELEASE_FLAVOR"
xcrun swiftc "$source_dir/parent-app/ios/HappyLifeParent/NativeModels.swift" \
  "$source_dir/parent-app/ios/Tests/NativeModelTests.swift" -o "$ATLAS_BUILD_WORK/native-model-tests"
"$ATLAS_BUILD_WORK/native-model-tests"
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

# Release only this completed build's idle asset helper before managed workspace cleanup.
python3 - <<'CLEANUP'
import os,signal,subprocess,time
work=os.environ['ATLAS_BUILD_WORK']
result=subprocess.run(['lsof','-a','-d','cwd','-Fpcn'],capture_output=True,text=True)
pid=command=None
for line in result.stdout.splitlines():
    if line.startswith('p'):pid=int(line[1:]);command=None
    elif line.startswith('c'):command=line[1:]
    elif line.startswith('n') and command=='ibtoold' and (line[1:]==work or line[1:].startswith(work+'/')):
        try:os.kill(pid,signal.SIGTERM)
        except ProcessLookupError:pass
time.sleep(3)
CLEANUP
