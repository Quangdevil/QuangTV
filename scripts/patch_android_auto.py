"""Add the native Android Auto projection host after patch_quangtv.py."""
from pathlib import Path
import hashlib
import re
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'upstream/flutter_app/android/app'
ANDROID = '{http://schemas.android.com/apk/res/android}'


def patch(app=APP):
    sdk = ROOT / 'vendor/android-auto/aauto.aar'
    expected = (ROOT / 'vendor/android-auto/SHA256SUMS').read_text().split()[0]
    if hashlib.sha256(sdk.read_bytes()).hexdigest() != expected:
        raise RuntimeError('Android Auto SDK checksum mismatch')
    (app / 'libs').mkdir(exist_ok=True)
    shutil.copyfile(sdk, app / 'libs/aauto.aar')
    source = app / 'src/main/java/app/tvviewer/player'
    source.mkdir(parents=True, exist_ok=True)
    for name in ('QuangAutoActivity.java', 'QuangAutoService.java', 'QuangAutoDiagnostics.java', 'QuangAutoDiagnosticsActivity.java'):
        shutil.copyfile(ROOT / 'overrides' / name, source / name)

    manifest = app / 'src/main/AndroidManifest.xml'
    text = manifest.read_text()
    # The upstream media browser service was private. Android Auto is a separate
    # UID, so discovery succeeded but every bind failed with Permission Denial.
    text, count = re.subn(
        r'(<service\b[^>]*android:name="com\.ryanheise\.audioservice\.AudioService"[^>]*android:exported=")false(")',
        r'\g<1>true\2', text)
    if count:
        manifest.write_text(text)
    # Preserve Flutter's placeholders, comments and namespace prefixes.
    if 'app.tvviewer.player.QuangAutoService' not in text:
        text = text.replace('</application>', '''
        <meta-data android:name="com.google.android.gms.car.application"
            android:resource="@xml/quangtv_automotive_app" />
        <meta-data android:name="com.google.android.gms.car.application.theme"
            android:resource="@style/QuangAutoTheme" />
        <activity android:name="app.tvviewer.player.QuangAutoDiagnosticsActivity"
            android:label="QuangTV Auto – Chẩn đoán" android:exported="true"
            android:theme="@android:style/Theme.Material.Light.NoActionBar">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name="app.tvviewer.player.QuangAutoService"
            android:exported="true" android:label="QuangTV Auto">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="com.google.android.gms.car.category.CATEGORY_PROJECTION" />
                <category android:name="com.google.android.gms.car.category.CATEGORY_PROJECTION_OEM" />
            </intent-filter>
        </service>
    </application>''')
        ET.fromstring(text)
        manifest.write_text(text)
    # AudioService's default BaseAudioHandler returns an empty browser tree.
    # Supply the same public catalog used by the native projection screen.
    flutter = app.parents[1]
    handler = flutter / 'lib/services/background_audio_service.dart'
    if handler.exists():
        shutil.copyfile(ROOT / 'overrides/quang_auto_media.dart', handler.parent / 'quang_auto_media.dart')
        tests = flutter / 'test'
        tests.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / 'tests/quang_auto_media_test.dart', tests / 'quang_auto_media_test.dart')
        content = handler.read_text()
        if '// QuangTV Auto media browser' not in content:
            content = "import 'dart:async';\nimport 'quang_auto_media.dart';\n" + content
            content = content.replace('  VideoPlayerController? _videoController;', AUDIO_BROWSER + '\n  VideoPlayerController? _videoController;', 1)
            # Upstream's write-only URL field is unused; keep this handler clean
            # under the expanded analyzer gate without suppressing diagnostics.
            content = re.sub(r'^.*_currentUrl(?:\s*=.*|;)\n', '', content, flags=re.MULTILINE)
            handler.write_text(content)
    resources = app / 'src/main/res'
    (resources / 'xml').mkdir(parents=True, exist_ok=True)
    (resources / 'xml/quangtv_automotive_app.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<automotiveApp><uses name="media" /><uses name="projection" /></automotiveApp>\n')
    (resources / 'values').mkdir(parents=True, exist_ok=True)
    (resources / 'values/quangtv_auto.xml').write_text('''<resources>
    <style name="QuangAutoTheme" parent="Theme.AppCompat.DayNight.NoActionBar">
        <item name="android:windowActionModeOverlay">true</item>
        <item name="android:colorAccent">#36C88B</item>
    </style>
</resources>
''')
    gradle = app / 'build.gradle'
    text = gradle.read_text()
    if 'libs/aauto.aar' not in text:
        gradle.write_text(text + '''
dependencies {
    implementation files('libs/aauto.aar')
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'androidx.fragment:fragment:1.8.5'
    implementation 'androidx.recyclerview:recyclerview:1.3.2'
}
''')
    rules = app / 'proguard-rules.pro'
    text = rules.read_text()
    if '# QuangTV Auto projection' not in text:
        rules.write_text(text + '''
# QuangTV Auto projection: legacy host discovers these classes reflectively.
-keep class com.google.android.apps.auto.sdk.** { *; }
-keep class com.google.android.gms.car.** { *; }
-keep class app.tvviewer.player.QuangAutoActivity { *; }
-keep class app.tvviewer.player.QuangAutoService { *; }
-keep class app.tvviewer.player.QuangAutoDiagnosticsActivity { *; }
''')


AUDIO_BROWSER = '''  // QuangTV Auto media browser
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId != AudioService.browsableRootId) return [];
    return quangAutoMediaItems();
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final items = await quangAutoMediaItems();
    final selected = items.where((item) => item.id == mediaId).firstOrNull;
    if (selected == null) return; // Never accept arbitrary external media URLs.
    await stop();
    _channelName = selected.title;
    mediaItem.add(selected);
    try {
      _updatePlaybackState(playing: false, state: AudioProcessingState.loading);
      await _audioPlayer.setUrl(selected.id);
      _isBackgroundActive = true;
      unawaited(_audioPlayer.play().catchError((Object error) {
        _isBackgroundActive = false;
        _updatePlaybackState(playing: false, state: AudioProcessingState.idle);
        logger.error('Android Auto audio playback failed', error);
      }));
      _updatePlaybackState(playing: true);
    } catch (error) {
      _isBackgroundActive = false;
      _updatePlaybackState(playing: false, state: AudioProcessingState.idle);
      logger.error('Android Auto audio source failed', error);
    }
  }
'''


if __name__ == '__main__':
    patch()
