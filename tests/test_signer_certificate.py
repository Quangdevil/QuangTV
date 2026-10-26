import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_signer_certificate import verify

SHA = '984be0208fe470cd7cb8f94365d5159ccc9ceee248f23ee0f903f9257b121b30'


class ReleaseCertificateTest(unittest.TestCase):
    def test_android_build_tools_output_formats(self):
        for label in ('Signer #1', 'V2 Signer', 'V3 Signer', 'V3.1 Signer'):
            with self.subTest(label=label):
                verify(f'Verifies\nNumber of signers: 1\n{label}: certificate SHA-256 digest: {SHA}\n', SHA)

    def test_wrong_or_missing_certificate_rejected(self):
        for line in (f'V2 Signer: certificate SHA-256 digest: {"a" * 64}',
                     f'V2 Signer: public key SHA-256 digest: {SHA}', ''):
            with self.subTest(line=line), self.assertRaises(ValueError):
                verify('Number of signers: 1\n' + line + '\n', SHA)

    def test_multiple_signers_rejected(self):
        with self.assertRaises(ValueError):
            verify(f'Number of signers: 2\nSigner #1: certificate SHA-256 digest: {SHA}\n', SHA)

    def test_invalid_keystore_fingerprint_rejected(self):
        with self.assertRaises(ValueError):
            verify('Number of signers: 1\n', '')


if __name__ == '__main__':
    unittest.main()
