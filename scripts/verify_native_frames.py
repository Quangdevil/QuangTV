"""Check actual moving HLS test-pattern pixels for each native engine.

VLC may report Size.zero for adaptive HLS despite rendering decoded frames.
Pair native playback progress assertions with host screenshots of actual output.
"""
import re
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

root = Path('playback-evidence')
output = (root / 'test-result.txt').read_text()
windows = re.findall(r'QUANGTV_VISUAL engine=(Media3|VLC) startMs=(\d+) endMs=(\d+)', output)
assert len(windows) == 2, 'Missing native playback evidence windows'
for engine, start, end in windows:
    frames = []
    for path in sorted(root.glob('frame-*.png')):
        timestamp = int(path.stem.split('-')[1]) * 1000
        if not int(start) <= timestamp <= int(end):
            continue
        with Image.open(path) as image:
            w, h = image.size
            frame = image.convert('RGB').crop((int(w * .2), int(h * .4), int(w * .8), int(h * .6))).resize((160, 100))
        pixels = list(frame.getdata())
        chroma = sum(max(p) > 150 and max(p) - min(p) > 80 for p in pixels) / len(pixels)
        if chroma > .4:
            frames.append((path, frame))
    assert len(frames) >= 2, f'{engine}: need two screenshots containing the decoded color-pattern video'
    first = frames[0][1]
    motion = max(sum(ImageStat.Stat(ImageChops.difference(first, frame)).mean) / 3 for _, frame in frames[1:])
    assert motion > 1.0, f'{engine}: displayed video frames did not change'
    print(f'QUANGTV_RENDER_PASS engine={engine} frames={len(frames)} meanPixelChange={motion:.2f}')
    frames[-1][0].replace(root / f'{engine}-verified.png')
