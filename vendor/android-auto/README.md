# Legacy projection SDK artifact

`aauto.aar` is the Android Auto projection SDK artifact distributed in the
Fermata repository at commit `7d2bd42e0fea98a796ba069b56c48ef07d874549`:
https://github.com/AndreyPavlenko/Fermata/blob/7d2bd42e0fea98a796ba069b56c48ef07d874549/fermata/lib/auto/aauto.aar

The bytes are unmodified. `SHA256SUMS` pins the artifact and the integration
script checks it before every build. This artifact is not a supported public
AndroidX Car App Library API. It exposes CarActivity and CarActivityService,
which a projection app uses to render native views inside Android Auto.
Fermata application code has not been copied into the QuangTV host.

The SDK archive contains no standalone license notice. Its inclusion in an
upstream repository does not establish redistribution rights. Confirm those
rights before any public release containing this artifact. This preview is
for compatibility investigation; do not publish it through the production OTA.

`preview-only.jks` is an intentionally public development signing key for the isolated Auto Preview 2 package (passwords: android; alias: androiddebugkey). It must never sign production releases.
