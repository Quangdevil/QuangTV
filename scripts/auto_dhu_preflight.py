"""Attempt Google's actual DHU; record blockers rather than call IPC tests AA UI."""
import os
from pathlib import Path
import re
import subprocess as S
import time
import xml.etree.ElementTree as E

out = Path('auto-evidence').resolve()
out.mkdir(exist_ok=True)
def adb(*args):
    r = S.run(['adb', *args], capture_output=True, text=True, timeout=35)
    return r.stdout + r.stderr

def snapshot(name):
    r = S.run(['adb', 'exec-out', 'screencap', '-p'], capture_output=True, timeout=20)
    (out / (name + '.png')).write_bytes(r.stdout)
    adb('shell', 'uiautomator', 'dump', '/sdcard/auto-ui.xml')
    xml = adb('exec-out', 'cat', '/sdcard/auto-ui.xml')
    (out / (name + '.xml')).write_text(xml)
    try: return list(E.fromstring(xml).iter('node'))
    except E.ParseError: return []

def tap(node):
    v = [int(n) for n in re.findall(r'\d+', node.get('bounds',''))]
    if len(v) == 4:
        adb('shell', 'input', 'tap', str((v[0]+v[2])//2), str((v[1]+v[3])//2))

def result(text):
    (out / 'dhu-result.txt').write_text(text+'\n')
    print(text)

pkg='com.google.android.projection.gearhead'
path=adb('shell','pm','path',pkg)
(out/'android-auto-package.txt').write_text(path + '\n' + adb('shell','dumpsys','package',pkg))
if 'package:' not in path:
    result('DHU_BLOCKED: official emulator system image has no Android Auto host installed. Media IPC results are separate.')
    raise SystemExit(0)
if 'AndroidAutoStubPrebuilt' in path:
    result('DHU_BLOCKED: emulator contains AndroidAutoStubPrebuilt only, not the full Google Android Auto projection host. Full Android Auto setup is required; media IPC tests passed separately.')
    raise SystemExit(0)
activity=adb('shell','am','start','-W','-a','android.settings.ANDROID_AUTO_SETTINGS')
if 'Error' in activity:
    activity += adb('shell','am','start','-W','-n',pkg+'/.companion.settings.DefaultSettingsActivity')
(out/'android-auto-start.txt').write_text(activity)
time.sleep(4)
nodes=snapshot('android-auto-initial')
# Only enable documented local developer settings if a real settings screen exists.
version=None
for _ in range(5):
    version=next((n for n in nodes if (n.get('text') or '').lower().startswith('version')), None)
    if version: break
    adb('shell','input','swipe','500','1600','500','450','400')
    time.sleep(.5)
    nodes=snapshot('android-auto-settings')
if version:
    for _ in range(11): tap(version)
    time.sleep(1)
    nodes=snapshot('android-auto-developer-dialog')
    ok=next((n for n in nodes if n.get('text','').lower() in ('ok','allow')),None)
    if ok: tap(ok)
    time.sleep(1)
    nodes=snapshot('android-auto-developer')
    menu=next((n for n in nodes if 'More options' in n.get('content-desc','')),None)
    if menu:
        tap(menu);time.sleep(1);nodes=snapshot('android-auto-menu')
        start=next((n for n in nodes if 'start head unit server' in n.get('text','').lower()),None)
        if start: tap(start);time.sleep(2)
adb('forward','tcp:5277','tcp:5277')
sdk=Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
dhu=sdk/'extras/google/auto/desktop-head-unit'
if not dhu.exists():
    result('DHU_BLOCKED: Desktop Head Unit package was not available from SDK Manager; see SDK install log.')
    raise SystemExit(0)
dhu.chmod(0o755)
log=out/'dhu-log.txt'
try:
    with log.open('w') as handle:
        process=S.Popen([str(dhu),'--headless','--adb=5277'],cwd=dhu.parent,stdin=S.PIPE,stdout=handle,stderr=S.STDOUT,text=True)
        time.sleep(12)
        if process.poll() is None:
            process.stdin.write('screenshot '+str(out/'dhu-screen.png')+'\n');process.stdin.flush()
            time.sleep(3)
            process.stdin.write('quit\n');process.stdin.flush()
            try: process.wait(timeout=8)
            except S.TimeoutExpired: process.terminate()
    if (out/'dhu-screen.png').exists():
        result('DHU_FRAME_CAPTURED: inspect screenshot and log; projection app launch has not been asserted.')
    else:
        result('DHU_BLOCKED: no Android Auto projected frame. Official image host setup / Google Play may be required; see captured settings and DHU logs.')
except (OSError, S.SubprocessError) as e:
    result('DHU_BLOCKED: '+str(e))
