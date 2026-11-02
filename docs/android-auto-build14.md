# Android Auto build 14 — cold-start fix and runtime checks

APK source b11fee7887e9d9e88a5d4121e04f9d434085e50e.
CI: https://github.com/Quangdevil/QuangTV/actions/runs/41319106838
Artifact: https://github.com/Quangdevil/QuangTV/actions/runs/41319106838/artifacts/13088209719

The previously empty media browser read only phone-exported preferences. It now bootstraps the same public Vietnamese IPTV catalog on its first service-only startup, without requiring the phone Activity. An explicitly saved empty catalog is respected; a failed download remains retryable. VTV audio selections request fresh anonymous VTVgo sources, use the appropriate headers, and fall back to the public playlist source if preparation fails. No private catalog is fetched during bootstrap.

The Auto branch also includes the current native QuangTV May phone home from main, rather than the old generic HomeScreen. Projection continues using the current hosted May interface.

## Runtime on the exact CI artifact

- Uninstalled previous preview, installed build 14, restarted AA, selected Application Mode Release. Android 17, AA 17.9.664044-release, Google DHU 2.0, 1280x720 with horizontal marginwidth 320 (effective 960x720 app region).
- Before opening any phone Activity, selected the audio entry: public channels populated instead of No items. Alphabet navigation to VTV and selecting VTV1 succeeded. MediaSession reached PLAYING; DHU closed an audio stream with buffered samples on pause. Output used SDL_AUDIODRIVER=dummy; the emulator used -no-audio. No listening claim.
- Selected the distinct projection entry: current May home and real VTV1 video rendered. The webpage Fullscreen button expanded video across the application region, without a side Maps pane. The first two fullscreen captures were identical because playback had not been started. Explicit Play produced moving but corrupted colored/striped video, so clean fullscreen playback initially FAILED on the SwiftShader emulator profile; see the GPU comparison below. The host AA navigation area and aspect-ratio letterboxing remain controlled by AA/player, not the app.
- Exited fullscreen and opened the phone Activity: current QuangTV May home and channels were present.
- Crash buffer was empty during these tested flows. Prior build 12 tested QuangTube playback; this run did not repeat that unchanged web path.

## Fullscreen rendering failure found during extended verification

After explicit Play, fullscreen VTV1 frames contained colored horizontal stripes and diagonally repeated images. This is not a passing visual result. Logs selected c2.goldfish.h264.decoder at 854×480. Setting debug.stagefright.ccodec=2 and restarting the app did not switch away from Goldfish and did not repair the corruption. It is therefore not a successful software-decoder comparison. No emulator-only workaround is shipped in the app, and the underlying cause is not established. The earlier clear first-frame screenshot must not be used as proof of moving fullscreen playback.

![Actual failed fullscreen playback](android-auto-build14/fullscreen-failed.jpg)

## GPU comparison: same build 14 passes on host GPU

The emulator was restarted with -gpu host (Apple M2 / gfxstream Metal), keeping the same APK, Android/AA versions, app data and DHU display profile. Explicit Play followed by the webpage Fullscreen button produced clean, changing VTV1 frames. The two player-region captures differ (result.json). No app code or source URL policy was changed between these rendering comparisons. This associates the corruption with the emulator graphics configuration; it does not establish a Samsung rendering problem. The test also had an empty Android crash buffer. Dummy audio remained enabled.

![Clean moving fullscreen playback on host GPU](android-auto-build14/fullscreen-host-gpu.jpg)

## Remaining limit

The real Samsung/One UI 9 vehicle has only been observed showing the audio entry. Its missing projection entry is not reproduced or repaired by this DHU admission test. This build fixes the empty cold media catalog and stale phone UI; it must not be described as a confirmed fix for real-car video admission. Developer options and unknown sources are still available in the emulator. No installer spoofing, root changes or host-policy modifications are used. No production OTA is published.

![Cold catalog before phone launch](android-auto-build14/cold-catalog.jpg)
![May video interface](android-auto-build14/may-video.jpg)
![Fullscreen video](android-auto-build14/fullscreen.jpg)
![Current phone UI](android-auto-build14/phone.jpg)

Machine-readable observations: [result.json](android-auto-build14/result.json).
