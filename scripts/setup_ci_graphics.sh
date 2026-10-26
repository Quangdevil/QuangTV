#!/usr/bin/env bash
# Provide Mesa's real GLX display for the CI-only -gpu host backend.
set -euo pipefail
mkdir -p playback-evidence
command -v Xvfb
nohup Xvfb "$DISPLAY" -screen 0 1280x1024x24 -nolisten tcp > playback-evidence/xvfb.txt 2>&1 &
pid=$!
sleep 2
kill -0 "$pid"
echo "QUANGTV_CI_GRAPHICS display=$DISPLAY software=$LIBGL_ALWAYS_SOFTWARE driver=$GALLIUM_DRIVER"
