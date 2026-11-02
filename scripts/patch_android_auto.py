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
    for name in ('QuangAutoActivity.java', 'QuangAutoService.java', 'QuangAutoDiagnostics.java', 'QuangAutoDiagnosticsActivity.java', 'QuangGeckoBrowser.java', 'QuangGeckoActivity.java'):
        shutil.copyfile(ROOT / 'overrides' / name, source / name)

    car_source = app / 'src/main/java/app/quangtv/car'
    car_source.mkdir(parents=True, exist_ok=True)
    for name in ('ParkedSensorMonitor.java', 'LegacyParkedSensors.java'):
        shutil.copyfile(ROOT / 'overrides' / name, car_source / name)

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
            android:label="QuangTV Auto – Chẩn đoán" android:exported="false"
            android:theme="@android:style/Theme.Material.Light.NoActionBar">
        </activity>
        <service android:name="app.tvviewer.player.QuangAutoService"
            android:exported="true" android:label="Mây · Video" android:icon="@drawable/quang_auto_video">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="com.google.android.gms.car.category.CATEGORY_PROJECTION" />
                <category android:name="com.google.android.gms.car.category.CATEGORY_PROJECTION_OEM" />
            </intent-filter>
        </service>
    </application>''')
        ET.fromstring(text)
        manifest.write_text(text)
    # Current Gecko requires API 37.2 and AGP 9. Keep Flutter 3.44's supported
    # legacy DSL/Kotlin flags; this applies to the isolated Auto flavor only.
    android_root = app.parent
    settings = android_root / 'settings.gradle'
    if settings.exists():
        settings.write_text(settings.read_text().replace('version "8.9.2"', 'version "9.5.0"').replace('version "1.9.22"', 'version "2.4.10"'))
        wrapper = android_root / 'gradle/wrapper/gradle-wrapper.properties'
        wrapper.write_text(wrapper.read_text().replace('gradle-8.11.1-all.zip', 'gradle-9.6.0-all.zip'))
        properties = android_root / 'gradle.properties'
        flags = properties.read_text() if properties.exists() else ''
        for key in ('android.newDsl', 'android.builtInKotlin'):
            if key + '=' not in flags: flags += '\n' + key + '=false\n'
        properties.write_text(flags)
    # One phone launcher icon. Diagnostics stays inside app settings.
    text = manifest.read_text()
    text = re.sub(r'(<activity\b[^>]*android:name="app\.tvviewer\.player\.QuangAutoDiagnosticsActivity"[^>]*>).*?</activity>',
        lambda m: re.sub(r'android:exported="true"', 'android:exported="false"', m.group(1)) + '</activity>', text, flags=re.S)
    if 'app.tvviewer.player.QuangGeckoActivity' not in text:
        text = text.replace('</application>', '''
        <activity android:name="app.tvviewer.player.QuangGeckoActivity" android:exported="false"
            android:theme="@android:style/Theme.Material.NoActionBar" android:hardwareAccelerated="true"
            android:resizeableActivity="true" android:windowSoftInputMode="adjustResize"
            android:configChanges="orientation|screenSize|screenLayout|smallestScreenSize|density|uiMode|keyboardHidden" />
        <activity-alias android:name="app.tvviewer.player.QuangParked" android:targetActivity="app.tvviewer.player.MainActivity"
            android:exported="true" android:label="QuangTV · Đỗ xe">
            <intent-filter><action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.CAR_LAUNCHER" /></intent-filter>
        </activity-alias>
        </application>''')
    if 'android:appCategory=' not in text:
        text = text.replace('<application', '<application android:appCategory="video"', 1)
    text = re.sub(r'(<service\b[^>]*android:name="com\.ryanheise\.audioservice\.AudioService")(?![^>]*android:label)', r'\1 android:label="QuangTV · Âm thanh"', text)
    if 'package android:name="com.google.android.projection.gearhead"' not in text and '<queries>' in text:
        text = text.replace('<queries>', '<queries><package android:name="com.google.android.projection.gearhead" />', 1)
    ET.fromstring(text)
    manifest.write_text(text)
    assets = app / 'src/main/assets/may_gecko'
    assets.mkdir(parents=True, exist_ok=True)
    for name in ('manifest.json', 'background.js', 'content.js'):
        shutil.copyfile(ROOT / 'overrides/may_gecko' / name, assets / name)
    activity = app / 'src/main/kotlin/app/tvviewer/player/MainActivity.kt'
    if activity.exists():
        kotlin = activity.read_text().replace('Intent(this, QuangBrowserActivity::class.java)', 'Intent(this, QuangGeckoActivity::class.java)')
        if '"quangtv/auto"' not in kotlin:
            kotlin = kotlin.replace('    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {', '''    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/auto").setMethodCallHandler { call, result ->
            if (call.method == "diagnostics") {
                startActivity(Intent(this, QuangAutoDiagnosticsActivity::class.java)); result.success(null)
            } else result.notImplemented()
        }
''', 1)
        activity.write_text(kotlin)

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
    (resources / 'drawable').mkdir(parents=True, exist_ok=True)
    (resources / 'drawable/quang_auto_video.xml').write_text('''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="48dp" android:height="48dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#8AE4D1" android:pathData="M19.35,10.04C18.67,6.59 15.64,4 12,4C9.11,4 6.6,5.64 5.35,8.04C2.34,8.36 0,10.91 0,14C0,17.31 2.69,20 6,20H19C21.76,20 24,17.76 24,15C24,12.36 21.95,10.22 19.35,10.04Z"/>
    <path android:fillColor="#0B3330" android:pathData="M10,9L10,16L16,12.5Z"/>
</vector>''')
    # audio_service looks these up by Dart-provided names at runtime. AGP 9's
    # optimized shrinker otherwise removes them, breaking PlaybackState updates.
    (resources / 'raw').mkdir(parents=True, exist_ok=True)
    (resources / 'raw/quangtv_auto_keep.xml').write_text('''<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/audio_service_*,@drawable/ic_notification" />''')
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
    if 'org.mozilla.geckoview:geckoview:' not in text:
        text += '\n// quangtv.gecko.native: independent browser engine, not Android WebView.\nrepositories { maven { url "https://maven.mozilla.org/maven2/" } }\ndependencies { implementation "org.mozilla.geckoview:geckoview:159.0.20261022150525" }\nandroid { compileSdkVersion "android-37.2" }\n'

    if 'libs/aauto.aar' not in text:
        gradle.write_text(text + '''
dependencies {
    implementation files('libs/aauto.aar')
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'androidx.fragment:fragment:1.8.5'
    implementation 'androidx.recyclerview:recyclerview:1.3.2'
}
''')
    else:
        gradle.write_text(text)
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
-keep class app.tvviewer.player.QuangGeckoBrowser { *; }
-keep class app.tvviewer.player.QuangGeckoActivity { *; }
''')


AUDIO_BROWSER = '''  // QuangTV Auto media browser
  int _autoPlaybackGeneration = 0;
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId != AudioService.browsableRootId) return [];
    return quangAutoMediaItems();
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) => quangAutoMediaItem(mediaId);

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final request = ++_autoPlaybackGeneration;
    final selected = await getMediaItem(mediaId);
    if (selected == null || request != _autoPlaybackGeneration) return;
    await stop();
    if (request != _autoPlaybackGeneration) return;
    _channelName = selected.title;
    queue.add([selected]);
    mediaItem.add(selected);
    try {
      _updatePlaybackState(playing: false, state: AudioProcessingState.loading);
      final sources = await quangAutoPlaybackSources(selected);
      Object? lastSourceError;
      bool prepared = false;
      for (final source in sources) {
        if (request != _autoPlaybackGeneration) return;
        try {
          await _audioPlayer.setUrl(source, headers: quangAutoPlaybackHeaders(selected));
          if (request != _autoPlaybackGeneration) return;
          prepared = true;
          break;
        } catch (error) {
          if (request != _autoPlaybackGeneration) return;
          lastSourceError = error;
        }
      }
      if (!prepared) throw lastSourceError ?? StateError('Không có nguồn phát');
      _isBackgroundActive = true;
      unawaited(_audioPlayer.play().catchError((Object error) async {
        if (request != _autoPlaybackGeneration) return;
        await _audioPlayer.stop();
        if (request != _autoPlaybackGeneration) return;
        _isBackgroundActive = false;
        _updatePlaybackState(playing: false, state: AudioProcessingState.idle);
        logger.error('Android Auto audio playback failed', error);
      }));
      _updatePlaybackState(playing: true);
    } catch (error) {
      if (request != _autoPlaybackGeneration) return;
      await _audioPlayer.stop();
      if (request != _autoPlaybackGeneration) return;
      _isBackgroundActive = false;
      _updatePlaybackState(playing: false, state: AudioProcessingState.idle);
      logger.error('Android Auto audio source failed', error);
    }
  }
'''


if __name__ == '__main__':
    patch()
