#!/usr/bin/env bash
set -euo pipefail
repo_root="$(pwd)"
mkdir -p "$repo_root/playback-evidence"
adb shell settings put secure immersive_mode_confirmations confirmed
adb logcat -c
adb shell dumpsys webviewupdate > "$repo_root/playback-evidence/webview-runtime.txt"
adb logcat -v threadtime > "$repo_root/playback-evidence/native-logcat.txt" &
log_pid=$!
(
  while true; do
    adb exec-out screencap -p > "$repo_root/playback-evidence/frame-$(date +%s).png" || true
    sleep 5
  done
) &
frame_pid=$!
# A real Android touch starts the original QuangTube player; do not inject play().
python3 scripts/tap_youtube_test.py &
tap_pid=$!
trap 'kill "$log_pid" "$frame_pid" "$tap_pid" 2>/dev/null || true' EXIT
cd upstream/flutter_app
set +e
flutter test integration_test/native_hls_test.dart -d emulator-5554 --dart-define=HLS_TEST_URL=http://10.0.2.2:8765/index.m3u8 2>&1 | tee "$repo_root/playback-evidence/test-result.txt"
hls_status=${PIPESTATUS[0]}

cd "$repo_root/upstream/flutter_app"
flutter test integration_test/ota_update_test.dart -d emulator-5554 2>&1 | tee "$repo_root/playback-evidence/ota-test-result.txt"
ota_status=${PIPESTATUS[0]}

cd "$repo_root"
/usr/bin/python3 scripts/verify_native_frames.py

visual_status=$?
if (( hls_status != 0 || ota_status != 0 || visual_status != 0 )); then
  exit 1
fi
