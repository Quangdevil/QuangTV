"""Check the same latest-release metadata endpoint consumed by the app."""
import hashlib, json, sys, time, urllib.request
from pathlib import Path

tag, filename = sys.argv[1:]
apk = Path(filename)
expected = 'sha256:' + hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest()
for attempt in range(12):
    request = urllib.request.Request('https://api.github.com/repos/Quangdevil/QuangTV/releases/latest', headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'QuangTV-OTA-verifier'})
    with urllib.request.urlopen(request, timeout=20) as response:
        release = json.load(response)
    if release['tag_name'] == tag:
        break
    time.sleep(5)
assert release['tag_name'] == tag, 'OTA latest release still points to another build'
assert not release['draft'] and not release['prerelease']
asset = next(a for a in release['assets'] if a['name'] == filename)
assert asset['size'] == apk.stat().st_size
assert asset['digest'] == expected
assert asset['browser_download_url'] == f'https://github.com/Quangdevil/QuangTV/releases/download/{tag}/{filename}'
print(f'QUANGTV_OTA_RELEASE_PASS tag={tag} bytes={asset["size"]} digest={expected}')
