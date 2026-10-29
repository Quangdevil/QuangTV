#!/usr/bin/env bash
# Prioritize changed browser behavior; never publish when required suites fail.
set -euo pipefail
# Clear unrelated boot-time ANR dialogs without disabling the launcher that
# System UI's recents service requires. Google downloadable fonts are optional;
# isolate their provider so a dying GMS boot process cannot kill the app under QA.
adb root
adb wait-for-device
test "$(adb shell id -u | tr -d '\r')" = 0
android_boot_command() {
  for attempt in {1..15}; do
    if adb shell "$@"; then return 0; fi
    sleep 2
  done
  return 1
}
android_boot_command am force-stop com.google.android.apps.nexuslauncher
android_boot_command pm disable --user 0 com.google.android.gms/.fonts.provider.FontsProvider
android_boot_command am force-stop com.google.android.gms
set +e
bash scripts/test_browser.sh
browser_status=$?
bash scripts/test_native_hls.sh
native_status=$?
bash scripts/test_vtv_live.sh
vtv_status=$?
printf 'QUANGTV_ANDROID_RESULTS native=%s browser=%s vtv=%s\n' "$native_status" "$browser_status" "$vtv_status"
if (( native_status != 0 || browser_status != 0 || vtv_status != 0 )); then exit 1; fi
echo 'QUANGTV_ANDROID_ALL_PASS native=true browser=true ota=true vtv=true'
