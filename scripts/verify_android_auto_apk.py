"""Check packaged manifest and R8 output; this does not test an AA host."""
import os
import hashlib
from pathlib import Path
import re
import subprocess
import sys
from zipfile import ZipFile
from verify_vlc_dex import class_definitions
from verify_signer_certificate import verify as verify_signer

apk = Path(sys.argv[1])
sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
tools = sorted((sdk / 'build-tools').glob('*'), key=lambda p: [int(n) for n in re.findall(r'\d+', p.name)])[-1]
signature = subprocess.check_output([str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
certificate = subprocess.check_output(['keytool', '-exportcert', '-keystore', 'vendor/android-auto/preview-only.jks', '-storepass', 'android', '-alias', 'androiddebugkey'])
verify_signer(signature, hashlib.sha256(certificate).hexdigest())
badging = subprocess.check_output([str(tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
assert "package: name='com.quangduren.quangtv.autopreview2'" in badging, badging
manifest = subprocess.check_output([str(tools / 'aapt'), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'], text=True)
services = re.split(r'(?=^\s*E: service\b)', manifest, flags=re.MULTILINE)
for name in ('app.tvviewer.player.QuangAutoService', 'com.ryanheise.audioservice.AudioService'):
    block = next((part for part in services[1:] if f'"{name}"' in part), '')
    # Only examine attributes of the service, before any child or next element.
    attributes = block.split('\n')
    attributes = '\n'.join(attributes[:next((i for i, line in enumerate(attributes[1:], 1) if 'E: ' in line), len(attributes))])
    assert re.search(r'android:exported.*(?:0xffffffff|true)', attributes), f'{name} must be exported'
assert 'android.intent.category.CAR_LAUNCHER' in manifest
assert 'org.mozilla.gecko.process.GeckoChildProcessServices' in manifest
assert 'android.media.browse.MediaBrowserService' in manifest
assert 'com.google.android.gms.car.category.CATEGORY_PROJECTION' in manifest
assert 'com.google.android.gms.car.category.CATEGORY_PROJECTION_OEM' in manifest
# Check the descriptor shipped in the APK, not merely Java/manifest classes.
resources = subprocess.check_output([str(tools / 'aapt'), 'dump', '--values', 'resources', str(apk)], text=True)
match = re.search(r'(?ms)^\s*resource 0x[0-9a-f]+ [^\n]*:xml/quangtv_automotive_app:.*?\(string8\) "([^"\n]+)"', resources)
if match:
    descriptor_path = match.group(1)
else:
    descriptor_path = 'res/xml/quangtv_automotive_app.xml'
descriptor = subprocess.check_output([str(tools / 'aapt'), 'dump', 'xmltree', str(apk), descriptor_path], text=True)
assert re.search(r'name="projection"|name[^\n]*"projection"', descriptor), 'Projection capability missing from packaged automotive descriptor'
assert re.search(r'name="media"|name[^\n]*"media"', descriptor), 'Media capability missing from packaged automotive descriptor'
with ZipFile(apk) as archive:
    defined = set()
    for name in archive.namelist():
        if re.fullmatch(r'classes\d*\.dex', name):
            defined.update(class_definitions(archive.read(name)))
    required = {
        'Lapp/tvviewer/player/QuangAutoDiagnosticsActivity;',
        'Lapp/tvviewer/player/QuangGeckoActivity;',
        'Lapp/tvviewer/player/QuangGeckoBrowser;',
        'Lapp/tvviewer/player/QuangAutoService;',
        'Lapp/tvviewer/player/QuangAutoActivity;',
        'Lcom/google/android/apps/auto/sdk/CarActivity;',
        'Lcom/google/android/apps/auto/sdk/CarActivityService;',
    }
    assert required <= defined, required - defined
print(f'QUANGTV_AUTO_APK_PASS package=autopreview2 stableSigner=true exportedMedia=true projectionClasses=true bytes={apk.stat().st_size}')
