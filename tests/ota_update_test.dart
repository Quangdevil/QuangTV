import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:tv_viewer/screens/quang_update_screen.dart';
import 'package:tv_viewer/screens/quang_discover_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const native = MethodChannel('quangtv/update');
  testWidgets(
    'Native OTA reports bytes and survives outside tap and screen reopen without duplicate download',
    (tester) async {
      const total = 2 * 1024 * 1024;
      final digest = sha256.convert(
        List<int>.generate(total, (index) => index % 256),
      );
      final args = {
        'url': 'http://10.0.2.2:8765/ota-fixture.apk',
        'total': total,
        'digest': 'sha256:$digest',
      };
      Map<dynamic, dynamic> status =
          await native.invokeMapMethod<dynamic, dynamic>('start', args) ?? {};
      await tester.pumpWidget(const MaterialApp(home: QuangUpdateScreen()));
      await tester.pump(const Duration(seconds: 1));
      final show = find.byKey(const ValueKey('ota-show-progress'));
      expect(show, findsOneWidget);
      await tester.tap(show);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining(' MB · Còn '), findsWidgets);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'Outside taps must not dismiss progress',
      );
      await native.invokeMapMethod<dynamic, dynamic>('start', args);
      final before =
          await native.invokeMapMethod<dynamic, dynamic>('status') ?? {};
      expect(before['downloaded'], greaterThan(0));
      expect(before['downloaded'], lessThan(total));
      await tester.tap(find.byKey(const ValueKey('ota-hide-progress')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const MaterialApp(home: QuangUpdateScreen()));
      await tester.pump(const Duration(seconds: 1));
      status = await native.invokeMapMethod<dynamic, dynamic>('status') ?? {};
      expect(status['downloaded'], greaterThanOrEqualTo(before['downloaded']));
      final until = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(until) && status['phase'] != 'ready') {
        await tester.pump(const Duration(milliseconds: 500));
        status = await native.invokeMapMethod<dynamic, dynamic>('status') ?? {};
        expect(
          status['phase'],
          isNot('error'),
          reason: status['message']?.toString(),
        );
      }
      expect(status['phase'], 'ready');
      expect(status['downloaded'], total);
      expect(status['total'], total);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('ota-install-ready')), findsOneWidget);
      final cached =
          await native.invokeMapMethod<dynamic, dynamic>('start', args) ?? {};
      expect(cached['phase'], 'ready');
      expect(cached['downloaded'], total);
      final response = await http.get(
        Uri.parse('http://10.0.2.2:8765/ota-metrics.json'),
      );
      expect(
        (jsonDecode(response.body) as Map)['requests'],
        1,
        reason:
            'Repeat taps and reopening must reuse the original download/APK',
      );
      debugPrint(
        'QUANGTV_OTA_PASS bytes=$total outsideTapProtected=true screenReopenRetained=true nativeRequests=1 cachedReuse=true checksumVerified=true',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  testWidgets(
    'YouTube action opens integrated QuangTube and plays public video',
    (tester) async {
      const youtube = MethodChannel('quangtv/youtube');
      SharedPreferences.setMockInitialValues({
        'quangtv_cached_channels':
            '[{"name":"Test","url":"https://example.org/test.m3u8"}]',
      });
      await tester.pumpWidget(const MaterialApp(home: QuangDiscoverScreen()));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byTooltip('YouTube'));
      await tester.pump(const Duration(milliseconds: 500));
      final search = find.byType(TextField).first;
      await tester.enterText(
        search,
        'https://m.youtube.com/watch?v=aqz-KE-bpKQ&autoplay=1',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      bool passed = false;
      await tester.runAsync(() async {
        double? first;
        final openedAt = DateTime.now();
        bool tapped = false;
        final until = DateTime.now().add(const Duration(seconds: 120));
        try {
          while (DateTime.now().isBefore(until)) {
            await Future<void>.delayed(const Duration(seconds: 1));
            final status =
                await youtube.invokeMapMethod<dynamic, dynamic>('status') ?? {};
            debugPrint('QUANGTV_YOUTUBE_STATE $status');
            if (!tapped && DateTime.now().difference(openedAt).inSeconds >= 8) {
              await youtube.invokeMethod<void>('requestTestTap');
              tapped = true;
            }
            final error = status['error']?.toString() ?? '';
            if (error.isNotEmpty) {
              debugPrint('QUANGTV_YOUTUBE_BLOCKED $error');
              break;
            }
            if (status['playing'] == true) {
              final position = (status['position'] as num?)?.toDouble() ?? 0;
              first ??= position;
              if (position - first >= 3) {
                passed = true;
                debugPrint(
                  'QUANGTV_YOUTUBE_PASS integratedAction=true advancedSeconds=${position - first}',
                );
                break;
              }
            }
          }
        } finally {
          await youtube.invokeMethod<void>('close');
        }
      });
      await tester.pump(const Duration(seconds: 1));
      expect(
        passed,
        isTrue,
        reason:
            'A public YouTube video must really play in integrated QuangTube',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
