#!/usr/bin/env bash
# CI tooling only; no FFmpeg binary is packaged into the Android application.
set -euo pipefail
root="${RUNNER_TEMP:-/tmp}/quangtv-ffmpeg-8.1"
archive="$root/ffmpeg.tar.xz"
mkdir -p "$root/bin"
url="https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-10-26-14-25/ffmpeg-n8.1.3-24-g92611900bb-linux64-gpl-8.1.tar.xz"
sha=d113aa5b57ab0dcfee171d835240ce3ea5db826a0ee80ed7528c8d26a61e87a4
if ! test -f "$archive" || ! echo "$sha  $archive" | sha256sum --check --status; then
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 "$url" -o "$archive"
fi
echo "$sha  $archive" | sha256sum --check
tar --no-same-owner -xJf "$archive" --wildcards --strip-components=2 -C "$root/bin" '*/bin/ffmpeg' '*/bin/ffprobe'
export PATH="$root/bin:$PATH"
if test -n "${GITHUB_PATH:-}"; then echo "$root/bin" >> "$GITHUB_PATH"; fi
ffmpeg -version | head -n 1
ffprobe -version | head -n 1
