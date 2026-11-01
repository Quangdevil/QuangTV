"""Restore the test's task through Android shell, as a real Recents selection.

The app cannot grant itself permission to pop a background activity on Android.
This driver does not start, finish, cancel, or fake any download.
"""
import os
import pathlib
import subprocess
import time

path = pathlib.Path(os.environ['QUANGTV_EVIDENCE']) / 'browser-logcat.txt'
path.touch(exist_ok=True)
with path.open(errors='replace') as log:
    while True:
        line = log.readline()
        if not line:
            time.sleep(.1)
            continue
        if 'QUANGTV_MAY_HOME_READY' in line:
            with (path.parent / 'may-home-native.png').open('wb') as image:
                subprocess.run(['adb', 'exec-out', 'screencap', '-p'], stdout=image, check=True)
        if 'QuangDownloadTest' in line and 'QUANGTV_DOWNLOADS_RESTORE_REQUEST' in line:
            subprocess.run(['adb','shell','am','force-stop','com.google.android.apps.nexuslauncher'],check=True)
            subprocess.run(['adb', 'shell', 'am', 'start', '-n',
                'com.quangduren.quangtv.debug/app.tvviewer.player.MainActivity',
                '-f', '0x20020000'], check=True, stdout=subprocess.DEVNULL)
