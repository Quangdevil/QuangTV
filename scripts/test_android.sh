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
exit "$browser_status"
