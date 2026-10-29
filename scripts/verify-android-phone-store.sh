#!/usr/bin/env bash
set -euo pipefail

: "${ATLAS_BUILD_OUTPUT:?run through host-build-output}"
: "${ANDROID_HOME:?Android SDK directory required}"
: "${ANDROID_EMULATOR:?Android emulator executable required}"
: "${SIGNED_APK:?signed APK path required}"

adb="$ANDROID_HOME/platform-tools/adb"
if [[ -n "$("$adb" devices | sed -n '2,$p' | tr -d '[:space:]')" ]]; then
  echo 'An Android device is already in use.' >&2
  exit 2
fi

"$ANDROID_EMULATOR" -avd HappyLifeAndroid35Phone -no-window -no-audio -no-snapshot-load -port 5592 \
  > "$ATLAS_BUILD_LOGS/emulator.log" 2>&1 &
emulator_pid=$!
cleanup() {
  "$adb" -s emulator-5592 emu kill >/dev/null 2>&1 || true
  wait "$emulator_pid" 2>/dev/null || true
}
trap cleanup EXIT

"$adb" -s emulator-5592 wait-for-device
for _ in $(seq 1 120); do
  [[ "$("$adb" -s emulator-5592 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
  sleep 1
done
[[ "$("$adb" -s emulator-5592 shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]
"$adb" -s emulator-5592 install -r "$SIGNED_APK"
"$adb" -s emulator-5592 shell monkey -p net.impx.happylife 1
sleep 5
"$adb" -s emulator-5592 shell dumpsys activity activities > "$ATLAS_BUILD_LOGS/activity.txt"
rg -q 'net\.impx\.happylife' "$ATLAS_BUILD_LOGS/activity.txt"
"$adb" -s emulator-5592 exec-out screencap -p > "$ATLAS_BUILD_OUTPUT/android-login.png"
printf 'installed_and_launched=net.impx.happylife\n' > "$ATLAS_BUILD_OUTPUT/verification.txt"
