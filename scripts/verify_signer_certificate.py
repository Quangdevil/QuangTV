"""Compare verified apksigner output with the permanent release certificate."""
import re
import sys
from pathlib import Path


def verify(text, expected):
    expected = expected.strip().lower()
    if not re.fullmatch(r'[0-9a-f]{64}', expected):
        raise ValueError('Invalid expected certificate SHA-256')
    if not re.search(r'^Number of signers: 1$', text, re.MULTILINE):
        raise ValueError('Release APK must have exactly one signer')
    # Android build-tools changed the label from Signer #1 to V2 Signer.
    certificates = set(re.findall(
        r'^(?:Signer #\d+|V[\d.]+ Signer): certificate SHA-256 digest: ([0-9a-fA-F]{64})$',
        text, re.MULTILINE))
    if {value.lower() for value in certificates} != {expected}:
        raise ValueError('APK signing certificate does not match the permanent keystore')


if __name__ == '__main__':
    verify(Path(sys.argv[1]).read_text(), sys.argv[2])
    print('QUANGTV_CERTIFICATE_PASS permanentKeystoreMatches=true')
