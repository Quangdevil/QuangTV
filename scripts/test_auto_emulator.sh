#!/usr/bin/env bash
set -euo pipefail
mkdir -p auto-evidence
sdk="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
tools=$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
platform=$(find "$sdk/platforms" -name android.jar | sort -V | tail -n 1)
probe="$RUNNER_TEMP/auto-probe"
mkdir -p "$probe/classes" "$probe/dex"
cat > "$probe/AndroidManifest.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="app.quangtv.autoprobe">
 <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/>
 <queries><package android:name="com.quangduren.quangtv.autopreview2"/></queries>
 <application android:label="QuangTV IPC test" android:debuggable="true"/>
 <instrumentation android:name="app.quangtv.autoprobe.AutoProbe" android:targetPackage="app.quangtv.autoprobe"/>
</manifest>
XML
javac -source 8 -target 8 -classpath "$platform" -d "$probe/classes" tests/auto_probe/AutoProbe.java
"$tools/d8" --lib "$platform" --output "$probe/dex" "$probe"/classes/app/quangtv/autoprobe/*.class
"$tools/aapt" package -f -M "$probe/AndroidManifest.xml" -I "$platform" -F "$probe/probe-unsigned.apk"
(cd "$probe/dex" && zip -q "$probe/probe-unsigned.apk" classes.dex)
"$tools/apksigner" sign --ks vendor/android-auto/preview-only.jks --ks-pass pass:android --ks-key-alias androiddebugkey --out "$probe/probe.apk" "$probe/probe-unsigned.apk"
adb install -r "$probe/probe.apk"
adb logcat -c
adb install -r auto-regression.apk
adb shell am instrument -w -e expect rejected app.quangtv.autoprobe/.AutoProbe | tee auto-evidence/private-service-test.txt
grep -q 'QUANGTV_AUTO_PROBE PASS expected-' auto-evidence/private-service-test.txt
adb logcat -d > auto-evidence/private-service-logcat.txt
grep -q 'Permission Denial: Accessing service.*AudioService.*not exported' auto-evidence/private-service-logcat.txt
adb install -r auto-fixed.apk
pkg=com.quangduren.quangtv.autopreview2
adb shell am force-stop "$pkg"
python3 - <<'PY' > "$RUNNER_TEMP/auto-prefs.xml"
import json,xml.etree.ElementTree as E
root=E.Element('map')
for key in ['flutter.quangtv_auto_channels','flutter.quangtv_cached_channels']:
 E.SubElement(root,'string',name=key).text=json.dumps([{'name':'QA tone','url':'http://10.0.2.2:8765/audio.wav'}])
print(E.tostring(root,encoding='unicode'))
PY
adb shell run-as "$pkg" mkdir -p shared_prefs
adb shell run-as "$pkg" sh -c '"cat > shared_prefs/FlutterSharedPreferences.xml"' < "$RUNNER_TEMP/auto-prefs.xml"
adb logcat -c
adb shell am start -W -n "$pkg/app.tvviewer.player.MainActivity" | tee auto-evidence/phone-startup.txt
sleep 12
adb shell am instrument -w -e expect connected app.quangtv.autoprobe/.AutoProbe | tee auto-evidence/fixed-service-test.txt
adb logcat -d > auto-evidence/fixed-service-logcat.txt
adb exec-out screencap -p > auto-evidence/phone.png
adb shell dumpsys media_session > auto-evidence/media-sessions.txt
grep -q 'QUANGTV_AUTO_PROBE PASS media-connected public-catalog play-pause-stop projection-service-bound' auto-evidence/fixed-service-test.txt
if grep -q 'Permission Denial: Accessing service.*quangtv.*AudioService' auto-evidence/fixed-service-logcat.txt; then exit 1; fi
echo 'QUANGTV_ANDROID_MEDIA_IPC_PASS regressionReproduced=true externalUid=true catalog=true controls=true projectionBind=true' | tee auto-evidence/summary.txt
