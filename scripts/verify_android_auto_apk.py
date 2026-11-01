"""Check packaged manifest and R8 output; this does not test an AA host."""
import os
from pathlib import Path
import re
import subprocess
import sys
from zipfile import ZipFile
from verify_vlc_dex import class_definitions

apk = Path(sys.argv[1])
sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
tools = sorted((sdk / 'build-tools').glob('*'), key=lambda p: [int(n) for n in re.findall(r'\d+', p.name)])[-1]
subprocess.run([str(tools / 'apksigner'), 'verify', str(apk)], check=True)
badging = subprocess.check_output([str(tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
assert "package: name='com.quangduren.quangtv.autopreview2'" in badging, badging
manifest = subprocess.check_output([str(tools / 'aapt'), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'], text=True)
assert 'app.tvviewer.player.QuangAutoService' in manifest
assert 'com.google.android.gms.car.category.CATEGORY_PROJECTION' in manifest
assert 'com.google.android.gms.car.category.CATEGORY_PROJECTION_OEM' in manifest
with ZipFile(apk) as archive:
    defined = set()
    for name in archive.namelist():
        if re.fullmatch(r'classes\d*\.dex', name):
            defined.update(class_definitions(archive.read(name)))
    required = {
        'Lapp/tvviewer/player/QuangAutoDiagnosticsActivity;',
        'Lapp/tvviewer/player/QuangAutoService;',
        'Lapp/tvviewer/player/QuangAutoActivity;',
        'Lcom/google/android/apps/auto/sdk/CarActivity;',
        'Lcom/google/android/apps/auto/sdk/CarActivityService;',
    }
    assert required <= defined, required - defined
print(f'QUANGTV_AUTO_APK_PASS package=autopreview signed=true projectionClasses=true bytes={apk.stat().st_size}')
