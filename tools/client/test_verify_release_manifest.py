import json
import unittest

from verify_release_manifest import validate


def manifest():
    return {
        "schema": "anarchi.recoveries.client-release-manifest.v1",
        "spec_sha256": "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869",
        "status": "NOT_RELEASED",
        "product": "ANARCHI / RECOVERIES",
        "target": {
            "platform": "windows",
            "architecture": "x64",
            "installer_name": "AnarchI-Recoveries-x64-Setup.exe",
            "install_scope": "user",
        },
        "update": {
            "channel": "disabled_until_signed",
            "requires_signed_artifact": True,
            "requires_release_receipt": True,
        },
        "artifact": None,
        "signature": None,
    }


class ReleaseManifestTests(unittest.TestCase):
    def test_unreleased_manifest_is_valid_and_has_no_artifact_claim(self):
        validate(manifest())

    def test_unreleased_manifest_cannot_claim_signature(self):
        value = manifest()
        value["signature"] = {"algorithm": "Authenticode", "certificate_sha256": "a" * 64}
        with self.assertRaisesRegex(ValueError, "cannot claim artifact or signature"):
            validate(value)

    def test_release_requires_signed_artifact_proof(self):
        value = manifest()
        value["status"] = "RELEASED"
        value["update"]["channel"] = "stable"
        with self.assertRaisesRegex(ValueError, "requires artifact and signature"):
            validate(value)


if __name__ == "__main__":
    unittest.main()
