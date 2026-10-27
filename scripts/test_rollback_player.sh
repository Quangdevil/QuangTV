#!/usr/bin/env bash
set -uo pipefail
repo_root="$(pwd)"
mkdir -p "$repo_root/playback-evidence"
adb shell settings put secure immersive_mode_confirmations confirmed
adb logcat -c
adb logcat -v threadtime > "$repo_root/playback-evidence/native-logcat.txt" &
log_pid=$!
(
  while true; do
    adb exec-out screencap -p > "$repo_root/playback-evidence/frame-$(date +%s).png" || true
    sleep 5
  done
) &
frame_pid=$!
python3 scripts/tap_youtube_test.py &
tap_pid=$!
trap 'kill "$log_pid" "$frame_pid" "$tap_pid" 2>/dev/null || true' EXIT
cd upstream/flutter_app
flutter test integration_test/native_hls_test.dart -d emulator-5554 --dart-define=HLS_TEST_URL=http://10.0.2.2:8765/index.m3u8 2>&1 | tee "$repo_root/playback-evidence/test-result.txt"
hls_status=${PIPESTATUS[0]}
flutter test integration_test/ota_update_test.dart -d emulator-5554 --plain-name 'Native OTA reports bytes and survives outside tap and screen reopen without duplicate download' 2>&1 | tee "$repo_root/playback-evidence/ota-test-result.txt"
ota_status=${PIPESTATUS[0]}
flutter test integration_test/ota_update_test.dart -d emulator-5554 --plain-name 'YouTube action opens integrated QuangTube and plays public video' 2>&1 | tee "$repo_root/playback-evidence/youtube-test-result.txt"
youtube_status=${PIPESTATUS[0]}
printf '%s\n' "$youtube_status" > "$repo_root/playback-evidence/youtube-exit.txt"
cd "$repo_root"
/usr/bin/python3 scripts/verify_native_frames.py 2>&1 | tee playback-evidence/visual-result.txt
visual_status=${PIPESTATUS[0]}
echo "QUANGTV_ROLLBACK_TEST_RESULTS hls=$hls_status ota=$ota_status visual=$visual_status youtube_deferred=$youtube_status"
if (( hls_status != 0 || ota_status != 0 || visual_status != 0 )); then exit 1; fi
grep -q QUANGTV_OTA_PASS playback-evidence/ota-test-result.txt || exit 1
if (( youtube_status != 0 )); then echo '::warning::YouTube test failed; the user deferred its repair.'; fi
