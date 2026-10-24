# QuangTV — Android IPTV build

Build based on MIT-licensed [TV Viewer](https://github.com/tv-viewer-app/tv_viewer), pinned to upstream commit `188df516a8acb4a2fda0d65fed8b6199c734603f`.

This repository currently contains a reproducible GitHub Actions build recipe, **not a complete independently maintained source fork**. The workflow checks out the pinned upstream source and compiles an Android APK on GitHub-hosted runners.

Features including PiP depend on the upstream source, Android version, and the stream. No promise of Android Auto compatibility. No new analytics, ads or credentials are added by this build workflow. Source and third-party dependencies have **not** yet undergone a full security audit.

Download APK from Actions > Build QuangTV APK > latest successful run > Artifacts. Android arm64 is appropriate for Samsung Fold devices.
