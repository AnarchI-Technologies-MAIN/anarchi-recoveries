import importlib.util
import json
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("verify_policy_baseline.py")
SPEC = importlib.util.spec_from_file_location("verify_policy_baseline", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PolicyBaselineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = json.loads(MODULE.MANIFEST.read_text(encoding="utf-8"))

    def test_frozen_manifest_is_review_only(self) -> None:
        MODULE.validate(self.manifest)

    def test_active_status_is_rejected(self) -> None:
        value = dict(self.manifest)
        value["status"] = "ACTIVE"
        with self.assertRaises(ValueError):
            MODULE.validate(value)

    def test_missing_document_is_rejected(self) -> None:
        value = dict(self.manifest)
        value["documents"] = value["documents"][:-1]
        with self.assertRaises(ValueError):
            MODULE.validate(value)

    def test_unsafe_retention_is_rejected(self) -> None:
        value = dict(self.manifest)
        value["retention"] = dict(value["retention"])
        value["retention"]["ordinary_backup_age_out_days"] = 365
        with self.assertRaises(ValueError):
            MODULE.validate(value)


if __name__ == "__main__":
    unittest.main()
