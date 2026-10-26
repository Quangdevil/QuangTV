#!/usr/bin/env bash
set -euo pipefail
apk="$1"
build="$2"
tools=$(find "${ANDROID_HOME:-$ANDROID_SDK_ROOT}/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
mkdir -p playback-evidence
"$tools/apksigner" verify --verbose --print-certs "$apk" | tee playback-evidence/release-signature.txt
expected=$(keytool -exportcert -keystore upstream/flutter_app/android/app/quangtv-release.jks -storepass:env KEYSTORE_PASSWORD -alias "$KEY_ALIAS" | sha256sum | cut -d' ' -f1)
python3 scripts/verify_signer_certificate.py playback-evidence/release-signature.txt "$expected"
"$tools/aapt" dump badging "$apk" > playback-evidence/release-package.txt
grep -q "package: name='com.quangduren.quangtv' versionCode='$build'" playback-evidence/release-package.txt
echo "QUANGTV_SIGNATURE_PASS releaseCertificateMatches=true versionCode=$build"
