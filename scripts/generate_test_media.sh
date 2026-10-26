#!/usr/bin/env bash
set -euo pipefail
mkdir -p /tmp/quangtv-hls playback-evidence
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=640x360:rate=24 -f lavfi -i sine=frequency=440 -t 60 -c:v libx264 -preset ultrafast -threads 2 -pix_fmt yuv420p -g 48 -c:a aac -f hls -hls_time 2 -hls_list_size 0 /tmp/quangtv-hls/index.m3u8
# Exercise the exact HLS demux/remux operation that crashed build 163.
ffmpeg -hide_banner -loglevel error -y -i /tmp/quangtv-hls/index.m3u8 -c copy /tmp/quangtv-hls/fixture.mp4
ffmpeg -hide_banner -loglevel error -y -i /tmp/quangtv-hls/fixture.mp4 -c:v copy -an -movflags +faststart /tmp/quangtv-hls/video-only.mp4
ffmpeg -hide_banner -loglevel error -y -i /tmp/quangtv-hls/fixture.mp4 -c:a copy -vn -movflags +faststart /tmp/quangtv-hls/audio-only.m4a
# Require real decodable HLS frames and both mux tracks, not only file existence.
ffmpeg -hide_banner -loglevel error -xerror -i /tmp/quangtv-hls/index.m3u8 -t 3 -f null -
ffprobe -v error -show_streams -show_format -of json /tmp/quangtv-hls/fixture.mp4 > playback-evidence/fixture-probe.json
python3 - <<'VERIFY'
import json
from pathlib import Path
probe=json.loads(Path('playback-evidence/fixture-probe.json').read_text())
assert {s['codec_name'] for s in probe['streams']} == {'h264', 'aac'}
assert float(probe['format']['duration']) >= 59
assert len(list(Path('/tmp/quangtv-hls').glob('*.ts'))) >= 20
print('QUANGTV_FIXTURE_PASS hlsDecoded=true avcAac=true durationSeconds=60')
VERIFY
cat > /tmp/quangtv-hls/browser.html <<'HTML'
<meta name="viewport" content="width=device-width"><h1>Browser fixture</h1><img hidden src="https://doubleclick.net/quangtv-fixture.png"><video controls preload="none" src="fixture.mp4"></video><script>fetch("fixture.mp4?resource=1").then(r=>r.arrayBuffer())</script>
HTML
