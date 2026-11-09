#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?run through host-build-output}"
: "${ATLAS_BUILD_OUTPUT:?run through host-build-output}"
: "${ATLAS_BUILD_LOGS:?run through host-build-output}"
root="$(git rev-parse --show-toplevel)"
commit="${MOMENT_RELEASE_COMMIT:-$(git -C "$root" rev-parse HEAD)}"
commit="$(git -C "$root" rev-parse "$commit^{commit}")"
remote="$(git -C "$root" ls-remote origin refs/heads/main | cut -f1)"
git -C "$root" cat-file -e "$commit^{commit}"
git -C "$root" merge-base --is-ancestor "$commit" "$remote" || { echo 'Release source must be included in origin/main.' >&2; exit 1; }
git -C "$root" diff --quiet HEAD -- parent-app/ios watch-app/apple scripts/build-moment-ios.sh
source_dir="$ATLAS_BUILD_WORK/source"
mkdir -p "$source_dir"
git -C "$root" archive "$commit" | tar -x -C "$source_dir"
common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
mkdir -p "$ATLAS_BUILD_WORK/AgentIdentity" "$ATLAS_BUILD_WORK/MyVnc" "$ATLAS_BUILD_WORK/Atlas"
connect_root="$(dirname "$(dirname "$common")")/MyVnc"
identity_root="$(dirname "$(dirname "$common")")/AgentIdentity"
atlas_root="$(dirname "$(dirname "$common")")/Atlas"

: "${CONNECT_RTC_LIBRARY_DIR:?Provide the matching committed ios-arm64 Connect native output}"
python3 - "$connect_root" "$identity_root" "$CONNECT_RTC_LIBRARY_DIR" "$ATLAS_BUILD_OUTPUT" "$atlas_root" <<'SDK'
import hashlib,json,subprocess,sys
from pathlib import Path
connect,identity,native,output,atlas=map(Path,sys.argv[1:])
receipts={}
packages={'connect':('MyVnc','sdk/MyVnc.Realtime.Apple'),'identity':('AgentIdentity','packages/AgentIdentity-iOS'),'atlas':('Atlas','packages/Atlas-Releases-Apple')}
for key,path,scope in [('connect',connect,['sdk/MyVnc.Realtime.Apple','native/rtc']),('identity',identity,['packages/AgentIdentity-iOS']),('atlas',atlas,['packages/Atlas-Releases-Apple'])]:
    commit=subprocess.check_output(['git','-C',str(path),'ls-remote','origin','refs/heads/main'],text=True).split()[0]
    if subprocess.run(['git','-C',str(path),'cat-file','-e',commit+'^{commit}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
        subprocess.run(['git','-C',str(path),'fetch','-q','--no-tags','origin',commit],check=True)
    # Archive the pushed commit below; concurrent working-tree edits are excluded.
    receipts[key]=commit
    # Freeze only the public SDK inputs; unrelated concurrent app work stays outside the archive.
    directory,package=packages[key]
    target=Path(__import__('os').environ['ATLAS_BUILD_WORK'])/directory
    archive=subprocess.Popen(['git','-C',str(path),'archive',commit,package],stdout=subprocess.PIPE)
    subprocess.run(['tar','-x','-C',str(target)],stdin=archive.stdout,check=True)
    archive.stdout.close(); assert archive.wait()==0
native_commit=(native/'source-commit.txt').read_text().strip()
subprocess.run(['git','-C',str(connect),'merge-base','--is-ancestor',native_commit,receipts['connect']],check=True)
for line in (native/'native-source-sha256.txt').read_text().splitlines():
    expected,relative=line.split(None,1);relative=relative.strip()
    assert relative.startswith('native/rtc/') and '..' not in Path(relative).parts
    committed=subprocess.check_output(['git','-C',str(connect),'show',receipts['connect']+':'+relative])
    assert hashlib.sha256(committed).hexdigest()==expected, 'Connect native source changed; rebuild native library'
receipts['connectNativeBuildCommit']=native_commit
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
xcrun swiftc -parse-as-library "$source_dir/parent-app/ios/HappyLifeParent/DiningModels.swift"   "$source_dir/parent-app/ios/Tests/DiningModelTests.swift" -o "$ATLAS_BUILD_WORK/dining-model-tests"
"$ATLAS_BUILD_WORK/dining-model-tests"
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
result=subprocess.run(['lsof','-a','-c','ibtoold','-Fpcn'],capture_output=True,text=True)
pid=command=None
for line in result.stdout.splitlines():
    if line.startswith('p'):pid=int(line[1:]);command=None
    elif line.startswith('c'):command=line[1:]
    elif line.startswith('n') and command=='ibtoold' and (line[1:]==work or line[1:].startswith(work+'/')):
        usage=subprocess.run(['ps','-p',str(pid),'-o','%cpu='],capture_output=True,text=True).stdout.strip()
        if usage and float(usage)<1:
            try:os.kill(pid,signal.SIGTERM)
            except ProcessLookupError:pass
time.sleep(3)
CLEANUP
