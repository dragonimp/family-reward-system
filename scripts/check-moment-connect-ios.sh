#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash "$root/../MyVnc/scripts/Build-NativeRtc.sh" ios-arm64 > "$ATLAS_BUILD_LOGS/native.log" 2>&1 || { tail -40 "$ATLAS_BUILD_LOGS/native.log"; exit 1; }
export CONNECT_RTC_LIBRARY_DIR="$ATLAS_BUILD_OUTPUT"
xcodebuild -project "$root/parent-app/ios/HappyLifeParent.xcodeproj" -scheme HappyLifeParent -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$ATLAS_BUILD_WORK/DerivedData" CODE_SIGNING_ALLOWED=NO build > "$ATLAS_BUILD_LOGS/ios.log" 2>&1 || { tail -70 "$ATLAS_BUILD_LOGS/ios.log"; exit 1; }
printf '%s\n' 'PASS: Moment iOS Connect SDK linked build' > "$ATLAS_BUILD_OUTPUT/ios-checks.txt"
# Xcode helper may retain its cwd after a completed build. Only this build's idle ibtoold is eligible.
python3 - <<'PY'
import os,subprocess,signal
work=os.environ['ATLAS_BUILD_WORK']
r=subprocess.run(['lsof','-a','-d','cwd','-Fpcn'],capture_output=True,text=True)
pid=command=None
for line in r.stdout.splitlines():
    if line.startswith('p'):pid=int(line[1:]);command=None
    elif line.startswith('c'):command=line[1:]
    elif line.startswith('n') and command=='ibtoold' and line[1:].startswith(work+'/'):
        try:os.kill(pid,signal.SIGTERM)
        except ProcessLookupError:pass
PY
