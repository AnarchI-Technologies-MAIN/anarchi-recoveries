import unittest

from verify_production_readiness import EXPECTED_WORKLOADS, validate


def manifest():
    return {
        "schema": "anarchi.recoveries.production-migration-readiness.v1",
        "spec_sha256": "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869",
        "status": "NOT_AUTHORIZED",
        "production_mutated": False,
        "source_stage": "founder_dev_wsl2_spine",
        "target_stage": "dedicated_early_production_stack",
        "dedicated_stack_slots": [
            {"slot": index, "workload": workload}
            for index, workload in enumerate(EXPECTED_WORKLOADS, start=1)
        ],
        "objectives": {
            "postgresql_rpo_minutes_max": 15,
            "core_recoveries_rto_hours_max": 4,
            "independent_full_backup": "nightly",
            "continuous_incremental_db_protection": True,
            "off_stack_encrypted_backup_minimum": 1,
            "backup_restoration_testing": "scheduled_and_recorded",
        },
        "preflight": {
            "authority_approved": False,
            "rollback_plan_approved": False,
            "backup_restore_proof": False,
            "secret_broker_vault_ready": False,
            "observability_ready": False,
            "dedicated_stack_reachable": False,
        },
    }


class ProductionReadinessTests(unittest.TestCase):
    def test_not_authorized_manifest_is_valid(self):
        validate(manifest())

    def test_authorization_requires_all_preflight_checks(self):
        value = manifest()
        value["status"] = "AUTHORIZED"
        with self.assertRaisesRegex(ValueError, "every preflight"):
            validate(value)

    def test_workload_order_is_pinned(self):
        value = manifest()
        value["dedicated_stack_slots"][0]["workload"] = "database"
        with self.assertRaisesRegex(ValueError, "workload map drifted"):
            validate(value)


if __name__ == "__main__":
    unittest.main()
