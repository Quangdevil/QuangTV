# QuangTV — Android IPTV build

Build based on MIT-licensed [TV Viewer](https://github.com/tv-viewer-app/tv_viewer), pinned to upstream commit `188df516a8acb4a2fda0d65fed8b6199c734603f`.

This repository contains a GitHub Actions build recipe and maintained QuangTV overrides, rather than a complete upstream source fork.

## Native playback validation

The workflow generates a deterministic H.264/AAC HLS video and exercises the actual QuangNativePlayer widget on Android API 30 with Media3 and VLC separately. Each engine must report nonzero video dimensions, active playback, and at least five seconds of advancing position. Initialization alone does not pass. Logcat and test output are retained as playback evidence even when a test fails.

Release signing and APK publishing run only on main, after the emulator tests succeed. The fix/native-playback-validation branch runs tests without publishing APKs or restoring release signing secrets. Passing the fixture verifies the playback path; it does not establish that every third-party live stream is reachable or compatible.

To reproduce on a connected Android device, apply scripts/patch_quangtv.py to the pinned upstream checkout, run flutter pub get, then run:

```sh
flutter test integration_test/native_hls_test.dart -d DEVICE_ID --dart-define=HLS_TEST_URL=http://HOST/index.m3u8
```

Features including PiP depend on the upstream source, Android version, and stream. No promise of Android Auto compatibility. No new analytics, ads or credentials are added by this build workflow. Source and third-party dependencies have not yet undergone a full security audit.
