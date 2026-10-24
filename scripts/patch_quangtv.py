from pathlib import Path
import shutil
shutil.copyfile('overrides/quang_discover_screen.dart', 'upstream/flutter_app/lib/screens/quang_discover_screen.dart')
shutil.copyfile('overrides/quang_web_screen.dart', 'upstream/flutter_app/lib/screens/quang_web_screen.dart')
shutil.copyfile('overrides/quang_audio_screen.dart', 'upstream/flutter_app/lib/screens/quang_audio_screen.dart')
pubspec=Path('upstream/flutter_app/pubspec.yaml')
pubspec.write_text(pubspec.read_text().replace('  # UI', '  webview_flutter: ^4.10.0\n  just_audio: ^0.9.46\n  # UI', 1))
p=Path("upstream/flutter_app/lib/screens/home_screen.dart")
s=p.read_text()
anchor="import 'package:flutter/material.dart';"
assert anchor in s
s=s.replace(anchor,anchor+"\nimport 'package:url_launcher/url_launcher.dart';\nimport 'quang_discover_screen.dart';",1)
anchor="        actions: ["
assert anchor in s
s=s.replace(anchor,"""        actions: [
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

# Back navigation asks whether to stop playback or continue in native PiP.
player = Path('upstream/flutter_app/lib/screens/player_screen.dart')
player_source = player.read_text()
old_back = """    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope("""
new_back = """    if (!mounted) return false;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tiếp tục phát?'),
        content: const Text('Đóng trình phát hoặc tiếp tục trong cửa sổ nổi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'close'), child: const Text('Đóng')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'pip'), child: const Text('Phát nền (PiP)')),
        ],
      ),
    );
    if (choice == 'pip') {
      await _enablePip();
      return false;
    }
    return choice == 'close';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope("""
assert old_back in player_source, 'PlayerScreen back handler changed upstream'
player.write_text(player_source.replace(old_back, new_back, 1))

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
