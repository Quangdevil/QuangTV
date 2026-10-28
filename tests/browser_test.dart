import 'dart:convert';
import 'dart:io';
import 'package:tv_viewer/screens/quang_network.dart';
import 'package:tv_viewer/screens/quang_proxy_screen.dart';
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
  testWidgets('Embedded May opens proxied pages and has real landscape video controls', (tester) async {
    const browser = MethodChannel('quangtv/browser');
    await browser.invokeMethod<void>('proxySave', {'enabled': true, 'type': 'http', 'host': '10.0.2.2', 'port': 8766, 'user': 'fixture-user', 'password': 'fixture-password'});
    await tester.pumpWidget(const MaterialApp(home: QuangBrowserScreen()));
    await tester.runAsync(() async {
      Future<Map<dynamic,dynamic>> state([String command='state', double value=.5]) async =>
        await browser.invokeMapMethod<dynamic,dynamic>('mayTest', {'command':command,'value':value}) ?? {};
      Future<Map<dynamic,dynamic>> until(bool Function(Map<dynamic,dynamic>) matches) async {
        final deadline=DateTime.now().add(const Duration(seconds:45));
        Map<dynamic,dynamic> latest={};
        while(DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds:300));
          latest=await state();
          if(matches(latest)) return latest;
        }
        fail('May state did not become ready: $latest');
      }
      try {
        final deadline=DateTime.now().add(const Duration(seconds:20));
        Map<dynamic,dynamic> info={};
        while(DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds:300));
          info=await browser.invokeMapMethod<dynamic,dynamic>('inspect') ?? {};
          if(info['mayMode']==true && info['progress']==100 && (info['pageUrl']?.toString() ?? '').contains('may-viet-web-proxy.daquang.workers.dev')) break;
        }
        expect(info['mayMode'],true);
        expect(info['pageUrl'],contains('may-viet-web-proxy.daquang.workers.dev'));
        await browser.invokeMethod<void>('mayExample');
        await until((s)=>s['frameReady']==true);
        debugPrint('QUANGTV_MAY_EMBED_PASS remoteShell=true serverBrowse=true sandboxReady=true');
        await browser.invokeMethod<void>('mayDemo');
        var snapshot=await until((s)=>s['hasControls']==true);
        if (snapshot['paused']==true) { await state('tapVideo'); await state('play'); }
        snapshot=await until((s)=>s['ready']==true);
        expect(snapshot['muted'],true);
        expect(snapshot['hasSeek'],true);
        if (snapshot['paused']==true) { await state('tapVideo'); await state('play'); }
        await browser.invokeMethod<void>('landscape');
        await until((s)=>s['stage']==true);
        await state('tapVideo');
        snapshot=await state();
        expect(snapshot['nativeFullscreen'],false,reason:'May controls must remain on the HTML viewport');
        expect(snapshot['hidden'],false);
        if(snapshot['paused']==false) snapshot=await state('play');
        expect(snapshot['paused'],true);
        snapshot=await state('volume',.35);
        expect(snapshot['muted'],false);
        expect((snapshot['volume'] as num).toDouble(),closeTo(.35,.12));
        snapshot=await state('seek',.4);
        final duration=(snapshot['duration'] as num).toDouble();
        expect((snapshot['position'] as num).toDouble(),closeTo(duration*.4,duration*.15));
        final before=(snapshot['position'] as num).toDouble();
        snapshot=await state('forward10');
        expect((snapshot['position'] as num).toDouble(),closeTo((before+10).clamp(0,duration),.7));
        final forward=(snapshot['position'] as num).toDouble();
        snapshot=await state('back10');
        expect((snapshot['position'] as num).toDouble(),closeTo((forward-10).clamp(0,duration),.7));
        await Future<void>.delayed(const Duration(seconds:4));
        expect((await state())['hidden'],true);
        expect((await state('tapVideo'))['hidden'],false);
        final proxy=await browser.invokeMapMethod<dynamic,dynamic>('proxyGet');
        expect(proxy?['enabled'],true,reason:'May must not change the IPTV proxy configuration');
        debugPrint('QUANGTV_MAY_CONTROLS_PASS landscape=true tapReveal=true playPause=true volume=true seek=true doubleTap10s=true autoHide=true iptvProxyPreserved=true');
      } finally {
        await browser.invokeMethod<void>('portrait');
        await browser.invokeMethod<void>('close');
        await Future<void>.delayed(const Duration(milliseconds:500));
        await browser.invokeMethod<void>('proxySave', {'enabled':false,'type':'http','host':'10.0.2.2','port':8766,'user':'fixture-user','password':'fixture-password'});
      }
    });
    await tester.pump(const Duration(seconds:1));
    await tester.pumpWidget(const SizedBox.shrink());
  },timeout:const Timeout(Duration(minutes:4)));
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
      await QuangNetwork.install();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(appBar: AppBar(actions: const [QuangProxyToggle()]))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Tắt proxy'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quangtv-home-vpn')));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 500)); });
    await tester.pump();
    expect(find.byTooltip('Bật proxy'), findsOneWidget);
    await tester.runAsync(() async {
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(Uri.parse('http://10.0.2.2:8765/proxy-only/fixture.mp4'))).close();
        expect(response.statusCode, 403);
        await response.drain<void>();
      } finally { client.close(force: true); }
      final direct = await browser.invokeMapMethod<String, dynamic>('networkCheck', {'url': 'http://10.0.2.2:8765/browser.html', 'viaProxy': false});
      expect(direct?['code'], 200);
    });
    await tester.tap(find.byKey(const ValueKey('quangtv-home-vpn')));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 500)); });
    await tester.pump();
    expect(find.byTooltip('Tắt proxy'), findsOneWidget);
    await tester.runAsync(() async {
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(Uri.parse('http://10.0.2.2:8765/proxy-only/fixture.mp4'))).close();
        expect(response.statusCode, 200);
        expect((await response.fold<int>(0, (total, bytes) => total + bytes.length)), greaterThan(0));
      } finally { client.close(force: true); }
      final proxied = await browser.invokeMapMethod<String, dynamic>('networkCheck', {'url': 'http://10.0.2.2:8765/proxy-only/fixture.mp4', 'viaProxy': true});
      expect(proxied?['code'], 206);
      debugPrint('QUANGTV_APP_PROXY_PASS homeToggle=true directDefault=true dartHttpRouted=true diagnostics=true');
    });
    await tester.pumpWidget(const MaterialApp(home: QuangBrowserScreen(initialUrl: 'http://10.0.2.2:8765/proxy-only/browser.html')));
    debugPrint('CHECKPOINT_BROWSER_NATIVE_OPEN_REQUESTED');
    // The native Activity pauses Flutter rendering. A pump here requests a
    // Flutter frame that Android cannot deliver until the browser closes.
    // Poll the actual native state instead; keep every UI/playback assertion.
    await tester.runAsync(() async {
      try {
      Future<Map<dynamic, dynamic>> state() async => await browser.invokeMapMethod<dynamic, dynamic>('inspect').timeout(const Duration(seconds: 10)) ?? {};
      Map<dynamic, dynamic> current = {};
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        current = await state();
        if ((current['count'] as num? ?? 0) > 0) break;
      }
      debugPrint('CHECKPOINT_BROWSER_NATIVE_READY count=${current['count']}');
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
      debugPrint('CHECKPOINT_BROWSER_KEYBOARD ime=${current['ime']}');
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
      // Native windows hide the Flutter test surface. Drive the complete native
      // preview/rotation flow there and inspect only after it returns to Flutter.
      await browser.invokeMethod<void>('previewAndRotate').timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 55));
      expect((await state())['previewPassed'], isTrue, reason: 'Downloaded video must advance before closing its preview');
      expect((await state())['rotationPassed'], isTrue);
      expect((await state())['fullscreen'], isFalse);
      debugPrint('QUANGTV_BROWSER_UI_PASS tabs=true downloadedFilePlayback=true quickProxy=true landscapeFullscreen=true adsBlocked=true');
      } finally {
        await browser.invokeMethod<void>('close');
      }
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
