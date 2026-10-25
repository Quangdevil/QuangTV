from pathlib import Path
import shutil
shutil.copyfile('overrides/quang_discover_screen.dart', 'upstream/flutter_app/lib/screens/quang_discover_screen.dart')
shutil.copyfile('overrides/quang_private_screen.dart', 'upstream/flutter_app/lib/screens/quang_private_screen.dart')
shutil.copyfile('overrides/quang_web_screen.dart', 'upstream/flutter_app/lib/screens/quang_web_screen.dart')
shutil.copyfile('overrides/quang_native_player.dart', 'upstream/flutter_app/lib/screens/quang_native_player.dart')
shutil.copyfile('overrides/quang_audio_screen.dart', 'upstream/flutter_app/lib/screens/quang_audio_screen.dart')
shutil.copyfile('overrides/quang_update_screen.dart', 'upstream/flutter_app/lib/screens/quang_update_screen.dart')
pubspec=Path('upstream/flutter_app/pubspec.yaml')
pubspec.write_text(pubspec.read_text().replace('  # UI', '  xml: ^6.5.0\n  webview_flutter: ^4.10.0\n  flutter_vlc_player: 7.4.3\n  flutter_vlc_player_platform_interface: 2.0.5\n  # UI', 1))
p=Path("upstream/flutter_app/lib/screens/home_screen.dart")
s=p.read_text()
anchor="import 'package:flutter/material.dart';"
assert anchor in s
s=s.replace(anchor,anchor+"\nimport 'package:url_launcher/url_launcher.dart';\nimport 'quang_discover_screen.dart';\nimport 'quang_update_screen.dart';",1)
anchor="        actions: ["
assert anchor in s
s=s.replace(anchor,"""        actions: [
          IconButton(tooltip: 'Cập nhật QuangTV', icon: const Icon(Icons.system_update), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const QuangUpdateScreen())); }),
          // QuangTV navigation: one discover screen, no overlay stacks.
          IconButton(
            tooltip: 'YouTube & Podcasts',
            icon: const Icon(Icons.smart_display, color: Colors.red),
            onPressed: () async {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const QuangDiscoverScreen()));
            },
          ),
""",1)
s=s.replace("'📺 TV Viewer'","'QuangTV'",1)
p.write_text(s)

manifest=Path('upstream/flutter_app/android/app/src/main/AndroidManifest.xml')
manifest.write_text(manifest.read_text().replace('android:label="TV Viewer"', 'android:label="QuangTV"'))

# Replace the upstream disabled PiP stub with QuangTV's native channel.
shutil.copyfile('overrides/pip_service.dart', 'upstream/flutter_app/lib/services/pip_service.dart')
activity = Path('upstream/flutter_app/android/app/src/main/kotlin/app/tvviewer/player/MainActivity.kt')
kotlin = activity.read_text()
pip_imports = """import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
"""
kotlin = kotlin.replace('import android.content.Intent', pip_imports + 'import android.content.Intent', 1)
anchor = '        // Video player intent channel'
assert anchor in kotlin
cast_handler = """        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/cast").setMethodCallHandler { call, result ->
            if (call.method == "openSettings") {
                try {
                    startActivity(Intent("android.settings.CAST_SETTINGS"))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            } else result.notImplemented()
        }

"""
kotlin = kotlin.replace(anchor, cast_handler + anchor, 1)
external_handler = """        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/external_player").setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
            } else {
                val url = call.argument<String>("url") ?: ""
                val uri = android.net.Uri.parse(url)
                if (uri.scheme != "https" && uri.scheme != "http") {
                    result.success(false)
                } else {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.apple.mpegurl")
                            addCategory(Intent.CATEGORY_DEFAULT)
                        }
                        startActivity(Intent.createChooser(intent, "Chọn trình phát IPTV"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
            }
        }

"""
kotlin = kotlin.replace(anchor, external_handler + anchor, 1)
pip_handler = """        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/pip").setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE))
                "enter" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
                        result.success(false)
                    } else {
                        val numerator = call.argument<Int>("numerator") ?: 16
                        val denominator = call.argument<Int>("denominator") ?: 9
                        runOnUiThread {
                            try {
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(numerator.coerceAtLeast(1), denominator.coerceAtLeast(1)))
                                    .build()
                                result.success(enterPictureInPictureMode(params))
                            } catch (e: Exception) {
                                result.error("PIP_FAILED", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

"""
kotlin = kotlin.replace(anchor, pip_handler + anchor, 1)
activity.write_text(kotlin)

# Replace upstream player entirely: no VLC, external intent or browser fallback.
shutil.copyfile('overrides/quang_player_screen.dart', 'upstream/flutter_app/lib/screens/player_screen.dart')

# Personal-use build: remove feedback/rating prompts and menu entries.
home = Path('upstream/flutter_app/lib/screens/home_screen.dart')
home_source = home.read_text()
home_source = home_source.replace('    final shouldShow = await FeedbackService.shouldShowRatingPrompt();', '    final shouldShow = false;')
start = home_source.find('              // ── Feedback ')
end = home_source.find('              // ── Help & info ', start)
assert start >= 0 and end > start, 'Feedback menu markers changed'
home_source = home_source[:start] + home_source[end:]
home.write_text(home_source)

# Stable standalone application identity for all future QuangTV releases.
gradle = Path('upstream/flutter_app/android/app/build.gradle')
gradle_source = gradle.read_text()
assert 'applicationId "app.tvviewer.player"' in gradle_source
gradle_source = gradle_source.replace('applicationId "app.tvviewer.player"', 'applicationId "com.quangduren.quangtv"', 1)
# The release APK must always use a persistent private keystore, never a fallback debug key.
gradle_source = gradle_source.replace(
    'signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug',
    'signingConfig signingConfigs.release',
    1,
)
# Compress native libraries; the release workflow selects the ARM64 ABI split.
gradle_source += '\nandroid {\n    packagingOptions {\n        jniLibs { useLegacyPackaging true }\n    }\n}\n'
# One published ABI: keep versionCode equal to the OTA build number.
gradle_source = gradle_source.replace('variant.versionCode * 10 + abiVersionCode', 'variant.versionCode')
gradle.write_text(gradle_source)

# QuangTV OTA: download APK privately and launch Android's package installer.
kotlin = activity.read_text()
ota = '''        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(QuangUpdateManager.status(this))
                    "start" -> result.success(QuangUpdateManager.start(this,
                        call.argument<String>("url") ?: "",
                        call.argument<Number>("total")?.toLong() ?: 0,
                        call.argument<String>("digest") ?: ""))
                    "installReady" -> { QuangUpdateManager.install(this); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("UPDATE", e.message, null)
            }
        }

'''
shutil.copyfile('overrides/QuangUpdateManager.kt', activity.parent / 'QuangUpdateManager.kt')
anchor = '        // Video player intent channel'
assert anchor in kotlin
kotlin = kotlin.replace(anchor, ota + anchor, 1)
activity.write_text(kotlin)
manifest = Path('upstream/flutter_app/android/app/src/main/AndroidManifest.xml')
m = manifest.read_text()
if 'android.permission.REQUEST_INSTALL_PACKAGES' not in m:
    m = m.replace('<manifest ', '<manifest ', 1)
    insert_at = m.find('>', m.find('<manifest')) + 1
    m = m[:insert_at] + '\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>' + m[insert_at:]
if 'androidx.core.content.FileProvider' not in m:
    provider = '''<provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.updateprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/quangtv_update_paths"/>
        </provider>'''
    assert '<application' in m, 'Android application element not found'
    application_start = m.index('>', m.index('<application')) + 1
    m = m[:application_start] + '\n        ' + provider + m[application_start:]
# IPTV playlists can be HTTPS while their HLS media segments use plain HTTP.
# Permit cleartext for this IPTV client so Android Media3 and VLC can fetch them.
if 'android:usesCleartextTraffic=' not in m:
    assert '<application' in m
    m = m.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
manifest.write_text(m)
paths = Path('upstream/flutter_app/android/app/src/main/res/xml/quangtv_update_paths.xml')
paths.parent.mkdir(parents=True, exist_ok=True)
paths.write_text('<?xml version="1.0" encoding="utf-8"?><paths xmlns:android="http://schemas.android.com/apk/res/android"><cache-path name="apk" path="."/><files-path name="update" path="updates/"/></paths>')

# Exercise the actual in-app player on an Android device, with both native engines.
tests = Path('upstream/flutter_app/integration_test')
tests.mkdir(exist_ok=True)
shutil.copyfile('tests/native_hls_test.dart', tests / 'native_hls_test.dart')
pubspec.write_text(pubspec.read_text().replace('dev_dependencies:', 'dev_dependencies:\n  integration_test:\n    sdk: flutter', 1))

# Android API 24+ prioritizes this XML over usesCleartextTraffic in the manifest.
# User-imported IPTV sources may use arbitrary HTTP segment/CDN hosts.
network = Path('upstream/flutter_app/android/app/src/main/res/xml/network_security_config.xml')
network.write_text(network.read_text().replace('cleartextTrafficPermitted="false"', 'cleartextTrafficPermitted="true"').replace('Default: require HTTPS for all traffic', 'IPTV: allow user-selected HTTP media hosts').replace('Restrict cleartext traffic to known streaming CDN domains only', 'Permit user-imported IPTV media over HTTP or HTTPS'))

# Android 15 / target 35: allow immersive video mode to hide system bars.
# Keep the existing theme items when adding the opt-out resource qualifier.
import xml.etree.ElementTree as ET
style_root = ET.parse('upstream/flutter_app/android/app/src/main/res/values/styles.xml').getroot()
for style in style_root.findall('style'):
    ET.SubElement(style, 'item', {'name': 'android:windowOptOutEdgeToEdgeEnforcement'}).text = 'true'
styles35 = Path('upstream/flutter_app/android/app/src/main/res/values-v35/styles.xml')
styles35.parent.mkdir(parents=True, exist_ok=True)
ET.ElementTree(style_root).write(styles35, encoding='utf-8', xml_declaration=True)

shutil.copyfile('tests/ota_update_test.dart', tests / 'ota_update_test.dart')

# Reuse the QuangTube Android WebView player in QuangTV's YouTube actions.
shutil.copyfile('overrides/QuangTubeActivity.kt', activity.parent / 'QuangTubeActivity.kt')
shutil.copyfile('overrides/QuangTubeAdSkipController.kt', activity.parent / 'QuangTubeAdSkipController.kt')
kotlin = activity.read_text()
anchor = '        // Video player intent channel'
youtube = '''        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/youtube").setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val url = call.argument<String>("url") ?: "https://m.youtube.com/"
                    val uri = Uri.parse(url)
                    val host = uri.host?.lowercase() ?: ""
                    if (uri.scheme != "https" || !(host == "youtube.com" || host.endsWith(".youtube.com") || host == "youtu.be")) {
                        result.error("URL", "Liên kết YouTube không hợp lệ", null)
                    } else {
                        startActivity(Intent(this, QuangTubeActivity::class.java).putExtra("url", url))
                        result.success(true)
                    }
                }
                "requestTestTap" -> if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) { android.util.Log.i("QuangTube", "QUANGTV_YOUTUBE_TAP"); result.success(null) } else result.notImplemented()
                "status" -> if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) result.success(QuangTubeActivity.status()) else result.notImplemented()
                "close" -> if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) { QuangTubeActivity.close(); result.success(null) } else result.notImplemented()
                else -> result.notImplemented()
            }
        }

'''
assert anchor in kotlin
activity.write_text(kotlin.replace(anchor, youtube + anchor, 1))
m = manifest.read_text()
assert '</application>' in m
m = m.replace('</application>', '<activity android:name=".QuangTubeActivity" android:exported="false" android:theme="@android:style/Theme.Material.Light.NoActionBar" android:hardwareAccelerated="true" android:supportsPictureInPicture="true" android:resizeableActivity="true" android:configChanges="orientation|screenSize|keyboardHidden|screenLayout|smallestScreenSize|uiMode" android:windowSoftInputMode="adjustResize"/></application>', 1)
manifest.write_text(m)

# audio_service must share the Activity engine; plain FlutterActivity creates a
# second headless engine during plugin attachment, racing the visible isolate.
kotlin = activity.read_text()
activity.write_text(kotlin.replace('class MainActivity: FlutterActivity()',
                                  'class MainActivity: com.ryanheise.audioservice.AudioServiceActivity()'))

# Replace both full-width and compact Map actions with the same browser route.
shutil.copyfile('overrides/quang_browser_screen.dart', 'upstream/flutter_app/lib/screens/quang_browser_screen.dart')
shutil.copyfile('overrides/QuangBrowserActivity.kt', activity.parent / 'QuangBrowserActivity.kt')
s = home.read_text().replace("import 'map_screen.dart';", "import 'quang_browser_screen.dart';")
s = s.replace('const MapScreen()', 'const QuangBrowserScreen()').replace('Icons.map', 'Icons.public')
s = s.replace("'World Map'", "'Trình duyệt'").replace("value == 'map'", "value == 'browser'").replace("value: 'map'", "value: 'browser'")
home.write_text(s)
kotlin = activity.read_text()
marker = 'class MainActivity: com.ryanheise.audioservice.AudioServiceActivity() {'
assert marker in kotlin
bridge = '''
    private var browserReply: MethodChannel.Result? = null
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 3101) return
        val reply = browserReply
        browserReply = null
        if (resultCode != android.app.Activity.RESULT_OK || data == null) { reply?.success(null); return }
        val json = org.json.JSONObject(data.getStringExtra("headers") ?: "{}")
        val headers = mutableMapOf<String, String>()
        json.keys().forEach { key -> headers[key] = json.optString(key) }
        reply?.success(mapOf("url" to data.getStringExtra("url"), "page" to data.getStringExtra("page"),
            "title" to data.getStringExtra("title"), "headers" to headers))
    }
'''
kotlin = kotlin.replace(marker, marker + bridge, 1)
browser = '''        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/browser").setMethodCallHandler { call, result ->
            if (call.method == "dnsStatus") {
                try {
                    val mode = android.provider.Settings.Global.getString(contentResolver, "private_dns_mode")
                    val host = android.provider.Settings.Global.getString(contentResolver, "private_dns_specifier")
                    result.success(when (mode) { "hostname" -> host ?: "DNS tùy chọn"; "off" -> "Tắt"; "opportunistic" -> "Tự động"; else -> "Xem trong cài đặt Android" })
                } catch (_: Exception) { result.success("Xem trong cài đặt Android") }
            } else if (call.method == "dnsSettings") {
                try {
                    startActivity(Intent("android.settings.PRIVATE_DNS_SETTINGS"))
                    result.success(null)
                } catch (_: Exception) {
                    try { startActivity(Intent(android.provider.Settings.ACTION_WIRELESS_SETTINGS)); result.success(null) }
                    catch (_: Exception) { result.error("SETTINGS", "Không mở được cài đặt mạng", null) }
                }
            } else if (call.method == "open") {
                if (browserReply != null) { result.error("BUSY", "Trình duyệt đang mở", null) }
                else {
                    browserReply = result
                    try { startActivityForResult(Intent(this, QuangBrowserActivity::class.java).putExtra("url", call.argument<String>("url") ?: ""), 3101) }
                    catch (e: Exception) { browserReply = null; result.error("BROWSER", "Không mở được trình duyệt", null) }
                }
            } else if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                when (call.method) {
                    "inspect" -> result.success(QuangBrowserActivity.inspect())
                    "focus", "select", "download", "confirmDownload", "toggleProxy", "showTabs", "newTab", "firstTab", "openDownloads", "openCompleted", "closePreview", "playPage", "landscape", "portrait", "clearDownloads", "close" -> { QuangBrowserActivity.testAction(call.method); result.success(null) }
                    else -> result.notImplemented()
                }
            } else result.notImplemented()
        }

'''
assert anchor in kotlin
activity.write_text(kotlin.replace(anchor, browser + anchor, 1))
m = manifest.read_text().replace('</application>', '<activity android:name=".QuangBrowserActivity" android:exported="false" android:theme="@android:style/Theme.Material.Light.NoActionBar" android:hardwareAccelerated="true" android:configChanges="orientation|screenSize|keyboardHidden|screenLayout|smallestScreenSize|uiMode" android:windowSoftInputMode="adjustResize"/></application>', 1)
m = m.replace('<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove"/>', '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>', 1)
manifest.write_text(m)

shutil.copyfile('tests/browser_test.dart', 'upstream/flutter_app/integration_test/browser_test.dart')

# Keep authenticated proxy credentials exclusively on the device.
shutil.copyfile('overrides/QuangProxy.kt', activity.parent / 'QuangProxy.kt')
java_source = Path('upstream/flutter_app/android/app/src/main/java/app/tvviewer/player')
java_source.mkdir(parents=True, exist_ok=True)
shutil.copyfile('overrides/QuangProxyRelay.java', java_source / 'QuangProxyRelay.java')
gradle = Path('upstream/flutter_app/android/app/build.gradle')
gradle.write_text(gradle.read_text() + '\ndependencies { implementation "androidx.webkit:webkit:1.12.1" }\n')
kotlin = activity.read_text()
proxy_handler = '''            if (call.method == "proxyGet") {
                try { result.success(QuangProxy.state(this)) } catch (_: Exception) { result.error("PROXY", "Không đọc được cấu hình proxy mã hóa. Hãy lưu lại cấu hình.", null) }
                return@setMethodCallHandler
            }
            if (call.method == "proxyToggle") {
                try {
                    QuangProxy.toggle(this, call.argument<Boolean>("enabled") == true)
                    QuangProxy.applyWeb(this, { result.success(QuangProxy.state(this)) }, { result.error("PROXY", "Không áp dụng được proxy", null) })
                } catch (_: Exception) { result.error("PROXY", "Hãy lưu cấu hình proxy trước khi bật", null) }
                return@setMethodCallHandler
            }
            if (call.method == "proxySave") {
                try {
                    QuangProxy.save(this, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    QuangProxy.applyWeb(this, { result.success(QuangProxy.state(this)) }, { result.error("PROXY", "Không áp dụng được proxy vào WebView", null) })
                } catch (_: Exception) { result.error("PROXY", "Cấu hình không hợp lệ hoặc WebView cần cập nhật", null) }
                return@setMethodCallHandler
            }
            if (call.method == "youtubeFixture" && applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                QuangYouTube.start(this, QuangYouTube.Choice("Mux fixture", "http://10.0.2.2:8765/proxy-only/video-only.mp4", "http://10.0.2.2:8765/proxy-only/audio-only.m4a", "360p"))
                result.success(null); return@setMethodCallHandler
            }
            if (call.method == "youtubeStatus" && applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                result.success(mapOf("running" to QuangYouTube.running, "status" to QuangYouTube.status, "completed" to QuangYouTube.completed(this).size)); return@setMethodCallHandler
            }
            if (call.method == "youtubeProbe" && applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                QuangYouTube.extract(this, "https://www.youtube.com/watch?v=aqz-KE-bpKQ") { choices, error -> result.success(mapOf("count" to (choices?.size ?: 0), "error" to (error ?: ""))) }; return@setMethodCallHandler
            }
            if (call.method == "proxyMediaUrl") {
                try { result.success(QuangProxy.downloadUrl(this, call.argument<String>("url") ?: "")) }
                catch (_: Exception) { result.error("PROXY", "Không chuẩn bị được nguồn phát qua proxy", null) }
                return@setMethodCallHandler
            }
            if (call.method == "proxyTest") {
                QuangProxy.test(this) { value -> if (value == null) result.error("PROXY", "Không kết nối được. Kiểm tra loại proxy, địa chỉ, tài khoản và mật khẩu.", null) else result.success(value) }
                return@setMethodCallHandler
            }
'''
anchor = '        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/browser").setMethodCallHandler { call, result ->\n'
assert anchor in kotlin
kotlin = kotlin.replace(anchor, '        try { QuangProxy.ensure(this) } catch (_: Exception) {}\n' + anchor + proxy_handler, 1)
activity.write_text(kotlin)
m = manifest.read_text()
import re
m = re.sub(r'android:allowBackup="[^"]*"', 'android:allowBackup="false"', m)
if 'android:allowBackup=' not in m: m = m.replace('<application', '<application android:allowBackup="false"', 1)
manifest.write_text(m)
shutil.copyfile('overrides/quang_proxy_screen.dart', 'upstream/flutter_app/lib/screens/quang_proxy_screen.dart')

# Lightweight Java extractor; Android MediaMuxer combines audio/video, without FFmpeg binaries.
shutil.copyfile('overrides/QuangYouTube.kt', activity.parent / 'QuangYouTube.kt')
root_gradle = Path('upstream/flutter_app/android/build.gradle')
root_gradle.write_text(root_gradle.read_text().replace('mavenCentral()', 'mavenCentral()\n        maven { url "https://jitpack.io" }', 1))
g = gradle.read_text().replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
g += '\ndependencies { coreLibraryDesugaring "com.android.tools:desugar_jdk_libs_nio:2.1.5"; implementation "com.github.TeamNewPipe:NewPipeExtractor:v0.26.5" }\n'
gradle.write_text(g)
proguard = Path('upstream/flutter_app/android/app/proguard-rules.pro')
proguard.write_text(proguard.read_text() + '\n-keep class org.mozilla.javascript.** { *; }\n-keep class org.mozilla.classfile.ClassFileWriter\n-dontwarn org.mozilla.javascript.tools.**\n')

# D8 directory transforms require the complete boot/library classpath with core desugaring.
props = Path('upstream/flutter_app/android/gradle.properties')
props.write_text(props.read_text() + '\nandroid.useFullClasspathForDexingTransform=true\n')
license_assets = Path('upstream/flutter_app/assets/licenses')
license_assets.mkdir(parents=True, exist_ok=True)
shutil.copyfile('COPYING.NewPipe', license_assets / 'newpipe.txt')
pubspec.write_text(pubspec.read_text().replace('  uses-material-design: true', '  uses-material-design: true\n  assets:\n    - assets/licenses/newpipe.txt', 1))
