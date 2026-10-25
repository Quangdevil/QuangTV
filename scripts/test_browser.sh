#!/usr/bin/env bash
set -euo pipefail
repo_root="$(pwd)"
mkdir -p "$repo_root/playback-evidence"
adb shell settings put secure immersive_mode_confirmations confirmed
adb logcat -c
adb logcat -v threadtime > "$repo_root/playback-evidence/browser-logcat.txt" &
log_pid=$!
(
  while true; do
    adb exec-out screencap -p > "$repo_root/playback-evidence/browser-$(date +%s).png" || true
    sleep 5
  done
) &
frame_pid=$!
trap 'kill "$log_pid" "$frame_pid" 2>/dev/null || true' EXIT
cd upstream/flutter_app
flutter test integration_test/browser_test.dart -d emulator-5554 2>&1 | tee "$repo_root/playback-evidence/browser-test-result.txt"

for marker in QUANGTV_PRIVATE_LAYOUT_PASS QUANGTV_BROWSER_PASS QUANGTV_BROWSER_PLAYER_PASS; do
  rg -q "$marker" "$repo_root/playback-evidence/browser-test-result.txt"
done
