#!/usr/bin/env bash
set -euo pipefail

: "${ATLAS_BUILD_WORK:?run through host-build-output}"
: "${ATLAS_BUILD_OUTPUT:?run through host-build-output}"
: "${ANDROID_HOME:?Android SDK directory required}"
: "${JAVA_HOME:?JDK directory required}"
: "${ANDROID_SIGNING_KEYSTORE:?release keystore path required}"
: "${ANDROID_SIGNING_PASSWORD_FILE:?release keystore password file required}"
: "${ANDROID_SIGNING_KEY_ALIAS:?release key alias required}"
: "${AGENT_IDENTITY_NATIVE_CLIENT_PROJECT:?AgentIdentity NativeClient project path required}"

root="$(git rev-parse --show-toplevel)"
commit="$(git -C "$root" rev-parse HEAD)"
remote="$(git -C "$root" ls-remote origin refs/heads/main | cut -f1)"
if [[ "$commit" != "$remote" ]]; then
  echo 'The release commit is not the current origin/main commit.' >&2
  exit 1
fi

source_dir="$ATLAS_BUILD_WORK/source"
mkdir -p "$source_dir" "$ATLAS_BUILD_OUTPUT"
git -C "$root" archive "$commit" | tar -x -C "$source_dir"

dotnet publish "$source_dir/parent-app/android/LinkoFamily.csproj" \
  -f net10.0-android -c Release \
  -p:JavaSdkDirectory="$JAVA_HOME" \
  -p:AgentIdentityNativeClientProject="$AGENT_IDENTITY_NATIVE_CLIENT_PROJECT" \
  -p:AndroidKeyStore=true \
  -p:AndroidSigningKeyStore="$ANDROID_SIGNING_KEYSTORE" \
  -p:AndroidSigningKeyAlias="$ANDROID_SIGNING_KEY_ALIAS" \
  -p:AndroidSigningKeyPass="file:$ANDROID_SIGNING_PASSWORD_FILE" \
  -p:AndroidSigningStorePass="file:$ANDROID_SIGNING_PASSWORD_FILE" \
  -p:AndroidPackageFormats=aab%3Bapk \
  -p:PublishDir="$ATLAS_BUILD_WORK/publish/" \
  -v:minimal

find "$ATLAS_BUILD_WORK/publish" -maxdepth 1 -type f \( -name '*-Signed.aab' -o -name '*-Signed.apk' \) \
  -exec cp {} "$ATLAS_BUILD_OUTPUT/" \;
if ! find "$ATLAS_BUILD_OUTPUT" -maxdepth 1 -type f -name '*-Signed.aab' | grep -q .; then
  echo 'Signed AAB was not produced.' >&2
  exit 1
fi
if ! find "$ATLAS_BUILD_OUTPUT" -maxdepth 1 -type f -name '*-Signed.apk' | grep -q .; then
  echo 'Signed APK was not produced.' >&2
  exit 1
fi
printf '%s\n' "$commit" > "$ATLAS_BUILD_OUTPUT/source-commit.txt"
shasum -a 256 "$ATLAS_BUILD_OUTPUT"/*-Signed.aab "$ATLAS_BUILD_OUTPUT"/*-Signed.apk > "$ATLAS_BUILD_OUTPUT/sha256.txt"
