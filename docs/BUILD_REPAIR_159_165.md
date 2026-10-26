# Build failures 159–165

This repair changes CI tooling and debug-only YouTube diagnostics. It preserves browser/player behavior, seek controls, mute, ad blocking, and the configured Mây Việt Worker.

| Build | Observed failure | Cause and handling |
| --- | --- | --- |
| 159 | Dart analyzer: unused `_toggleControls` | Fixed by build 160; retain the actual tap handler. |
| 160 | Emulator exited during video decoding; adb went offline | Not a successful test, despite Flutter printing two tests passed. Restore SwiftShader with Vulkan/emulator hardware decoder disabled; precompile before boot. Physical-device acceleration is unchanged. No host OOM evidence was present; exact emulator crash backtrace was unavailable. |
| 161 | apt install timeout, exit 124 | Package provisioning depended on a slow mirror and a large recommended package set. |
| 162 | ffmpeg missing | Removing provisioning did not make FFmpeg available. |
| 163 | FFmpeg 7.0.2 static: SIGSEGV/139 reading HLS | Replace the unpinned binary with a checksum-pinned toolchain; retain the same HLS remux command and require real HLS decoding. |
| 164 | Invalid YAML colon in a shell command | Corrected block scalar in 165; workflow parsed before retry. |
| 165 | Live QuangTube playback could not start | Screenshot shows YouTube sign-in/bot verification on the runner network. Do not bypass authentication or convert this failure to success. Improve debug-only error detection. |

Build 165 passed: proxy HTTP/SOCKS and WebSocket tests, five Worker tests, FFmpeg fixture decode, Dart analysis, signed-release compilation, browser discovery/download/playback/landscape, native Media3 and VLC playback, rendered moving frames, mute/volume, tap/autohide, rotation retention, OTA byte/checksum/single-request/reopen tests. The live YouTube test failed, so no release was published.

All emulator suites are mandatory for every release, including browser releases. Signature checks compare apksigner's certificate to the permanent keystore and check the package versionCode. Publication is gated on tests; a draft asset is downloaded and compared before publishing, then the app's latest-release metadata endpoint is checked for tag, size, SHA-256 and APK URL. FFmpeg exists only on CI and is not packaged in the APK.
