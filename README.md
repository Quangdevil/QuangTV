# QuangTV — Android IPTV build

Build based on MIT-licensed [TV Viewer](https://github.com/tv-viewer-app/tv_viewer), pinned to upstream commit `188df516a8acb4a2fda0d65fed8b6199c734603f`.

This repository contains a GitHub Actions build recipe and maintained QuangTV overrides, rather than a complete upstream source fork.

## Native playback validation

The workflow generates a deterministic H.264/AAC HLS video and exercises the actual QuangNativePlayer widget on Android API 30 with Media3 and VLC separately. Each engine must report active playback and at least five seconds of advancing position. Host screenshots must also show the decoded color-pattern video changing across multiple frames. Media3 dimensions are checked directly; VLC can report zero HLS track dimensions despite decoding, so its actual rendered pixels are verified instead. The integration binding uses fullyLive scheduling to match normal app rendering. Initialization alone does not pass. Logcat, test output, and screenshots are retained even when a test fails.

VLC is pinned to 7.4.3 with platform interface 2.0.5 so Dart and Android Pigeon channels match. The build copies these dependencies locally, scopes the VLC factory to each FlutterEngine (including the background audio engine), and uses Android hierarchy hybrid composition. The shared pub cache is not modified.

Release signing and APK publishing run only on main, after the emulator tests succeed. The fix/native-playback-validation branch runs tests without publishing APKs or restoring release signing secrets. Passing the fixture verifies the playback path; it does not establish that every third-party live stream is reachable or compatible.

For the complete emulator and moving-frame gate, follow .github/workflows/build-apk.yml. To reproduce the native assertions on a connected Android device, first apply scripts/patch_quangtv.py to the pinned upstream checkout, run flutter pub get in upstream/flutter_app, run scripts/patch_vlc_engine.py from the repository root, then run flutter pub get again. From upstream/flutter_app run:

```sh
flutter test integration_test/native_hls_test.dart -d DEVICE_ID --dart-define=HLS_TEST_URL=http://HOST/index.m3u8
```

Features including PiP depend on the upstream source, Android version, and stream. No promise of Android Auto compatibility. No new analytics, ads or credentials are added by this build workflow. Source and third-party dependencies have not yet undergone a full security audit.
