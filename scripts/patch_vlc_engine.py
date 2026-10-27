"""Give each FlutterEngine its own VLC channels and platform-view factory.

AudioService creates a background FlutterEngine before the activity engine. The
upstream VLC static factory otherwise registers only on that first engine.
Use a local dependency copy so the shared pub cache is never modified.
"""
import json
import shutil
from pathlib import Path
from urllib.parse import unquote, urlparse

app = Path('upstream/flutter_app').resolve()
config = app / '.dart_tool/package_config.json'
packages = json.loads(config.read_text())['packages']
package = next(p for p in packages if p['name'] == 'flutter_vlc_player')
uri = urlparse(package['rootUri'])
assert uri.scheme in ('', 'file'), 'Expected a local resolved VLC package'
source = Path(unquote(uri.path))
if not source.is_absolute():
    source = (config.parent / source).resolve()
target = app / 'third_party/flutter_vlc_player'
if source != target:
    shutil.copytree(source, target, dirs_exist_ok=True)
plugin = target / 'android/src/main/java/software/solid/fluttervlcplayer/FlutterVlcPlayerPlugin.java'
s = plugin.read_text()
for old, new in [
    ('private static FlutterVlcPlayerFactory flutterVlcPlayerFactory;', 'private FlutterVlcPlayerFactory flutterVlcPlayerFactory;'),
    ('private static void startListening()', 'private void startListening()'),
    ('private static void stopListening()', 'private void stopListening()'),
]:
    assert old in s or new in s, f'VLC source changed: {old}'
    s = s.replace(old, new)
# Fail early if dependency resolution ever changes the Dart/native wire protocol.
interface = next(p for p in packages if p['name'] == 'flutter_vlc_player_platform_interface')
interface_uri = urlparse(interface['rootUri'])
interface_root = Path(unquote(interface_uri.path))
if not interface_root.is_absolute():
    interface_root = (config.parent / interface_root).resolve()
wire_channel = 'dev.flutter.pigeon.VlcPlayerApi.initialize'
assert wire_channel in (target / 'android/src/main/java/software/solid/fluttervlcplayer/Messages.java').read_text(), 'VLC Android Pigeon channel mismatch'
assert wire_channel in (interface_root / 'lib/src/messages/messages.dart').read_text(), 'VLC Dart Pigeon channel mismatch'
plugin.write_text(s)
pubspec = app / 'pubspec.yaml'
s = pubspec.read_text()
if 'dependency_overrides:' not in s:
    s += '\ndependency_overrides:\n  flutter_vlc_player:\n    path: third_party/flutter_vlc_player\n'
else:
    assert 'path: third_party/flutter_vlc_player' in s, 'Unexpected existing dependency overrides'
pubspec.write_text(s)
print('VLC factory and channels now belong to each engine; shared pub cache unchanged')

# LibVLC may decode HLS before getCurrentVideoTrack() exposes dimensions.
# Report dimensions from the actual decoded-video layout callback in that case.
texture = target / 'android/src/main/java/software/solid/fluttervlcplayer/VLCTextureView.java'
s = texture.read_text()
s = s.replace('private boolean wasPlaying = false;', '''private boolean wasPlaying = false;
    private volatile int decodedVideoWidth = 0;
    private volatile int decodedVideoHeight = 0;
    public int getDecodedVideoWidth() { return decodedVideoWidth; }
    public int getDecodedVideoHeight() { return decodedVideoHeight; }''')
anchor = 'if (width * height == 0) return;'
assert anchor in s
s = s.replace(anchor, '''if (width * height == 0) return;
        decodedVideoWidth = visibleWidth > 0 ? visibleWidth : width;
        decodedVideoHeight = visibleHeight > 0 ? visibleHeight : height;''', 1)
texture.write_text(s)
player = target / 'android/src/main/java/software/solid/fluttervlcplayer/FlutterVlcPlayer.java'
s = player.read_text()
anchor = '''                            width = currentVideoTrack.width;
                        }'''
assert anchor in s
s = s.replace(anchor, anchor + '''
                        if (width <= 0 || height <= 0) {
                            width = textureView.getDecodedVideoWidth();
                            height = textureView.getDecodedVideoHeight();
                        }''', 1)
player.write_text(s)

# Flutter's initSurfaceAndroidView may still choose texture-layer composition.
# Force actual Android hierarchy composition for continuously updating VLC frames.
interface_target = app / 'third_party/flutter_vlc_player_platform_interface'
if interface_root != interface_target:
    shutil.copytree(interface_root, interface_target, dirs_exist_ok=True)
method_channel = interface_target / 'lib/src/method_channel/method_channel_vlc_player.dart'
s = method_channel.read_text()
assert 'PlatformViewsService.initSurfaceAndroidView(' in s or 'PlatformViewsService.initExpensiveAndroidView(' in s
method_channel.write_text(s.replace('PlatformViewsService.initSurfaceAndroidView(', 'PlatformViewsService.initExpensiveAndroidView('))
s = pubspec.read_text()
if 'path: third_party/flutter_vlc_player_platform_interface' not in s:
    s += '  flutter_vlc_player_platform_interface:\n    path: third_party/flutter_vlc_player_platform_interface\n'
pubspec.write_text(s)
