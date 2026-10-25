"""Tap the video once when the integration test requests a user gesture."""
import re
import subprocess

log = subprocess.Popen(['adb', 'logcat', '-v', 'brief'], stdout=subprocess.PIPE, text=True)
try:
    for line in log.stdout:
        if 'QUANGTV_YOUTUBE_TAP' not in line:
            continue
        size = subprocess.check_output(['adb', 'shell', 'wm', 'size'], text=True)
        width, height = map(int, re.findall(r'(\d+)x(\d+)', size)[-1])
        subprocess.run(['adb', 'shell', 'input', 'tap', str(width // 2), str(height // 4)], check=True)
        break
finally:
    log.terminate()
