#!/usr/bin/env bash
set -euo pipefail
repo_root="$(pwd)"
mkdir -p playback-evidence
adb logcat -c
adb logcat -v threadtime > playback-evidence/vtv-live-logcat.txt &
log_pid=$!
(
  while true; do
    adb exec-out screencap -p > "playback-evidence/vtv-frame-$(date +%s).png" || true
    sleep 2
  done
) &
frame_pid=$!
trap 'kill "$log_pid" "$frame_pid" 2>/dev/null || true' EXIT
cd upstream/flutter_app
flutter test integration_test/vtv_live_test.dart -d emulator-5554 2>&1 | tee "$repo_root/playback-evidence/vtv-live-result.txt"
grep -q 'QUANGTV_VTV_LIVE_PASS channel=VTV1' "$repo_root/playback-evidence/vtv-live-result.txt"
grep -q 'QUANGTV_VTV_LIVE_PASS channel=VTV3' "$repo_root/playback-evidence/vtv-live-result.txt"

cd "$repo_root"
python3 scripts/verify_vtv_frames.py | tee playback-evidence/vtv-live-visual.txt
