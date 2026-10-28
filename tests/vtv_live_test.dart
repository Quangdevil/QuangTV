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
      Duration? first;
      final deadline = DateTime.now().add(const Duration(seconds: 70));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 500));
        final players = tester.widgetList<VideoPlayer>(find.byType(VideoPlayer));
        if (players.isEmpty) continue;
        final player = players.first.controller;
        final value = player.value;
        if (!value.isPlaying || value.size.width <= 0 || value.size.height <= 0) continue;
        expect(player.dataSource, isNot(contains('example.org')));
        expect(value.volume, 0);
        first ??= value.position;
        if (value.position - first >= const Duration(seconds: 5)) {
          debugPrint('QUANGTV_VTV_LIVE_PASS channel=$name freshOfficialSource=true realVideo=true width=${value.size.width} height=${value.size.height} advancedMs=${(value.position-first).inMilliseconds}');
          return;
        }
      }
      fail('$name must decode and advance real official live video; fixture playback is insufficient');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
