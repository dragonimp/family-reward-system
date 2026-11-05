#!/usr/bin/env bash
set -euo pipefail
: "${ATLAS_BUILD_WORK:?Run using host-build-queue and host-build-output}"
: "${ATLAS_BUILD_OUTPUT:?}"
: "${ATLAS_BUILD_LOGS:?}"
root="$(git rev-parse --show-toplevel)"
commit="$(git -C "$root" rev-parse HEAD)"
export MOMENT_RELEASE_COMMIT="$commit"
checks="$ATLAS_BUILD_WORK/dining-checks"
mkdir -p "$checks/source"
git -C "$root" archive "$commit" | tar -x -C "$checks/source"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$checks/source"
dotnet run --project tests/Dining/Dining.csproj --artifacts-path "$checks/server-tests" > "$ATLAS_BUILD_LOGS/dining-tests.log" 2>&1 || { tail -40 "$ATLAS_BUILD_LOGS/dining-tests.log"; exit 1; }
cat "$ATLAS_BUILD_LOGS/dining-tests.log"
dotnet build parent-app/android/LinkoFamily.csproj -f net10.0-android -c Debug \
  --artifacts-path "$checks/android" \
  -p:AgentIdentityNativeClientProject=/Users/wengzhishan/Projects/AgentIdentity/src/AgentIdentity.NativeClient/AgentIdentity.NativeClient.csproj \
  -p:AtlasSdkRoot=/Users/wengzhishan/Projects/Atlas \
  -p:AndroidSdkDirectory=/opt/homebrew/share/android-commandlinetools \
  -p:JavaSdkDirectory=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  -m:2 -v:minimal > "$ATLAS_BUILD_LOGS/android.log" 2>&1 || { tail -45 "$ATLAS_BUILD_LOGS/android.log"; exit 1; }
tail -7 "$ATLAS_BUILD_LOGS/android.log"
xcrun swiftc -parse-as-library parent-app/ios/Tests/DiningMapSearchCheck.swift -o "$checks/live-map-check"
"$checks/live-map-check"
cd "$root"
bash "$checks/source/scripts/build-moment-ios.sh"
printf 'Dining HTTP/model tests, live Apple Maps, Android compile and signed iOS verification passed\n' > "$ATLAS_BUILD_OUTPUT/dining-validation.txt"
