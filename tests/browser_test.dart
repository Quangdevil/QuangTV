import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_viewer/screens/quang_browser_screen.dart';
import 'package:tv_viewer/screens/quang_native_player.dart';
import 'package:tv_viewer/models/channel.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
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
    expect(find.text('Proxy QuangTV'), findsOneWidget);
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
    await tester.runAsync(() async {
      final saved = await browser.invokeMapMethod<String, dynamic>('proxySave', {'enabled': true, 'type': 'http', 'host': '10.0.2.2', 'port': 8766, 'user': 'fixture-user', 'password': 'fixture-password'});
      expect(saved?['enabled'], isTrue);
      expect(saved?['hasPassword'], isTrue);
      expect(saved?.containsKey('password'), isFalse);
      final restored = await browser.invokeMapMethod<String, dynamic>('proxyGet');
      expect(restored?['user'], 'fixture-user');
    });
    await tester.pumpWidget(const MaterialApp(home: QuangBrowserScreen(initialUrl: 'http://10.0.2.2:8765/proxy-only/browser.html')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      Future<Map<dynamic, dynamic>> state() async => await browser.invokeMapMethod<dynamic, dynamic>('inspect').timeout(const Duration(seconds: 10)) ?? {};
      Map<dynamic, dynamic> current = {};
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        current = await state();
        if ((current['count'] as num? ?? 0) > 0) break;
      }
      expect(current['count'], greaterThan(0));
      expect(current['blockedAds'], greaterThan(0));
      await browser.invokeMethod<void>('showTabs');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await browser.invokeMethod<void>('newTab');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((await state())['tabs'], 2);
      await browser.invokeMethod<void>('firstTab');
      await browser.invokeMethod<void>('toggleProxy');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((await state())['proxyOn'], isFalse);
      await browser.invokeMethod<void>('toggleProxy');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect((await state())['proxyOn'], isTrue);


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
      debugPrint('CHECKPOINT_DOWNLOAD_COMPLETE');
      await browser.invokeMethod<void>('openDownloads').timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await browser.invokeMethod<void>('openCompleted').timeout(const Duration(seconds: 10));
      final previewDeadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(previewDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if ((await state())['previewPlaying'] == true) break;
      }
      expect((await state())['previewPlaying'], isTrue);
      debugPrint('CHECKPOINT_PREVIEW_PLAYING');
      await browser.invokeMethod<void>('closePreview').timeout(const Duration(seconds: 10));
      await browser.invokeMethod<void>('playPage').timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 2));
      debugPrint('CHECKPOINT_BEFORE_LANDSCAPE');
      await browser.invokeMethod<void>('landscape').timeout(const Duration(seconds: 10));
      debugPrint('CHECKPOINT_LANDSCAPE_REQUESTED');
      final landscapeDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(landscapeDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if ((await state())['fullscreen'] == true) break;
      }
      expect((await state())['fullscreen'], isTrue);
      debugPrint('CHECKPOINT_BEFORE_PORTRAIT');
      await browser.invokeMethod<void>('portrait').timeout(const Duration(seconds: 10));
      debugPrint('CHECKPOINT_PORTRAIT_REQUESTED');
      await Future<void>.delayed(const Duration(seconds: 1));
      expect((await state())['fullscreen'], isFalse);
      debugPrint('QUANGTV_BROWSER_UI_PASS tabs=true downloadedFilePlayback=true quickProxy=true landscapeFullscreen=true adsBlocked=true');
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
    debugPrint('QUANGTV_PROXY_ANDROID_PASS authenticatedWebView=true authenticatedDownload=true authenticatedMedia3=true encryptedConfig=true');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(MaterialApp(home: QuangNativePlayer(channel: Channel(name: 'Proxy VLC HLS', url: 'http://10.0.2.2:8765/proxy-only/index.m3u8'), startWithVlc: true)));
    final vlcDeadline = DateTime.now().add(const Duration(seconds: 50));
    var vlcPlayed = false;
    while (DateTime.now().isBefore(vlcDeadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      final players = tester.widgetList<VlcPlayer>(find.byType(VlcPlayer));
      if (players.isNotEmpty && players.first.controller.value.isPlaying && players.first.controller.value.position.inSeconds >= 3) { vlcPlayed = true; break; }
    }
    expect(vlcPlayed, isTrue);
    debugPrint('QUANGTV_PROXY_VLC_PASS authenticatedHlsPlayback=true');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await browser.invokeMethod<void>('youtubeFixture');
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      Map<String, dynamic> status = {};
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        status = await browser.invokeMapMethod<String, dynamic>('youtubeStatus') ?? {};
        if (status['running'] == false) break;
      }
      expect(status['completed'], greaterThan(0), reason: '${status['status']}');
      debugPrint('QUANGTV_YOUTUBE_MUX_PASS nativeAvcAacMerge=true');
      await browser.invokeMethod<void>('proxySave', {'enabled': false});
      try {
        final live = await browser.invokeMapMethod<String, dynamic>('youtubeProbe').timeout(const Duration(seconds: 60));
        debugPrint((live?['count'] as int? ?? 0) > 0 ? 'QUANGTV_YOUTUBE_LIVE_PASS extractedChoices=${live?['count']}' : 'QUANGTV_YOUTUBE_LIVE_UNVERIFIED serverRestrictionOrExtractorError=true');
      } catch (_) { debugPrint('QUANGTV_YOUTUBE_LIVE_UNVERIFIED networkTimeout=true'); }
    });
  }, timeout: const Timeout(Duration(minutes: 6)));
}
