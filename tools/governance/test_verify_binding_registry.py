import importlib.util
import json
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("verify_binding_registry.py")
SPEC = importlib.util.spec_from_file_location("verify_binding_registry", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BindingRegistryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = json.loads(MODULE.REGISTRY_PATH.read_text(encoding="utf-8"))

    def test_frozen_empty_registry_is_not_ready(self) -> None:
        empty = dict(self.registry)
        empty["status"] = "NOT_READY"
        empty["bindings"] = []
        self.assertEqual(MODULE.validate_registry(empty), 0)

    def test_duplicate_binding_id_is_rejected(self) -> None:
        binding = {
            "binding_id": "ENF-RECOVERIES-TEST",
            "canonical_rule_id": "RULE-AUTH-TEST",
            "rule_version": "1.0",
            "authority_class": "TECHNICAL_AUTHORIZATION",
            "system": "anarchi-recoveries",
            "component": "proof",
            "operation": "test",
            "enforcement_point": "proof.gate",
            "implementation_ref": "git:abcdef1",
            "test_ref": "test.txt",
            "proof_fixture": "fixture.json",
            "fail_mode": "DENY",
            "status": "STAGED",
        }
        self.registry["bindings"] = [binding, dict(binding)]
        with self.assertRaises(ValueError, msg="duplicate binding IDs must fail closed"):
            MODULE.validate_registry(self.registry)

    def test_active_binding_requires_real_proof_files(self) -> None:
        binding = {
            "binding_id": "ENF-RECOVERIES-TEST",
            "canonical_rule_id": "RULE-AUTH-TEST",
            "rule_version": "1.0",
            "authority_class": "TECHNICAL_AUTHORIZATION",
            "system": "anarchi-recoveries",
            "component": "proof",
            "operation": "test",
            "enforcement_point": "proof.gate",
            "implementation_ref": "git:abcdef1",
            "test_ref": "missing-test.txt",
            "proof_fixture": "missing-fixture.json",
            "fail_mode": "DENY",
            "status": "ACTIVE",
        }
        self.registry["bindings"] = [binding]
        with self.assertRaises(ValueError, msg="active bindings need executable proof"):
            MODULE.validate_registry(self.registry)

    def test_non_deny_fail_mode_is_rejected(self) -> None:
        binding = {
            "binding_id": "ENF-RECOVERIES-TEST",
            "canonical_rule_id": "RULE-AUTH-TEST",
            "rule_version": "1.0",
            "authority_class": "TECHNICAL_AUTHORIZATION",
            "system": "anarchi-recoveries",
            "component": "proof",
            "operation": "test",
            "enforcement_point": "proof.gate",
            "implementation_ref": "git:abcdef1",
            "test_ref": "test.txt",
            "proof_fixture": "fixture.json",
            "fail_mode": "ALLOW",
            "status": "STAGED",
        }
        self.registry["bindings"] = [binding]
        with self.assertRaises(ValueError, msg="bindings must fail closed"):
            MODULE.validate_registry(self.registry)


if __name__ == "__main__":
    unittest.main()
