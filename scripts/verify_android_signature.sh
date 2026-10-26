#!/usr/bin/env bash
set -euo pipefail
apk="$1"
build="$2"
tools=$(find "${ANDROID_HOME:-$ANDROID_SDK_ROOT}/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
mkdir -p playback-evidence
"$tools/apksigner" verify --verbose --print-certs "$apk" | tee playback-evidence/release-signature.txt
actual=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' playback-evidence/release-signature.txt)
expected=$(keytool -exportcert -keystore upstream/flutter_app/android/app/quangtv-release.jks -storepass:env KEYSTORE_PASSWORD -alias "$KEY_ALIAS" | sha256sum | cut -d' ' -f1)
test "$actual" = "$expected"
"$tools/aapt" dump badging "$apk" > playback-evidence/release-package.txt
grep -q "package: name='com.quangduren.quangtv' versionCode='$build'" playback-evidence/release-package.txt
echo "QUANGTV_SIGNATURE_PASS releaseCertificateMatches=true versionCode=$build"
