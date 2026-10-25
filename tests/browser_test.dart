import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_viewer/screens/quang_browser_screen.dart';
import 'package:tv_viewer/screens/quang_discover_screen.dart';
import 'package:tv_viewer/screens/quang_private_screen.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Private actions stay in one row and the last channel is deletable', (tester) async {
    SharedPreferences.setMockInitialValues({'quangtv_private_channels': List.generate(30, (i) => jsonEncode({'name': 'Channel $i', 'url': 'https://example.org/$i.m3u8'}))});
    await tester.pumpWidget(const MaterialApp(home: QuangPrivateScreen()));
    final loadedBy = DateTime.now().add(const Duration(seconds: 10));
    while (find.text('Channel 0').evaluate().isEmpty && DateTime.now().isBefore(loadedBy)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Channel 0'), findsOneWidget);
    final y = tester.getRect(find.text('Thêm kênh')).center.dy;
    expect(tester.getRect(find.text('Nhập M3U')).center.dy, closeTo(y, 2));
    expect(tester.getRect(find.text('Tải lại M3U')).center.dy, closeTo(y, 2));
    await tester.scrollUntilVisible(find.text('Channel 29'), 400, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.tap(find.descendant(of: find.widgetWithText(ListTile, 'Channel 29'), matching: find.byIcon(Icons.delete_outline)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Xóa kênh Private?'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugPrint('QUANGTV_PRIVATE_LAYOUT_PASS oneRow=true lastDeleteAccessible=true');
  });
  testWidgets('Settings separates Private PIN and system DNS', (tester) async {
    SharedPreferences.setMockInitialValues({'quangtv_cached_channels': '[]'});
    await tester.pumpWidget(const MaterialApp(home: QuangDiscoverScreen()));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Đổi PIN Private'), findsOneWidget);
    await tester.tap(find.text('DNS hệ thống'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Google DNS'), findsOneWidget);
    expect(find.text('Nhập DNS thủ công'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugPrint('QUANGTV_DNS_SETTINGS_PASS separatePanel=true googleAndCustom=true');
  });
  testWidgets('Browser discovers a direct MP4, respects bars and keyboard, downloads and opens native player', (tester) async {
    const browser = MethodChannel('quangtv/browser');
    await tester.pumpWidget(const MaterialApp(home: QuangBrowserScreen(initialUrl: 'http://10.0.2.2:8765/browser.html')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      Future<Map<dynamic, dynamic>> state() async => await browser.invokeMapMethod<dynamic, dynamic>('inspect') ?? {};
      Map<dynamic, dynamic> current = {};
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        current = await state();
        if ((current['count'] as num? ?? 0) > 0) break;
      }
      expect(current['count'], greaterThan(0));
      expect(current['top'], greaterThanOrEqualTo(current['statusBar']));
      final top = current['top'];
      final height = current['height'] as num;
      await browser.invokeMethod<void>('focus');
      final keyboardDeadline = DateTime.now().add(const Duration(seconds: 12));
      while (DateTime.now().isBefore(keyboardDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        current = await state();
        if (current['ime'] == true) break;
      }
      expect(current['ime'], isTrue);
      expect(current['top'], top);
      expect(current['height'], lessThan(height));
      expect(current['height'], greaterThan(100));
      await browser.invokeMethod<void>('download');
      await Future<void>.delayed(const Duration(seconds: 1));
      await browser.invokeMethod<void>('confirmDownload');
      final downloadDeadline = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(downloadDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        current = await state();
        if ((current['downloaded'] as num? ?? 0) > 0) break;
      }
      expect(current['downloaded'], greaterThan(0));
      debugPrint('QUANGTV_BROWSER_PASS directDiscovery=true safeTop=true keyboardResizesBottom=true downloadedBytes=${current['downloaded']}');
      await browser.invokeMethod<void>('clearDownloads');
      await browser.invokeMethod<void>('select');
    });
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    var played = false;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      final players = tester.widgetList<VideoPlayer>(find.byType(VideoPlayer));
      if (players.isNotEmpty && players.first.controller.value.isPlaying && players.first.controller.value.position.inSeconds >= 3) { played = true; break; }
    }
    expect(played, isTrue);
    debugPrint('QUANGTV_BROWSER_PLAYER_PASS nativePlaybackAdvanced=true');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
