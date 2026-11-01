#!/usr/bin/env bash
set +e
bash scripts/test_auto_emulator.sh
media_status=$?
python3 scripts/auto_dhu_preflight.py
dhu_status=$?
if (( dhu_status != 0 )); then echo "DHU preflight script failed: $dhu_status"; fi
exit "$media_status"
