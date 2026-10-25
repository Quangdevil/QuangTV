from pathlib import Path
import shutil
shutil.copyfile('overrides/quang_discover_screen.dart', 'upstream/flutter_app/lib/screens/quang_discover_screen.dart')
shutil.copyfile('overrides/quang_private_screen.dart', 'upstream/flutter_app/lib/screens/quang_private_screen.dart')
shutil.copyfile('overrides/quang_web_screen.dart', 'upstream/flutter_app/lib/screens/quang_web_screen.dart')
shutil.copyfile('overrides/quang_native_player.dart', 'upstream/flutter_app/lib/screens/quang_native_player.dart')
shutil.copyfile('overrides/quang_audio_screen.dart', 'upstream/flutter_app/lib/screens/quang_audio_screen.dart')
shutil.copyfile('overrides/quang_update_screen.dart', 'upstream/flutter_app/lib/screens/quang_update_screen.dart')
pubspec=Path('upstream/flutter_app/pubspec.yaml')
pubspec.write_text(pubspec.read_text().replace('  # UI', '  xml: ^6.5.0\n  webview_flutter: ^4.10.0\n  flutter_vlc_player: ^7.4.3\n  # UI', 1))
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
gradle.write_text(gradle_source)

# QuangTV OTA: download APK privately and launch Android's package installer.
kotlin = activity.read_text()
kotlin = kotlin.replace('import android.content.Intent', '''import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread''', 1)
ota = '''        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quangtv/update").setMethodCallHandler { call, result ->
            if (call.method != "install") {
                result.notImplemented()
            } else {
                val url = call.argument<String>("url") ?: ""
                if (!url.startsWith("https://github.com/Quangdevil/QuangTV/releases/download/")) {
                    result.error("URL", "Invalid GitHub release URL", null)
                } else {
                    thread {
                        try {
                            val file = File(cacheDir, "quangtv-update.apk")
                            var connection = URL(url).openConnection() as HttpURLConnection
                            connection.connectTimeout = 20000
                            connection.readTimeout = 30000
                            connection.instanceFollowRedirects = true
                            connection.connect()
                            // GitHub assets redirect to HTTPS CDN hosts.
                            var redirects = 0
                            while (connection.responseCode in 300..399 && redirects++ < 6) {
                                val next = URL(connection.getHeaderField("Location") ?: throw Exception("Missing redirect"))
                                if (next.protocol != "https") throw Exception("Insecure redirect")
                                connection.disconnect()
                                connection = next.openConnection() as HttpURLConnection
                                connection.connectTimeout = 20000
                                connection.readTimeout = 30000
                                connection.connect()
                            }
                            if (connection.responseCode != 200) throw Exception("Download HTTP ${connection.responseCode}")
                            connection.inputStream.use { input -> file.outputStream().use { output -> input.copyTo(output) } }
                            connection.disconnect()
                            if (file.length() < 1000000) throw Exception("APK incomplete")
                            val apkUri = FileProvider.getUriForFile(this, "$packageName.updateprovider", file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(apkUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            Handler(Looper.getMainLooper()).post {
                                try {
                                    startActivity(intent)
                                    result.success(null)
                                } catch (e: Exception) {
                                    result.error("INSTALL", e.message, null)
                                }
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("DOWNLOAD", e.message, null) }
                        }
                    }
                }
            }
        }

'''
anchor = '        // Video player intent channel'
assert anchor in kotlin
kotlin = kotlin.replace(anchor, ota + anchor, 1)
activity.write_text(kotlin)
manifest = Path('upstream/flutter_app/android/app/src/main/AndroidManifest.xml')
m = manifest.read_text()
if 'android.permission.REQUEST_INSTALL_PACKAGES' not in m:
    m = m.replace('<manifest ', '<manifest ', 1)
    insert_at = m.find('>', m.find('<manifest')) + 1
    m = m[:insert_at] + '\\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>' + m[insert_at:]
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
    m = m[:application_start] + '\\n        ' + provider + m[application_start:]
manifest.write_text(m)
paths = Path('upstream/flutter_app/android/app/src/main/res/xml/quangtv_update_paths.xml')
paths.parent.mkdir(parents=True, exist_ok=True)
paths.write_text('<?xml version="1.0" encoding="utf-8"?><paths xmlns:android="http://schemas.android.com/apk/res/android"><cache-path name="apk" path="."/></paths>')
