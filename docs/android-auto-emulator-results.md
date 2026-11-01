# Preview 2 Android emulator results — 2026-11-01

Source under test: Preview 2 build 9, commit e6a002f9c8ee225e71a85aef995ecfb8fe644793.
Runtime: Android 15 / API 35, Google Play x86_64 emulator. ARM64 phone release is unchanged.
Both test APKs use normal release/AOT/R8 compilation and the Preview 2 signer.

Run: https://github.com/Quangdevil/QuangTV/actions/runs/41288899820
Evidence artifact: Preview2-Android-runtime-evidence.

- PASS: original private AudioService configuration rejects an independent UID's MediaBrowser client, with the same not-exported Permission Denial found in the phone bugreport.
- PASS: repaired service connects from the independent client and supplies the seeded public channel catalog.
- PASS: playFromMediaId, pause and stop commands produce the expected Android media session states using a local WAV fixture.
- BLOCKED: native projection service cannot load Google's host. The system image contains AndroidAutoStubPrebuilt (version 1.2.542030-stub), not full Android Auto. Invoking the legacy projection service in this environment logs Android Auto is not installed.
- NOT TESTED: actual Google Android Auto app launcher, projection UI, YouTube/video/fullscreen/touch, VF8 and Samsung Android 17 compatibility, or end-to-end OTA installation.

The first DHU SDK installation attempt also exposed a missing sdkmanager PATH entry. The workflow now resolves its SDK executable explicitly. The preflight now reports the stub-host blocker immediately instead of treating it as a projection test result.

A passing media IPC result does not establish that the projection UI works.
Google's full DHU setup procedure: https://developer.android.com/training/cars/testing/dhu
