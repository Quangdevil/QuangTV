import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:tv_viewer/models/channel.dart';
import 'package:tv_viewer/screens/quang_native_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const url = String.fromEnvironment('HLS_TEST_URL');
  for (final engine in ['Media3', 'VLC']) {
    testWidgets(
      '$engine decodes HLS video and advances playback',
      (tester) async {
        expect(
          url,
          isNotEmpty,
          reason: 'Supply HLS_TEST_URL; never pass without playback',
        );
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(
          MaterialApp(
            home: QuangNativePlayer(
              channel: Channel(name: 'HLS playback test', url: url),
              startWithVlc: engine == 'VLC',
              startMuted: true,
            ),
          ),
        );
        Duration? firstPosition;
        int? firstVideoMs;
        var passed = false;
        var lastDiagnostic = DateTime.fromMillisecondsSinceEpoch(0);
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 500));
          Duration? position;
          if (engine == 'Media3') {
            final players = tester.widgetList<VideoPlayer>(
              find.byType(VideoPlayer),
            );
            if (players.isNotEmpty) {
              final v = players.first.controller.value;
              if (DateTime.now().difference(lastDiagnostic).inSeconds >= 10) {
                debugPrint(
                  'QUANGTV_STATE engine=$engine playing=${v.isPlaying} positionMs=${v.position.inMilliseconds} size=${v.size}',
                );
                lastDiagnostic = DateTime.now();
              }
              expect(v.hasError, isFalse, reason: v.errorDescription);
              if (v.isPlaying && v.size.width > 0 && v.size.height > 0)
                position = v.position;
            }
          } else {
            final players = tester.widgetList<VlcPlayer>(
              find.byType(VlcPlayer),
            );
            if (players.isNotEmpty) {
              final v = players.first.controller.value;
              if (DateTime.now().difference(lastDiagnostic).inSeconds >= 10) {
                debugPrint(
                  'QUANGTV_STATE engine=$engine playing=${v.isPlaying} positionMs=${v.position.inMilliseconds} size=${v.size}',
                );
                lastDiagnostic = DateTime.now();
              }
              expect(v.hasError, isFalse, reason: v.errorDescription);
              if (v.isPlaying) position = v.position;
            }
          }
          if (position != null) {
            firstPosition ??= position;
            firstVideoMs ??= DateTime.now().millisecondsSinceEpoch;
            if (position - firstPosition >= const Duration(seconds: 5)) {
              passed = true;
              debugPrint(
                'QUANGTV_PLAYBACK_PASS engine=$engine progressedMs=${(position - firstPosition).inMilliseconds}',
              );
              break;
            }
          }
        }
        expect(
          passed,
          isTrue,
          reason:
              '$engine must play and advance >=5s; host also checks rendered video frames',
        );
        // Keep the verified video visible long enough for host-side screenshots.
        await tester.pump(const Duration(seconds: 12));
        debugPrint(
          'QUANGTV_VISUAL engine=$engine startMs=$firstVideoMs endMs=${DateTime.now().millisecondsSinceEpoch}',
        );
        final panel = find.byKey(const ValueKey('player-controls'));
        final surface = find.byKey(const ValueKey('player-tap-surface'));
        expect(tester.widget<IgnorePointer>(panel).ignoring, isTrue);
        await tester.tapAt(tester.getCenter(surface));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<IgnorePointer>(panel).ignoring, isFalse);
        await tester.tapAt(tester.getCenter(surface));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<IgnorePointer>(panel).ignoring, isTrue);
        await tester.tapAt(tester.getCenter(surface));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<IgnorePointer>(panel).ignoring, isFalse);
        await tester.pump(const Duration(milliseconds: 3300));
        expect(tester.widget<IgnorePointer>(panel).ignoring, isTrue);
        await tester.tapAt(tester.getCenter(surface));
        await tester.pump(const Duration(milliseconds: 300));
        debugPrint(
          'QUANGTV_CONTROLS_PASS engine=$engine tapToggle=true autoHideSeconds=3 portrait=true',
        );
        Future<double> nativeVolume() async {
          if (engine == 'Media3') {
            return tester
                .widget<VideoPlayer>(find.byType(VideoPlayer))
                .controller
                .value
                .volume;
          }
          return (await tester
                      .widget<VlcPlayer>(find.byType(VlcPlayer))
                      .controller
                      .getVolume() ??
                  -100) /
              100;
        }

        Object currentController() => engine == 'Media3'
            ? tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller
            : tester.widget<VlcPlayer>(find.byType(VlcPlayer)).controller;
        expect(
          await nativeVolume(),
          closeTo(0, .01),
          reason: 'Private must start muted',
        );
        final slider = find.byKey(const ValueKey('player-volume'));
        tester.widget<Slider>(slider).onChanged!(.35);
        await tester.pump(const Duration(seconds: 1));
        expect(await nativeVolume(), closeTo(.35, .02));
        final mute = find.byKey(const ValueKey('player-mute'));
        await tester.tap(mute);
        await tester.pump(const Duration(seconds: 1));
        expect(await nativeVolume(), closeTo(0, .01));
        await tester.tap(mute);
        await tester.pump(const Duration(seconds: 1));
        expect(
          await nativeVolume(),
          closeTo(.35, .02),
          reason: 'Unmute restores in-app level',
        );
        await tester.tap(mute);
        await tester.pump(const Duration(seconds: 1));
        final originalController = currentController();
        Duration currentPosition() => engine == 'Media3'
            ? tester
                  .widget<VideoPlayer>(find.byType(VideoPlayer))
                  .controller
                  .value
                  .position
            : tester
                  .widget<VlcPlayer>(find.byType(VlcPlayer))
                  .controller
                  .value
                  .position;
        final beforeRotationPosition = currentPosition();
        Future<void> waitOrientation(Orientation desired) async {
          final until = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(until)) {
            await tester.pump(const Duration(milliseconds: 500));
            final context = tester.element(find.byType(QuangNativePlayer));
            if (MediaQuery.orientationOf(context) == desired) return;
          }
          fail('Android did not rotate to $desired');
        }

        try {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
          ]);
          await waitOrientation(Orientation.landscape);
          expect(
            find.byType(AppBar),
            findsNothing,
            reason: 'Landscape must enter fullscreen',
          );
          expect(
            currentController(),
            same(originalController),
            reason: 'Rotation must retain playback',
          );
          final context = tester.element(find.byType(QuangNativePlayer));
          final size = MediaQuery.sizeOf(context);
          final rect = tester.getRect(
            engine == 'Media3'
                ? find.byType(VideoPlayer)
                : find.byType(VlcPlayer),
          );
          expect(
            rect.width / size.width > .95 || rect.height / size.height > .95,
            isTrue,
            reason: 'Video must fit the full landscape viewport',
          );
          expect(
            await nativeVolume(),
            closeTo(0, .01),
            reason: 'Rotation must preserve Private mute',
          );
          final landscapeStart = DateTime.now().millisecondsSinceEpoch;
          await tester.pump(const Duration(seconds: 8));
          debugPrint(
            'QUANGTV_LANDSCAPE engine=$engine startMs=$landscapeStart endMs=${DateTime.now().millisecondsSinceEpoch}',
          );
          expect(
            currentPosition() - beforeRotationPosition,
            greaterThan(const Duration(seconds: 3)),
            reason: 'Playback must continue while rotated',
          );
          expect(tester.takeException(), isNull);
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
          await waitOrientation(Orientation.portrait);
          expect(find.byType(AppBar), findsOneWidget);
          expect(currentController(), same(originalController));
          expect(await nativeVolume(), closeTo(0, .01));
          expect(tester.takeException(), isNull);
          debugPrint(
            'QUANGTV_UI_PASS engine=$engine privateMuted=true volumeControl=true landscapeFullscreen=true retainedController=true',
          );
        } finally {
          await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
