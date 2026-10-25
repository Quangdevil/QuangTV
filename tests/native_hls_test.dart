import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:tv_viewer/models/channel.dart';
import 'package:tv_viewer/screens/quang_native_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('HLS_TEST_URL');
  for (final engine in ['Media3', 'VLC']) {
    testWidgets('$engine decodes HLS video and advances playback', (tester) async {
      expect(url, isNotEmpty, reason: 'Supply HLS_TEST_URL; never pass without playback');
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(home: QuangNativePlayer(
        channel: Channel(name: 'HLS playback test', url: url),
        startWithVlc: engine == 'VLC',
      )));
      Duration? firstPosition;
      var passed = false;
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 500));
        Duration? position;
        if (engine == 'Media3') {
          final players = tester.widgetList<VideoPlayer>(find.byType(VideoPlayer));
          if (players.isNotEmpty) {
            final v = players.first.controller.value;
            expect(v.hasError, isFalse, reason: v.errorDescription);
            if (v.isPlaying && v.size.width > 0 && v.size.height > 0) position = v.position;
          }
        } else {
          final players = tester.widgetList<VlcPlayer>(find.byType(VlcPlayer));
          if (players.isNotEmpty) {
            final v = players.first.controller.value;
            expect(v.hasError, isFalse, reason: v.errorDescription);
            if (v.isPlaying && v.size.width > 0 && v.size.height > 0) position = v.position;
          }
        }
        if (position != null) {
          firstPosition ??= position;
          if (position - firstPosition >= const Duration(seconds: 5)) {
            passed = true;
            debugPrint('QUANGTV_PLAYBACK_PASS engine=$engine progressedMs=${(position - firstPosition).inMilliseconds}');
            break;
          }
        }
      }
      expect(passed, isTrue, reason: '$engine must show video dimensions and advance >=5s');
      // Keep the verified video visible long enough for host-side screenshots.
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
