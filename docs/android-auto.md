# QuangTV Auto preview

## Build 12: current Mây interface

The projection screen now loads https://may-viet-web-proxy.daquang.workers.dev/
in its WebView, so the TV catalog, fresh VTV playback sources, QuangTube,
Podcast/Radio tabs and responsive interface come from the current Mây app.
It no longer recreates IPTV with a separate VideoView or a phone-saved catalog.
The standard Android Auto audio browser remains a separate audio-only entry.
The native seven-button UI documented below describes builds 11 and earlier.

Runtime evidence and remaining real-head-unit admission limitations are in
[the build 12 report](android-auto-may-runtime.md).

## Previous native preview (through build 11)

The preview adds a projection service with a native CarActivity, following the
same legacy host interface used by Fermata Auto. It is not screen mirroring and
does not require the phone's Flutter Activity to stay on screen.

Implemented: YouTube WebView, Android Auto search, back navigation, web video
fullscreen, play/pause, ±10 seconds, and native playback of saved public IPTV
channels or a direct HTTP(S) media URL. Saved IPTV channels are read from this
installation's Flutter SharedPreferences. Open QuangTV's TV screen on the phone
and load the playlist before opening TV in the car. The preview package is
separate, so it starts with its own empty preferences.

The car player currently uses Android VideoView; it does not include the
phone player's Media3/VLC failover, fresh VTV source resolution, custom stream
headers, proxy settings or private channel access. YouTube uses the system
WebView and availability depends on YouTube and the current network. This
preview does not promise ad-free playback. It stops playback when its car host
stops and destroys WebViews/players when switching screens or disconnecting.

## Compatibility is a separate gate

Declaring CATEGORY_PROJECTION is necessary, but does not guarantee Android
Auto will list or accept a sideloaded package. AAAD does not automatically add
arbitrary packages to its catalog or remove Android Auto validation. Android
17 / One UI 9 and the user's head unit have not been tested. Do not label this
integration compatible until it is launched through Android Auto and actual
video, sound, touch input, search and disconnect behavior have been verified.

Reference implementation:
https://github.com/AndreyPavlenko/Fermata/tree/7d2bd42e0fea98a796ba069b56c48ef07d874549/fermata/src/auto

## Build and verification

After checking out the TV Viewer revision pinned by the main workflow:

```sh
python3 -m unittest discover -s tests -p test_android_auto_patch.py
python3 scripts/patch_quangtv.py
python3 scripts/patch_android_auto.py
```

Continue with the existing Flutter dependency/VLC/build steps. The patch is
idempotent. The candidate workflow compiles an isolated ARM64 preview signed
with a development key. It uploads an artifact, never changes production OTA,
and does not claim runtime validation. The main build retains its existing
runtime gates. See vendor/android-auto/README.md for the unresolved SDK
redistribution notice; public release requires resolving it first.

## Preview 2 startup diagnosis

Preview 2 opens a native channel/home screen first and creates WebView only after tapping YouTube. Optional host chrome/search setup errors are recorded without aborting the native screen. Startup stages and exception stacks are stored locally and available through the phone launcher entry **QuangTV Auto – Chẩn đoán**, which has a manual Share button. This does not establish the cause of the first real-car failure; the recorded stages are needed to distinguish host initialization and WebView failures. The package is `.autopreview2`, named QuangTV Auto 2 on the car, and uses an intentionally public stable test key so future Preview 2 updates retain their signature.

## Bugreport binding repair and Preview 2 updates

The 2026-11-01 phone bugreport records repeated Android Auto bind failures:
`AudioService ... not exported` for both preview packages. The integration now
exports that specific media browser service, preserves its mediaPlayback type,
and supplies its public saved channel catalog. This is a confirmed binding
failure; it does not by itself establish the cause of a projection launch failure.

Preview 2 retains package `com.quangduren.quangtv.autopreview2` and the stable
preview-only signer. Its updater reads only `auto-preview2-buildN` prereleases
and `QuangTV-Auto-Preview2-...-arm64.apk` assets. Native download/install checks
reject a different package, signer, and older or equal version. The regular app
continues using production Releases/latest. The candidate workflow publishes
only experimental Preview 2 prereleases and never changes production/latest.
Existing Preview 2 builds block OTA: install this first update manually over
Preview 2, without uninstalling. Later builds use the phone's Cập nhật QuangTV
screen with existing percentage/MB progress. Real car validation remains pending.
