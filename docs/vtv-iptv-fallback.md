# Lazy VTV IPTV fallback

VTVgo remains the first choice with its unchanged URL resolver and player settings. Only a failed resolver or exhausted VTVgo sources loads the same public default Vietnam playlist used by Discover and Mây. There is no extra request on successful startup. Metadata is bounded to 2 MB, cached in memory for ten minutes, and concurrent fallback loads share one request.

Only exact-channel, HTTPS HLS entries without DRM, custom headers, credentials or sensitive query parameters are eligible. Regional VTV5 channels remain distinct. URL order and contents are preserved. Playlist sources receive no saved cookies/auth or VTVgo-specific headers. Existing player retries and buffering thresholds stay unchanged. Retry/dispose invalidates pending fallback results.

The default playlist is community maintained, not a guarantee of availability or independent distribution rights. Observed 2026-10-30: its FPT VTV3 URL returned 403 INVALID_TOKEN. This change does not acquire tokens or bypass that restriction. Failover may still exhaust all sources. It does not apply to catch-up playback.

The check workflow analyzes source and runs resolver tests without building an APK, publishing a release, or changing OTA. Installed APKs do not acquire this code until a separate build is installed.
