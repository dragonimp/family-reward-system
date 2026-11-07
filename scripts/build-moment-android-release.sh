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
git -C "$identity" diff --quiet HEAD -- src/AgentIdentity.NativeClient src/AgentIdentity.Maui src/AgentIdentity.Sdk
git -C "$atlas" diff --quiet HEAD -- sdk
dotnet publish "$source/parent-app/android/LinkoFamily.csproj" -f net10.0-android -c Release -r android-arm64 \
 --artifacts-path "$ATLAS_BUILD_WORK/compiled" -m:1 -p:UseSharedCompilation=false \
 -p:AgentIdentityNativeClientProject="$identity/src/AgentIdentity.NativeClient/AgentIdentity.NativeClient.csproj" -p:AtlasSdkRoot="$atlas" \
 -p:AndroidSdkDirectory="$ANDROID_HOME" -p:JavaSdkDirectory="$JAVA_HOME" -p:AndroidPackageFormats=apk \
 -p:AndroidKeyStore=false \
 -o "$ATLAS_BUILD_WORK/publish" > "$ATLAS_BUILD_LOGS/android.log" 2>&1 || { tail -35 "$ATLAS_BUILD_LOGS/android.log"; exit 1; }
apk="$(find "$ATLAS_BUILD_WORK/publish" -name '*-Signed.apk' -print -quit)"; [[ -n "$apk" ]]
"$ANDROID_HOME/build-tools/36.0.0/apksigner" sign --ks "$signing/linko-dear-android-release.jks" --ks-key-alias linko-dear-parent --ks-pass "file:$signing/key-password"  --out "$ATLAS_BUILD_OUTPUT/Moment-Android-1.0.7-16.apk" "$apk"
apk="$ATLAS_BUILD_OUTPUT/Moment-Android-1.0.7-16.apk"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$apk" > "$ATLAS_BUILD_LOGS/signature.log"
rg -qi '4596cdb1ea8a5eea1a2567c6800d2bf4f90f051198a5518beb13abb7ac359c83' "$ATLAS_BUILD_LOGS/signature.log"
rg -q 'Verified using v2 scheme.*true' "$ATLAS_BUILD_LOGS/signature.log"
"$ANDROID_HOME/build-tools/36.0.0/aapt2" dump badging "$apk" > "$ATLAS_BUILD_LOGS/manifest.log"
python3 - "$ATLAS_BUILD_OUTPUT" "$ATLAS_BUILD_LOGS" "$commit" <<'PY'
from pathlib import Path
import sys,json,hashlib
out,logs=map(Path,sys.argv[1:3]);m=(logs/'manifest.log').read_text();assert "name='net.impx.happylife'" in m and "versionName='1.0.7'" in m and "versionCode='16'" in m
apk=out/'Moment-Android-1.0.7-16.apk';receipt={'sourceCommit':sys.argv[3],'version':'1.0.7','buildNumber':'16','sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'signatureVerified':True};(out/'build-receipt.json').write_text(json.dumps(receipt))
(out/'bundle.json').write_text(json.dumps({'version':'1.0.7','activate':False,'sourceCommit':sys.argv[3],'releaseNotes':'下厨房默认全不选、分类可再次点击取消，新增甜品分类，扩充服务端菜谱。','artifacts':[{'path':apk.name,'platform':'android','architecture':'arm64'},{'path':'build-receipt.json','platform':'release-metadata','architecture':'arm64'}]},ensure_ascii=False))
PY
