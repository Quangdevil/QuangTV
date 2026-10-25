"""Reject extra native ABIs and accidental APK growth before publication."""
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

apk = Path(sys.argv[1])
with ZipFile(apk) as archive:
    libraries = [entry for entry in archive.infolist() if entry.filename.startswith('lib/') and entry.filename.endswith('.so')]
    abis = {entry.filename.split('/')[1] for entry in libraries}
    if abis != {'arm64-v8a'}:
        raise SystemExit(f'Unexpected release ABIs: {sorted(abis)}')
    if any(entry.compress_type != ZIP_DEFLATED for entry in libraries):
        raise SystemExit('Release native libraries must be compressed')
    if apk.stat().st_size > 45_000_000:
        raise SystemExit(f'APK size exceeds 45 MB: {apk.stat().st_size} bytes')
    print(f'QUANGTV_APK_SIZE_PASS bytes={apk.stat().st_size} abis=arm64-v8a compressed=true')
    for entry in sorted(libraries, key=lambda item: item.compress_size, reverse=True)[:4]:
        print(f'{entry.filename}: {entry.compress_size} bytes in APK')
