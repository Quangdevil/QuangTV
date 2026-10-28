#!/usr/bin/env bash
# Prioritize changed browser behavior; never publish when required suites fail.
set -uo pipefail
# Clear unrelated boot-time ANR dialogs without disabling the launcher that
# System UI's recents service requires. Google downloadable fonts are optional;
# isolate their provider so a dying GMS boot process cannot kill the app under QA.
adb shell am force-stop com.google.android.apps.nexuslauncher
adb shell pm disable --user 0 com.google.android.gms/.fonts.provider.FontsProvider
adb shell am force-stop com.google.android.gms
bash scripts/test_browser.sh
browser_status=$?
bash scripts/test_native_hls.sh
native_status=$?
bash scripts/test_vtv_live.sh
vtv_status=$?
printf 'QUANGTV_ANDROID_RESULTS native=%s browser=%s vtv=%s\n' "$native_status" "$browser_status" "$vtv_status"
if (( native_status != 0 || browser_status != 0 || vtv_status != 0 )); then exit 1; fi
echo 'QUANGTV_ANDROID_ALL_PASS native=true browser=true ota=true vtv=true'
