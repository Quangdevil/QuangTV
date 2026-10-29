#!/usr/bin/env bash
# Prioritize changed browser behavior; never publish when required suites fail.
set -euo pipefail
# Clear unrelated boot-time ANR dialogs without disabling the launcher that
# System UI's recents service requires. Google downloadable fonts are optional;
# isolate their provider so a dying GMS boot process cannot kill the app under QA.
adb root
adb wait-for-device
test "$(adb shell id -u | tr -d '\r')" = 0
adb shell am force-stop com.google.android.apps.nexuslauncher
adb shell pm disable --user 0 com.google.android.gms/.fonts.provider.FontsProvider
adb shell am force-stop com.google.android.gms
set +e
bash scripts/test_browser.sh
browser_status=$?
exit "$browser_status"
