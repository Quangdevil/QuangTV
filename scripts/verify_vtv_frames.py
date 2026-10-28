"""Verify visible moving live-channel video independently of sliding HLS clocks."""
import re
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

root = Path('playback-evidence')
output = (root / 'vtv-live-result.txt').read_text()
windows = re.findall(r'QUANGTV_VTV_VISUAL channel=(VTV1|VTV3) startMs=(\d+) endMs=(\d+)', output)
assert {w[0] for w in windows} == {'VTV1', 'VTV3'}, 'Both real VTV channels must play'
for name, start, end in windows:
    frames = []
    for path in sorted(root.glob('vtv-frame-*.png')):
        timestamp = int(path.stem.split('-')[-1]) * 1000
        if not int(start) <= timestamp <= int(end):
            continue
        with Image.open(path) as image:
            width, height = image.size
            crop = image.convert('RGB').crop((int(width * .2), int(height * .4), int(width * .8), int(height * .6))).resize((160, 100))
        visible = sum(max(pixel) > 35 for pixel in crop.getdata()) / 16000
        if visible > .2:
            frames.append((path, crop))
    assert len(frames) >= 2, f'{name}: missing real nonblack video screenshots'
    motion = max(sum(ImageStat.Stat(ImageChops.difference(frames[0][1], frame)).mean) / 3 for _, frame in frames[1:])
    assert motion > .5, f'{name}: no changing decoded video pixels'
    frames[-1][0].replace(root / f'{name}-live-verified.png')
    print(f'QUANGTV_VTV_RENDER_PASS channel={name} frames={len(frames)} meanPixelChange={motion:.2f}')
