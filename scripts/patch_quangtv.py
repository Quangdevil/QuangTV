from pathlib import Path
import shutil
shutil.copyfile('overrides/quang_discover_screen.dart', 'upstream/flutter_app/lib/screens/quang_discover_screen.dart')
shutil.copyfile('overrides/quang_web_screen.dart', 'upstream/flutter_app/lib/screens/quang_web_screen.dart')
pubspec=Path('upstream/flutter_app/pubspec.yaml')
pubspec.write_text(pubspec.read_text().replace('  # UI', '  webview_flutter: ^4.10.0\n  # UI', 1))
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
