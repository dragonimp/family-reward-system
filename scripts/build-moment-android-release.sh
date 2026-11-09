#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?Use host-build-queue and host-build-output}" "${ATLAS_BUILD_OUTPUT:?}" "${ATLAS_BUILD_LOGS:?}"
root="$(cd "$(dirname "$0")/.." && pwd)"
identity="${AGENTIDENTITY_ROOT:-$HOME/Projects/AgentIdentity}"
atlas="${ATLAS_ROOT:-$HOME/Projects/Atlas}"
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$JAVA_HOME/bin:$PATH" MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_USE_MSBUILD_SERVER=0
signing="$HOME/.local/share/android-signing/linko-dear"
[[ -f "$signing/linko-dear-android-release.jks" && -f "$signing/key-password" ]]
# Build only the pushed commit archived below; preserve unrelated working-tree edits.
commit="$(git -C "$root" rev-parse HEAD)"
git -C "$root" fetch -q origin main
git -C "$root" merge-base --is-ancestor "$commit" origin/main
source="$ATLAS_BUILD_WORK/android-source"
mkdir -p "$source"
git -C "$root" archive "$commit" | tar -x -C "$source"
sdk_root="$ATLAS_BUILD_WORK/android-sdk"
mkdir -p "$sdk_root/AgentIdentity" "$sdk_root/Atlas"
for dependency in AgentIdentity Atlas MyVnc; do
  if [[ "$dependency" == AgentIdentity ]]; then repository="$identity"; elif [[ "$dependency" == Atlas ]]; then repository="$atlas"; else repository="$HOME/Projects/MyVnc"; fi
  sdk_commit="$(git -C "$repository" rev-parse HEAD)"
  sdk_remote="$(git -C "$repository" ls-remote origin refs/heads/main | cut -f1)"
  [[ "$sdk_commit" == "$sdk_remote" ]] || { echo "$dependency SDK is not published main"; exit 1; }
  mkdir -p "$sdk_root/$dependency"
  git -C "$repository" archive "$sdk_commit" | tar -x -C "$sdk_root/$dependency"
  printf '%s %s\n' "$dependency" "$sdk_commit" >> "$ATLAS_BUILD_OUTPUT/android-sdk-dependencies.txt"
done
native="$HOME/Projects/MyVnc/artifacts/native-rtc/android-arm64"
python3 - "$HOME/Projects/MyVnc" "$native" "$ATLAS_BUILD_OUTPUT" <<'NATIVE'
from pathlib import Path
import subprocess,hashlib,json,sys
repo,native,out=map(Path,sys.argv[1:]);commit=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
built=(native/'source-commit.txt').read_text().strip()
subprocess.run(['git','-C',str(repo),'merge-base','--is-ancestor',built,commit],check=True)
assert (native/'native-version.txt').read_text().splitlines()[0]=='android-arm64'
for line in (native/'native-source-sha256.txt').read_text().splitlines():
 sha,name=line.split(None,1);name=name.strip();assert name.startswith('native/rtc/') and '..' not in Path(name).parts
 data=subprocess.check_output(['git','-C',str(repo),'show',commit+':'+name]);assert hashlib.sha256(data).hexdigest()==sha,'Rebuild native Connect library'
data=(native/'libmyvnc-rtc.so').read_bytes()
for symbol in [b'myvnc_data_create',b'myvnc_data_abi_version',b'myvnc_data_read']:assert symbol in data
(out/'connect-native-receipt.json').write_text(json.dumps({'sdkCommit':commit,'nativeBuildCommit':built,'nativeSha256':hashlib.sha256(data).hexdigest()}))
NATIVE
mkdir -p "$sdk_root/MyVnc/artifacts/native-rtc/android-arm64"
cp -R "$native/." "$sdk_root/MyVnc/artifacts/native-rtc/android-arm64/"
identity="$sdk_root/AgentIdentity"
atlas="$sdk_root/Atlas"
dotnet publish "$source/parent-app/android/LinkoFamily.csproj" -f net10.0-android -c Release -r android-arm64 \
 --artifacts-path "$ATLAS_BUILD_WORK/compiled" -m:1 -p:UseSharedCompilation=false \
 -p:AgentIdentityNativeClientProject="$identity/src/AgentIdentity.NativeClient/AgentIdentity.NativeClient.csproj" -p:AtlasSdkRoot="$atlas" -p:MyVncSdkRoot="$sdk_root/MyVnc" \
 -p:AndroidSdkDirectory="$ANDROID_HOME" -p:JavaSdkDirectory="$JAVA_HOME" -p:AndroidPackageFormats=apk \
 -p:AndroidKeyStore=false \
 -o "$ATLAS_BUILD_WORK/publish" > "$ATLAS_BUILD_LOGS/android.log" 2>&1 || { tail -35 "$ATLAS_BUILD_LOGS/android.log"; exit 1; }
apk="$(find "$ATLAS_BUILD_WORK/publish" -name '*-Signed.apk' -print -quit)"; [[ -n "$apk" ]]
"$ANDROID_HOME/build-tools/36.0.0/apksigner" sign --ks "$signing/linko-dear-android-release.jks" --ks-key-alias linko-dear-parent --ks-pass "file:$signing/key-password"  --out "$ATLAS_BUILD_OUTPUT/Moment-Android-1.0.23-32.apk" "$apk"
apk="$ATLAS_BUILD_OUTPUT/Moment-Android-1.0.23-32.apk"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$apk" > "$ATLAS_BUILD_LOGS/signature.log"
rg -qi '4596cdb1ea8a5eea1a2567c6800d2bf4f90f051198a5518beb13abb7ac359c83' "$ATLAS_BUILD_LOGS/signature.log"
rg -q 'Verified using v2 scheme.*true' "$ATLAS_BUILD_LOGS/signature.log"
"$ANDROID_HOME/build-tools/36.0.0/aapt2" dump badging "$apk" > "$ATLAS_BUILD_LOGS/manifest.log"
python3 - "$ATLAS_BUILD_OUTPUT" "$ATLAS_BUILD_LOGS" "$commit" <<'PY'
from pathlib import Path
import sys,json,hashlib
out,logs=map(Path,sys.argv[1:3]);m=(logs/'manifest.log').read_text();assert "name='net.impx.happylife'" in m and "versionName='1.0.23'" in m and "versionCode='32'" in m
apk=out/'Moment-Android-1.0.23-32.apk';receipt={'sourceCommit':sys.argv[3],'version':'1.0.23','buildNumber':'32','sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'signatureVerified':True};(out/'build-receipt.json').write_text(json.dumps(receipt))
(out/'bundle.json').write_text(json.dumps({'version':'1.0.23','activate':False,'sourceCommit':sys.argv[3],'releaseNotes':'干饭记录、收藏和偏好按账号跨设备合并同步；活动首页整页滚动、原文件原生接收；干饭导航支持选择地图。','artifacts':[{'path':'connect-native-receipt.json','platform':'sdk-metadata','architecture':'arm64'},{'path':apk.name,'platform':'android','architecture':'arm64'},{'path':'build-receipt.json','platform':'release-metadata','architecture':'arm64'}]},ensure_ascii=False))
PY
