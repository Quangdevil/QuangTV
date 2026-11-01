# QuangTV Auto preview

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
