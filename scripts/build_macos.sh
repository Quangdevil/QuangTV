#!/usr/bin/env bash
# Build the pinned recipe on macOS; QA is a separate, installable application.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
mode="${1:---qa}"
case "$mode" in --qa|--release) ;; *) echo 'Usage: build_macos.sh [--qa|--release]' >&2; exit 2 ;; esac
tools="${AUTODEV_TOOLS:-$HOME/.local/share/autodev}"
export JAVA_HOME="${JAVA_HOME:-$tools/jdk-17/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$tools/android-sdk}"
export PATH="$JAVA_HOME/bin:$HOME/.local/bin:$PATH"
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.vfs.watch=false"
flutter="${FLUTTER_BIN:-$tools/flutter-3.44.4/bin/flutter}"
[[ -x "$flutter" ]] || { echo 'Flutter 3.44.4 is required; set FLUTTER_BIN.' >&2; exit 2; }
mkdir -p .local-build/logs .local-build/cache .local-build/artifacts
log_step() { local name="$1"; shift; "$@" 2>&1 | tee "$root/.local-build/logs/$name.log"; }
"$flutter" --version --machine > .local-build/logs/flutter-version.json
python3 - <<'PY'
import json
assert json.load(open('.local-build/logs/flutter-version.json'))['frameworkVersion'] == '3.44.4', 'Use the same Flutter version as CI: 3.44.4'
PY
fingerprint=$(python3 - <<'PY'
from pathlib import Path
import hashlib
h = hashlib.sha256()
files = list(Path('overrides').rglob('*')) + list(Path('scripts').glob('patch_*.py')) + list(Path('tests').rglob('*')) + [Path('COPYING.NewPipe')]
for p in sorted(p for p in files if p.is_file() and '__pycache__' not in p.parts):
    h.update(str(p).encode()); h.update(p.read_bytes())
print(h.hexdigest())
PY
)
pin=188df516a8acb4a2fda0d65fed8b6199c734603f
if [[ ! -f .local-build/prepared-source ]]; then
  if [[ ! -d upstream ]]; then
    git clone --no-checkout https://github.com/tv-viewer-app/tv_viewer.git upstream
    git -C upstream checkout --detach "$pin"
  fi
  [[ "$(git -C upstream rev-parse HEAD)" == "$pin" ]] || { echo 'Unexpected upstream revision.' >&2; exit 2; }
  [[ -z "$(git -C upstream status --porcelain)" ]] || { echo 'Preserve/move modified upstream before preparing a fresh checkout.' >&2; exit 2; }
  log_step patch python3 scripts/patch_quangtv.py
  (cd upstream/flutter_app; log_step dependencies "$flutter" pub get)
  log_step vlc python3 scripts/patch_vlc_engine.py
  (cd upstream/flutter_app; log_step local-dependencies "$flutter" pub get)
  printf '%s\n' "$fingerprint" > .local-build/prepared-source
else
  [[ "$(cat .local-build/prepared-source)" == "$fingerprint" ]] || { echo 'Recipe changed. Preserve/move upstream and .local-build/prepared-source before rebuilding.' >&2; exit 2; }
fi
if [[ "$mode" == --release ]]; then
  [[ -s upstream/flutter_app/android/key.properties ]] || { echo 'Permanent release key.properties and keystore are required; no debug fallback.' >&2; exit 3; }
  [[ "${BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]] || { echo 'Set BUILD_NUMBER above the published OTA build.' >&2; exit 3; }
fi
sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
log_step sdk "$sdkmanager" --sdk_root="$ANDROID_HOME" 'platforms;android-36' 'build-tools;35.0.0' 'ndk;28.2.13676358'
gradle="$root/.local-build/cache/gradle-8.11.1-bin.zip"
if [[ ! -f "$gradle" ]]; then
  curl -fL --retry 3 https://downloads.gradle.org/distributions/gradle-8.11.1-bin.zip -o "$gradle.download"
  mv "$gradle.download" "$gradle"
fi
curl -fsSL --retry 3 https://services.gradle.org/distributions/gradle-8.11.1-bin.zip.sha256 -o "$gradle.sha256"
python3 - "$gradle" "$mode" <<'PY'
from pathlib import Path
import hashlib, sys
archive = Path(sys.argv[1])
assert hashlib.sha256(archive.read_bytes()).hexdigest() == Path(str(archive) + '.sha256').read_text().strip(), 'Gradle checksum mismatch'
android = Path('upstream/flutter_app/android')
p = android / 'gradle/wrapper/gradle-wrapper.properties'
p.write_text('\n'.join('distributionUrl=' + archive.as_uri() if x.startswith('distributionUrl=') else x for x in p.read_text().splitlines()) + '\n')
p = android / 'gradle.properties'
lines = [x for x in p.read_text().splitlines() if not x.startswith(('org.gradle.jvmargs=', 'org.gradle.vfs.watch=', 'org.gradle.workers.max='))]
p.write_text('\n'.join(lines) + '\norg.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G\norg.gradle.vfs.watch=false\norg.gradle.workers.max=2\n')
qa = sys.argv[2] == '--qa'
p = android / 'app/build.gradle'; s = p.read_text()
s = s.replace('applicationId "com.quangduren.quangtv.localqa"', 'applicationId "com.quangduren.quangtv"')
s = s.replace('signingConfig signingConfigs.debug', 'signingConfig signingConfigs.release')
if qa:
    s = s.replace('applicationId "com.quangduren.quangtv"', 'applicationId "com.quangduren.quangtv.localqa"')
    s = s.replace('signingConfig signingConfigs.release', 'signingConfig signingConfigs.debug')
p.write_text(s)
p = android / 'app/src/main/AndroidManifest.xml'
s = p.read_text().replace('android:label="QuangTV Local QA"', 'android:label="QuangTV"')
if qa: s = s.replace('android:label="QuangTV"', 'android:label="QuangTV Local QA"')
p.write_text(s)
PY
log_step signer-tests python3 -m unittest discover -s tests -p test_signer_certificate.py
log_step proxy-tests python3 cloudflare/test_native_websocket.py
log_step reader-tests node --test cloudflare/worker.test.mjs
version=1.3.0
build="${BUILD_NUMBER:-1}"
[[ "$mode" != --qa ]] || { version=1.3.0-localqa; build=1; }
(
  cd upstream/flutter_app
  log_step dependencies-final "$flutter" pub get
  log_step analyze "$flutter" analyze lib/screens/quang_native_browser.dart lib/screens/quang_native_tube.dart lib/screens/quang_may_shell.dart lib/screens/quang_vtv_source.dart lib/screens/quang_network.dart lib/screens/quang_discover_screen.dart lib/screens/quang_native_player.dart lib/screens/quang_audio_screen.dart lib/screens/quang_update_screen.dart lib/screens/quang_browser_screen.dart lib/screens/quang_proxy_screen.dart integration_test/browser_test.dart
  log_step unit-tests "$flutter" test test/quang_vtv_source_test.dart
  log_step apk "$flutter" build apk --release --split-per-abi --target-platform android-arm64 --build-name="$version" --build-number="$build"
)
apk=".local-build/artifacts/QuangTV-$version-build$build-arm64.apk"
cp upstream/flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$apk"
log_step apk-layout python3 scripts/verify_release_apk.py "$apk"
log_step apk-signature "$ANDROID_HOME/build-tools/35.0.0/apksigner" verify --verbose "$apk"
shasum -a 256 "$apk" | tee "$apk.sha256"
echo "Built $apk; QA certificates are not production OTA signing keys."
