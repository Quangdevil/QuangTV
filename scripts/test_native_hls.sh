#!/usr/bin/env bash
set -euo pipefail
repo_root="$(pwd)"
mkdir -p "$repo_root/playback-evidence"
adb logcat -c
adb logcat -v threadtime > "$repo_root/playback-evidence/native-logcat.txt" &
log_pid=$!
(
  while true; do
    adb exec-out screencap -p > "$repo_root/playback-evidence/frame-$(date +%s).png" || true
    sleep 10
  done
) &
frame_pid=$!
trap 'kill "$log_pid" "$frame_pid" 2>/dev/null || true' EXIT
cd upstream/flutter_app
flutter test integration_test/native_hls_test.dart -d emulator-5554 --dart-define=HLS_TEST_URL=http://10.0.2.2:8765/index.m3u8 2>&1 | tee "$repo_root/playback-evidence/test-result.txt"
