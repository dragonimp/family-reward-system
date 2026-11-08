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
git -C "$root" diff --quiet HEAD -- parent-app/android scripts/build-moment-android-release.sh
commit="$(git -C "$root" rev-parse HEAD)"
git -C "$root" fetch -q origin main
git -C "$root" merge-base --is-ancestor "$commit" origin/main
source="$ATLAS_BUILD_WORK/android-source"
mkdir -p "$source"
git -C "$root" archive "$commit" | tar -x -C "$source"
sdk_root="$ATLAS_BUILD_WORK/android-sdk"
mkdir -p "$sdk_root/AgentIdentity" "$sdk_root/Atlas"
for dependency in AgentIdentity Atlas; do
  if [[ "$dependency" == AgentIdentity ]]; then repository="$identity"; else repository="$atlas"; fi
  sdk_commit="$(git -C "$repository" rev-parse HEAD)"
  sdk_remote="$(git -C "$repository" ls-remote origin refs/heads/main | cut -f1)"
  [[ "$sdk_commit" == "$sdk_remote" ]] || { echo "$dependency SDK is not published main"; exit 1; }
  git -C "$repository" archive "$sdk_commit" | tar -x -C "$sdk_root/$dependency"
  printf '%s %s\n' "$dependency" "$sdk_commit" >> "$ATLAS_BUILD_OUTPUT/android-sdk-dependencies.txt"
done
identity="$sdk_root/AgentIdentity"
atlas="$sdk_root/Atlas"
dotnet publish "$source/parent-app/android/LinkoFamily.csproj" -f net10.0-android -c Release -r android-arm64 \
 --artifacts-path "$ATLAS_BUILD_WORK/compiled" -m:1 -p:UseSharedCompilation=false \
 -p:AgentIdentityNativeClientProject="$identity/src/AgentIdentity.NativeClient/AgentIdentity.NativeClient.csproj" -p:AtlasSdkRoot="$atlas" \
 -p:AndroidSdkDirectory="$ANDROID_HOME" -p:JavaSdkDirectory="$JAVA_HOME" -p:AndroidPackageFormats=apk \
 -p:AndroidKeyStore=false \
 -o "$ATLAS_BUILD_WORK/publish" > "$ATLAS_BUILD_LOGS/android.log" 2>&1 || { tail -35 "$ATLAS_BUILD_LOGS/android.log"; exit 1; }
apk="$(find "$ATLAS_BUILD_WORK/publish" -name '*-Signed.apk' -print -quit)"; [[ -n "$apk" ]]
"$ANDROID_HOME/build-tools/36.0.0/apksigner" sign --ks "$signing/linko-dear-android-release.jks" --ks-key-alias linko-dear-parent --ks-pass "file:$signing/key-password"  --out "$ATLAS_BUILD_OUTPUT/Moment-Android-1.0.11-20.apk" "$apk"
apk="$ATLAS_BUILD_OUTPUT/Moment-Android-1.0.11-20.apk"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$apk" > "$ATLAS_BUILD_LOGS/signature.log"
rg -qi '4596cdb1ea8a5eea1a2567c6800d2bf4f90f051198a5518beb13abb7ac359c83' "$ATLAS_BUILD_LOGS/signature.log"
rg -q 'Verified using v2 scheme.*true' "$ATLAS_BUILD_LOGS/signature.log"
"$ANDROID_HOME/build-tools/36.0.0/aapt2" dump badging "$apk" > "$ATLAS_BUILD_LOGS/manifest.log"
python3 - "$ATLAS_BUILD_OUTPUT" "$ATLAS_BUILD_LOGS" "$commit" <<'PY'
from pathlib import Path
import sys,json,hashlib
out,logs=map(Path,sys.argv[1:3]);m=(logs/'manifest.log').read_text();assert "name='net.impx.happylife'" in m and "versionName='1.0.11'" in m and "versionCode='20'" in m
apk=out/'Moment-Android-1.0.11-20.apk';receipt={'sourceCommit':sys.argv[3],'version':'1.0.11','buildNumber':'20','sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'signatureVerified':True};(out/'build-receipt.json').write_text(json.dumps(receipt))
(out/'bundle.json').write_text(json.dumps({'version':'1.0.11','activate':False,'sourceCommit':sys.argv[3],'releaseNotes':'新增栏目启用设置，默认隐藏带娃，我的固定启用。','artifacts':[{'path':apk.name,'platform':'android','architecture':'arm64'},{'path':'build-receipt.json','platform':'release-metadata','architecture':'arm64'}]},ensure_ascii=False))
PY
