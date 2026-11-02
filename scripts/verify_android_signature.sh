#!/usr/bin/env bash
set -euo pipefail
apk="$1"
build="$2"
tools=$(python3 - "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" <<'PY'
import re
import sys
from pathlib import Path
root = Path(sys.argv[1]) / 'build-tools'
versions = [p for p in root.iterdir() if re.fullmatch(r'\d+(?:\.\d+)+', p.name) and (p / 'apksigner').is_file()]
if not versions:
    raise SystemExit('No installed Android build-tools with apksigner')
print(max(versions, key=lambda p: tuple(map(int, p.name.split('.')))))
PY
)
mkdir -p playback-evidence
"$tools/apksigner" verify --verbose --print-certs "$apk" | tee playback-evidence/release-signature.txt
expected=$(keytool -exportcert -keystore upstream/flutter_app/android/app/quangtv-release.jks -storepass:env KEYSTORE_PASSWORD -alias "$KEY_ALIAS" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
python3 scripts/verify_signer_certificate.py playback-evidence/release-signature.txt "$expected"
"$tools/aapt" dump badging "$apk" > playback-evidence/release-package.txt
grep -q "package: name='com.quangduren.quangtv' versionCode='$build'" playback-evidence/release-package.txt
echo "QUANGTV_SIGNATURE_PASS releaseCertificateMatches=true versionCode=$build"
