import unittest

from verify_release_freeze import REQUIRED_GATES, validate


def manifest():
    return {
        "schema": "anarchi.recoveries.pilot-release-freeze.v1",
        "spec_sha256": "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869",
        "status": "HOLD_NOT_READY",
        "release_decision": "HOLD",
        "production_mutated": False,
        "gates": {gate: False for gate in REQUIRED_GATES},
        "hold_reasons": ["missing independent release proof"],
    }


class PilotFreezeTests(unittest.TestCase):
    def test_hold_manifest_is_valid(self):
        validate(manifest())

    def test_ready_requires_every_gate(self):
        value = manifest()
        value["status"] = "READY"
        value["release_decision"] = "RELEASE"
        value["hold_reasons"] = []
        with self.assertRaisesRegex(ValueError, "every gate"):
            validate(value)

    def test_ready_with_all_gates_and_no_hold_reasons_is_valid(self):
        value = manifest()
        value["status"] = "READY"
        value["release_decision"] = "RELEASE"
        value["gates"] = {gate: True for gate in REQUIRED_GATES}
        value["hold_reasons"] = []
        validate(value)


if __name__ == "__main__":
    unittest.main()
