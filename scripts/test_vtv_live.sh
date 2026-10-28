#!/usr/bin/env bash
set -euo pipefail
repo_root="$(pwd)"
mkdir -p playback-evidence
adb logcat -c
adb logcat -v threadtime > playback-evidence/vtv-live-logcat.txt &
log_pid=$!
trap 'kill "$log_pid" 2>/dev/null || true' EXIT
cd upstream/flutter_app
flutter test integration_test/vtv_live_test.dart -d emulator-5554 2>&1 | tee "$repo_root/playback-evidence/vtv-live-result.txt"
grep -q 'QUANGTV_VTV_LIVE_PASS channel=VTV1' "$repo_root/playback-evidence/vtv-live-result.txt"
grep -q 'QUANGTV_VTV_LIVE_PASS channel=VTV3' "$repo_root/playback-evidence/vtv-live-result.txt"
