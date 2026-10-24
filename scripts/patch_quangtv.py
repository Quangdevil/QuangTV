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
