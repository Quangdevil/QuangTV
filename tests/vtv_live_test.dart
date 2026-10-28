import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:tv_viewer/models/channel.dart';
import 'package:tv_viewer/screens/quang_native_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final name in ['VTV1', 'VTV3']) {
    testWidgets('$name obtains fresh official free source and plays real video', (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
      await tester.pumpWidget(MaterialApp(home: QuangNativePlayer(
        channel: Channel(name: name, url: 'https://example.org/expired-vtv-source.m3u8'),
        startMuted: true,
      )));
      Duration? previous;
      Duration progressed = Duration.zero;
      int? firstVideoMs;
      var lastLog = DateTime.fromMillisecondsSinceEpoch(0);
      final deadline = DateTime.now().add(const Duration(seconds: 70));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 500));
        final players = tester.widgetList<VideoPlayer>(find.byType(VideoPlayer));
        if (players.isEmpty) continue;
        final player = players.first.controller;
        final value = player.value;
        if (DateTime.now().difference(lastLog).inSeconds >= 5) {
          debugPrint('QUANGTV_VTV_STATE channel=$name host=${Uri.parse(player.dataSource).host} playing=${value.isPlaying} buffering=${value.isBuffering} positionMs=${value.position.inMilliseconds} width=${value.size.width} height=${value.size.height}');
          lastLog = DateTime.now();
        }
        if (!value.isPlaying || value.size.width <= 0 || value.size.height <= 0) continue;
        expect(player.dataSource, isNot(contains('example.org')));
        expect(value.volume, 0);
        firstVideoMs ??= DateTime.now().millisecondsSinceEpoch;
        // Live windows can slide backwards; count forward playback across
        // those timeline resets and independently verify changing video pixels.
        final delta = previous == null ? Duration.zero : value.position - previous;
        if (delta > Duration.zero && delta < const Duration(seconds: 2)) progressed += delta;
        previous = value.position;
        if (progressed >= const Duration(seconds: 5)) {
          await tester.pump(const Duration(seconds: 6));
          debugPrint('QUANGTV_VTV_VISUAL channel=$name startMs=$firstVideoMs endMs=${DateTime.now().millisecondsSinceEpoch}');
          debugPrint('QUANGTV_VTV_LIVE_PASS channel=$name freshOfficialSource=true realVideo=true width=${value.size.width} height=${value.size.height} advancedMs=${progressed.inMilliseconds}');
          return;
        }
      }
      fail('$name must decode and advance real official live video; fixture playback is insufficient');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
