from pathlib import Path
import shutil
shutil.copyfile('overrides/quang_discover_screen.dart', 'upstream/flutter_app/lib/screens/quang_discover_screen.dart')
p=Path("upstream/flutter_app/lib/screens/home_screen.dart")
s=p.read_text()
anchor="import 'package:flutter/material.dart';"
assert anchor in s
s=s.replace(anchor,anchor+"\nimport 'package:url_launcher/url_launcher.dart';\nimport 'quang_discover_screen.dart';",1)
anchor="        actions: ["
assert anchor in s
s=s.replace(anchor,"""        actions: [
          // Official YouTube app owns Google sign-in, subscriptions and podcast playback.
          // No embedded WebView, injected CSS, cookie interception or fake sign-in.
          IconButton(
            tooltip: 'YouTube & Podcasts',
            icon: const Icon(Icons.smart_display, color: Colors.red),
            onPressed: () async {
              final app = Uri.parse('vnd.youtube://www.youtube.com/');
              final web = Uri.parse('https://www.youtube.com/');
              Navigator.push(context, MaterialPageRoute(builder: (_) => const QuangDiscoverScreen()));
            },
          ),
""",1)
s=s.replace("'📺 TV Viewer'","'QuangTV'",1)
p.write_text(s)
